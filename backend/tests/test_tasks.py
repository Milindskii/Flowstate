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

@pytest.mark.asyncio
async def test_compound_natural_language_parsing_with_provenance(auth_headers):
    # The exact acceptance test prompt:
    raw_prompt = "Finish ML assignment tomorrow, study DBMS for one hour, and go to gym at 6"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": raw_prompt})
        assert res.status_code == 200
        candidates = res.json()
        assert len(candidates) == 3

        # Candidate 1: "Finish ML assignment tomorrow"
        c1 = candidates[0]
        assert "Finish ML assignment" in c1["title"]
        assert c1["task_type"] == "deep_work"
        assert c1["difficulty"] == "high"
        assert c1["priority"] == "high"
        assert c1["deadline_at"] is not None
        assert c1["confidence"] >= 0.7
        assert c1["field_provenance"]["deadline"]["source"] == "explicit"
        assert c1["field_provenance"]["task_type"]["source"] == "inferred"

        # Candidate 2: "study DBMS for one hour"
        c2 = candidates[1]
        assert "Study DBMS" in c2["title"]
        assert c2["estimated_minutes"] == 60
        assert c2["task_type"] == "study"
        assert c2["difficulty"] == "medium"
        assert c2["field_provenance"]["duration"]["source"] == "explicit"

        # Candidate 3: "and go to gym at 6"
        c3 = candidates[2]
        assert "gym" in c3["title"].lower()
        assert c3["task_type"] == "physical"
        assert c3["difficulty"] == "physical"
        assert c3["scheduled_start"] is not None
        # Must track ambiguity for bare time number without AM/PM
        assert "time_am_pm" in c3["ambiguities"]
        assert c3["field_provenance"]["scheduled_time"]["source"] == "inferred"
        assert c3["field_provenance"]["scheduled_time"]["confidence"] == 0.70

@pytest.mark.asyncio
async def test_missing_fields_no_llm_call(auth_headers):
    # Parsing failure != parsing ambiguity. Should NOT fail or require LLM for "study tomorrow"
    raw = "study tomorrow"

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": raw})
        assert res.status_code == 200
        candidates = res.json()
        assert len(candidates) == 1
        c = candidates[0]
        assert "Study" in c["title"]
        assert "duration" in c["missing_fields"]
        assert c["estimated_minutes"] == 45  # Default duration applied
        assert c["field_provenance"]["duration"]["source"] == "default"
        assert c["field_provenance"]["duration"]["confidence"] == 0.50

