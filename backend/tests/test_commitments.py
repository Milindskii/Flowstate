"""A commitment (tasks.is_commitment, always time_locked) is a block the user will be away for, e.g. "Going out
6:30-8:30". It blocks scheduling and is visible everywhere, but it is not work: no remaining minutes, never the
"do this now" task, never missed/failed, no complete/skip/redo, untouched by Replan, and it survives a restart.
A plain time_locked task (a dentist appointment) keeps its normal behaviour."""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task
from app.models.task_deviation import TaskDeviation
from app.services.task_state import derive_task_state, task_slot_elapsed
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, seed

D = date(2026, 10, 5)


def deviations(uid):
    db = SessionLocal()
    try:
        return db.query(TaskDeviation).filter(TaskDeviation.user_id == uid).all()
    finally:
        db.close()


def _real_task(uid, title, start_offset_min, minutes=60, **kw):
    real = datetime.now(timezone.utc)
    start = real + timedelta(minutes=start_offset_min)
    return seed(uid, title, start, minutes, planned_date=real.astimezone(IST).date(), **kw)


# ── pure state rule ──────────────────────────────────────────────────────────
def test_a_commitment_never_derives_missed_or_failed():
    kw = dict(completed=False, cancelled=False, active=False, start=at(18, 30), end=at(20, 30), day_boundary=at(23))
    assert derive_task_state(now=at(17), commitment=True, **kw) == "commitment"
    assert derive_task_state(now=at(19), commitment=True, **kw) == "commitment"
    assert derive_task_state(now=at(21), commitment=True, **kw) == "commitment"
    assert derive_task_state(now=at(23, 30), commitment=True, **kw) == "commitment"
    assert derive_task_state(now=at(21), **kw) == "missed"  # a normal task still does


def test_a_commitment_slot_is_never_elapsed_work():
    t = Task(user_id="u", title="Going out", estimated_minutes=120, scheduled_start=at(18, 30), scheduled_end=at(20, 30),
             time_locked=True, is_commitment=True)
    assert task_slot_elapsed(t, at(22)) is False


# ── persistence + visibility ─────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_commitment_is_persisted_and_visible_on_calendar_and_after_a_restart():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    async with client() as ac:
        r = await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": "2026-10-05", "timezone": "Asia/Kolkata", "current_local_time": at(21).isoformat()})
    item = next(i for i in r.json()["timeline"] if i["task_id"] == c)
    assert item["is_commitment"] is True and item["time_locked"] is True
    assert item["state"] == "commitment" and item["is_missed"] is False
    assert get(c).is_commitment is True  # a fresh session reads the stored flag


@pytest.mark.asyncio
async def test_calendar_never_writes_history_for_a_passed_commitment():
    uid, h = make_user()
    seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    async with client() as ac:
        await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": "2026-10-05", "timezone": "Asia/Kolkata", "current_local_time": at(22).isoformat()})
        diff = await replan(ac, h, "running 15 min late", now=at(22))
    assert deviations(uid) == []
    assert diff is not None


# ── Today ────────────────────────────────────────────────────────────────────
async def _today(ac, h):
    r = await ac.get("/api/v1/today", headers=h, params={"timezone": "Asia/Kolkata"})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.asyncio
async def test_commitment_is_not_remaining_work_and_never_current():
    uid, h = make_user()
    c = _real_task(uid, "Going out", -10, 120, time_locked=True, is_commitment=True)  # inside its block right now
    async with client() as ac:
        body = await _today(ac, h)
    assert body["workload_summary"]["planned_minutes"] == 0
    assert body["workload_summary"]["missed_minutes"] == 0
    rec = body["current_recommendation"]
    assert rec is None or rec["task"]["id"] != c
    listed = [i for i in body["upcoming_timeline"] if i["title"] == "Going out"]
    assert listed and listed[0].get("is_commitment") is True and listed[0]["state"] == "commitment"


@pytest.mark.asyncio
async def test_commitment_does_not_beat_real_work_even_when_urgent_and_next():
    uid, h = make_user()
    _real_task(uid, "Going out", 2, 120, time_locked=True, is_commitment=True, priority="urgent")
    work = _real_task(uid, "Essay", 5, 30)
    async with client() as ac:
        body = await _today(ac, h)
    assert body["current_recommendation"]["task"]["id"] == work


@pytest.mark.asyncio
async def test_plain_locked_task_keeps_normal_behaviour():
    uid, h = make_user()
    d = _real_task(uid, "Dentist", -10, 60, time_locked=True)
    async with client() as ac:
        body = await _today(ac, h)
        done = await ac.post(f"/api/v1/tasks/{d}/complete", headers=h, json={})
    assert body["workload_summary"]["planned_minutes"] == 60
    assert done.status_code == 200, done.text


# ── no complete / start / skip / redo ────────────────────────────────────────
@pytest.mark.asyncio
async def test_commitment_cannot_be_completed_or_started():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    async with client() as ac:
        done = await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})
        started = await ac.post(f"/api/v1/tasks/{c}/start", headers=h)
    for r in (done, started):
        assert r.status_code == 409, r.text
        assert r.json()["detail"]["code"] == "commitment_not_completable"
    assert get(c).status.value == "todo"


@pytest.mark.asyncio
@pytest.mark.parametrize("reason", ["skip", "later", "wrong_timing", "do_this_now"])
async def test_today_override_refuses_to_skip_move_or_pick_a_commitment(reason):
    uid, h = make_user()
    c = _real_task(uid, "Going out", -10, 120, time_locked=True, is_commitment=True)
    _real_task(uid, "Essay", 5, 30)
    before = get(c).scheduled_start
    async with client() as ac:
        today = await _today(ac, h)
        r = await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": today["decision_id"], "reason": reason, "chosen_task_id": c, "timezone": "Asia/Kolkata"})
    assert r.status_code == 409, r.text
    assert r.json()["detail"]["code"] == "commitment_not_movable"
    assert get(c).scheduled_start == before and get(c).status.value == "todo"
    assert deviations(uid) == []


# ── Replan ───────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
@pytest.mark.parametrize("msg", ["skip going out", "redo going out", "I missed going out", "defer going out"])
async def test_replan_never_skips_defers_or_redoes_a_commitment(msg):
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    seed(uid, "Gym", at(11), 60, planned_date=D)
    async with client() as ac:
        diff = await replan(ac, h, msg, now=at(21))
    assert any("commitment" in x.lower() or "fixed" in x.lower() for x in diff["conflicts"]), diff["conflicts"]
    assert all(u["task_id"] != c for u in diff["apply_request"]["task_updates"])
    assert c not in diff["apply_request"]["cancelled_task_ids"]


@pytest.mark.asyncio
@pytest.mark.parametrize("msg", ["move going out to tomorrow", "cancel going out"])
async def test_replan_cancels_or_moves_a_commitment_only_when_the_user_names_it(msg):
    """Explicit cancel/move of a named commitment is proposed (never silently applied); the row is not touched by
    the dry run."""
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    seed(uid, "Gym", at(11), 60, planned_date=D)
    async with client() as ac:
        diff = await replan(ac, h, msg, now=at(9))
    req = diff["apply_request"]
    assert c in req["cancelled_task_ids"] or any(u["task_id"] == c for u in req["task_updates"])
    assert get(c).status.value == "todo" and get(c).scheduled_start.astimezone(IST).hour == 18


@pytest.mark.asyncio
async def test_running_late_does_not_shift_a_commitment():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    seed(uid, "Essay", at(16), 60, planned_date=D)
    async with client() as ac:
        diff = await replan(ac, h, "I'm running 30 min late", now=at(15))
    assert all(u["task_id"] != c for u in diff["apply_request"]["task_updates"])


@pytest.mark.asyncio
async def test_apply_cannot_override_a_commitment_even_with_user_override():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    async with client() as ac:
        diff = await replan(ac, h, "running 10 min late", now=at(15))
        req = {**diff["apply_request"], "task_updates": [{
            "task_id": c, "scheduled_start": at(10).isoformat(), "scheduled_end": at(12).isoformat(),
            "user_override": True}]}
        await apply(ac, h, req, now=at(15))
    assert get(c).scheduled_start == at(18, 30).astimezone(timezone.utc)


# ── edit guard ───────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_commitment_can_move_but_never_unlock_or_unschedule():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=D, time_locked=True, is_commitment=True)
    async with client() as ac:
        bad = await ac.put(f"/api/v1/tasks/{c}", headers=h, json={"time_locked": False})
        assert bad.status_code == 409 and bad.json()["detail"]["code"] == "commitment_locked"
        bad2 = await ac.put(f"/api/v1/tasks/{c}", headers=h, json={"scheduled_start": None})
        assert bad2.status_code == 409
        ok = await ac.put(f"/api/v1/tasks/{c}", headers=h, json={"title": "Dinner out"})
        assert ok.status_code == 200, ok.text
    assert get(c).is_commitment is True and get(c).time_locked is True
