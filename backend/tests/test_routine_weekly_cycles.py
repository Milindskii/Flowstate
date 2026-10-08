"""Weekly routine cycles: a routine plans one confirmed week; at the end Noya asks "Continue your routine next week?".

Gym Mon/Wed/Fri at 19:00, created Monday 2026-10-05 08:00 IST.
"""
from datetime import date, datetime, timedelta

import pytest

from app.db.session import SessionLocal
from app.models.flow_progression import FlowProfile
from app.models.task import Task, TaskStatus
from tests.plan_helpers import IST, client, make_user
from tests.test_routines import NOW, TODAY, add_routine, rows

GYM = dict(title="Gym", recurrence="weekly", weekdays=[0, 2, 4], start_hhmm="19:00")


def at(day_offset, h=9):
    return (datetime(2026, 10, 5, h, 0, tzinfo=IST) + timedelta(days=day_offset)).isoformat()


async def listed(ac, h, when):
    r = await ac.get("/api/v1/routines", headers=h, params={"timezone": "Asia/Kolkata", "current_local_time": when})
    assert r.status_code == 200, r.text
    return r.json()


async def answer(ac, h, rid, decision, cycle_end, when):
    r = await ac.post(f"/api/v1/routines/{rid}/continuation", headers=h, json={
        "decision": decision, "cycle_end": cycle_end, "timezone": "Asia/Kolkata", "current_local_time": when})
    assert r.status_code == 200, r.text
    return r.json()


def dates(uid):
    return sorted(t.routine_date for t in rows(uid) if t.routine_date)


@pytest.mark.asyncio
async def test_weekly_routine_plans_only_its_weekdays_for_the_confirmed_week():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h, **GYM)
    assert res["routine"]["confirmed_through"] == (TODAY + timedelta(days=6)).isoformat()
    assert res["routine"]["continuation_due"] is False
    assert dates(uid) == [date(2026, 10, 5), date(2026, 10, 7), date(2026, 10, 9)]   # Mon, Wed, Fri
    assert all(t.scheduled_start.astimezone(IST).hour == 19 if t.scheduled_start.tzinfo else True for t in rows(uid))


@pytest.mark.asyncio
async def test_no_silent_extension_and_the_question_comes_once_at_the_end_of_the_week():
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h, **GYM)
        mid = await listed(ac, h, at(3))
        assert mid[0]["continuation_due"] is False
        last_day = await listed(ac, h, at(6))      # Sunday: the cycle's last day
        again = await listed(ac, h, at(6, h=20))   # reopening the app the same day: still the same question
    assert last_day[0]["continuation_due"] is True
    assert again[0]["continuation_due"] is True
    assert max(dates(uid)) == date(2026, 10, 9), "nothing planned past the confirmed week by itself"


@pytest.mark.asyncio
async def test_continue_plans_next_week_once_whatever_the_retries_and_costs_no_shield():
    uid, h = make_user()
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        res = await add_routine(ac, h, **GYM)
        rid, end = res["routine"]["id"], res["routine"]["confirmed_through"]
        with SessionLocal() as db:
            shields = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available
        first = await answer(ac, h, rid, "continue", end, at(6))
        replay = await answer(ac, h, rid, "continue", end, at(6))          # double tap / retry / second device
        after = await listed(ac, h, at(6, h=21))
    assert first["created_count"] == 3 and first["replayed"] is False
    assert replay["created_count"] == 0 and replay["replayed"] is True
    assert dates(uid) == [date(2026, 10, d) for d in (5, 7, 9, 12, 14, 16)]
    assert after[0]["continuation_due"] is False
    assert after[0]["confirmed_through"] == "2026-10-18"
    with SessionLocal() as db:
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == shields


@pytest.mark.asyncio
async def test_not_now_plans_nothing_keeps_the_routine_and_does_not_ask_again_this_cycle():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h, **GYM)
        rid, end = res["routine"]["id"], res["routine"]["confirmed_through"]
        out = await answer(ac, h, rid, "not_now", end, at(6))
        same_day = await listed(ac, h, at(6, h=22))
        next_week = await listed(ac, h, at(9))
    assert out["created_count"] == 0
    assert same_day[0]["continuation_due"] is False
    assert len(next_week) == 1 and next_week[0]["paused"] is True, "the routine definition is kept"
    assert max(dates(uid)) == date(2026, 10, 9)


@pytest.mark.asyncio
async def test_resuming_later_plans_from_today_never_backfills_the_past():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h, **GYM)
        rid, end = res["routine"]["id"], res["routine"]["confirmed_through"]
        await answer(ac, h, rid, "not_now", end, at(6))
        resumed = await answer(ac, h, rid, "continue", end, at(15))       # Wednesday two weeks later
    assert resumed["created_count"] > 0
    new = [d for d in dates(uid) if d > date(2026, 10, 9)]
    assert min(new) >= date(2026, 10, 20), "no occurrences invented for the paused weeks"


@pytest.mark.asyncio
async def test_deleted_occurrence_stays_deleted_and_history_is_unchanged():
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h, **GYM)
        rid, end = res["routine"]["id"], res["routine"]["confirmed_through"]
        with SessionLocal() as db:
            monday = db.query(Task).filter(Task.routine_id == rid, Task.routine_date == date(2026, 10, 5)).one()
            monday.status = TaskStatus.completed
            wed = db.query(Task).filter(Task.routine_id == rid, Task.routine_date == date(2026, 10, 7)).one()
            db.delete(wed)
            db.commit()
            done_id = monday.id
        await answer(ac, h, rid, "continue", end, at(6))
        await listed(ac, h, at(8))
    all_dates = dates(uid)
    assert date(2026, 10, 7) not in all_dates
    assert len(all_dates) == len(set(all_dates))
    with SessionLocal() as db:
        assert db.get(Task, done_id).status == TaskStatus.completed


@pytest.mark.asyncio
async def test_another_account_cannot_continue_my_routine():
    uid, h = make_user()
    _, other = make_user()
    async with client() as ac:
        res = await add_routine(ac, h, **GYM)
        r = await ac.post(f"/api/v1/routines/{res['routine']['id']}/continuation", headers=other, json={
            "decision": "continue", "cycle_end": res["routine"]["confirmed_through"], "timezone": "Asia/Kolkata",
            "current_local_time": at(6)})
    assert r.status_code == 404
