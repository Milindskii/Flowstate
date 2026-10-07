"""Date invariant: ``planned_date`` (or, for legacy rows, the stored slot) decides which day owns a task.

``created_at`` and ``completed_at`` never move a task into today's bucket. Only an explicit reschedule
(a new slot, a new planned date, "Later", an applied replan) changes ``planned_date``.

Frozen "now": 2026-10-06 00:30 IST, so the user's local today is Oct 6.
"""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task, TaskStatus
from tests.plan_helpers import IST, client, make_user

INSTANT = datetime(2026, 10, 5, 19, 0, tzinfo=timezone.utc)  # Oct 6 00:30 IST
TODAY = date(2026, 10, 6)


@pytest.fixture
def frozen(monkeypatch):
    import app.api.routes.today as today_mod
    import app.services.task_service as task_service_mod

    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return INSTANT if tz is None else INSTANT.astimezone(tz)

    monkeypatch.setattr(today_mod, "datetime", Frozen)
    monkeypatch.setattr(task_service_mod, "datetime", Frozen)


def at(d: date, hour: int, minute: int = 0) -> str:
    return datetime(d.year, d.month, d.day, hour, minute, tzinfo=IST).isoformat()


async def create(ac, h, **body):
    res = await ac.post("/api/v1/tasks", headers=h, json={"title": "t", "estimated_minutes": 30, **body})
    assert res.status_code == 201, res.text
    return res.json()


async def today_ids(ac, h):
    return {t["id"] for t in (await ac.get("/api/v1/tasks/today", headers=h)).json()}


async def day(ac, h, d: date):
    res = await ac.get("/api/v1/calendar/day", headers=h, params={
        "date": d.isoformat(), "timezone": "Asia/Kolkata", "current_local_time": INSTANT.astimezone(IST).isoformat()})
    assert res.status_code == 200, res.text
    body = res.json()
    ids = lambda key: {i["task_id"] for i in body[key]}
    return {"completed": ids("completed_tasks"), "open": ids("timeline") | ids("unscheduled_tasks")}


@pytest.mark.asyncio
async def test_task_planned_oct4_completed_today_stays_on_oct4(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    oct4 = TODAY - timedelta(days=2)
    async with client() as ac:
        t = await create(ac, h, title="Planned Oct 4", planned_date=oct4.isoformat())
        done = (await ac.post(f"/api/v1/tasks/{t['id']}/complete", headers=h,
                              json={"completed_at": INSTANT.isoformat()})).json()
        assert done["status"] == "completed"
        assert done["planned_date"] == oct4.isoformat(), "completing must never change planned_date"

        assert t["id"] in (await day(ac, h, oct4))["completed"]
        today_view = await day(ac, h, TODAY)
        assert t["id"] not in today_view["completed"] | today_view["open"]
        assert t["id"] not in await today_ids(ac, h)


@pytest.mark.asyncio
async def test_task_created_today_but_planned_tomorrow_is_not_today(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    tomorrow = TODAY + timedelta(days=1)
    async with client() as ac:
        t = await create(ac, h, title="Tomorrow", planned_date=tomorrow.isoformat())
        assert t["id"] not in await today_ids(ac, h)
        assert t["id"] not in (await day(ac, h, TODAY))["open"]
        assert t["id"] in (await day(ac, h, tomorrow))["open"]


@pytest.mark.asyncio
async def test_missed_task_without_deadline_stays_on_its_own_day(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    oct4 = TODAY - timedelta(days=2)
    async with client() as ac:
        t = await create(ac, h, title="Missed", planned_date=oct4.isoformat())
        assert t["id"] not in await today_ids(ac, h)
        assert t["id"] in (await day(ac, h, oct4))["open"]


@pytest.mark.asyncio
async def test_overdue_deadline_surfaces_today_without_moving_the_task(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    oct4 = TODAY - timedelta(days=2)
    async with client() as ac:
        t = await create(ac, h, title="Overdue", planned_date=oct4.isoformat(), deadline_at=at(oct4, 18))
        assert t["id"] in await today_ids(ac, h)
        got = (await ac.get(f"/api/v1/tasks/{t['id']}", headers=h)).json()
        assert got["planned_date"] == oct4.isoformat()


@pytest.mark.asyncio
async def test_create_always_stores_an_explicit_planned_date(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    fri = TODAY + timedelta(days=4)
    async with client() as ac:
        bare = await create(ac, h, title="No date")
        due = await create(ac, h, title="Due Friday", deadline_at=at(fri, 17))
        slotted = await create(ac, h, title="Slotted", scheduled_start=at(TODAY + timedelta(days=2), 9),
                               planned_date=TODAY.isoformat())
    assert bare["planned_date"] == TODAY.isoformat()
    assert due["planned_date"] == fri.isoformat()
    assert slotted["planned_date"] == (TODAY + timedelta(days=2)).isoformat(), "a stored slot fixes the day"


@pytest.mark.asyncio
async def test_timed_reschedule_moves_ownership_to_the_slot_day(frozen):
    """Flutter sends planned_date=null alongside a timed reschedule (app_state_provider.rescheduleTask)."""
    _, h = make_user(tz="Asia/Kolkata")
    target = TODAY + timedelta(days=2)
    async with client() as ac:
        t = await create(ac, h, title="Move me")
        res = await ac.patch(f"/api/v1/tasks/{t['id']}", headers=h, json={
            "scheduled_start": at(target, 10), "scheduled_end": at(target, 10, 30), "planned_date": None})
        assert res.status_code == 200, res.text
        assert res.json()["planned_date"] == target.isoformat()
        assert t["id"] not in await today_ids(ac, h)


@pytest.mark.asyncio
async def test_date_only_reschedule_sets_planned_date(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    target = TODAY + timedelta(days=3)
    async with client() as ac:
        t = await create(ac, h, title="Date only", scheduled_start=at(TODAY, 15))
        res = await ac.patch(f"/api/v1/tasks/{t['id']}", headers=h, json={
            "scheduled_start": None, "scheduled_end": None, "planned_date": target.isoformat()})
        assert res.json()["planned_date"] == target.isoformat()
        assert res.json()["scheduled_start"] is None


@pytest.mark.asyncio
async def test_legacy_row_completed_today_is_not_bucketed_by_completed_at(frozen):
    uid, h = make_user(tz="Asia/Kolkata")
    db = SessionLocal()
    row = Task(user_id=uid, title="Legacy", estimated_minutes=30, status=TaskStatus.completed,
               completed_at=INSTANT, created_at=INSTANT)  # no planned_date, no slot
    db.add(row)
    db.commit()
    tid = row.id
    db.close()
    async with client() as ac:
        assert tid not in (await day(ac, h, TODAY))["completed"]
