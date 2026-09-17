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
