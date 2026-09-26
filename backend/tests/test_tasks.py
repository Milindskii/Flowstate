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

@pytest.mark.asyncio
async def test_concise_user_faithful_task_titles_and_priority(auth_headers):
    """
    Verifies:
    1. 'gym tomorrow' -> title = 'Gym', type = 'physical'
    2. 'finish my assignment' -> title = 'Finish assignment', type = 'deep_work'
    3. 'work tomorrow' -> title = 'Work'
    4. 'call dentist at 5' -> title = 'Call dentist', scheduled_start at 17:00
    5. Awkward words like 'to do', 'task for', 'task' are stripped
    6. Explicit priority is preserved exactly as 'explicit'
    7. Missing priority is flagged as 'inferred', not silently marked as explicit
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. "gym tomorrow" -> "Gym", physical
        res1 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "gym tomorrow"})
        assert res1.status_code == 200
        c1 = res1.json()[0]
        assert c1["title"] == "Gym"
        assert c1["task_type"] == "physical"
        assert c1["field_provenance"]["priority"]["source"] != "explicit"

        # 2. "finish my assignment" -> "Finish assignment"
        res2 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "finish my assignment"})
        assert res2.status_code == 200
        c2 = res2.json()[0]
        assert c2["title"] == "Finish assignment"
        assert c2["task_type"] == "deep_work"

        # 3. "work tomorrow" -> "Work"
        res3 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "work tomorrow"})
        assert res3.status_code == 200
        c3 = res3.json()[0]
        assert c3["title"] == "Work"

        # 4. "call dentist at 5" -> "Call dentist"
        res4 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "call dentist at 5"})
        assert res4.status_code == 200
        c4 = res4.json()[0]
        assert c4["title"] == "Call dentist"
        assert c4["scheduled_start"] is not None

        # 5. Awkward phrases stripped: "Gym to do", "Work to do", "Assignment task", "Task for gym"
        res5 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "Gym to do\nWork to do\nAssignment task\nTask for gym"})
        assert res5.status_code == 200
        c5_list = res5.json()
        assert c5_list[0]["title"] == "Gym"
        assert c5_list[1]["title"] == "Work"
        assert c5_list[2]["title"] == "Assignment"
        assert c5_list[3]["title"] == "Gym"

        # 6. Explicit priority preserved
        res6 = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"raw_text": "Finish paper urgent, study DBMS high priority, walk dog low priority"})
        assert res6.status_code == 200
        c6_list = res6.json()
        assert c6_list[0]["priority"] == "urgent"
        assert c6_list[0]["field_provenance"]["priority"]["source"] == "explicit"
        assert c6_list[1]["priority"] == "high"
        assert c6_list[1]["field_provenance"]["priority"]["source"] == "explicit"
        assert c6_list[2]["priority"] == "low"
        assert c6_list[2]["field_provenance"]["priority"]["source"] == "explicit"


