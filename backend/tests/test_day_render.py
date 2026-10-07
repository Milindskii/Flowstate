"""Calendar day view renders persisted state (spec C13, D5; findings 2, 15)."""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task, TaskStatus
from tests.plan_helpers import IST, client, make_user


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


async def day(ac, h, now, d="2026-10-05"):
    r = await ac.get("/api/v1/calendar/day", headers=h, params={"date": d, "timezone": "Asia/Kolkata", "current_local_time": now.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.asyncio
async def test_persisted_slots_rendered_as_stored_regardless_of_now():
    uid, h = make_user()
    seed(uid, "Flexible report", at(14), 60)
    seed(uid, "Study", at(16), 45)
    async with client() as ac:
        a = await day(ac, h, at(8))
        b = await day(ac, h, at(9, 37))
        c = await day(ac, h, at(13, 50))
    key = lambda d: [(i["title"], i["start_time"], i["end_time"]) for i in d["timeline"]]
    assert key(a) == key(b) == key(c)
    assert [i["time"] for i in a["timeline"]] == ["2:00", "4:00"]


@pytest.mark.asyncio
async def test_calendar_tags_fixed_only_when_locked():
    uid, h = make_user()
    seed(uid, "Dentist", at(18), 45, time_locked=True)
    seed(uid, "Flexible", at(11), 45)
    async with client() as ac:
        d = await day(ac, h, at(8))
    by = {i["title"]: i for i in d["timeline"]}
    assert by["Dentist"]["is_fixed"] is True and by["Dentist"]["tag_text"] == "FIXED" and by["Dentist"]["time_locked"] is True
    assert by["Flexible"]["is_fixed"] is False and by["Flexible"]["tag_text"] != "FIXED"
    assert [i["title"] for i in d["fixed_commitments"]] == ["Dentist"]
    assert [i["title"] for i in d["remaining_tasks"]] == ["Flexible"]


@pytest.mark.asyncio
async def test_unslotted_task_gets_flagged_suggestion_and_is_not_persisted():
    uid, h = make_user()
    tid = seed(uid, "No time yet", None, 45)
    async with client() as ac:
        d = await day(ac, h, at(9))
    item = next(i for i in d["timeline"] if i["task_id"] == tid)
    assert item["is_suggested"] is True and item["is_fixed"] is False
    db = SessionLocal()
    assert db.query(Task).filter(Task.id == tid).one().scheduled_start is None
    db.close()


@pytest.mark.asyncio
async def test_missed_slot_flagged_not_silently_moved():
    uid, h = make_user()
    seed(uid, "Missed", at(8), 30)
    async with client() as ac:
        d = await day(ac, h, at(11))
    it = d["timeline"][0]
    assert it["is_missed"] is True and it["time"] == "8:00"


@pytest.mark.asyncio
async def test_completed_and_in_progress_rendered_and_tz_reported():
    uid, h = make_user()
    seed(uid, "Done", at(8), 30, status=TaskStatus.completed, completed_at=at(8, 30).astimezone(timezone.utc))
    seed(uid, "Doing", at(9), 45, status=TaskStatus.in_progress, started_at=at(9).astimezone(timezone.utc))
    async with client() as ac:
        d = await day(ac, h, at(9, 10))
    assert d["timezone_used"] == "Asia/Kolkata"
    assert [i["title"] for i in d["completed_tasks"]] == ["Done"]
    assert next(i for i in d["timeline"] if i["title"] == "Doing")["is_active"] is True


@pytest.mark.asyncio
async def test_future_day_shows_only_that_days_tasks_and_user_scoped():
    ua, ha = make_user(prefix="dayA")
    ub, hb = make_user(prefix="dayB")
    seed(ua, "A friday", at(15, day=9), 60)
    seed(ub, "B friday", at(15, day=9), 60)
    async with client() as ac:
        a = await day(ac, ha, at(8), d="2026-10-09")
        b = await day(ac, hb, at(8), d="2026-10-09")
        today_a = await day(ac, ha, at(8))
    assert [i["title"] for i in a["timeline"]] == ["A friday"]
    assert [i["title"] for i in b["timeline"]] == ["B friday"]
    assert today_a["timeline"] == []


@pytest.mark.asyncio
async def test_day_view_survives_suggestion_planner_failure(monkeypatch):
    import app.services.calendar_service as cs

    uid, h = make_user()
    seed(uid, "Stored", at(14), 30)
    tid = seed(uid, "No time yet", None, 45)
    monkeypatch.setattr(cs, "plan", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("planner bug")))
    async with client() as ac:
        d = await day(ac, h, at(9))
    assert [i["title"] for i in d["timeline"]] == ["Stored"], "stored slots still render"
    assert [i["task_id"] for i in d["unscheduled_tasks"]] == [tid], "the unslotted task is listed, not lost"
