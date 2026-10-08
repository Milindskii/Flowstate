"""A user with ZERO Shields (and the free AI plan spent) still has a complete, ordinary planner.

Shields pay for AI work only. Every deterministic planner action below must succeed with no balance, must not
touch the balance, and must not need the AI economy; the one genuinely AI action must be refused cleanly.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest

from app.db.session import SessionLocal
from app.models.flow_progression import FlowProfile
from app.services.ai_economy_service import AIEconomyService
from app.services.ai_service import AIService
from tests.plan_helpers import IST, client, make_user
from tests.test_ai_gateway import _exhaust_free
from tests.test_routines import NOW, add_routine, routine_body


def _broke_user():
    uid, headers = make_user()
    _exhaust_free(uid)
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid).shields_available = 0
        db.commit()
    return uid, headers


def _shields(uid):
    with SessionLocal() as db:
        return db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available


@pytest.mark.asyncio
async def test_manual_task_lifecycle_needs_no_shield_and_spends_none():
    uid, h = _broke_user()
    start = (datetime.now(timezone.utc) + timedelta(days=1)).replace(hour=12, minute=30, second=0, microsecond=0)
    async with client() as ac:
        # create: type, duration, priority, date and a FIXED time
        res = await ac.post("/api/v1/tasks", headers=h, json={
            "title": "Dentist", "task_type": "personal", "estimated_minutes": 45, "priority": "high",
            "scheduled_start": start.isoformat(), "time_locked": True, "source": "manual"})
        assert res.status_code == 201, res.text
        task = res.json()
        assert task["time_locked"] is True and task["scheduled_start"] is not None
        tid = task["id"]

        # a second, un-timed task, then edit both
        res2 = await ac.post("/api/v1/tasks", headers=h, json={"title": "Read", "estimated_minutes": 30})
        assert res2.status_code == 201
        edit = await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={"title": "Dentist (moved)", "priority": "urgent"})
        assert edit.status_code == 200 and edit.json()["title"] == "Dentist (moved)"

        # manual reschedule: change date/time, then drop the fixed time
        later = start + timedelta(days=2)
        moved = await ac.patch(f"/api/v1/tasks/{tid}", headers=h, json={"scheduled_start": later.isoformat(), "time_locked": True})
        assert moved.status_code == 200
        put = await ac.put(f"/api/v1/tasks/{tid}", headers=h, json={"title": "Dentist (moved)", "estimated_minutes": 45})
        assert put.status_code == 200

        # complete, then delete the other one
        done = await ac.post(f"/api/v1/tasks/{tid}/complete", headers=h, json={"actual_minutes": 40})
        assert done.status_code == 200 and done.json()["status"] == "completed"
        assert (await ac.delete(f"/api/v1/tasks/{res2.json()['id']}", headers=h)).status_code == 204

        # viewing: Calendar day, task list
        day = await ac.get(f"/api/v1/calendar/day?date={start.date().isoformat()}&timezone=Asia/Kolkata", headers=h)
        assert day.status_code == 200
        assert (await ac.get("/api/v1/tasks", headers=h)).status_code == 200
    assert _shields(uid) == 0, "no planner action charges or grants a Shield"


@pytest.mark.asyncio
async def test_routine_management_needs_no_shield():
    uid, h = _broke_user()
    async with client() as ac:
        created = await add_routine(ac, h)
        rid = created["routine"]["id"]
        retime = await ac.patch(f"/api/v1/routines/{rid}", headers=h, json={
            "start_hhmm": "18:30", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
        assert retime.status_code == 200, retime.text
        assert (await ac.get("/api/v1/routines", headers=h)).status_code == 200
        gone = await ac.delete(f"/api/v1/routines/{rid}?timezone=Asia/Kolkata", headers=h)
        assert gone.status_code == 200 and gone.json()["deleted"] is True
    assert _shields(uid) == 0


@pytest.mark.asyncio
async def test_deterministic_parse_needs_no_shield():
    uid, h = _broke_user()
    async with client() as ac:
        res = await ac.post("/api/v1/tasks/parse", headers=h, json={"raw_text": "Gym at 6pm for 1 hr"})
    assert res.status_code == 200 and len(res.json()) == 1
    assert _shields(uid) == 0


@pytest.mark.asyncio
async def test_the_genuine_ai_action_is_refused_cleanly_and_free_of_charge():
    uid, h = _broke_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini") as gemini:
            res = await ac.post("/api/v1/ai/plan", headers=h, json={
                "raw_text": "Finish the report", "idempotency_key": "zero-shield-1", "consume_shield": True})
            status = (await ac.get("/api/v1/ai/status", headers=h)).json()
    assert res.status_code == 403 and res.json()["failure_code"] == "insufficient_shields"
    gemini.assert_not_called()                      # no model call, nothing charged
    assert _shields(uid) == 0
    # what the app needs to explain it: the price, the balance, when the next free Shield lands
    assert status["shields_available"] == 0 and status["shield_cost"] == 2 and status["can_afford_shield_plan"] is False
    assert status["next_shield_refill_at"] and status["server_now"]


@pytest.mark.asyncio
async def test_accounts_never_share_shields_or_cooldowns():
    a, ha = _broke_user()
    b, hb = make_user()
    async with client() as ac:
        sa = (await ac.get("/api/v1/ai/status", headers=ha)).json()
        sb = (await ac.get("/api/v1/ai/status", headers=hb)).json()
        fa = (await ac.get("/api/v1/flow", headers=ha)).json()["profile"]
        fb = (await ac.get("/api/v1/flow", headers=hb)).json()["profile"]
    assert (sa["shields_available"], fa["shields_available"]) == (0, 0)
    assert (sb["shields_available"], fb["shields_available"]) == (2, 2)
    assert sb["free_use_available"] is True and sa["free_use_available"] is False
