import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token

@pytest.fixture
def auth_headers():
    token = create_access_token({"sub": "user-perf-tester", "email": "perf@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_record_task_performance_feedback(auth_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Create and complete a task
        task_res = await ac.post("/api/v1/tasks", headers=auth_headers, json={"title": "Deep Code Session", "estimated_minutes": 60})
        task_id = task_res.json()["id"]

        await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=auth_headers, json={"actual_minutes": 65})

        # 2. Record post-session reflection feedback
        feedback_payload = {
            "actual_minutes": 65,
            "focus_score": 5,
            "energy_score": 4,
            "difficulty_score": 4,
            "distraction_score": 1,
            "notes": "Entered deep flow state around 20 minutes in."
        }

        fb_res = await ac.post(f"/api/v1/tasks/{task_id}/feedback", headers=auth_headers, json=feedback_payload)
        assert fb_res.status_code == 201
        data = fb_res.json()
        assert data["task_id"] == task_id
        assert data["focus_score"] == 5
        assert data["energy_score"] == 4
        assert data["notes"] == "Entered deep flow state around 20 minutes in."
