"""Personal routines in Build My Day (Phase 1).

Gemini is stubbed at the transport seam with the JSON shapes the prompt asks for, so the real mapper -> routine
proposal -> planner -> confirm -> DB path runs. The client clock is pinned: Monday 2026-10-05 08:00 IST.
"""
import json
import uuid
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.routine import Routine
from app.models.task import Task, TaskStatus
from app.services import routine_service
from tests.plan_helpers import IST, client, make_user, post_plan
from tests.test_build_my_day_quality import _gemini_returns

NOW = datetime(2026, 10, 5, 8, 0, tzinfo=IST)   # Monday
TODAY = NOW.date()


def task(ref, title, **kw):
    base = {"ref": ref, "title": title, "type": "physical", "category": "Fitness", "estimated_minutes": 60,
            "duration_source": "inferred", "difficulty": "physical", "priority": "medium", "priority_source": "inferred",
            "focus_level": "low", "focus_source": "inferred", "depends_on": [], "target_date": None,
            "deadline": None, "fixed_start": None, "confidence": 0.95}
    base.update(kw)
    return base


def dump(*tasks, ctx=None):
    return {"tasks": list(tasks), "planning_context": ctx or {}, "ambiguities": []}


async def plan(ac, h, monkeypatch, payload, text="dump"):
    _gemini_returns(monkeypatch, payload)
    r = await post_plan(ac, h, NOW, text=text)
    assert r.status_code == 200, r.text
    return r.json()


def rows(uid, routine_id=None):
    db = SessionLocal()
    try:
        q = db.query(Task).filter(Task.user_id == uid)
        if routine_id:
            q = q.filter(Task.routine_id == routine_id)
        return q.order_by(Task.scheduled_start).all()
    finally:
        db.close()


def routine_body(**kw):
    b = {"title": "Gym", "task_type": "physical", "category": "Fitness", "estimated_minutes": 60, "kind": "fixed",
         "recurrence": "daily", "start_hhmm": "16:00", "idempotency_key": uuid.uuid4().hex,
         "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()}
    b.update(kw)
    return b


async def add_routine(ac, h, **kw):
    r = await ac.post("/api/v1/routines", headers=h, json=routine_body(**kw))
    assert r.status_code == 201, r.text
    return r.json()


def local(dt):
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(IST)


# ── interpretation -> proposal (nothing is saved without confirmation) ───────

@pytest.mark.asyncio
async def test_daily_routine_is_a_proposal_not_task_rows(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Gym", fixed_start="16:00", recurrence="daily")),
                       "I go to the gym every day at 4 PM.")
    assert d["tasks"] == []
    (p,) = d["routine_proposals"]
    assert (p["kind"], p["recurrence"], p["start_hhmm"], p["title"]) == ("fixed", "daily", "16:00", "Gym")
    assert p["summary"] == "Every day · 4:00 PM"
    assert p["plan_dates"] == [(TODAY + timedelta(days=i)).isoformat() for i in range(7)]
    assert rows(uid) == []                                # confirmation cancelled / not yet given: nothing persisted


@pytest.mark.asyncio
async def test_weekly_routine(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Class", type="meeting", fixed_start="10:00",
                                                    recurrence="weekly", recurrence_weekdays=["mon"])),
                       "I have class every Monday at 10 AM.")
    (p,) = d["routine_proposals"]
    assert (p["recurrence"], p["weekdays"], p["start_hhmm"]) == ("weekly", [0], "10:00")
    assert p["summary"] == "Every Monday · 10:00 AM"
    # 08:00 is before today's 10:00 and next Monday is outside the 7-day horizon: exactly one date is planned
    assert p["plan_dates"] == [TODAY.isoformat()]


@pytest.mark.asyncio
async def test_one_time_fixed_task_is_not_a_routine(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Gym", fixed_start="16:00", target_date=TODAY.isoformat())),
                       "I have gym today at 4 PM.")
    assert d["routine_proposals"] == []
    (t,) = d["tasks"]
    assert t["time_locked"] is True and local(datetime.fromisoformat(t["scheduled_start"])).hour == 16


@pytest.mark.asyncio
async def test_soft_preference_is_a_preferred_routine(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Gym", preferred_start_hhmm="16:00", recurrence="daily")),
                       "I usually go to the gym around 4 PM.")
    (p,) = d["routine_proposals"]
    assert (p["kind"], p["start_hhmm"]) == ("preferred", "16:00")
    assert p["summary"] == "Every day · usually around 4:00 PM"


@pytest.mark.asyncio
async def test_routine_without_a_stated_time_invents_none(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch, dump(task("t1", "Gym", recurrence="daily")), "I go to the gym every day.")
    assert d["routine_proposals"] == []          # no time stated -> not a routine we can plan; stays an ordinary task
    assert len(d["tasks"]) == 1


@pytest.mark.asyncio
async def test_earliest_time_constraint_is_a_boundary_not_a_start(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        d = await plan(ac, h, monkeypatch,
                       dump(task("t1", "Gym", earliest_start_hhmm="16:00", target_date=TODAY.isoformat())),
                       "Gym anytime after 4 PM.")
    (t,) = d["tasks"]
    assert t["time_locked"] is False
    assert local(datetime.fromisoformat(t["recommended_slot_start"])) >= datetime(2026, 10, 5, 16, 0, tzinfo=IST)


@pytest.mark.asyncio
async def test_unavailable_window_keeps_the_activity_out(monkeypatch):
    uid, h = make_user()
    ctx = {"avoid_windows": [{"activity": "workout", "start_time": "18:00", "end_time": "20:00", "recurring": True}]}
    async with client() as ac:
        d = await plan(ac, h, monkeypatch,
                       dump(task("t1", "Gym session", target_date=TODAY.isoformat(), preferred_start_hhmm="18:30"),
                            ctx=ctx), "I never work out between 6 and 8.")
    (t,) = d["tasks"]
    s = local(datetime.fromisoformat(t["recommended_slot_start"]))
    e = s + timedelta(minutes=t["estimated_minutes"])
    assert not (s < datetime(2026, 10, 5, 20, 0, tzinfo=IST) and datetime(2026, 10, 5, 18, 0, tzinfo=IST) < e)
    (p,) = d["routine_proposals"]
    assert (p["kind"], p["start_hhmm"], p["end_hhmm"]) == ("avoid", "18:00", "20:00")


# ── confirmation: accepted creates the bounded horizon only ──────────────────

@pytest.mark.asyncio
async def test_confirmation_accepted_plans_next_7_days_only(monkeypatch):
    uid, h = make_user()
    async with client() as ac:
        res = await add_routine(ac, h)
    assert res["created_count"] == 7 and len(res["planned_dates"]) == 7
    rs = rows(uid)
    assert len(rs) == 7 and all(t.time_locked for t in rs)
    assert {local(t.scheduled_start).hour for t in rs} == {16}
    assert max(t.routine_date for t in rs) == TODAY + timedelta(days=6)    # never an unbounded set of rows


@pytest.mark.asyncio
async def test_double_confirm_is_idempotent():
    uid, h = make_user()
    key = uuid.uuid4().hex
    async with client() as ac:
        a = await add_routine(ac, h, idempotency_key=key)
        b = await add_routine(ac, h, idempotency_key=key)
    assert b["replayed"] is True and a["routine"]["id"] == b["routine"]["id"]
    assert len(rows(uid)) == 7


@pytest.mark.asyncio
async def test_weekly_routine_confirm_creates_only_matching_weekdays():
    uid, h = make_user()
    async with client() as ac:
        await add_routine(ac, h, title="Class", task_type="meeting", recurrence="weekly", weekdays=[0],
                          start_hhmm="10:00", estimated_minutes=60)
    rs = rows(uid)
    assert [t.routine_date for t in rs] == [TODAY]          # only Monday inside the horizon
