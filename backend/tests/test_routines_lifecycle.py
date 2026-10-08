"""Routine lifecycle + scheduling around routines: edit, delete, override, restart, history, conflicts."""
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.routine import Routine
from app.models.task import Task, TaskStatus
from app.services import routine_service
from tests.plan_helpers import IST, client, make_user, post_plan
from tests.test_build_my_day_quality import _gemini_returns
from tests.test_routines import NOW, TODAY, add_routine, dump, local, plan, routine_body, rows, task


def at(h, m=0, day=0):
    return datetime(2026, 10, 5 + day, h, m, tzinfo=IST)


async def confirm(ac, h, items, now=NOW, **kw):
    b = {"tasks": items, "timezone": "Asia/Kolkata", "current_local_time": now.isoformat(),
         "plan_id": kw.pop("plan_id", None) or f"p-{id(items)}"}
    b.update(kw)
    r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=b)
    assert r.status_code == 201, r.text
    return r.json()


# ── scheduling around a confirmed routine ────────────────────────────────────

@pytest.mark.asyncio
async def test_build_my_day_protects_routine_time(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h)
        d = await plan(ac, h, monkeypatch, dump(
            task("t1", "Finish ML assignment", type="deep_work", estimated_minutes=120, target_date=TODAY.isoformat()),
            task("t2", "Study DSA", type="study", estimated_minutes=90, target_date=TODAY.isoformat()),
            task("t3", "Work on Flowstate", type="deep_work", estimated_minutes=90, target_date=TODAY.isoformat())),
            "Finish my ML assignment, study DSA and work on Flowstate.")
    gym = (at(16), at(17))
    assert len(d["tasks"]) == 3
    for t in d["tasks"]:
        s = local(datetime.fromisoformat(t["recommended_slot_start"]))
        e = s + timedelta(minutes=t["estimated_minutes"])
        assert not (s < gym[1] and gym[0] < e), (t["title"], s, e)
    today_gym = [t for t in rows(uid) if t.routine_date == TODAY]
    assert len(today_gym) == 1 and local(today_gym[0].scheduled_start) == gym[0]


@pytest.mark.asyncio
async def test_routine_plus_deadline_finishes_before_the_routine(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h)
        d = await plan(ac, h, monkeypatch, dump(
            task("t1", "Submit report", type="deep_work", estimated_minutes=90, target_date=TODAY.isoformat(),
                 deadline=TODAY.isoformat(), deadline_time="17:00", deadline_kind="hard", deadline_phrase="by")),
            "Submit report by 5 PM today.")
    (t,) = d["tasks"]
    s = local(datetime.fromisoformat(t["recommended_slot_start"]))
    e = s + timedelta(minutes=90)
    assert e <= at(16) or s >= at(17)
    assert e <= at(17)


@pytest.mark.asyncio
async def test_routine_plus_conflicting_fixed_task_is_reported_not_overlapped(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h)
        d = await plan(ac, h, monkeypatch, dump(
            task("t1", "Team call", type="meeting", fixed_start="16:15", target_date=TODAY.isoformat(),
                 estimated_minutes=30)), "Team call today at 4:15 PM.")
    (t,) = d["tasks"]
    s = local(datetime.fromisoformat(t["scheduled_start"])) if t.get("scheduled_start") else None
    flagged = bool(d["conflicts"]) or t.get("unscheduled_reason") or (s is not None and not (s < at(17) and at(16) < s + timedelta(minutes=30)))
    assert flagged, "an overlap with the routine must be surfaced, never silent"


@pytest.mark.asyncio
async def test_one_day_override_moves_today_only(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h)
        rid = res["routine"]["id"]
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Gym", fixed_start="18:00", target_date=TODAY.isoformat())),
                       "Today I have gym at 6 PM.")
        (t,) = d["tasks"]
        assert d["routine_proposals"] == []
        assert t["routine_override_id"] == rid and t["routine_override_date"] == TODAY.isoformat()
        assert local(datetime.fromisoformat(t["scheduled_start"])) == at(18)
        item = {k: t.get(k) for k in ("title", "task_type", "priority", "estimated_minutes", "time_locked", "planned_date",
                                      "candidate_id", "routine_override_id", "routine_override_date")}
        item.update(client_ref=t["candidate_id"], scheduled_start=t["scheduled_start"], scheduled_end=t["scheduled_end"])
        await confirm(ac, h, [item])
    by_day = {t.routine_date or t.planned_date: t for t in rows(uid) if t.title == "Gym"}
    assert local(by_day[TODAY].scheduled_start) == at(18)                                 # today uses 6 PM
    assert [t for t in rows(uid) if t.routine_date == TODAY] == []                        # the 4 PM occurrence is gone
    tomorrow = [t for t in rows(uid) if t.routine_date == TODAY + timedelta(days=1)]
    assert len(tomorrow) == 1 and local(tomorrow[0].scheduled_start).hour == 16           # the routine is unchanged
    db = SessionLocal()
    try:
        r = db.get(Routine, rid)
        assert r.start_hhmm == "16:00" and r.deleted_at is None
    finally:
        db.close()


# ── edit / delete / history ──────────────────────────────────────────────────

def _complete_today(uid):
    db = SessionLocal()
    try:
        t = db.query(Task).filter(Task.user_id == uid, Task.routine_date == TODAY).one()
        t.status = TaskStatus.completed
        t.completed_at = at(17).astimezone(timezone.utc)
        db.commit()
        return t.id
    finally:
        db.close()


@pytest.mark.asyncio
async def test_edit_changes_future_occurrences_never_history():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h)
        rid = res["routine"]["id"]
        done_id = _complete_today(uid)
        tomorrow_9 = at(9, day=1)
        r = await ac.patch(f"/api/v1/routines/{rid}", headers=h, json={
            "start_hhmm": "17:30", "timezone": "Asia/Kolkata", "current_local_time": tomorrow_9.isoformat()})
        assert r.status_code == 200, r.text
    all_rows = rows(uid)
    done = next(t for t in all_rows if t.id == done_id)
    assert local(done.scheduled_start) == at(16) and done.status == TaskStatus.completed   # history untouched
    future = [t for t in all_rows if t.routine_date and t.routine_date > TODAY]
    assert future and all(local(t.scheduled_start).strftime("%H:%M") == "17:30" for t in future)
    assert len({t.routine_date for t in future}) == len(future)                              # no duplicates
    assert max(t.routine_date for t in future) == TODAY + timedelta(days=1) + timedelta(days=6)


@pytest.mark.asyncio
async def test_delete_stops_future_keeps_history():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h)
        rid = res["routine"]["id"]
        done_id = _complete_today(uid)
        r = await ac.delete(f"/api/v1/routines/{rid}", headers=h, params={
            "timezone": "Asia/Kolkata", "current_local_time": at(17, 30).isoformat()})
        assert r.status_code == 200 and r.json()["deleted"] is True
        listed = await ac.get("/api/v1/routines", headers=h, params={
            "timezone": "Asia/Kolkata", "current_local_time": at(17, 30).isoformat()})
        assert listed.json() == []
    left = rows(uid)
    assert [t.id for t in left] == [done_id] and left[0].status == TaskStatus.completed


# ── restart / rolling horizon ────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_app_restart_keeps_the_confirmed_week_without_duplicates_or_resurrecting_deletions():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h)
        deleted = [t for t in rows(uid) if t.routine_date == TODAY + timedelta(days=2)][0]
        db = SessionLocal()
        try:
            db.delete(db.get(Task, deleted.id))     # the user removed one occurrence
            db.commit()
        finally:
            db.close()
        later = at(9, day=3)                          # app reopened three days later
        r = await ac.get("/api/v1/routines", headers=h, params={
            "timezone": "Asia/Kolkata", "current_local_time": later.isoformat()})
        assert r.status_code == 200 and len(r.json()) == 1
        r2 = await ac.get("/api/v1/routines", headers=h, params={
            "timezone": "Asia/Kolkata", "current_local_time": later.isoformat()})
        assert r2.status_code == 200
    days = sorted(t.routine_date for t in rows(uid))
    assert len(days) == len(set(days))                                    # still one per day
    assert TODAY + timedelta(days=2) not in days                          # a deleted occurrence is not resurrected
    # bounded by the confirmed weekly cycle: a restart never extends the routine silently (Continue does, see
    # test_routine_weekly_cycles.py)
    assert days[-1] == TODAY + timedelta(days=6)


@pytest.mark.asyncio
async def test_future_build_my_day_after_routine_exists_schedules_around_it(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h)
        _gemini_returns(monkeypatch, dump(task("t1", "Study DSA", type="study", estimated_minutes=240,
                                               target_date=(TODAY + timedelta(days=1)).isoformat())))
        r = await post_plan(ac, h, NOW, text="Study DSA tomorrow for four hours")
        assert r.status_code == 200, r.text
    (t,) = r.json()["tasks"]
    s = local(datetime.fromisoformat(t["recommended_slot_start"]))
    e = s + timedelta(minutes=240)
    assert s.date() == (TODAY + timedelta(days=1))
    assert not (s < at(17, day=1) and at(16, day=1) < e)


# ── unit rules ───────────────────────────────────────────────────────────────

def test_weekday_parsing_and_summaries():
    assert routine_service.parse_weekdays(["mon", "Wednesday", 4, "bogus", "mon"]) == [0, 2, 4]
    assert routine_service.summarize("fixed", "weekly", [0, 1, 2, 3, 4], "09:00", None) == "Weekdays · 9:00 AM"
    assert routine_service.summarize("avoid", "daily", None, "18:00", "20:00") == "Every day · not between 6:00 PM and 8:00 PM"
    assert routine_service.titles_match("Gym session", "gym") and routine_service.titles_match("Workout", "Gym")
    assert not routine_service.titles_match("Gym", "Study")
