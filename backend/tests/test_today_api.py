"""
Tests for the Today aggregated endpoint.

Updated assertions to match real ReadinessEngineV2 output and
GenericRecommendationEngine scoring (no more hardcoded score=78, 
no more "Overdue task" exact string — engine now uses "Overdue — needs attention now").
"""
import pytest
import uuid
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token
from app.core.config import settings
from app.db.session import SessionLocal
from app.models.user import User
from app.models.task import Task, TaskStatus
from app.models.task_performance import TaskPerformance

@pytest.fixture
def unique_user_headers():
    user_id = f"user-today-{uuid.uuid4().hex[:8]}"
    email = f"{user_id}@flowstate.local"
    # Ensure user exists in db
    db = SessionLocal()
    user = User(id=user_id, email=email, name="Test Runner")
    db.add(user)
    db.commit()
    db.close()

    token = create_access_token({"sub": user_id, "email": email})
    return {"headers": {"Authorization": f"Bearer {token}"}, "user_id": user_id}

@pytest.mark.asyncio
async def test_today_new_user_state(unique_user_headers):
    headers = unique_user_headers["headers"]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/today", headers=headers)
        assert res.status_code == 200
        data = res.json()

        assert data["lifecycle_state"] == "new_user"
        # Must not fabricate readiness score for new users
        assert data["readiness"]["score"] is None
        assert data["readiness"]["is_calibrated"] is False
        assert data["readiness"]["confidence"] == 0.0
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION
        assert data["readiness"]["status_message"] == "Learning your rhythm"
        # Explanation now describes the learning state honestly
        assert "rhythm" in data["readiness"]["explanation"].lower()

        # Workload and AI Brief
        assert data["workload_summary"]["planned_minutes"] == 0
        assert data["workload_summary"]["message"] == "Let's build your day."
        assert data["ai_brief"]["title"] == "FLOWSTATE"
        assert "haven't planned" in data["ai_brief"]["message"]
        assert data["current_recommendation"] is None
        assert data["upcoming_timeline"] == []

@pytest.mark.asyncio
async def test_today_learning_state_with_task(unique_user_headers):
    headers = unique_user_headers["headers"]
    user_id = unique_user_headers["user_id"]

    deadline = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    task_payload = {
        "title": "Implement Transformer Model",
        "description": "Attention mechanisms",
        "category": "Study",
        "task_type": "deep_work",
        "difficulty": "high",
        "priority": "high",
        "estimated_minutes": 75,
        "deadline_at": deadline,
        "scheduled_start": datetime.now(timezone.utc).isoformat(),
        "source": "manual",
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create a task for today
        c_res = await ac.post("/api/v1/tasks", headers=headers, json=task_payload)
        assert c_res.status_code == 201

        res = await ac.get("/api/v1/today", headers=headers)
        assert res.status_code == 200
        data = res.json()

        assert data["lifecycle_state"] == "learning"

        # Learning state: readiness engine returns a real score (not None) even at learning stage
        # because ReadinessEngineV2 computes a Stage A prior from profile
        assert data["readiness"]["is_calibrated"] is False
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION

        # Deterministic recommendation from engine
        assert data["current_recommendation"] is not None
        assert data["current_recommendation"]["task"]["title"] == "Implement Transformer Model"
        assert len(data["current_recommendation"]["reasons"]) >= 1

        # Decision should be logged and returned
        assert data["decision_id"] is not None

        # AI Brief is time-aware (not hardcoded phrases)
        assert data["ai_brief"]["title"] == "FLOWSTATE"
        assert "Implement Transformer Model" in data["ai_brief"]["message"]
        assert data["ai_brief"]["action_label"] == "Use this plan"

        # Workload summary
        assert data["workload_summary"]["planned_minutes"] == 75
        assert data["workload_summary"]["is_overloaded"] is False

@pytest.mark.asyncio
async def test_today_calibrated_state(unique_user_headers):
    headers = unique_user_headers["headers"]
    user_id = unique_user_headers["user_id"]

    # Insert enough completed performance sessions to reach calibrated state
    db = SessionLocal()
    long_ago = datetime.now(timezone.utc) - timedelta(days=30)
    for i in range(settings.CALIBRATION_MIN_SESSIONS):
        # task_performance.task_id is a real foreign key: each session belongs to a (long finished) task.
        db.add(Task(id=f"task-dummy-{user_id}-{i}", user_id=user_id, title=f"Past task {i}", estimated_minutes=45,
                    status=TaskStatus.completed, planned_date=long_ago.date(), completed_at=long_ago))
    db.flush()
    for i in range(settings.CALIBRATION_MIN_SESSIONS):
        perf = TaskPerformance(
            id=f"perf-{user_id}-{i}",
            task_id=f"task-dummy-{user_id}-{i}",
            user_id=user_id,
            estimated_minutes=45,
            actual_minutes=45,
            focus_score=5,
            energy_score=4,
            difficulty_score=3,
            distraction_score=1,
        )
        db.add(perf)
    db.commit()
    db.close()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/today", headers=headers)
        assert res.status_code == 200
        data = res.json()

        assert data["lifecycle_state"] == "calibrated"
        # Score is now a real ReadinessEngineV2 output (not hardcoded 78)
        assert data["readiness"]["score"] is not None
        assert 0 <= data["readiness"]["score"] <= 100
        assert data["readiness"]["is_calibrated"] is True
        assert data["readiness"]["confidence"] > 0.0
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION
        assert len(data["readiness"]["factors"]) > 0
        # Hourly rhythm is now computed from profile (8 points: 6a through 8p)
        assert len(data["readiness"]["hourly_rhythm"]) == 8

@pytest.mark.asyncio
async def test_today_includes_overdue_tasks(unique_user_headers):
    headers = unique_user_headers["headers"]
    user_id = unique_user_headers["user_id"]

    # Deadline was yesterday (overdue)
    overdue_deadline = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    task_payload = {
        "title": "Finish Assignment Yesterday",
        "category": "Study",
        "task_type": "deep_work",
        "difficulty": "high",
        "priority": "high",
        "estimated_minutes": 60,
        "deadline_at": overdue_deadline,
        "source": "manual",
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        c_res = await ac.post("/api/v1/tasks", headers=headers, json=task_payload)
        assert c_res.status_code == 201

        res = await ac.get("/api/v1/today", headers=headers)
        assert res.status_code == 200
        data = res.json()

        # Overdue unfinished task MUST appear in today
        assert data["current_recommendation"] is not None
        assert data["current_recommendation"]["task"]["title"] == "Finish Assignment Yesterday"
        # Recommendation engine marks overdue tasks clearly
        reasons = data["current_recommendation"]["reasons"]
        assert any("overdue" in r.lower() or "attention" in r.lower() for r in reasons)

        # decision_id must be present
        assert data["decision_id"] is not None

@pytest.mark.asyncio
async def test_today_override_endpoint(unique_user_headers):
    """Test the POST /today/override endpoint records user decisions."""
    headers = unique_user_headers["headers"]

    # No deadline: "Later" must be able to book the next window. With a deadline 3 hours away the old code booked
    # tomorrow anyway, i.e. AFTER the deadline. That is now refused: the planner never violates a deadline
    # (tests/test_override_planner.py::test_later_never_places_a_task_after_its_deadline covers that case).
    task_payload = {
        "title": "Override Test Task",
        "category": "Work",
        "task_type": "deep_work",
        "difficulty": "medium",
        "priority": "medium",
        "estimated_minutes": 45,
        "source": "manual",
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.post("/api/v1/tasks", headers=headers, json=task_payload)

        # Get today to receive a decision_id
        today_res = await ac.get("/api/v1/today", headers=headers)
        assert today_res.status_code == 200
        today_data = today_res.json()
        decision_id = today_data.get("decision_id")
        assert decision_id is not None

        # Record a "later" override
        override_res = await ac.post(
            "/api/v1/today/override",
            headers=headers,
            json={"decision_id": decision_id, "reason": "later"},
        )
        assert override_res.status_code == 200
        override_data = override_res.json()
        assert override_data["recorded"] is True
        # Should suggest a next window for "later"
        assert override_data.get("next_window") is not None
        assert "label" in override_data["next_window"]


@pytest.mark.asyncio
async def test_today_later_updates_recommendation_to_another_task(unique_user_headers):
    """When a user presses Later on Task A, Task B becomes the current recommendation."""
    headers = unique_user_headers["headers"]

    deadline = (datetime.now(timezone.utc) + timedelta(hours=4)).isoformat()
    task_a = {
        "title": "Task Alpha (Original Top)",
        "category": "Work",
        "task_type": "deep_work",
        "difficulty": "high",
        "priority": "high",
        "estimated_minutes": 60,
        "deadline_at": deadline,
        "source": "manual",
    }
    task_b = {
        "title": "Task Beta (Alternative)",
        "category": "Work",
        "task_type": "deep_work",
        "difficulty": "medium",
        "priority": "medium",
        "estimated_minutes": 30,
        "deadline_at": deadline,
        "source": "manual",
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.post("/api/v1/tasks", headers=headers, json=task_a)
        await ac.post("/api/v1/tasks", headers=headers, json=task_b)

        # First Today request: Alpha should be top
        res1 = await ac.get("/api/v1/today", headers=headers)
        assert res1.status_code == 200
        d1 = res1.json()
        assert d1["current_recommendation"]["task"]["title"] == "Task Alpha (Original Top)"
        decision_id = d1["decision_id"]

        # User presses "Later" on Task Alpha
        later_res = await ac.post(
            "/api/v1/today/override",
            headers=headers,
            json={"decision_id": decision_id, "reason": "later"},
        )
        assert later_res.status_code == 200
        assert later_res.json()["recorded"] is True

        # Second Today request: Beta should now become top recommendation!
        res2 = await ac.get("/api/v1/today", headers=headers)
        assert res2.status_code == 200
        d2 = res2.json()
        assert d2["current_recommendation"]["task"]["title"] == "Task Beta (Alternative)"

