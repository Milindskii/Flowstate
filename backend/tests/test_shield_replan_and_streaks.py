"""Regression tests for:
1. Replan Shield enforcement: 0 Shields is rejected with 403 insufficient_shields BEFORE AI is called.
2. AI Replan with 1+ Shields deducts 1 Shield.
3. Daily streak progression on task completion:
   - First qualifying completion produces Day 1.
   - Consecutive date completion produces Day 2.
   - Multiple completions on same date increment only once.
   - Missed date breaks streak.
4. 7-hour streak recovery window:
   - Starts persistent 7-hour countdown.
   - Does not reset on repeated queries.
   - Restore with Shield deducts 1 Shield atomically.
   - Recovery expires after deadline (resets streak, blocks restoration).
"""
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import pytest

from app.db.session import SessionLocal
from app.models.flow_progression import FlowProfile
from app.models.task import Task
from app.services import replan_ai
from tests.plan_helpers import client, make_user
from tests.test_replan_ai import NOW, Model, _day, op, ops, ref

IST = ZoneInfo("Asia/Kolkata")
AI_MESSAGE = "scrap the evening plans with friends"


def _body(message, date="2026-10-05"):
    return {
        "selected_date": date,
        "user_message": message,
        "current_local_time": NOW.isoformat(),
        "timezone": "Asia/Kolkata",
    }


def _set_profile(uid, **values):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        for k, v in values.items():
            setattr(p, k, v)
        db.commit()


def _get_profile(uid):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        return {
            "shields_available": p.shields_available,
            "current_streak": p.current_streak,
            "longest_streak": p.longest_streak,
            "last_qualifying_date": p.last_qualifying_date,
            "streak_recovery_deadline_at": p.streak_recovery_deadline_at,
            "streak_recovery_ad_progress": p.streak_recovery_ad_progress,
        }


@pytest.fixture(autouse=True)
def _fresh_minute_guard():
    replan_ai._RECENT.clear()
    yield
    replan_ai._RECENT.clear()


# ── 1. Replan Shield Enforcement ─────────────────────────────────────────────

@pytest.mark.asyncio
async def test_replan_with_zero_shields_is_refused_with_403_before_calling_gemini(monkeypatch):
    called = []

    def answer(prompt):
        called.append(prompt)
        return ops(op("cancel_task", ref(prompt, "Going out")))

    Model(monkeypatch, answer)
    uid, h = make_user()
    _day(uid)

    async with client() as ac:
        # Initialize flow profile then set shields to 0
        await ac.get("/api/v1/flow/overview", headers=h)
        _set_profile(uid, shields_available=0)

        # Attempt AI Replan
        res = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
        assert res.status_code == 403
        data = res.json()
        assert "insufficient_shields" in str(data)

        # Gemini model was NEVER called
        assert len(called) == 0

        # Shields balance remained 0
        p = _get_profile(uid)
        assert p["shields_available"] == 0


@pytest.mark.asyncio
async def test_replan_with_available_shields_charges_one_shield(monkeypatch):
    def answer(prompt):
        return ops(op("cancel_task", ref(prompt, "Going out")))

    Model(monkeypatch, answer)
    uid, h = make_user()
    _day(uid)

    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        _set_profile(uid, shields_available=2)

        res = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
        assert res.status_code == 200

        # Exactly 1 Shield was deducted
        p = _get_profile(uid)
        assert p["shields_available"] == 1


# ── 2. Daily Streak Progression on Task Completion ──────────────────────────

@pytest.mark.asyncio
async def test_task_completion_streak_progression():
    uid, h = make_user()

    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)

        # Create two tasks for the user
        t1_res = await ac.post("/api/v1/tasks", headers=h, json={"title": "Task 1", "estimated_minutes": 30})
        assert t1_res.status_code == 201
        t1_id = t1_res.json()["id"]

        t2_res = await ac.post("/api/v1/tasks", headers=h, json={"title": "Task 2", "estimated_minutes": 25})
        assert t2_res.status_code == 201
        t2_id = t2_res.json()["id"]

        # Day 1: Complete Task 1 -> Streak becomes 1
        c1 = await ac.post(f"/api/v1/tasks/{t1_id}/complete", headers=h, json={})
        assert c1.status_code == 200

        p1 = _get_profile(uid)
        assert p1["current_streak"] == 1
        assert p1["last_qualifying_date"] is not None

        # Completing Task 2 on the same day counts as only 1 streak day (no duplicate increment)
        c2 = await ac.post(f"/api/v1/tasks/{t2_id}/complete", headers=h, json={})
        assert c2.status_code == 200

        p2 = _get_profile(uid)
        assert p2["current_streak"] == 1

        # Simulate consecutive day (Day 2): set last_qualifying_date to yesterday in user's timezone
        today_local = datetime.now(timezone.utc).astimezone(IST).date()
        yesterday_str = (today_local - timedelta(days=1)).strftime("%Y-%m-%d")
        _set_profile(uid, last_qualifying_date=yesterday_str, current_streak=1)

        # Create and complete Task 3 today -> Streak increments to Day 2
        t3_res = await ac.post("/api/v1/tasks", headers=h, json={"title": "Task 3", "estimated_minutes": 20})
        assert t3_res.status_code == 201
        t3_id = t3_res.json()["id"]

        c3 = await ac.post(f"/api/v1/tasks/{t3_id}/complete", headers=h, json={})
        assert c3.status_code == 200

        p3 = _get_profile(uid)
        assert p3["current_streak"] == 2


# ── 3. 7-Hour Streak Recovery Window ─────────────────────────────────────────

@pytest.mark.asyncio
async def test_7_hour_recovery_window_persistence_and_restore():
    uid, h = make_user()

    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)

        # Set up a broken streak: 2 days missed
        today_local = datetime.now(timezone.utc).astimezone(IST).date()
        broken_date = (today_local - timedelta(days=3)).strftime("%Y-%m-%d")
        _set_profile(uid, current_streak=5, longest_streak=5, last_qualifying_date=broken_date,
                     shields_available=2, streak_recovery_deadline_at=None)

        # First read: starts the 7-hour recovery countdown
        rec1 = await ac.get("/api/v1/flow/streak/recovery", headers=h)
        assert rec1.status_code == 200
        d1 = rec1.json()
        assert d1["eligible"] is True
        assert d1["expired"] is False
        assert d1["streak"] == 5
        assert d1["seconds_remaining"] > 6 * 3600  # approximately 7 hours remaining
        assert d1["deadline_at"] is not None
        deadline_str = d1["deadline_at"]

        # Second read: countdown persists, deadline does NOT reset
        rec2 = await ac.get("/api/v1/flow/streak/recovery", headers=h)
        assert rec2.status_code == 200
        d2 = rec2.json()
        assert d2["deadline_at"] == deadline_str

        # Option A: Restore with 1 Shield
        restore_res = await ac.post("/api/v1/flow/streak/restore", headers=h, json={
            "idempotency_key": "restore-test-key-12345",
            "expected_cost": 1,
            "restore_method": "shield",
        })
        assert restore_res.status_code == 200
        restored = restore_res.json()
        assert restored["restored"] is True
        assert restored["current_streak"] == 5
        assert restored["shields_spent"] == 1
        assert restored["shields_available"] == 1

        # Profile is restored and recovery window is cleared
        p = _get_profile(uid)
        assert p["current_streak"] == 5
        assert p["shields_available"] == 1
        assert p["streak_recovery_deadline_at"] is None


@pytest.mark.asyncio
async def test_recovery_window_expiration_blocks_restore():
    uid, h = make_user()

    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)

        # Set a broken streak where the 7-hour window has already passed
        today_local = datetime.now(timezone.utc).astimezone(IST).date()
        broken_date = (today_local - timedelta(days=3)).strftime("%Y-%m-%d")
        expired_deadline = datetime.now(timezone.utc) - timedelta(hours=1)

        _set_profile(uid, current_streak=5, longest_streak=5, last_qualifying_date=broken_date,
                     shields_available=2, streak_recovery_deadline_at=expired_deadline)

        # Query recovery: reports expired
        rec = await ac.get("/api/v1/flow/streak/recovery", headers=h)
        assert rec.status_code == 200
        d = rec.json()
        assert d["eligible"] is False
        assert d["expired"] is True
        assert d["seconds_remaining"] == 0

        # Attempt to restore: rejected with 409 conflict
        restore_res = await ac.post("/api/v1/flow/streak/restore", headers=h, json={
            "idempotency_key": "restore-expired-test-key",
            "expected_cost": 1,
            "restore_method": "shield",
        })
        assert restore_res.status_code == 409
        assert "expired" in restore_res.json()["detail"].lower()

        # Shields were NOT charged
        p = _get_profile(uid)
        assert p["shields_available"] == 2
        # Broken streak reset to 0
        assert p["current_streak"] == 0
