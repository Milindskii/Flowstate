"""/tasks/parse can no longer spend unmetered Gemini calls, and test_mode is dev-only."""
import pytest
from jose import jwt

from app.api.routes import tasks as tasks_routes
from app.core.config import settings
from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.models.ai_usage import AIUsageRecord
from app.services.ai_service import AIService

from .plan_helpers import client, make_user


@pytest.fixture
def gemini_calls(monkeypatch):
    calls = []

    def fake(cls, raw_text, now_local, tz, request_id=None):
        calls.append(raw_text)
        return []

    monkeypatch.setattr(settings, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(AIService, "_try_gemini_fallback", classmethod(fake))
    monkeypatch.setattr(AIService, "_try_ollama_fallback", classmethod(lambda cls, *a, **k: []))
    return calls


@pytest.mark.asyncio
async def test_free_user_ai_parse_is_capped_per_day(monkeypatch, gemini_calls):
    monkeypatch.setattr(tasks_routes, "FREE_PARSE_AI_PER_DAY", 2)
    monkeypatch.setattr(tasks_routes, "MAX_PARSE_PER_MINUTE", 100)
    _, headers = make_user()
    async with client() as ac:
        for i in range(5):
            res = await ac.post(
                "/api/v1/tasks/parse", headers=headers, json={"raw_text": f"gym tomorrow {i}", "use_ai": True}
            )
            assert res.status_code == 200  # over the cap it silently degrades to the local parser
    assert len(gemini_calls) == 2


@pytest.mark.asyncio
async def test_zero_candidate_fallback_to_ai_is_also_metered(monkeypatch, gemini_calls):
    monkeypatch.setattr(tasks_routes, "FREE_PARSE_AI_PER_DAY", 1)
    monkeypatch.setattr(tasks_routes, "MAX_PARSE_PER_MINUTE", 100)
    _, headers = make_user()
    async with client() as ac:
        for _ in range(3):
            await ac.post("/api/v1/tasks/parse", headers=headers, json={"raw_text": "zzzz qqqq"})
    assert len(gemini_calls) <= 1


@pytest.mark.asyncio
async def test_pro_user_gets_a_larger_budget(monkeypatch, gemini_calls):
    monkeypatch.setattr(tasks_routes, "FREE_PARSE_AI_PER_DAY", 1)
    monkeypatch.setattr(tasks_routes, "PRO_PARSE_AI_PER_DAY", 3)
    monkeypatch.setattr(tasks_routes, "MAX_PARSE_PER_MINUTE", 100)
    uid, headers = make_user()
    db = SessionLocal()
    try:
        db.add(AIUsageRecord(user_id=uid, free_uses_total=1, free_uses_consumed=0, shield_uses_consumed=0,
                             total_ai_uses=0, is_pro=True, subscription_tier="pro", subscription_status="active"))
        db.commit()
    finally:
        db.close()
    async with client() as ac:
        for i in range(5):
            await ac.post("/api/v1/tasks/parse", headers=headers, json={"raw_text": f"gym tomorrow {i}", "use_ai": True})
    assert len(gemini_calls) == 3


@pytest.mark.asyncio
async def test_budget_is_per_user(monkeypatch, gemini_calls):
    monkeypatch.setattr(tasks_routes, "FREE_PARSE_AI_PER_DAY", 1)
    monkeypatch.setattr(tasks_routes, "MAX_PARSE_PER_MINUTE", 100)
    _, h1 = make_user()
    _, h2 = make_user()
    async with client() as ac:
        for h in (h1, h1, h2, h2):
            await ac.post("/api/v1/tasks/parse", headers=h, json={"raw_text": "gym tomorrow", "use_ai": True})
    assert len(gemini_calls) == 2


@pytest.mark.asyncio
async def test_test_mode_ignored_outside_development(monkeypatch):
    _, headers = make_user()
    async with client() as ac:
        start = await ac.post("/api/v1/flow/session/start", headers=headers, json={})
        sid = start.json()["session_id"]
        monkeypatch.setattr(settings, "ENVIRONMENT", "production")
        monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", "a-real-secret-value-0123456789abcdef")
        uid = jwt.get_unverified_claims(headers["Authorization"].split()[1])["sub"]
        headers = {"Authorization": f"Bearer {create_access_token({'sub': uid, 'email': f'{uid}@flowstate.local'})}"}
        res = await ac.post(
            f"/api/v1/flow/session/{sid}/complete?test_mode=true", headers=headers, json={"task_completed": True}
        )
    assert res.status_code == 400
    assert "below the minimum qualifying duration" in res.json()["detail"]
