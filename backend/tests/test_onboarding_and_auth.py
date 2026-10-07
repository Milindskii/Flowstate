import pytest
import uuid
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_access_token

@pytest.fixture
def unique_new_user_a():
    uid = f"user-a-{uuid.uuid4().hex[:8]}"
    email = f"{uid}@flowstate.local"
    token = create_access_token({"sub": uid, "email": email})
    return {"headers": {"Authorization": f"Bearer {token}"}, "user_id": uid, "email": email}

@pytest.fixture
def unique_new_user_b():
    uid = f"user-b-{uuid.uuid4().hex[:8]}"
    email = f"{uid}@flowstate.local"
    token = create_access_token({"sub": uid, "email": email})
    return {"headers": {"Authorization": f"Bearer {token}"}, "user_id": uid, "email": email}

@pytest.mark.asyncio
async def test_brand_new_user_onboarding_is_false(unique_new_user_a):
    """
    Guarantees that a brand-new user has onboarding_completed == False.
    Calling /readiness/profile must NOT mutate onboarding_completed to True.
    """
    headers = unique_new_user_a["headers"]
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Fetch user profile -> must have onboarding_completed == False
        me_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res.status_code == 200
        me_data = me_res.json()
        assert me_data["onboarding_completed"] is False

        # 2. Fetch baseline readiness profile -> must not mutate user.onboarding_completed
        profile_res = await ac.get("/api/v1/readiness/profile", headers=headers)
        assert profile_res.status_code == 200

        # 3. Check /auth/me again -> MUST STILL BE FALSE
        me_res_2 = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res_2.status_code == 200
        assert me_res_2.json()["onboarding_completed"] is False

@pytest.mark.asyncio
async def test_submit_onboarding_marks_user_completed(unique_new_user_a):
    """
    Submitting the onboarding questionnaire establishes the user's starting rhythm
    and marks onboarding_completed == True.
    """
    headers = unique_new_user_a["headers"]
    payload = {
        "preferred_peak_start": "08:30",
        "preferred_peak_end": "11:30",
        "weekday_wake_time": "06:30",
        "weekend_wake_time": "08:00",
        "bedtime": "22:30",
        "sleep_inertia_minutes": 25,
        "preferred_session_minutes": 50,
        "draining_work_types": ["coding", "architecture"],
        "fatigue_symptom": "distracted",
        "primary_goal": "deep_focus",
        "energy_predictability": "mostly_predictable",
        "timezone": "America/New_York",
    }
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        onb_res = await ac.post("/api/v1/readiness/onboarding", headers=headers, json=payload)
        assert onb_res.status_code == 201
        onb_data = onb_res.json()
        assert onb_data["preferred_peak_start"] == "08:30"
        assert onb_data["weekday_wake_time"] == "06:30"

        # Verify /auth/me now reflects onboarding_completed == True
        me_res = await ac.get("/api/v1/auth/me", headers=headers)
        assert me_res.status_code == 200
        assert me_res.json()["onboarding_completed"] is True

@pytest.mark.asyncio
async def test_account_a_and_b_onboarding_and_personalization_isolation(unique_new_user_a, unique_new_user_b):
    """
    Verifies that Account A completing onboarding does NOT mark Account B as completed.
    Account B remains onboarding_completed == False and receives default/isolated profile.
    """
    headers_a = unique_new_user_a["headers"]
    headers_b = unique_new_user_b["headers"]

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # User A completes onboarding with morning focus (07:00 peak)
        payload_a = {
            "preferred_peak_start": "07:00",
            "preferred_peak_end": "09:30",
            "weekday_wake_time": "06:00",
            "weekend_wake_time": "07:30",
            "bedtime": "22:00",
            "sleep_inertia_minutes": 15,
            "draining_work_types": ["writing"],
            "primary_goal": "early_morning",
            "energy_predictability": "highly_predictable",
        }
        res_a = await ac.post("/api/v1/readiness/onboarding", headers=headers_a, json=payload_a)
        assert res_a.status_code == 201

        # User A is now completed
        me_a = await ac.get("/api/v1/auth/me", headers=headers_a)
        assert me_a.json()["onboarding_completed"] is True

        # User B MUST NOT be completed
        me_b = await ac.get("/api/v1/auth/me", headers=headers_b)
        assert me_b.json()["onboarding_completed"] is False

        # User B's profile must not have User A's custom 07:00 peak
        profile_b = await ac.get("/api/v1/readiness/profile", headers=headers_b)
        assert profile_b.status_code == 200
        assert profile_b.json()["preferred_peak_start"] != "07:00"

        # User B completes onboarding with evening peak (18:00)
        payload_b = {
            "preferred_peak_start": "18:00",
            "preferred_peak_end": "21:00",
            "weekday_wake_time": "09:00",
            "weekend_wake_time": "10:30",
            "bedtime": "01:00",
            "sleep_inertia_minutes": 45,
            "draining_work_types": ["calls"],
            "primary_goal": "night_owl",
            "energy_predictability": "variable",
        }
        res_b = await ac.post("/api/v1/readiness/onboarding", headers=headers_b, json=payload_b)
        assert res_b.status_code == 201

        # Now User B is completed with their own distinct profile
        me_b_2 = await ac.get("/api/v1/auth/me", headers=headers_b)
        assert me_b_2.json()["onboarding_completed"] is True

        profile_b_2 = await ac.get("/api/v1/readiness/profile", headers=headers_b)
        assert profile_b_2.json()["preferred_peak_start"] == "18:00"

        # User A's profile is still intact at 07:00
        profile_a = await ac.get("/api/v1/readiness/profile", headers=headers_a)
        assert profile_a.json()["preferred_peak_start"] == "07:00"

@pytest.mark.asyncio
async def test_explicit_onboarding_complete_endpoint(unique_new_user_a):
    """
    Tests POST /api/v1/auth/onboarding-complete explicitly marks user completed.
    """
    headers = unique_new_user_a["headers"]
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/auth/onboarding-complete", headers=headers)
        assert res.status_code == 200
        assert res.json()["onboarding_completed"] is True

        me = await ac.get("/api/v1/auth/me", headers=headers)
        assert me.json()["onboarding_completed"] is True
