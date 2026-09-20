import pytest
import uuid
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token
from app.core.config import settings
from app.db.session import SessionLocal
from app.models.user import User
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
        # Must not fabricate readiness score
        assert data["readiness"]["score"] is None
        assert data["readiness"]["is_calibrated"] is False
        assert data["readiness"]["confidence"] == 0.0
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION
        assert data["readiness"]["status_message"] == "Learning your rhythm"
        assert data["readiness"]["explanation"] == "We're still learning when you work best."

        # Workload and AI Brief
        assert data["workload_summary"]["planned_minutes"] == 0
        assert data["workload_summary"]["message"] == "Let's build your day."
        assert data["ai_brief"]["title"] == "FLOWSTATE"
        assert "haven't planned" in data["ai_brief"]["message"]
        assert data["current_recommendation"] is None

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
        assert data["readiness"]["score"] is None
        assert data["readiness"]["is_calibrated"] is False
        assert data["readiness"]["confidence"] == 0.0
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION

        # Deterministic recommendation
        assert data["current_recommendation"] is not None
        assert data["current_recommendation"]["task"]["title"] == "Implement Transformer Model"
        assert len(data["current_recommendation"]["reasons"]) == 3

        # Deterministic AI Brief template without LLM
        assert data["ai_brief"]["title"] == "FLOWSTATE"
        assert "1 important tasks today" in data["ai_brief"]["message"]
        assert "Implement Transformer Model" in data["ai_brief"]["message"]
        assert data["ai_brief"]["action_label"] == "Use this plan"

        # Workload summary
        assert data["workload_summary"]["planned_minutes"] == 75
        assert data["workload_summary"]["is_overloaded"] is False

@pytest.mark.asyncio
async def test_today_calibrated_state(unique_user_headers):
    headers = unique_user_headers["headers"]
    user_id = unique_user_headers["user_id"]

    # Insert 30 completed performance sessions
    db = SessionLocal()
    for i in range(settings.CALIBRATION_MIN_SESSIONS):
        perf = TaskPerformance(
            id=f"perf-{user_id}-{i}",
            task_id=f"task-dummy-{i}",
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
        assert data["readiness"]["score"] == 78
        assert data["readiness"]["is_calibrated"] is True
        assert data["readiness"]["confidence"] >= 0.70
        assert data["readiness"]["model_version"] == settings.READINESS_MODEL_VERSION
        assert len(data["readiness"]["factors"]) > 0
        assert len(data["readiness"]["hourly_rhythm"]) == 7
