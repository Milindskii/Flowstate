"""What a client can read from an AI failure: neutral Flowstate wording, stable machine codes, no entitlement leak.

Provider/model/internal terms may live in logs and diagnostics rows, never in an API response message.
"""
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from jose import jwt

from app.core import security
from app.core.config import settings
from app.db.session import SessionLocal
from app.models.ai_usage import AIPlanningAttempt, AIUsageRecord
from app.services.ai_service import AIService, GeminiFailure

from .plan_helpers import client, make_user

FORBIDDEN = re.compile(r"gemini|google|openai|anthropic|claude|\bmodel\b|api key|http[_ ]?\d{3}|\b(429|503|502)\b|traceback|"
                       r"stack|sqlalchemy|psycopg|alembic|relation|migration", re.I)

CODES = ["provider_quota", "provider_auth", "model_not_found", "provider_unavailable", "timeout", "network",
         "malformed", "gemini_error"]


@pytest.mark.asyncio
@pytest.mark.parametrize("code", CODES)
async def test_failure_detail_is_neutral_but_the_machine_code_is_stable(code):
    uid, headers = make_user()
    reason = {"provider_quota": "Gemini's usage quota is exhausted (HTTP 429)",
              "provider_auth": "Gemini rejected the API key (HTTP 403)",
              "model_not_found": "The configured Gemini model was not found (HTTP 404)"}.get(code, f"Gemini {code} (HTTP 503)")
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=GeminiFailure(code, reason)):
            res = await ac.post("/api/v1/ai/plan", headers=headers,
                                json={"raw_text": "Finish the report", "idempotency_key": f"k-{uuid.uuid4().hex}"})
    body = res.json()
    assert res.status_code == 502 and body["failure_code"] == code
    assert body["detail"].startswith("AI task structuring failed")
    assert "were not charged" in body["detail"]
    assert not FORBIDDEN.search(body["detail"]), body["detail"]
    # Internal diagnostics keep the real reason for operators.
    with SessionLocal() as db:
        row = db.query(AIPlanningAttempt).filter(AIPlanningAttempt.user_id == uid).one()
        assert row.failure_code == code and "Gemini" in (row.failure_reason or "")


@pytest.mark.asyncio
async def test_unexpected_exception_detail_is_neutral():
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=RuntimeError("psycopg relation ai_requests does not exist")):
            res = await ac.post("/api/v1/ai/plan", headers=headers,
                                json={"raw_text": "Finish the report", "idempotency_key": f"k-{uuid.uuid4().hex}"})
    assert res.status_code == 502 and not FORBIDDEN.search(res.json()["detail"])


@pytest.mark.asyncio
async def test_gateway_refusals_use_neutral_copy_and_keep_their_codes(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1)
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=GeminiFailure("timeout", "x")):
            await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Finish the report", "idempotency_key": "a1"})
            limited = await ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": "Finish the report", "idempotency_key": "a2"})
    assert limited.status_code == 429 and limited.json()["failure_code"] == "rate_limited"
    assert not FORBIDDEN.search(limited.json()["detail"])
    with SessionLocal() as db:  # a failure never costs entitlement
        assert db.query(AIUsageRecord).filter(AIUsageRecord.user_id == uid).one().free_uses_consumed == 0


# ---- JWT rejections are diagnosable without leaking anything ----------------------------------------------------

def _tok(**claims):
    payload = {"sub": "u1", "aud": "authenticated", "iss": f"{settings.SUPABASE_URL}/auth/v1",
               "exp": datetime.now(timezone.utc) + timedelta(hours=1)}
    payload.update(claims)
    return jwt.encode(payload, settings.SUPABASE_JWT_SECRET, algorithm="HS256")


@pytest.mark.parametrize("claims,expected", [
    ({"aud": "other"}, "audience"),
    ({"iss": "https://evil.example/auth/v1"}, "issuer"),
    ({"exp": datetime.now(timezone.utc) - timedelta(seconds=30)}, "expired"),
])
def test_jwt_rejection_logs_a_reason_but_never_the_token(caplog, claims, expected):
    token = _tok(**claims)
    with caplog.at_level(logging.WARNING):
        assert security.decode_access_token(token) is None
    text = caplog.text.lower()
    assert "jwt_rejected" in text and expected in text
    assert token not in caplog.text and token.split(".")[1] not in caplog.text


def test_valid_jwt_logs_nothing(caplog):
    with caplog.at_level(logging.WARNING):
        assert security.decode_access_token(_tok()) is not None
    assert "jwt_rejected" not in caplog.text
