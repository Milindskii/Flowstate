"""Calendar day path: a skipped / bypassed task keeps its stop (manual verification 2026-10-06).

A -> B -> C -> D. When B is skipped (the server moves B's slot) or runs out of time (derived, never stored), B's stop
must stay where it was. The day view therefore keeps a history node at B's ORIGINAL slot even when B itself is still
on this day (a skip that landed later today, a Redo) - the app merges that node with the live item into one stop.
"""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task
from app.models.task_deviation import TaskDeviation
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, seed
from tests.test_missed_state import D, day, deviations, now_at

DAY = "2026-10-05"


def _plan(uid):
    ids = {n: seed(uid, n, at(h), 60, planned_date=D) for n, h in (("A", 9), ("B", 10), ("C", 11), ("D", 12))}
    return ids


def _skip_to_later_today(uid, task_id, original_start, new_start):
    """The persisted result of a skip that landed later the same day (what /today/override writes)."""
    db = SessionLocal()
    try:
        db.add(TaskDeviation(user_id=uid, task_id=task_id, deviation_date=D, kind="skipped",
                             original_start=original_start.astimezone(timezone.utc),
                             original_end=(original_start + timedelta(minutes=60)).astimezone(timezone.utc)))
        t = db.get(Task, task_id)
        t.scheduled_start = new_start.astimezone(timezone.utc)
        t.scheduled_end = (new_start + timedelta(minutes=60)).astimezone(timezone.utc)
        db.commit()
    finally:
        db.close()


def _by_title(items):
    return {i["title"]: i for i in items}


@pytest.mark.asyncio
async def test_skip_that_lands_later_today_keeps_a_node_at_the_original_slot():
    uid, h = make_user()
    ids = _plan(uid)
    _skip_to_later_today(uid, ids["B"], at(10), at(15))
    async with client() as ac:
        view = await day(ac, h, now_at(9, 30))

    # the live task is where the server put it ...
    live_b = _by_title(view["timeline"])["B"]
    assert live_b["start_time"].startswith("2026-10-05T15:00")
    # ... and its history node is still at the original slot (before the fix it was hidden because B is "on the day")
    ghosts = [i for i in view["deviations"] if i["task_id"] == ids["B"]]
    assert len(ghosts) == 1
    assert ghosts[0]["deviation"] == "skipped" and ghosts[0]["is_skipped"] is True
    assert ghosts[0]["start_time"].startswith("2026-10-05T10:00")
    assert ghosts[0]["id"] != live_b["id"]  # two records of one task: the app merges them into one stop


@pytest.mark.asyncio
async def test_history_node_for_a_task_that_left_the_day_keeps_the_live_items_id():
    """sched-<id> before the skip, sched-<id> after it: the stop keeps its identity (no remount, the route can morph)."""
    uid, h = make_user()
    b = seed(uid, "Bravo", at(12), 60, planned_date=D)
    seed(uid, "Alpha", at(10), 60, planned_date=D)
    async with client() as ac:
        before = await day(ac, h, now_at(9))
        diff = await replan(ac, h, "skip bravo")
        assert (await apply(ac, h, diff["apply_request"])).status_code == 200
        after = await day(ac, h, now_at(9))
    assert _by_title(before["timeline"])["Bravo"]["id"] == f"sched-{b}"
    ghost = [i for i in after["deviations"] if i["task_id"] == b]
    assert [g["id"] for g in ghost] == [f"sched-{b}"]
    assert get(b).planned_date == date(2026, 10, 6)


@pytest.mark.asyncio
async def test_redo_of_a_missed_task_keeps_its_original_node_and_the_live_task_moves_on():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(8), 60, planned_date=D)
    now = now_at(15)
    async with client() as ac:
        diff = await replan(ac, h, "redo the missed task", now=now)
        assert (await apply(ac, h, diff["apply_request"], now=now)).status_code == 200
        view = await day(ac, h, now)
    ghosts = [i for i in view["deviations"] if i["task_id"] == gym]
    assert len(ghosts) == 1 and ghosts[0]["deviation"] == "missed" and ghosts[0]["start_time"].startswith("2026-10-05T08:00")
    assert any(i["task_id"] == gym for i in view["timeline"])  # the live task is on its new slot, same day


@pytest.mark.asyncio
async def test_automatic_bypass_writes_no_skip_and_leaves_the_node_in_place():
    uid, h = make_user()
    ids = _plan(uid)
    async with client() as ac:
        before = await day(ac, h, now_at(9, 30))
        after = await day(ac, h, now_at(10, 30))  # B's slot (10-11) is over only at 11; at 11:30 it is missed
        missed = await day(ac, h, now_at(11, 30))
    order = lambda v: [i["title"] for i in v["timeline"]]
    assert order(before) == order(after) == order(missed) == ["A", "B", "C", "D"]
    b = _by_title(missed["timeline"])["B"]
    assert b["state"] == "missed" and b["start_time"] == _by_title(before["timeline"])["B"]["start_time"]
    assert missed["deviations"] == []
    assert deviations(uid) == []  # derived, never a fake manual skip
    assert get(ids["B"]).scheduled_start == at(10).astimezone(timezone.utc)


@pytest.mark.asyncio
async def test_real_skip_endpoint_leaves_exactly_one_node_at_the_original_slot():
    """Whatever slot the planner picks for the skipped task (later today or another day), the day it was skipped
    from still shows it once, at the original slot."""
    uid, h = make_user()
    real = datetime.now(timezone.utc)
    local_day = real.astimezone(IST).date()
    first = seed(uid, "First", real + timedelta(minutes=5), 30, planned_date=local_day)
    seed(uid, "Second", real + timedelta(minutes=90), 30, planned_date=local_day)
    seed(uid, "Third", real + timedelta(minutes=180), 30, planned_date=local_day)
    original = get(first).scheduled_start
    async with client() as ac:
        today = (await ac.get("/api/v1/today", headers=h, params={"timezone": "Asia/Kolkata"})).json()
        assert today["current_recommendation"]["task"]["id"] == first
        r = await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": today["decision_id"], "reason": "skip", "chosen_task_id": first, "timezone": "Asia/Kolkata"})
        assert r.status_code == 200, r.text
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": local_day.isoformat(), "timezone": "Asia/Kolkata", "current_local_time": real.isoformat()})).json()
    assert [d.kind for d in deviations(uid)] == ["skipped"]
    ghosts = [i for i in view["deviations"] if i["task_id"] == first]
    assert len(ghosts) == 1 and ghosts[0]["deviation"] == "skipped"
    assert datetime.fromisoformat(ghosts[0]["start_time"]) == original.replace(tzinfo=timezone.utc)


# ── skip registered without a Today decision (Task page / Calendar) ─────────

@pytest.mark.asyncio
async def test_skip_endpoint_registers_without_a_decision_and_keeps_history():
    uid, h = make_user()
    real = datetime.now(timezone.utc)
    local_day = real.astimezone(IST).date()
    task = seed(uid, "Read paper", real + timedelta(minutes=30), 30, planned_date=local_day)
    original = get(task).scheduled_start
    async with client() as ac:
        r = await ac.post(f"/api/v1/today/skip/{task}", headers=h, json={"timezone": "Asia/Kolkata"})
        assert r.status_code == 200, r.text
        body = r.json()
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": local_day.isoformat(), "timezone": "Asia/Kolkata", "current_local_time": real.isoformat()})).json()
    assert body["recorded"] is True
    assert [d.kind for d in deviations(uid)] == ["skipped"]
    ghosts = [i for i in view["deviations"] if i["task_id"] == task]
    assert len(ghosts) == 1
    assert datetime.fromisoformat(ghosts[0]["start_time"]) == original.replace(tzinfo=timezone.utc)
    if body["next_window"] is not None:  # moved to its next window
        assert get(task).scheduled_start.replace(tzinfo=timezone.utc) > original.replace(tzinfo=timezone.utc)


@pytest.mark.asyncio
async def test_skip_endpoint_refuses_commitments_and_other_users_tasks():
    uid, h = make_user()
    other, _ = make_user()
    out = seed(uid, "Going out", at(18), 60, planned_date=D, time_locked=True, is_commitment=True)
    foreign = seed(other, "Theirs", at(12), 60, planned_date=D)
    async with client() as ac:
        r1 = await ac.post(f"/api/v1/today/skip/{out}", headers=h, json={})
        r2 = await ac.post(f"/api/v1/today/skip/{foreign}", headers=h, json={})
    assert r1.status_code == 409 and r2.status_code == 404
    assert deviations(uid) == []


# ── a completed task's stop stays at its planned slot ───────────────────────

@pytest.mark.asyncio
async def test_completed_item_anchor_is_its_planned_slot_not_the_session_time():
    from app.models.task import TaskStatus

    uid, h = make_user()
    b = seed(uid, "B", at(10), 60, planned_date=D)
    db = SessionLocal()
    try:
        t = db.get(Task, b)
        t.status = TaskStatus.completed
        t.started_at = at(14).astimezone(timezone.utc)
        t.completed_at = at(15).astimezone(timezone.utc)
        db.commit()
    finally:
        db.close()
    async with client() as ac:
        view = await day(ac, h, now_at(16))
    item = next(i for i in view["timeline"] if i["task_id"] == b)
    assert item["start_time"].startswith("2026-10-05T14:00")      # the session is still reported as it ran
    assert item["anchor_start"].startswith("2026-10-05T10:00")     # the stop stays where it was planned


# ── day complete: Noya's trophy XP ──────────────────────────────────────────

@pytest.mark.asyncio
async def test_day_complete_trophy_only_when_every_task_is_done_and_only_once():
    from app.models.task import TaskStatus

    uid, h = make_user()
    a = seed(uid, "A", at(9), 30, planned_date=D)
    seed(uid, "Going out", at(18), 60, planned_date=D, time_locked=True, is_commitment=True)
    b = seed(uid, "B", at(10), 30, planned_date=D)

    def complete(task_id):
        db = SessionLocal()
        try:
            t = db.get(Task, task_id)
            t.status = TaskStatus.completed
            t.completed_at = at(11).astimezone(timezone.utc)
            db.commit()
        finally:
            db.close()

    async with client() as ac:
        complete(a)
        half = await day(ac, h, now_at(12))
        early = await ac.post("/api/v1/flow/day-complete/claim", headers=h, json={"date": DAY, "timezone": "Asia/Kolkata"})
        complete(b)
        done = await day(ac, h, now_at(12))
        first = await ac.post("/api/v1/flow/day-complete/claim", headers=h, json={"date": DAY, "timezone": "Asia/Kolkata"})
        second = await ac.post("/api/v1/flow/day-complete/claim", headers=h, json={"date": DAY, "timezone": "Asia/Kolkata"})
        after = await day(ac, h, now_at(12))
    assert half["day_complete"]["eligible"] is False
    assert early.status_code == 409
    assert done["day_complete"] == {"eligible": True, "claimed": False, "xp": 25}  # the commitment does not block it
    assert first.status_code == 200 and first.json()["xp_awarded"] == 25 and first.json()["already_claimed"] is False
    assert second.status_code == 200 and second.json()["xp_awarded"] == 0 and second.json()["already_claimed"] is True
    assert second.json()["companion_xp"] == first.json()["companion_xp"]
    assert after["day_complete"]["claimed"] is True
