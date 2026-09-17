import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token

@pytest.mark.asyncio
async def test_auth_me_unauthorized():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/api/v1/auth/me")
    assert response.status_code == 401

@pytest.mark.asyncio
async def test_auth_me_with_jwt():
    token = create_access_token({"sub": "user-supabase-123", "email": "alex@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/api/v1/auth/me", headers=headers)

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == "user-supabase-123"
    assert data["email"] == "alex@flowstate.local"
    assert data["preferences"]["timezone"] == "Asia/Kolkata"

@pytest.mark.asyncio
async def test_update_user_preferences():
    token = create_access_token({"sub": "user-pref-test", "email": "pref@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        patch_res = await ac.patch(
            "/api/v1/auth/preferences",
            headers=headers,
            json={"timezone": "America/New_York", "focus_peak": "afternoon"}
        )
    assert patch_res.status_code == 200
    data = patch_res.json()
    assert data["timezone"] == "America/New_York"
    assert data["focus_peak"] == "afternoon"
