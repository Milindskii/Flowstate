"""Today "Later" / "Do this now" are part of the scheduling contract (integrity-review defect 3).

POST /today/override used to write scheduled_start straight from the recommendation engine, with no
overlap, past-time or deadline check. It now asks the shared planner. These tests drive the real
endpoints; the wall clock is real, so assertions are invariants, not exact times.
"""
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task, TaskStatus
from tests.plan_helpers import IST, LA, client, make_user


def _add(uid, title, start=None, minutes=45, **kw):
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


def _row(task_id):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.id == task_id).one()
    finally:
        db.close()


def _others_overlap(uid, task_id):
    db = SessionLocal()
    try:
        me = db.query(Task).filter(Task.id == task_id).one()
        if me.scheduled_start is None:
            return []
        end = me.scheduled_end or me.scheduled_start + timedelta(minutes=me.estimated_minutes)
        clash = []
        for o in db.query(Task).filter(Task.user_id == uid, Task.id != task_id,
                                       Task.status.in_([TaskStatus.todo, TaskStatus.in_progress])).all():
            if o.scheduled_start is None:
                continue
            oe = o.scheduled_end or o.scheduled_start + timedelta(minutes=o.estimated_minutes)
            if me.scheduled_start < oe and end > o.scheduled_start:
                clash.append(o.title)
        return clash
    finally:
        db.close()


async def _decision(ac, h):
    today = (await ac.get("/api/v1/today", headers=h)).json()
    rec = today["current_recommendation"]
    assert rec is not None, today
    return today["decision_id"], rec["task"]["id"]


def _wall(uid, day_offset, tz=IST, h0=6, h1=23, title="Wall"):
    base = datetime.now(tz) + timedelta(days=day_offset)
    start = base.replace(hour=h0, minute=0, second=0, microsecond=0)
    return _add(uid, title, start, (h1 - h0) * 60 + 30, time_locked=True)


@pytest.mark.asyncio
async def test_later_books_a_planner_slot_that_is_future_unlocked_and_overlap_free():
    uid, h = make_user()
    a = _add(uid, "Write report", None, 45, task_type="admin")
    tomorrow = datetime.now(IST) + timedelta(days=1)
    _add(uid, "Tomorrow block", tomorrow.replace(hour=9, minute=30, second=0, microsecond=0), 120, time_locked=True)
    async with client() as ac:
        decision_id, rec_id = await _decision(ac, h)
        assert rec_id == a
        r = await ac.post("/api/v1/today/override", headers=h, json={"decision_id": decision_id, "reason": "later"})
    assert r.status_code == 200
    row = _row(a)
    assert row.scheduled_start is not None and row.scheduled_start > datetime.now(timezone.utc)
    assert row.time_locked is False, "a scheduler-chosen time is never user-locked"
    assert _others_overlap(uid, a) == []
    nw = r.json()["next_window"]
    local = row.scheduled_start.astimezone(IST)
    assert nw["suggested_date"] == local.date().isoformat() and nw["suggested_time"] == local.strftime("%H:%M"), \
        "the advertised window is the booked slot"


@pytest.mark.asyncio
async def test_later_is_not_booked_when_every_valid_slot_is_taken_and_says_so():
    uid, h = make_user()
    a = _add(uid, "Admin chore", None, 45, task_type="admin")        # non-deep work => "tomorrow" suggestion
    _wall(uid, 1)                                                      # tomorrow is fully booked by a fixed item
    async with client() as ac:
        decision_id, _ = await _decision(ac, h)
        r = await ac.post("/api/v1/today/override", headers=h, json={"decision_id": decision_id, "reason": "later"})
    assert r.status_code == 200
    row = _row(a)
    assert row.scheduled_start is None, "'Later' must not fall back to an earlier slot than the one the user chose"
    assert r.json()["next_window"] is None and "couldn't find a free slot" in r.json()["message"]


@pytest.mark.asyncio
async def test_later_never_places_a_task_after_its_deadline():
    uid, h = make_user()
    deadline = datetime.now(timezone.utc) + timedelta(minutes=40)
    a = _add(uid, "Due soon", None, 20, task_type="admin", deadline_at=deadline)
    async with client() as ac:
        decision_id, _ = await _decision(ac, h)
        r = await ac.post("/api/v1/today/override", headers=h, json={"decision_id": decision_id, "reason": "later"})
    assert r.status_code == 200
    row = _row(a)
    assert row.scheduled_start is None or row.scheduled_end <= row.deadline_at
    assert _others_overlap(uid, a) == []


@pytest.mark.asyncio
async def test_later_never_overlaps_another_task_even_when_the_suggested_window_is_taken():
    uid, h = make_user()
    a = _add(uid, "Write report", None, 60, task_type="admin")
    for off in (0, 1):
        _wall(uid, off, h0=7, h1=12, title=f"Morning block {off}")   # locks the typical peak windows
    async with client() as ac:
        decision_id, _ = await _decision(ac, h)
        await ac.post("/api/v1/today/override", headers=h, json={"decision_id": decision_id, "reason": "later"})
    assert _others_overlap(uid, a) == []
    row = _row(a)
    assert row.scheduled_start is None or row.scheduled_start > datetime.now(timezone.utc)


@pytest.mark.asyncio
async def test_do_this_now_never_overlaps_and_never_starts_in_the_past():
    uid, h = make_user()
    _add(uid, "Top priority", None, 45, priority="urgent")
    chosen = _add(uid, "Chosen instead", None, 30, priority="low")
    now = datetime.now(IST)
    busy = _add(uid, "In a meeting", now.replace(second=0, microsecond=0), 180, time_locked=True)   # busy right now
    async with client() as ac:
        decision_id, rec_id = await _decision(ac, h)
        pick = chosen if rec_id != chosen else rec_id
        if pick == rec_id:
            pytest.skip("recommendation happened to be the chosen task")
        r = await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": decision_id, "chosen_task_id": pick, "reason": "something_more_important"})
    assert r.status_code == 200
    row = _row(pick)
    assert _others_overlap(uid, pick) == [], "the meeting is untouched and not overlapped"
    assert _row(busy).scheduled_start is not None
    assert row.scheduled_start is None or row.scheduled_start >= datetime.now(timezone.utc) - timedelta(seconds=90)
    assert row.scheduled_end is None or row.scheduled_end > row.scheduled_start, "no half-written slot (start without end)"


@pytest.mark.asyncio
async def test_do_this_now_uses_the_current_minute_when_it_is_free():
    uid, h = make_user()
    _add(uid, "Top priority", None, 45, priority="urgent")
    chosen = _add(uid, "Chosen instead", None, 30, priority="low")
    async with client() as ac:
        decision_id, rec_id = await _decision(ac, h)
        if rec_id == chosen:
            pytest.skip("recommendation happened to be the chosen task")
        before = datetime.now(timezone.utc)
        await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": decision_id, "chosen_task_id": chosen, "reason": "something_more_important"})
    row = _row(chosen)
    if row.scheduled_start is not None:     # outside waking hours the planner may defer it, which is also valid
        assert row.scheduled_start >= before.replace(second=0, microsecond=0)
        assert row.scheduled_end == row.scheduled_start + timedelta(minutes=30)
        assert row.time_locked is False


@pytest.mark.asyncio
async def test_later_ignores_other_users_tasks():
    ua, ha = make_user(prefix="later-a")
    ub, _ = make_user(prefix="later-b")
    a = _add(ua, "Admin chore", None, 45, task_type="admin")
    _wall(ub, 1)                                       # B's whole tomorrow is booked; A must not care
    async with client() as ac:
        decision_id, _ = await _decision(ac, ha)
        r = await ac.post("/api/v1/today/override", headers=ha, json={"decision_id": decision_id, "reason": "later"})
    assert r.json()["next_window"] is not None and _row(a).scheduled_start is not None


@pytest.mark.asyncio
async def test_override_uses_the_shared_timezone_rule():
    uid, h = make_user(tz="Asia/Kolkata")
    a = _add(uid, "Admin chore", None, 45, task_type="admin")
    async with client() as ac:
        decision_id, _ = await _decision(ac, h)
        r = await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": decision_id, "reason": "later", "timezone": "America/Los_Angeles"})
    nw = r.json()["next_window"]
    local = _row(a).scheduled_start.astimezone(LA)
    assert nw["suggested_time"] == local.strftime("%H:%M") and nw["suggested_date"] == local.date().isoformat()


@pytest.mark.asyncio
async def test_other_users_decision_cannot_move_my_task():
    ua, ha = make_user(prefix="owner")
    ub, hb = make_user(prefix="intruder")
    a = _add(ua, "Mine", None, 45, task_type="admin")
    async with client() as ac:
        decision_id, _ = await _decision(ac, ha)
        r = await ac.post("/api/v1/today/override", headers=hb, json={"decision_id": decision_id, "reason": "later"})
    assert r.status_code == 200 and r.json()["recorded"] is False
    assert _row(a).scheduled_start is None
