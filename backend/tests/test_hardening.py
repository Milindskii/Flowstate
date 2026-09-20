import pytest
from datetime import datetime, timezone, timedelta
from fastapi import status
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.core.config import settings
from app.core.security import create_access_token, verify_security_environment
from app.models.task import Task, TaskStatus, TaskType, TaskDifficulty, TaskPriority
from app.models.task_performance import TaskPerformance
from app.db.session import get_db

@pytest.fixture
def auth_headers():
    token = create_access_token({"sub": "hardening-user-1", "email": "hardening@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

def test_production_fail_closed_guard(monkeypatch):
    """
    Ensures that if DEV_BYPASS_AUTH is True while ENVIRONMENT is production,
    the application fail-closed check immediately raises RuntimeError.
    """
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(settings, "DEV_BYPASS_AUTH", True)

    with pytest.raises(RuntimeError) as exc_info:
        verify_security_environment()

    assert "CRITICAL SECURITY VIOLATION" in str(exc_info.value)

@pytest.mark.asyncio
async def test_soft_delete_preserves_task_performance(auth_headers):
    """
    Verifies that DELETE /tasks/{id} soft-deletes (archives) the task by default
    and preserves all associated TaskPerformance records.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Create a task
        create_res = await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Preserve My History Task",
            "estimated_minutes": 45,
        })
        assert create_res.status_code == status.HTTP_201_CREATED
        task_id = create_res.json()["id"]

        # 2. Complete and log performance feedback
        await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=auth_headers)
        fb_res = await ac.post(f"/api/v1/tasks/{task_id}/feedback", headers=auth_headers, json={
            "actual_minutes": 50,
            "focus_score": 5,
            "energy_score": 4,
            "difficulty_score": 3,
            "notes": "Valuable ML training signal",
        })
        assert fb_res.status_code == status.HTTP_201_CREATED

        # 3. Perform standard user deletion
        del_res = await ac.delete(f"/api/v1/tasks/{task_id}", headers=auth_headers)
        assert del_res.status_code == status.HTTP_204_NO_CONTENT

        # 4. Check that regular list ignores it
        list_res = await ac.get("/api/v1/tasks", headers=auth_headers)
        active_ids = [t["id"] for t in list_res.json()["items"]]
        assert task_id not in active_ids

        # 5. Check direct fetch: task is archived (not destroyed)
        archived_task = (await ac.get(f"/api/v1/tasks/{task_id}", headers=auth_headers)).json()
        assert archived_task["status"] == "archived"

        # 6. Verify in DB session that TaskPerformance record is fully intact
        db = next(get_db())
        perf = db.query(TaskPerformance).filter(TaskPerformance.task_id == task_id).first()
        assert perf is not None
        assert perf.focus_score == 5
        assert perf.notes == "Valuable ML training signal"

@pytest.mark.asyncio
async def test_task_state_machine_transitions(auth_headers):
    """
    Verifies legal vs illegal task status transitions:
    - todo -> start (allowed)
    - in_progress -> start (idempotent)
    - in_progress -> complete (allowed)
    - completed -> complete (idempotent)
    - completed -> start (forbidden: 400)
    - cancelled -> start (forbidden: 400)
    - cancelled -> complete (forbidden: 400)
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create fresh task
        res = await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "State Machine Task",
        })
        task_id = res.json()["id"]

        # 1. Start task from todo -> in_progress
        start_res = await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        assert start_res.status_code == status.HTTP_200_OK
        assert start_res.json()["status"] == "in_progress"

        # 2. Idempotent start
        start_idem = await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        assert start_idem.status_code == status.HTTP_200_OK
        assert start_idem.json()["status"] == "in_progress"

        # 3. Complete task -> completed
        comp_res = await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=auth_headers)
        assert comp_res.status_code == status.HTTP_200_OK
        assert comp_res.json()["status"] == "completed"

        # 4. Idempotent complete
        comp_idem = await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=auth_headers)
        assert comp_idem.status_code == status.HTTP_200_OK

        # 5. Starting a completed task must be rejected with 400
        illegal_start = await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        assert illegal_start.status_code == status.HTTP_400_BAD_REQUEST
        assert "already been completed" in illegal_start.json()["detail"]

        # 6. Test cancelled task
        cancelled_res = await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Cancelled Task",
        })
        c_id = cancelled_res.json()["id"]
        await ac.patch(f"/api/v1/tasks/{c_id}", headers=auth_headers, json={"status": "cancelled"})

        illegal_c_start = await ac.post(f"/api/v1/tasks/{c_id}/start", headers=auth_headers)
        assert illegal_c_start.status_code == status.HTTP_400_BAD_REQUEST

        illegal_c_comp = await ac.post(f"/api/v1/tasks/{c_id}/complete", headers=auth_headers)
        assert illegal_c_comp.status_code == status.HTTP_400_BAD_REQUEST

@pytest.mark.asyncio
async def test_parse_endpoint_rate_limiting_and_bounds(auth_headers):
    """
    Tests input size validation and rate limiting on POST /tasks/parse.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Test too short input (<2 chars)
        short_res = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"text": "a"})
        assert short_res.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

        # 2. Test excessive length (>1500 chars)
        long_res = await ac.post("/api/v1/tasks/parse", headers=auth_headers, json={"text": "x" * 1501})
        assert long_res.status_code in (status.HTTP_422_UNPROCESSABLE_ENTITY, 400)

        # 3. Rate limiting test
        rate_headers = {"Authorization": f"Bearer {create_access_token({'sub': 'spammer-user'})}"}
        for i in range(10):
            ok_res = await ac.post("/api/v1/tasks/parse", headers=rate_headers, json={"text": f"Task number {i}"})
            assert ok_res.status_code == status.HTTP_200_OK

        # 11th request must be rejected with 429 Too Many Requests
        exceeded_res = await ac.post("/api/v1/tasks/parse", headers=rate_headers, json={"text": "Task overflow"})
        assert exceeded_res.status_code == status.HTTP_429_TOO_MANY_REQUESTS
        assert "Rate limit exceeded" in exceeded_res.json()["detail"]

@pytest.mark.asyncio
async def test_precise_today_semantics(auth_headers):
    """
    Crucial test:
    A task with deadline = Friday and scheduled = None should NOT appear in today's view on Monday.
    Only tasks scheduled today, or due today, or actively in progress should appear.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        now = datetime.now(timezone.utc)
        friday = now + timedelta(days=4)
        today_time = now
        tomorrow = now + timedelta(days=1)

        # Task 1: Deadline Friday, not scheduled -> MUST NOT appear today
        t1 = (await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Due Friday Task",
            "deadline_at": friday.isoformat(),
        })).json()

        # Task 2: Scheduled today -> MUST appear today
        t2 = (await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Scheduled Today Task",
            "scheduled_start": today_time.isoformat(),
        })).json()

        # Task 3: Deadline today, not scheduled elsewhere -> MUST appear today
        t3 = (await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Due Today Task",
            "deadline_at": today_time.isoformat(),
        })).json()

        # Task 4: Deadline today, but scheduled for tomorrow -> MUST NOT appear today
        t4 = (await ac.post("/api/v1/tasks", headers=auth_headers, json={
            "title": "Due Today But Pushed to Tomorrow",
            "deadline_at": today_time.isoformat(),
            "scheduled_start": tomorrow.isoformat(),
        })).json()

        today_res = await ac.get("/api/v1/tasks/today", headers=auth_headers)
        assert today_res.status_code == status.HTTP_200_OK
        today_ids = [t["id"] for t in today_res.json()]

        assert t2["id"] in today_ids, "Task scheduled today must appear in today's list"
        assert t3["id"] in today_ids, "Task due today without future schedule must appear"
        assert t1["id"] not in today_ids, "Friday task must NEVER bleed into today's list!"
        assert t4["id"] not in today_ids, "Task scheduled for tomorrow must not appear today"

@pytest.mark.asyncio
async def test_flutter_e2e_contract_lifecycle(auth_headers):
    """
    Simulates the exact full mobile app lifecycle from Flutter:
    1. Flutter User creates task with TaskItem payload
    2. Flutter fetches today's tasks
    3. User clicks 'Start' -> transitions to in_progress
    4. User clicks 'Complete' -> transitions to completed
    5. User fills reflection sheet -> POST /feedback
    6. User deletes task -> soft-deleted / archived
    7. App refresh -> task removed from active view, performance signal preserved in DB
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        now = datetime.now(timezone.utc)
        today_start = now + timedelta(hours=1)

        # 1. Flutter TaskItem.toJson() creation payload
        flutter_task_payload = {
            "title": "Build Flowstate Mobile Feature",
            "description": "Full-stack integration verify",
            "category": "Work",
            "task_type": "deep_work",
            "difficulty": "high",
            "priority": "high",
            "estimated_minutes": 60,
            "scheduled_start": today_start.isoformat(),
        }
        res_create = await ac.post("/api/v1/tasks", headers=auth_headers, json=flutter_task_payload)
        assert res_create.status_code == status.HTTP_201_CREATED
        task_data = res_create.json()
        task_id = task_data["id"]
        assert task_data["status"] == "todo"

        # 2. Flutter loads today's tasks for dashboard
        res_today = await ac.get("/api/v1/tasks/today", headers=auth_headers)
        assert res_today.status_code == status.HTTP_200_OK
        today_tasks = res_today.json()
        assert any(t["id"] == task_id for t in today_tasks)

        # 3. User taps "Start" in "RIGHT NOW" card
        res_start = await ac.post(f"/api/v1/tasks/{task_id}/start", headers=auth_headers)
        assert res_start.status_code == status.HTTP_200_OK
        assert res_start.json()["status"] == "in_progress"
        assert res_start.json()["started_at"] is not None

        # 4. User completes focus session
        res_comp = await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=auth_headers, json={
            "actual_minutes": 55,
        })
        assert res_comp.status_code == status.HTTP_200_OK
        assert res_comp.json()["status"] == "completed"

        # 5. User submits post-session reflection sheet (FeedbackLog.toJson())
        flutter_feedback_payload = {
            "actual_minutes": 55,
            "focus_score": 5,
            "energy_score": 4,
            "difficulty_score": 4,
            "distraction_score": 1,
            "notes": "Entered deep flow state. Clean architecture!",
        }
        res_fb = await ac.post(f"/api/v1/tasks/{task_id}/feedback", headers=auth_headers, json=flutter_feedback_payload)
        assert res_fb.status_code == status.HTTP_201_CREATED
        fb_data = res_fb.json()
        assert fb_data["focus_score"] == 5
        assert fb_data["task_id"] == task_id

        # 6. User archives / deletes task from list
        res_del = await ac.delete(f"/api/v1/tasks/{task_id}", headers=auth_headers)
        assert res_del.status_code == status.HTTP_204_NO_CONTENT

        # 7. App reopens / refreshes:
        # Active today tasks must not include the archived task
        res_today_refreshed = await ac.get("/api/v1/tasks/today", headers=auth_headers)
        assert not any(t["id"] == task_id for t in res_today_refreshed.json())

        # General task list must not include archived task
        res_list_refreshed = await ac.get("/api/v1/tasks", headers=auth_headers)
        assert not any(t["id"] == task_id for t in res_list_refreshed.json()["items"])

        # Direct database query verifies training data was preserved
        db = next(get_db())
        perf_records = db.query(TaskPerformance).filter(TaskPerformance.task_id == task_id).all()
        assert len(perf_records) == 1
        assert perf_records[0].actual_minutes == 55
        assert perf_records[0].focus_score == 5

