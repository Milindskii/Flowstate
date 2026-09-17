import pytest
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token

@pytest.fixture
def auth_headers():
    token = create_access_token({"sub": "user-task-tester-1", "email": "tester@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_create_and_get_task(auth_headers):
    deadline = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    task_payload = {
        "title": "Finish ML Assignment",
        "description": "Implement neural net backpropagation",
        "category": "College",
        "task_type": "deep_work",
        "difficulty": "high",
        "priority": "high",
        "estimated_minutes": 90,
        "deadline_at": deadline,
        "source": "manual",
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Create
        create_res = await ac.post("/api/v1/tasks", headers=auth_headers, json=task_payload)
        assert create_res.status_code == 201
        created = create_res.json()
        task_id = created["id"]
        assert created["title"] == "Finish ML Assignment"
        assert created["status"] == "todo"
        assert created["estimated_minutes"] == 90
        assert created["task_type"] == "deep_work"
        assert created["deadline_at"] is not None

        # 2. Get Single
        get_res = await ac.get(f"/api/v1/tasks/{task_id}", headers=auth_headers)
        assert get_res.status_code == 200
        assert get_res.json()["id"] == task_id

@pytest.mark.asyncio
async def test_patch_task(auth_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create
        c_res = await ac.post("/api/v1/tasks", headers=auth_headers, json={"title": "Draft Outline", "estimated_minutes": 30})
        task_id = c_res.json()["id"]

        # Partial update with PATCH
        patch_res = await ac.patch(
            f"/api/v1/tasks/{task_id}",
            headers=auth_headers,
            json={"difficulty": "high", "estimated_minutes": 60}
        )
        assert patch_res.status_code == 200
        patched = patch_res.json()
        assert patched["difficulty"] == "high"
        assert patched["estimated_minutes"] == 60
        assert patched["title"] == "Draft Outline" # Unchanged

@pytest.mark.asyncio
async def test_start_and_complete_task_lifecycle(auth_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create
        c_res = await ac.post("/api/v1/tasks", headers=auth_headers, json={"title": "Workout Session", "task_type": "physical"})
        task_id = c_res.json()["id"]

        # Start task
        start_res = await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        assert start_res.status_code == 200
        started = start_res.json()
        assert started["status"] == "in_progress"
        assert started["started_at"] is not None

        # Complete task
        complete_res = await ac.post(
            f"/api/v1/tasks/{task_id}/complete",
            headers=auth_headers,
            json={"actual_minutes": 55}
        )
        assert complete_res.status_code == 200
        completed = complete_res.json()
        assert completed["status"] == "completed"
        assert completed["completed_at"] is not None

@pytest.mark.asyncio
async def test_paginated_task_list(auth_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        list_res = await ac.get("/api/v1/tasks?limit=10&offset=0", headers=auth_headers)
        assert list_res.status_code == 200
        data = list_res.json()
        assert "items" in data
        assert "total" in data
        assert isinstance(data["items"], list)
        assert data["limit"] == 10

@pytest.mark.asyncio
async def test_ai_task_parse_endpoint(auth_headers):
    raw_dump = "Finish ML assignment by tomorrow night 90m; Reply to professor emails 20m; Gym upper body 1 hr"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": raw_dump})
        assert res.status_code == 200
        candidates = res.json()
        assert len(candidates) == 3
        assert candidates[0]["estimated_minutes"] == 90
        assert candidates[0]["task_type"] == "deep_work"
        assert candidates[1]["task_type"] == "admin"
        assert candidates[2]["task_type"] == "physical"
