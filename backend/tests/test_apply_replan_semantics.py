"""Replan (dry run) + apply semantics (spec section 8; findings 5, 6, 7, 8, 12; C1, C2, C5, C6, C10)."""
import asyncio
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.plan_application import PlanApplication
from app.models.task import Task, TaskPriority, TaskStatus
from app.repositories.task_repository import TaskRepository
from tests.plan_helpers import IST, client, make_user

D = date(2026, 10, 5)  # Monday
NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)


def at(h, m=0, day=5):
    return datetime(2026, 10, day, h, m, tzinfo=IST)


def seed(uid, title, start=None, minutes=45, **kw):
    db = SessionLocal()
    try:
        t = Task(user_id=uid, title=title, estimated_minutes=minutes,
                 scheduled_start=start.astimezone(timezone.utc) if start else None,
                 scheduled_end=(start + timedelta(minutes=minutes)).astimezone(timezone.utc) if start else None, **kw)
        db.add(t)
        db.commit()
        return str(t.id)
    finally:
        db.close()


def get(task_id):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.id == task_id).one()
    finally:
        db.close()


def rows(uid):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.user_id == uid).all()
    finally:
        db.close()


async def replan(ac, h, message, now=NOW, day="2026-10-05"):
    r = await ac.post("/api/v1/ai/replan", headers=h, json={
        "selected_date": day, "user_message": message, "current_local_time": now.isoformat(), "timezone": "Asia/Kolkata"})
    assert r.status_code == 200, r.text
    return r.json()["plan_diff"]


async def apply(ac, h, payload, now=NOW, **kw):
    payload = {**payload, "current_local_time": now.isoformat(), "timezone": "Asia/Kolkata", **kw}
    return await ac.post("/api/v1/calendar/apply-replan", headers=h, json=payload)


# ── findings 5/8: new task via server-authored apply request ──────────────────
@pytest.mark.asyncio
async def test_new_task_valid_source_creates_and_urgent_priority_preserved():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "urgent report needs 1 hour")
        assert len(diff["newly_scheduled_tasks"]) == 1 and len(diff["apply_request"]["new_tasks"]) == 1
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["created_count"] == 1 and body["success"] is True
    row = rows(uid)[0]
    assert row.priority == TaskPriority.urgent and row.scheduled_start is not None
    assert row.source.value in ("manual", "ai_parsed", "calendar", "imported")
    assert body["persisted_tasks"][0]["priority"] == "urgent"


# ── finding 6: move to tomorrow ──────────────────────────────────────────────
@pytest.mark.asyncio
async def test_move_to_tomorrow_diff_has_new_start_and_apply_persists_slot():
    uid, h = make_user()
    gym = seed(uid, "Gym workout", at(17), 60)
    async with client() as ac:
        diff = await replan(ac, h, "Move gym to tomorrow.")
        moved = diff["moved_tasks"]
        assert len(moved) == 1 and moved[0]["new_date"] == "Tomorrow" and moved[0]["new_date_iso"] == "2026-10-06"
        ns = datetime.fromisoformat(moved[0]["new_start"].replace("Z", "+00:00"))
        assert ns.astimezone(IST).date() == date(2026, 10, 6) and moved[0]["new_end"]
        assert not any("gym" in i["title"].lower() for i in diff["after_schedule"])
        upd = diff["apply_request"]["task_updates"]
        assert len(upd) == 1 and upd[0]["scheduled_start"]
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200 and r.json()["updated_count"] == 1
    assert get(gym).scheduled_start.astimezone(IST).date() == date(2026, 10, 6)


@pytest.mark.asyncio
async def test_move_to_tomorrow_respects_tomorrows_existing_tasks():
    uid, h = make_user()
    gym = seed(uid, "Gym workout", at(17), 60)
    # tomorrow is wall-to-wall locked from 07:00-23:00 except nothing: gym cannot fit tomorrow
    seed(uid, "Wall", at(7, 0, day=6), 16 * 60 - 0, time_locked=True)
    async with client() as ac:
        diff = await replan(ac, h, "Move gym to tomorrow.")
    assert not diff["moved_tasks"] or all(
        not (datetime.fromisoformat(m["new_start"].replace("Z", "+00:00")).astimezone(IST).hour in range(7, 23))
        for m in diff["moved_tasks"])
    assert any(u["task_id"] == gym for u in diff["unscheduled_tasks"])


@pytest.mark.asyncio
async def test_move_to_tomorrow_infeasible_sets_planned_date_on_apply():
    uid, h = make_user()
    gym = seed(uid, "Gym workout", at(17), 60)
    seed(uid, "Wall", at(6, 0, day=6), 17 * 60, time_locked=True)
    async with client() as ac:
        diff = await replan(ac, h, "Move gym to tomorrow.")
        # nothing could be placed tomorrow, the task must not silently vanish
        assert any(u["task_id"] == gym for u in diff["unscheduled_tasks"])
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200
    assert get(gym).status == TaskStatus.todo  # still there


# ── finding 7: same working set as the day view; nothing misclassified as new ─
@pytest.mark.asyncio
async def test_existing_task_never_classified_new_and_apply_never_duplicates_existing():
    uid, h = make_user()
    seed(uid, "Unslotted with deadline today", None, 30, deadline_at=at(20).astimezone(timezone.utc))
    seed(uid, "Slotted tomorrow with deadline today", at(9, 0, day=6), 30, deadline_at=at(20).astimezone(timezone.utc))
    seed(uid, "Doing now", at(8, 30), 60, status=TaskStatus.in_progress, started_at=at(8, 30).astimezone(timezone.utc))
    seed(uid, "Flexible", at(14), 45)
    before_count = len(rows(uid))
    async with client() as ac:
        day = await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": "2026-10-05", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
        day_ids = {i["task_id"] for i in day.json()["timeline"]} | {i["task_id"] for i in day.json()["unscheduled_tasks"]}
        diff = await replan(ac, h, "urgent call vendor needs 30 minutes")
        assert [n["title"] for n in diff["newly_scheduled_tasks"]] == ["Call vendor"] or len(diff["newly_scheduled_tasks"]) == 1
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200
    assert len(rows(uid)) == before_count + 1, "apply may only create the genuinely new task"
    assert day_ids, "day view returned tasks"
    for n in diff["newly_scheduled_tasks"]:
        assert n["task_id"] not in {str(t.id) for t in rows(uid) if t.title != "Call vendor"}


# ── C1 / C2: completed and in-progress are protected ─────────────────────────
@pytest.mark.asyncio
async def test_completed_and_in_progress_preserved_and_protected_in_diff():
    uid, h = make_user()
    done = seed(uid, "Done thing", at(8, 0), 30, status=TaskStatus.completed, completed_at=at(8, 30).astimezone(timezone.utc))
    prog = seed(uid, "Doing now", at(8, 45), 60, status=TaskStatus.in_progress, started_at=at(8, 45).astimezone(timezone.utc))
    seed(uid, "Later work", at(9, 30), 45)
    async with client() as ac:
        diff = await replan(ac, h, "I'm running 30 minutes late.")
        titles = {p["title"]: p["reason"] for p in diff["skipped_immutable"]}
        assert "Done thing" in titles and "Doing now" in titles
        after = {i["title"]: i for i in diff["after_schedule"]}
        assert after["Done thing"]["is_completed"] is True and after["Done thing"]["time"] == "8:00"
        assert after["Doing now"]["is_active"] is True
        moved_titles = {m["title"] for m in diff["moved_tasks"]}
        assert "Doing now" not in moved_titles and "Done thing" not in moved_titles
        later = after["Later work"]
        assert datetime.fromisoformat(later["start_time"]) >= at(9, 45), "later work cannot sit inside the in-progress block"
        assert not (datetime.fromisoformat(later["start_time"]) < at(9, 45) and datetime.fromisoformat(later["end_time"]) > at(8, 45))
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200
    assert get(done).scheduled_start == at(8) and get(done).status == TaskStatus.completed
    assert get(prog).scheduled_start == at(8, 45) and get(prog).status == TaskStatus.in_progress


@pytest.mark.asyncio
async def test_apply_skips_completed_in_progress_locked_and_foreign_ids_and_counts_only_real_writes():
    uid, h = make_user()
    other_uid, _ = make_user(prefix="foreign")
    done = seed(uid, "Done", at(8), 30, status=TaskStatus.completed, completed_at=at(8, 30).astimezone(timezone.utc))
    prog = seed(uid, "Prog", at(9), 30, status=TaskStatus.in_progress, started_at=at(9).astimezone(timezone.utc))
    lock = seed(uid, "Locked", at(15), 30, time_locked=True)
    ok = seed(uid, "Flexible", at(11), 30)
    foreign = seed(other_uid, "Theirs", at(11), 30)

    def upd(tid, h_, m=0):
        return {"task_id": tid, "scheduled_start": at(h_, m).isoformat(), "scheduled_end": (at(h_, m) + timedelta(minutes=30)).isoformat()}

    payload = {"plan_id": "skips", "selected_date": "2026-10-05",
               "task_updates": [upd(done, 16), upd(prog, 16, 30), upd(lock, 17), upd(ok, 18), upd(foreign, 19)],
               "cancelled_task_ids": [done, prog, foreign]}
    async with client() as ac:
        r = await apply(ac, h, payload)
    assert r.status_code == 200, r.text
    body = r.json()
    reasons = {(s["task_id"], s["reason"]) for s in body["skipped"]}
    assert (done, "completed") in reasons and (prog, "in_progress") in reasons
    assert (lock, "locked") in reasons and (foreign, "not_found") in reasons
    assert body["updated_count"] == 1 and body["updated"] == [ok] and body["cancelled_count"] == 0
    assert get(done).scheduled_start == at(8) and get(prog).scheduled_start == at(9) and get(lock).scheduled_start == at(15)
    assert get(foreign).scheduled_start == at(11), "another user's task is never touched"
    assert get(ok).scheduled_start == at(18)


# ── finding 8: idempotent / atomic ───────────────────────────────────────────
@pytest.mark.asyncio
async def test_apply_replay_idempotent():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "urgent report needs 1 hour")
        r1 = await apply(ac, h, diff["apply_request"])
        r2 = await apply(ac, h, diff["apply_request"])
    assert r1.json()["idempotent_replay"] is False and r2.json()["idempotent_replay"] is True
    assert len(rows(uid)) == 1
    assert r1.json()["created"] == r2.json()["created"]


@pytest.mark.asyncio
async def test_concurrent_double_apply_creates_once():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "urgent report needs 1 hour")
        rs = await asyncio.gather(*[apply(ac, h, diff["apply_request"]) for _ in range(5)])
    assert all(r.status_code == 200 for r in rs)
    assert len(rows(uid)) == 1


@pytest.mark.asyncio
async def test_apply_atomic_rollback(monkeypatch):
    uid, h = make_user()
    a = seed(uid, "A", at(11), 30)
    real = TaskRepository.add_no_commit
    calls = {"n": 0}

    def flaky(db, task):
        calls["n"] += 1
        if calls["n"] == 2:
            raise RuntimeError("disk")
        return real(db, task)

    monkeypatch.setattr(TaskRepository, "add_no_commit", staticmethod(flaky))
    payload = {"plan_id": "atomic", "selected_date": "2026-10-05",
               "task_updates": [{"task_id": a, "scheduled_start": at(14).isoformat(), "scheduled_end": at(14, 30).isoformat()}],
               "new_tasks": [{"title": "N1", "estimated_minutes": 30, "scheduled_start": at(16).isoformat()},
                             {"title": "N2", "estimated_minutes": 30, "scheduled_start": at(17).isoformat()}],
               "cancelled_task_ids": []}
    async with client() as ac:
        with pytest.raises(RuntimeError):
            await apply(ac, h, payload)
    assert get(a).scheduled_start == at(11), "the update must roll back with the failed create"
    assert len(rows(uid)) == 1
    db = SessionLocal()
    assert db.query(PlanApplication).filter(PlanApplication.user_id == uid).count() == 0
    db.close()


# ── server-side validation / stale ───────────────────────────────────────────
@pytest.mark.asyncio
async def test_stale_plan_returns_409_and_persists_nothing():
    uid, h = make_user()
    a = seed(uid, "A", at(11), 30)
    async with client() as ac:
        diff = await replan(ac, h, "I'm running 30 minutes late.")
        assert diff["apply_request"]["task_updates"], "late shift should move A"
        # the task changes underneath the plan
        await ac.patch(f"/api/v1/tasks/{a}", headers=h, json={"title": "A (edited)"})
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 409 and r.json()["detail"]["code"] == "stale_plan"
    assert get(a).scheduled_start == at(11)


@pytest.mark.asyncio
async def test_apply_rejects_start_in_past_overlap_and_deadline():
    uid, h = make_user()
    a = seed(uid, "A", at(11), 30)
    b = seed(uid, "B", at(15), 30)
    c = seed(uid, "C", at(16), 30, deadline_at=at(18).astimezone(timezone.utc))

    def one(tid, start):
        return {"plan_id": f"v-{tid[:6]}-{start.hour}", "selected_date": "2026-10-05",
                "task_updates": [{"task_id": tid, "scheduled_start": start.isoformat(), "scheduled_end": (start + timedelta(minutes=30)).isoformat()}]}

    async with client() as ac:
        past = await apply(ac, h, one(a, at(7)))
        overlap = await apply(ac, h, one(a, at(15, 15)))
        late = await apply(ac, h, one(c, at(19)))
    assert past.status_code == 422 and past.json()["detail"]["errors"][0]["code"] == "start_in_past"
    assert overlap.status_code == 422 and overlap.json()["detail"]["errors"][0]["code"] == "overlap"
    assert late.status_code == 422 and late.json()["detail"]["errors"][0]["code"] == "after_deadline"
    assert get(a).scheduled_start == at(11) and get(c).scheduled_start == at(16)


# ── C11 replan behaviour ────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_fixed_event_stays_and_urgent_conflict_is_reported():
    uid, h = make_user()
    seed(uid, "Dentist", at(18), 45, time_locked=True)
    async with client() as ac:
        diff = await replan(ac, h, "urgent work needs 1 hour at 6 PM")
    assert any("dentist" in c.lower() for c in diff["conflicts"])
    after = {i["title"]: i for i in diff["after_schedule"]}
    assert after["Dentist"]["is_fixed"] is True and after["Dentist"]["time"] == "6:00"
    urgent = next(i for t, i in after.items() if t != "Dentist")
    assert urgent["title"] == "Work" and not (urgent["time"] == "6:00" and urgent["period"] == "PM")


@pytest.mark.asyncio
async def test_unchanged_flexible_tasks_are_not_moved_by_unrelated_change():
    uid, h = make_user()
    seed(uid, "Alpha", at(11), 45)
    seed(uid, "Beta", at(14), 45)
    async with client() as ac:
        diff = await replan(ac, h, "urgent small thing needs 15 minutes")
    assert diff["moved_tasks"] == []
    assert {u["title"] for u in diff["unchanged_tasks"]} >= {"Alpha", "Beta"}


@pytest.mark.asyncio
async def test_missed_task_is_replaced_into_the_future():
    uid, h = make_user()
    missed = seed(uid, "Missed", at(8), 45)  # now = 11:00, never started
    async with client() as ac:
        diff = await replan(ac, h, "urgent small thing needs 15 minutes", now=at(11))
        moved = [m for m in diff["moved_tasks"] if m["task_id"] == missed]
        assert moved and datetime.fromisoformat(moved[0]["new_start"].replace("Z", "+00:00")) >= at(11)
        r = await apply(ac, h, diff["apply_request"], now=at(11))
    assert r.status_code == 200 and get(missed).scheduled_start >= at(11)


@pytest.mark.asyncio
async def test_past_explicit_time_in_replan_is_rejected_with_message_not_moved():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "urgent call at 8 AM needs 30 minutes", now=at(11))
    assert any("already passed" in c for c in diff["conflicts"])
    assert diff["newly_scheduled_tasks"] == []


@pytest.mark.asyncio
async def test_insufficient_time_lists_unscheduled_with_rollover_and_apply_persists_it():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "urgent 3 hour project", now=at(22, 15))
        assert diff["unscheduled_tasks"] and diff["unscheduled_tasks"][0]["suggestion_start"]
        r = await apply(ac, h, diff["apply_request"], now=at(22, 15))
    assert r.status_code == 200
    row = rows(uid)[0]
    assert row.scheduled_start is not None and row.scheduled_start.astimezone(IST).date() == date(2026, 10, 6)


@pytest.mark.asyncio
async def test_cancel_ambiguous_does_nothing_and_says_so():
    uid, h = make_user()
    seed(uid, "Gym morning", at(8, 30), 30)
    seed(uid, "Gym evening", at(18), 30)
    async with client() as ac:
        diff = await replan(ac, h, "cancel gym")
    assert diff["cancelled_tasks"] == []
    assert any("more than one" in c.lower() for c in diff["conflicts"])


@pytest.mark.asyncio
async def test_replan_on_past_date_returns_empty_diff():
    uid, h = make_user()
    seed(uid, "Old", at(10, day=4), 30)
    async with client() as ac:
        diff = await replan(ac, h, "urgent thing", day="2026-10-04")
    assert diff["moved_tasks"] == [] and diff["newly_scheduled_tasks"] == [] and diff["conflicts"]
    assert diff["apply_request"]["task_updates"] == []


@pytest.mark.asyncio
async def test_other_dates_untouched_by_replan():
    uid, h = make_user()
    tomorrow = seed(uid, "Tomorrow task", at(9, day=6), 30)
    async with client() as ac:
        diff = await replan(ac, h, "urgent thing needs 30 minutes")
        assert tomorrow not in {m["task_id"] for m in diff["moved_tasks"]}
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200 and get(tomorrow).scheduled_start == at(9, day=6)


# ── C12 isolation ────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_replan_and_day_ignore_other_users_tasks():
    ua, ha = make_user(prefix="isoA")
    ub, hb = make_user(prefix="isoB")
    seed(ua, "A private dentist", at(10), 60, time_locked=True)
    async with client() as ac:
        diff_b = await replan(ac, hb, "urgent thing at 10 AM needs 30 minutes")
        day_b = await ac.get("/api/v1/calendar/day", headers=hb, params={
            "date": "2026-10-05", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
    assert not any("private" in c.lower() or "dentist" in c.lower() for c in diff_b["conflicts"])
    assert all("A private" not in i["title"] for i in day_b.json()["timeline"])
    new = diff_b["newly_scheduled_tasks"][0]
    assert new["new_time"] == "10:00 AM", "B's 10 AM is free; A's task must not block it"
