import pytest
from datetime import datetime, timezone
from fastapi import status
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.db.session import get_db
from app.models.user import User
from app.models.readiness_profile import ReadinessProfile
from app.models.readiness_observation import ReadinessObservation, ObservationSource
from app.models.readiness_prediction import ReadinessPrediction
from app.models.readiness_evaluation import ReadinessEvaluation
from app.core.security import create_access_token
from app.core.hashing import hash_password, verify_password
from app.engines.readiness_engine import ReadinessEngineV2

@pytest.fixture
def test_user_headers():
    token = create_access_token({"sub": "test-readiness-user", "email": "readiness@flowstate.local"})
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture
def test_admin_headers():
    token = create_access_token({"sub": "test-admin-user", "email": "admin@flowstate.local"})
    db = next(get_db())
    user = db.query(User).filter(User.id == "test-admin-user").first()
    if not user:
        user = User(id="test-admin-user", email="admin@flowstate.local", name="Admin", is_admin=True)
        db.add(user)
        db.commit()
    else:
        user.is_admin = True
        db.commit()
    return {"Authorization": f"Bearer {token}"}

def test_password_hashing():
    pw = "super-secret-flowstate-pass"
    hashed = hash_password(pw)
    assert verify_password(pw, hashed) is True
    assert verify_password("wrong-password", hashed) is False

def test_readiness_engine_mathematical_progression():
    engine = ReadinessEngineV2()

    # Stage A (0-9 observations)
    code_a, label_a = engine.determine_stage(5)
    assert code_a == "Stage A"
    assert "Stage A" in label_a

    # Stage B (10-49 observations)
    code_b, label_b = engine.determine_stage(25)
    assert code_b == "Stage B"
    assert "Shrinkage" in label_b

    # Stage C (50+ observations)
    code_c, label_c = engine.determine_stage(55)
    assert code_c == "Stage C"
    assert "Personalized" in label_c

@pytest.mark.asyncio
async def test_onboarding_submission_creates_profile(test_user_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        onboarding_payload = {
            "preferred_peak_start": "08:30",
            "preferred_peak_end": "11:00",
            "weekday_wake_time": "06:30",
            "weekend_wake_time": "08:00",
            "bedtime": "22:45",
            "sleep_inertia_minutes": 25,
            "draining_work_types": ["Coding", "Problem solving"],
            "fatigue_symptom": "procrastinate",
            "session_disruptor": "phone",
            "preferred_session_minutes": 40,
            "primary_goal": "stay_focused",
            "energy_predictability": "mostly_predictable",
            "schedule_disruptors": ["College"],
        }
        res = await ac.post("/api/v1/readiness/onboarding", headers=test_user_headers, json=onboarding_payload)
        assert res.status_code == status.HTTP_201_CREATED
        data = res.json()
        assert data["preferred_peak_start"] == "08:30"
        assert data["preferred_peak_end"] == "11:00"
        assert data["sleep_inertia_minutes"] == 25
        assert data["wake_variability"] == 1.5

@pytest.mark.asyncio
async def test_readiness_today_endpoint(test_user_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/readiness/today", headers=test_user_headers)
        assert res.status_code == status.HTTP_200_OK
        data = res.json()
        assert "readiness_score" in data
        assert "recommendation_band" in data
        assert "stage" in data
        assert "hourly_rhythm" in data
        assert len(data["hourly_rhythm"]) > 0

@pytest.mark.asyncio
async def test_observation_creation_with_provenance(test_user_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        obs_payload = {
            "wake_time": "07:00",
            "sleep_minutes": 480,
            "sleep_quality": 4,
            "energy_rating": 4,
            "focus_rating": 5,
            "difficulty_rating": 3,
            "distraction_rating": 1,
            "task_type": "deep_work",
            "source": "self_report",
        }
        res = await ac.post("/api/v1/readiness/observations", headers=test_user_headers, json=obs_payload)
        assert res.status_code == status.HTTP_201_CREATED
        data = res.json()
        assert data["source"] == "self_report"
        assert data["energy_rating"] == 4
        assert data["focus_rating"] == 5

@pytest.mark.asyncio
async def test_personalization_settings_and_update(test_user_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Get settings
        get_res = await ac.get("/api/v1/personalization/settings", headers=test_user_headers)
        assert get_res.status_code == status.HTTP_200_OK
        assert get_res.json()["personalization_enabled"] is True

        # Update settings
        patch_res = await ac.patch("/api/v1/personalization/settings", headers=test_user_headers, json={
            "use_task_history": False,
        })
        assert patch_res.status_code == status.HTTP_200_OK
        assert patch_res.json()["use_task_history"] is False

@pytest.mark.asyncio
async def test_personalization_export_and_reset(test_user_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Export
        export_res = await ac.get("/api/v1/personalization/export", headers=test_user_headers)
        assert export_res.status_code == status.HTTP_200_OK
        assert "observations" in export_res.json()
        assert "profile" in export_res.json()

        # Reset
        reset_res = await ac.post("/api/v1/personalization/reset", headers=test_user_headers)
        assert reset_res.status_code == status.HTTP_200_OK
        assert reset_res.json()["status"] == "success"

@pytest.mark.asyncio
async def test_feedback_to_evaluation_lifecycle(test_user_headers):
    """
    End-to-end integration:
    Task created -> Task completed -> Feedback recorded -> Observation saved ->
    ReadinessEvaluation created with Brier calibration score!
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Create Task
        t_res = await ac.post("/api/v1/tasks", headers=test_user_headers, json={
            "title": "Evaluation LifeCycle Task",
            "task_type": "deep_work",
            "difficulty": "high",
            "estimated_minutes": 50,
        })
        assert t_res.status_code == status.HTTP_201_CREATED
        task_id = t_res.json()["id"]

        # 2. Complete Task
        await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=test_user_headers)

        # 3. Post Feedback
        fb_res = await ac.post(f"/api/v1/tasks/{task_id}/feedback", headers=test_user_headers, json={
            "actual_minutes": 48,
            "focus_score": 5,
            "energy_score": 4,
            "difficulty_score": 4,
            "distraction_score": 1,
            "notes": "Seamless flow state!",
        })
        assert fb_res.status_code == status.HTTP_201_CREATED

        # 4. Check Evaluation Metrics API
        eval_res = await ac.get("/api/v1/personalization/evaluation", headers=test_user_headers)
        assert eval_res.status_code == status.HTTP_200_OK
        eval_data = eval_res.json()
        assert "brier_calibration_score" in eval_data
        assert "overall_completion_rate" in eval_data

@pytest.mark.asyncio
async def test_admin_route_protection(test_user_headers, test_admin_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Regular user must receive 403 Forbidden
        reg_res = await ac.get("/api/v1/admin/stats", headers=test_user_headers)
        assert reg_res.status_code == status.HTTP_403_FORBIDDEN

        # Admin user must receive 200 OK
        admin_res = await ac.get("/api/v1/admin/stats", headers=test_admin_headers)
        assert admin_res.status_code == status.HTTP_200_OK
        assert admin_res.json()["status"] == "authorized"

@pytest.mark.asyncio
async def test_security_headers_present():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/health")
        assert res.headers["X-Content-Type-Options"] == "nosniff"
        assert res.headers["X-Frame-Options"] == "DENY"
        assert res.headers["X-XSS-Protection"] == "1; mode=block"
