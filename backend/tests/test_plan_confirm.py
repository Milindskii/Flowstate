"""Build My Day confirm: atomic, idempotent, server-validated (spec section 7; findings 8, 11, D6)."""
import asyncio
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.plan_application import PlanApplication
from app.models.task import Task
from app.repositories.task_repository import TaskRepository
from tests.plan_helpers import IST, client, make_user

NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)


def at(h, m=0, day=5):
    return datetime(2026, 10, day, h, m, tzinfo=IST)


def item(title, start=None, minutes=45, **kw):
    d = {"title": title, "estimated_minutes": minutes, "client_ref": kw.pop("client_ref", f"ref-{title}")}
    if start is not None:
        d["scheduled_start"] = start.isoformat()
        d["scheduled_end"] = (start + timedelta(minutes=minutes)).isoformat()
    d.update(kw)
    return d


def body(items, plan_id=None, **kw):
    b = {"tasks": items, "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()}
    if plan_id:
        b["plan_id"] = plan_id
    b.update(kw)
    return b


def count(uid):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.user_id == uid).count()
    finally:
        db.close()


def rows(uid):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.user_id == uid).order_by(Task.title).all()
    finally:
        db.close()


@pytest.mark.asyncio
async def test_confirm_persists_slots_locks_and_refs():
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([
            item("Dentist", at(18), 45, time_locked=True),
            item("Write report", at(11), 60),
        ], plan_id="p-1"))
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["created_count"] == 2 and data["client_refs"] == ["ref-Dentist", "ref-Write report"]
    by_title = {t.title: t for t in rows(uid)}
    assert by_title["Dentist"].time_locked is True and by_title["Write report"].time_locked is False
    assert by_title["Dentist"].scheduled_start == at(18) and by_title["Write report"].scheduled_start == at(11)
    assert data["timezone_used"] == "Asia/Kolkata"


@pytest.mark.asyncio
async def test_replay_same_plan_id_no_duplicates():
    uid, h = make_user()
    b = body([item("A", at(11)), item("B", at(14))], plan_id="same-plan")
    async with client() as ac:
        r1 = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
        r2 = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
    assert r1.status_code == 201 and r2.status_code == 201
    assert r2.json()["idempotent_replay"] is True and r1.json()["idempotent_replay"] is False
    assert [t["id"] for t in r1.json()["tasks"]] == [t["id"] for t in r2.json()["tasks"]]
    assert count(uid) == 2


@pytest.mark.asyncio
async def test_idempotency_key_honored():
    uid, h = make_user()
    b = body([item("A", at(11))])
    b["idempotency_key"] = "legacy-key"
    async with client() as ac:
        await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
        r2 = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
    assert r2.json()["idempotent_replay"] is True and count(uid) == 1


@pytest.mark.asyncio
async def test_concurrent_same_plan_id_single_create():
    uid, h = make_user()
    b = body([item("A", at(11)), item("B", at(14))], plan_id="race")
    async with client() as ac:
        rs = await asyncio.gather(*[ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b) for _ in range(6)])
    assert all(r.status_code == 201 for r in rs), [r.text for r in rs if r.status_code != 201]
    assert count(uid) == 2
    assert sum(1 for r in rs if r.json()["idempotent_replay"] is False) == 1


@pytest.mark.asyncio
async def test_same_plan_id_for_two_users_is_independent():
    ua, ha = make_user(prefix="pa")
    ub, hb = make_user(prefix="pb")
    b = body([item("A", at(11))], plan_id="shared-id")
    async with client() as ac:
        ra = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=ha, json=b)
        rb = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=hb, json=b)
    assert ra.json()["idempotent_replay"] is False and rb.json()["idempotent_replay"] is False
    assert count(ua) == 1 and count(ub) == 1
    assert ra.json()["tasks"][0]["id"] != rb.json()["tasks"][0]["id"]


@pytest.mark.asyncio
async def test_batch_failure_rolls_back_all(monkeypatch):
    uid, h = make_user()
    real = TaskRepository.add_no_commit
    calls = {"n": 0}

    def flaky(db, task):
        calls["n"] += 1
        if calls["n"] == 2:
            raise RuntimeError("disk on fire")
        return real(db, task)

    monkeypatch.setattr(TaskRepository, "add_no_commit", staticmethod(flaky))
    async with client() as ac:
        with pytest.raises(RuntimeError):
            await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h,
                          json=body([item("A", at(11)), item("B", at(14)), item("C", at(16))], plan_id="boom"))
    assert count(uid) == 0
    db = SessionLocal()
    assert db.query(PlanApplication).filter(PlanApplication.user_id == uid).count() == 0
    db.close()
    # and a clean retry with the SAME plan_id now succeeds (failure did not burn the key)
    monkeypatch.setattr(TaskRepository, "add_no_commit", staticmethod(real))
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h,
                          json=body([item("A", at(11)), item("B", at(14)), item("C", at(16))], plan_id="boom"))
    assert r.status_code == 201 and count(uid) == 3


@pytest.mark.asyncio
async def test_confirm_422_structured_error_for_past_explicit_time_and_nothing_persisted():
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([
            item("Fine", at(14)),
            item("Call mom", at(7), 30, time_locked=True, client_ref="tmp-2"),
        ], plan_id="p-past"))
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == "validation_failed"
    err = detail["errors"][0]
    assert err["code"] == "explicit_time_in_past" and err["index"] == 1 and err["client_ref"] == "tmp-2"
    assert err["field"] == "scheduled_start"
    assert err["message"] == "“Call mom” is set for 7:00 AM, which has already passed. Choose a new time."
    assert count(uid) == 0
    # the failed attempt does not consume the plan_id; fixing the time succeeds
    async with client() as ac:
        ok = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([
            item("Fine", at(14)), item("Call mom", at(19), 30, time_locked=True)], plan_id="p-past"))
    assert ok.status_code == 201 and count(uid) == 2


@pytest.mark.asyncio
@pytest.mark.parametrize("patch,code", [
    ({"scheduled_end": at(8).isoformat()}, "invalid_range"),
    ({"deadline_at": at(11, 10).isoformat()}, "deadline_before_end"),
    ({"scheduled_start": "2026-10-05T11:00:00"}, "missing_timezone"),
    ({"scheduled_start": None, "scheduled_end": None, "time_locked": True}, "locked_without_start"),
])
async def test_confirm_validation_codes(patch, code):
    uid, h = make_user()
    it = item("X", at(11), 60)
    it.update(patch)
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([it]))
    assert r.status_code == 422, r.text
    assert r.json()["detail"]["errors"][0]["code"] == code and count(uid) == 0


@pytest.mark.asyncio
async def test_flexible_past_slot_is_replaced_not_rejected():
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([item("Write", at(7), 45)]))
    assert r.status_code == 201, r.text
    d = r.json()
    assert d["adjustments"] and d["adjustments"][0]["reason"] == "slot_no_longer_available"
    assert datetime.fromisoformat(d["tasks"][0]["scheduled_start"].replace("Z", "+00:00")) >= NOW
    assert rows(uid)[0].scheduled_start >= NOW


@pytest.mark.asyncio
async def test_stale_slot_overlapping_existing_task_is_replaced_and_existing_untouched():
    uid, h = make_user()
    s = at(11).astimezone(timezone.utc)
    db = SessionLocal()
    db.add(Task(user_id=uid, title="Existing", estimated_minutes=60, scheduled_start=s, scheduled_end=s + timedelta(hours=1)))
    db.commit()
    db.close()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([item("New", at(11, 15), 45)]))
    assert r.status_code == 201
    by = {t.title: t for t in rows(uid)}
    assert by["Existing"].scheduled_start == at(11), "pre-existing task must never move"
    ns, ne = by["New"].scheduled_start, by["New"].scheduled_end
    assert not (ns < at(12) and ne > at(11))
    assert r.json()["adjustments"]


@pytest.mark.asyncio
async def test_infeasible_item_is_persisted_unscheduled_with_planned_date_not_dropped():
    uid, h = make_user()
    s = at(9, 15).astimezone(timezone.utc)
    db = SessionLocal()
    db.add(Task(user_id=uid, title="Wall", estimated_minutes=13 * 60 + 45, scheduled_start=s,
                scheduled_end=s + timedelta(minutes=13 * 60 + 45), time_locked=True))
    db.commit()
    db.close()
    it = item("Must today", None, 60)
    it["deadline_at"] = at(20).isoformat()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([it]))
    d = r.json()
    assert r.status_code == 201 and d["unscheduled"][0]["reason"] == "deadline_infeasible"
    row = [t for t in rows(uid) if t.title == "Must today"][0]
    assert row.scheduled_start is None and row.planned_date == datetime(2026, 10, 5).date()


@pytest.mark.asyncio
async def test_duplicate_like_input_without_plan_id_not_recreated():
    uid, h = make_user()
    b = body([item("Gym", at(17), 60)])
    async with client() as ac:
        await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
        r2 = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
    assert r2.status_code == 201 and r2.json()["deduplicated"] == ["ref-Gym"] and r2.json()["created_count"] == 0
    assert count(uid) == 1


@pytest.mark.asyncio
async def test_tomorrow_date_survives_confirm():
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([item("Study", at(9, 30, day=6), 60)]))
    assert r.status_code == 201
    row = rows(uid)[0]
    assert row.scheduled_start.astimezone(IST).date() == datetime(2026, 10, 6).date()
    assert row.scheduled_start == at(9, 30, day=6)


@pytest.mark.asyncio
async def test_empty_batch_is_a_noop():
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json={"tasks": []})
    assert r.status_code == 201 and r.json()["created_count"] == 0 and count(uid) == 0


# ── commitments are time windows, not deadline work (regression: "Going out" 10:30 PM → 12:30 AM) ──────────
@pytest.mark.asyncio
async def test_commitment_across_midnight_ignores_a_stray_same_day_deadline_and_persists():
    uid, h = make_user()
    start = at(22, 30)
    going_out = item("Going out", start, 120, time_locked=True, is_commitment=True,
                     deadline_at=at(23, 59).isoformat())  # the editor's "today" must not reject the window
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([going_out], plan_id="p-midnight"))
        assert r.status_code == 201, r.text
        # restart-equivalent: read it back from the database through a fresh request
        listed = await ac.get("/api/v1/tasks", headers=h)
    row = rows(uid)[0]
    assert row.is_commitment and row.time_locked
    assert row.scheduled_start.astimezone(IST) == start
    assert row.scheduled_end.astimezone(IST) == at(0, 30, day=6)
    assert listed.status_code == 200 and "Going out" in listed.text


@pytest.mark.asyncio
async def test_ordinary_task_deadline_validation_is_unchanged():
    uid, h = make_user()
    ordinary = item("Write", at(22, 30), 120, deadline_at=at(23, 59).isoformat())
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([ordinary], plan_id="p-ord"))
    assert r.status_code == 422
    assert r.json()["detail"]["errors"][0]["code"] == "deadline_before_end"
    assert count(uid) == 0


@pytest.mark.asyncio
async def test_editing_a_commitment_window_across_midnight_persists_and_stays_a_commitment():
    """6:30-8:30 PM → 10:30 PM-12:30 AM through the task editor's PATCH, then read back."""
    uid, h = make_user()
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body([
            item("Going out", at(18, 30), 120, time_locked=True, is_commitment=True)], plan_id="p-edit"))
        assert r.status_code == 201, r.text
        tid = r.json()["tasks"][0]["id"]
        p = await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={
            "scheduled_start": at(22, 30).isoformat(), "scheduled_end": at(0, 30, day=6).isoformat(),
            "estimated_minutes": 120, "time_locked": True})
        assert p.status_code == 200, p.text
        g = await ac.get(f"/api/v1/tasks/{tid}", headers=h)
    body_ = g.json()
    assert body_["is_commitment"] is True and body_["time_locked"] is True
    assert datetime.fromisoformat(body_["scheduled_start"].replace("Z", "+00:00")).astimezone(IST) == at(22, 30)
    assert datetime.fromisoformat(body_["scheduled_end"].replace("Z", "+00:00")).astimezone(IST) == at(0, 30, day=6)
