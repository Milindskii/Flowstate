import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token

@pytest.fixture
def user_a_headers():
    token = create_access_token({"sub": "user-alice-uuid", "email": "alice@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture
def user_b_headers():
    token = create_access_token({"sub": "user-bob-uuid", "email": "bob@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_strict_user_isolation_returns_404_on_all_operations(user_a_headers, user_b_headers):
    """
    Ensures that when User B attempts to view or mutate User A's task,
    the API returns strictly HTTP 404 Not Found (never 403) across all endpoints,
    preventing ID enumeration and unauthorized access.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. User A creates a task
        create_res = await ac.post(
            "/api/v1/tasks",
            headers=user_a_headers,
            json={"title": "Alice Private Research", "estimated_minutes": 60}
        )
        assert create_res.status_code == 201
        alice_task_id = create_res.json()["id"]

        # 2. User B tries GET -> 404
        get_res = await ac.get(f"/api/v1/tasks/{alice_task_id}", headers=user_b_headers)
        assert get_res.status_code == 404

        # 3. User B tries PATCH -> 404
        patch_res = await ac.patch(
            f"/api/v1/tasks/{alice_task_id}",
            headers=user_b_headers,
            json={"title": "Hacked Title"}
        )
        assert patch_res.status_code == 404

        # 4. User B tries START -> 404
        start_res = await ac.post(f"/api/v1/tasks/{alice_task_id}/start", headers=user_b_headers)
        assert start_res.status_code == 404

        # 5. User B tries COMPLETE -> 404
        complete_res = await ac.post(f"/api/v1/tasks/{alice_task_id}/complete", headers=user_b_headers)
        assert complete_res.status_code == 404

        # 6. User B tries FEEDBACK -> 404
        feedback_res = await ac.post(
            f"/api/v1/tasks/{alice_task_id}/feedback",
            headers=user_b_headers,
            json={"focus_score": 5}
        )
        assert feedback_res.status_code == 404

        # 7. User B tries DELETE -> 404
        del_res = await ac.delete(f"/api/v1/tasks/{alice_task_id}", headers=user_b_headers)
        assert del_res.status_code == 404

        # Verify Alice's task was never altered or deleted
        alice_check = await ac.get(f"/api/v1/tasks/{alice_task_id}", headers=user_a_headers)
        assert alice_check.status_code == 200
        assert alice_check.json()["title"] == "Alice Private Research"

@pytest.mark.asyncio
async def test_onboarding_and_today_user_isolation(user_a_headers, user_b_headers):
    """
    Ensures User A and User B maintain completely isolated readiness profiles,
    task lists, and today plans. User B never receives User A's data.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. User A submits onboarding questionnaire
        a_onboarding = {
            "preferred_peak_start": "06:30",
            "preferred_peak_end": "09:00",
            "weekday_wake_time": "05:30",
            "weekend_wake_time": "07:00",
            "bedtime": "22:00",
            "sleep_inertia_minutes": 20,
            "draining_work_types": ["Deep code"],
            "primary_goal": "focus_early",
            "energy_predictability": "mostly_predictable",
            "timezone": "America/New_York",
        }
        res_a = await ac.post("/api/v1/readiness/onboarding", headers=user_a_headers, json=a_onboarding)
        assert res_a.status_code == 201
        data_a = res_a.json()
        assert data_a["preferred_peak_start"] == "06:30"
        assert "starting_rhythm" in data_a
        assert data_a["starting_rhythm"]["focus_window_range"] == "06:30 – 09:00"

        # 2. User B requests their profile -> User B must NOT receive User A's profile
        res_b_profile = await ac.get("/api/v1/readiness/profile", headers=user_b_headers)
        assert res_b_profile.status_code == 200
        data_b = res_b_profile.json()
        assert data_b["user_id"] == "user-bob-uuid"
        assert data_b["preferred_peak_start"] != "06:30" # Default is 09:30, not Alice's 06:30

        # 3. User A has task, User B today tasks list is completely empty
        today_b = await ac.get("/api/v1/tasks/today", headers=user_b_headers)
        assert today_b.status_code == 200
        assert len(today_b.json()) == 0

