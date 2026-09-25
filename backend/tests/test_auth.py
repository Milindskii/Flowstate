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

@pytest.mark.asyncio
async def test_get_delete_account_page():
    """Verify Google Play compliant external web deletion portal renders properly"""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/delete-account")
    assert res.status_code == 200
    assert "Account & Data Deletion Portal" in res.text
    assert "Google Play User Data Compliance" in res.text
    assert 'action="/delete-account"' in res.text

@pytest.mark.asyncio
async def test_post_delete_account_web_authenticated():
    """Verify authenticated web deletion request purges account and returns confirmation page"""
    token = create_access_token({"sub": "web-delete-user-id", "email": "delete-me@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create user via authenticated endpoint
        me_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res.status_code == 200

        # Submit external web deletion form with valid authentication
        form_data = "email=delete-me@flowstate.local&confirm=on"
        del_headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        del_res = await ac.post("/delete-account", content=form_data, headers=del_headers)
        assert del_res.status_code == 200
        assert "Account &amp; Data Purged" in del_res.text
        assert "delete-me@flowstate.local" in del_res.text

@pytest.mark.asyncio
async def test_post_delete_account_web_unauthenticated_protects_user():
    """Verify unauthenticated external deletion request does NOT delete user and requires verification"""
    token = create_access_token({"sub": "victim-user-id", "email": "victim@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # User exists
        me_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res.status_code == 200

        # Attacker submits victim's email without token
        form_data = "email=victim@flowstate.local&confirm=on"
        del_res = await ac.post(
            "/delete-account",
            content=form_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        assert del_res.status_code == 200
        assert "Verification Required" in del_res.text
        assert "victim@flowstate.local" in del_res.text

        # Verify victim user still exists and was not maliciously wiped
        verify_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert verify_res.status_code == 200
        assert verify_res.json()["email"] == "victim@flowstate.local"

@pytest.mark.asyncio
async def test_deactivate_and_reactivate_account():
    """Verify distinct account deactivation and reactivation workflows"""
    token = create_access_token({"sub": "deactivate-user-id", "email": "deactivate@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Create user
        me_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res.status_code == 200

        # Deactivate
        deact_res = await ac.post("/api/v1/auth/deactivate", headers=headers)
        assert deact_res.status_code == 200
        assert deact_res.json()["status"] == "deactivated"

        # Calling normal authenticated endpoints returns 403 Forbidden (deactivated)
        blocked_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert blocked_res.status_code == 403
        assert "deactivated" in blocked_res.json()["detail"].lower()

        # Reactivate
        react_res = await ac.post("/api/v1/auth/reactivate", headers=headers)
        assert react_res.status_code == 200
        assert react_res.json()["status"] == "active"

        # Now active again
        restored_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert restored_res.status_code == 200

@pytest.mark.asyncio
async def test_submit_privacy_grievance():
    """Verify transparent grievance submission without false SLA promises"""
    token = create_access_token({"sub": "grievance-user-id", "email": "grievance@flowstate.local"})
    headers = {"Authorization": f"Bearer {token}"}

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        payload = {
            "request_type": "access",
            "message": "I would like clarification on the data stored for my circadian rhythm.",
        }
        res = await ac.post("/api/v1/auth/grievance", headers=headers, json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "received"
        assert "Milindkrishnan24@gmail.com" in data["contact_email"]
        assert "applicable law" in data["message"].lower()
        assert data["ticket_id"] is not None


