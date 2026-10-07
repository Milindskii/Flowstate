"""
Complimentary-first-AI-plan entitlement (Build My Day).

Every new account gets one free successful AI plan. A failed Gemini attempt never spends it, a retry stays
eligible, replaying a request key never charges twice, entitlement and cache are per user, and a *provider*
quota failure (Gemini's project quota) is a different thing from the user's Flowstate entitlement.
"""
import uuid
from unittest.mock import patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.ai_usage import AIPlanningAttempt, AIRequest, AIUsageRecord
from app.schemas.task import (FieldProvenance, TaskCandidateResponse, TaskDifficulty, TaskPriority,
                              TaskSource, TaskType)
from app.services.ai_service import AIService, GeminiFailure


def _user():
    return f"entl_{uuid.uuid4().hex[:10]}"


def _headers(user_id):
    return {"Authorization": f"Bearer {create_access_token({'sub': user_id, 'email': f'{user_id}@flowstate.local'})}"}


def _ok():
    task = TaskCandidateResponse(
        title="Finish report", estimated_minutes=60, task_type=TaskType.deep_work, difficulty=TaskDifficulty.medium,
        priority=TaskPriority.high, category="Work", confidence=0.9, source=TaskSource.ai_parsed,
        field_provenance={"priority": FieldProvenance(source="explicit", confidence=1.0)},
    )
    return [task], [], False


def _plan(ac, user_id, key=None, text="Finish the report", **extra):
    body = {"raw_text": text, **extra}
    if key:
        body["idempotency_key"] = key
    return ac.post("/api/v1/ai/plan", headers=_headers(user_id), json=body)


def _status(ac, user_id):
    return ac.get("/api/v1/ai/status", headers=_headers(user_id))


def _cache_rows(user_id):
    """Replayable (succeeded) requests: a failure must never be cached."""
    with SessionLocal() as db:
        return db.query(AIRequest).filter(AIRequest.user_id == user_id, AIRequest.status == "succeeded",
                                          AIRequest.response_json.is_not(None)).count()


def _usage(user_id):
    with SessionLocal() as db:
        return db.query(AIUsageRecord).filter(AIUsageRecord.user_id == user_id).one()


def _attempts(user_id):
    with SessionLocal() as db:
        return db.query(AIPlanningAttempt).filter(AIPlanningAttempt.user_id == user_id).order_by(AIPlanningAttempt.created_at).all()


@pytest.mark.asyncio
@pytest.mark.parametrize("code", ["provider_unavailable", "timeout", "model_not_found", "network", "gemini_error"])
async def test_B_new_user_failed_gemini_keeps_the_free_use(code):
    user = _user()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=GeminiFailure(code, "x")):
            res = await _plan(ac, user, key=f"k-{uuid.uuid4().hex}")
        assert res.status_code == 502
        assert res.json()["failure_code"] == code
        st = (await _status(ac, user)).json()
        assert st["free_uses_remaining"] == 1 and st["can_plan_free"] is True
        assert st["shields_available"] == 2
        assert _usage(user).free_uses_consumed == 0
        assert _cache_rows(user) == 0, "a failure must never be cached"


@pytest.mark.asyncio
async def test_C_retry_after_failure_with_the_same_key_is_still_free_and_gets_its_own_attempt():
    user, key = _user(), f"k-{uuid.uuid4().hex}"
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=GeminiFailure("provider_unavailable", "503")):
            assert (await _plan(ac, user, key=key)).status_code == 502
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            res = await _plan(ac, user, key=key)
        assert res.status_code == 200 and extract.call_count == 1, "retry must reach Gemini again"
        assert res.json()["free_consumed"] is True and res.json()["shield_consumed"] is False
        usage = _usage(user)
        assert (usage.free_uses_consumed, usage.shield_uses_consumed, usage.total_ai_uses) == (1, 0, 1)
        statuses = [(a.status, a.failure_code) for a in _attempts(user)]
        assert statuses == [("failed", "provider_unavailable"), ("succeeded", None)]
        assert len({a.attempt_id for a in _attempts(user)}) == 2


@pytest.mark.asyncio
async def test_D_replaying_the_key_after_success_does_not_charge_again_or_call_gemini():
    user, key = _user(), f"k-{uuid.uuid4().hex}"
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            assert (await _plan(ac, user, key=key)).status_code == 200
            for _ in range(3):
                replay = await _plan(ac, user, key=key)
                assert replay.status_code == 200 and len(replay.json()["tasks"]) == 1
            assert extract.call_count == 1
        assert _usage(user).free_uses_consumed == 1 and _usage(user).total_ai_uses == 1


@pytest.mark.asyncio
async def test_E_another_account_does_not_inherit_usage_or_replay_a_key():
    a, b, key = _user(), _user(), f"shared-{uuid.uuid4().hex}"
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            assert (await _plan(ac, a, key=key)).status_code == 200
            # B starts fresh: A's consumption is invisible to B ...
            st_b = (await _status(ac, b)).json()
            assert st_b["free_uses_remaining"] == 1 and st_b["can_plan_free"] is True
            # ... and idempotency keys are private to their user: the same key string from B is just B's own
            # new request (never A's cached plan, never a 409 that would let B block A's key).
            res_b = await _plan(ac, b, key=key)
            assert res_b.status_code == 200 and res_b.json()["free_consumed"] is True
            assert extract.call_count == 2, "B's request is its own provider call, not a replay of A's"
        assert _usage(a).free_uses_consumed == 1 and _usage(b).free_uses_consumed == 1
        assert _cache_rows(a) == 1 and _cache_rows(b) == 1


@pytest.mark.asyncio
async def test_F_provider_quota_is_distinct_from_flowstate_entitlement():
    user = _user()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Provider (Gemini project) quota: 502 + provider_quota, user untouched, still eligible.
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=GeminiFailure("provider_quota", "429")):
            res = await _plan(ac, user, key=f"k-{uuid.uuid4().hex}")
        assert res.status_code == 502 and res.json()["failure_code"] == "provider_quota"
        st = (await _status(ac, user)).json()
        assert st["free_uses_remaining"] == 1 and st["shields_available"] == 2
        # Flowstate entitlement exhausted: 402 + quota_exhausted, a different code and status.
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            assert (await _plan(ac, user, key=f"k-{uuid.uuid4().hex}")).status_code == 200
            res2 = await _plan(ac, user, key=f"k-{uuid.uuid4().hex}")
        assert res2.status_code == 402 and res2.json()["failure_code"] == "quota_exhausted"
