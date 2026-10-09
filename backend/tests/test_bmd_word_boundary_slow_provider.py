"""Build My Day around the 200-word limit when Gemini is slow to generate.

Live probe (2026-10-09, gemini-3.1-flash-lite): a full-size dump sends ~5k input tokens and gets back 2-4.3k output
tokens; generation took 5.6 s to 23.6 s. The request is bounded by AI_REQUEST_DEADLINE_SECONDS (25 s), but each
attempt used to be capped at GEMINI_REQUEST_TIMEOUT_SECONDS (12 s): a plan that needed 14 s timed out on the primary,
then the fallback model had to regenerate the same answer in the ~12 s left and timed out too (502 `timeout`).

These tests scale the clock down (per-attempt cap 0.3 s, deadline 2 s, generation 0.6 s) and drive the real
/ai/plan route and the real `_gemini_generate` transport, stubbing only `httpx.Client.post`.
"""
import json
import time
import uuid
from unittest.mock import patch

import httpx
import pytest

from app.core import ai_limits, economy_config
from app.core.config import settings
from app.db.session import SessionLocal
from app.models.flow_progression import FlowProfile
from app.services.ai_service import AIService

from .plan_helpers import client, make_user

GENERATION_SECONDS = 0.6

_GOOD_BODY = {"candidates": [{"content": {"parts": [{"text": json.dumps({"tasks": [{
    "title": "Finish lab report", "type": "deep_work", "estimated_minutes": 90, "difficulty": "high",
    "priority": "high", "priority_source": "explicit", "deadline": None, "fixed_start": None, "confidence": 0.95,
    "needs_confirmation": False}], "ambiguities": []})}]}, "finishReason": "STOP"}],
    "usageMetadata": {"promptTokenCount": 4987, "candidatesTokenCount": 4285}}


def _dump(n_words: int) -> str:
    sentence = ("Finish the lab report for two hours before Friday then study graph algorithms and call the dentist "
                "and go to the gym for an hour after lunch").split()
    return " ".join((sentence * (n_words // len(sentence) + 1))[:n_words])


@pytest.fixture
def slow_gemini(monkeypatch):
    """A healthy Gemini whose answer takes GENERATION_SECONDS: longer than one attempt's old cap, inside the deadline."""
    monkeypatch.setattr(settings, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1000)
    monkeypatch.setattr(settings, "GEMINI_REQUEST_TIMEOUT_SECONDS", 0.3)
    monkeypatch.setattr(settings, "AI_REQUEST_DEADLINE_SECONDS", 2.0)
    calls = []

    def post(self, url, **kw):
        timeout = kw.get("timeout")
        calls.append({"model": url.split("/models/")[-1].split(":")[0], "timeout": timeout})
        if timeout is not None and timeout < GENERATION_SECONDS:
            time.sleep(timeout)
            raise httpx.ReadTimeout("generation still running")
        time.sleep(GENERATION_SECONDS)
        return httpx.Response(200, json=_GOOD_BODY, request=httpx.Request("POST", url))

    with patch("httpx.Client.post", post):
        yield calls


def _shields(uid):
    with SessionLocal() as db:
        return db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available


async def _plan(ac, headers, text):
    await ac.get("/api/v1/ai/status", headers=headers)  # the one-time onboarding Shield grant
    return await ac.post("/api/v1/ai/plan", headers=headers, json={
        "raw_text": text, "timezone": "Asia/Kolkata", "consume_shield": True, "idempotency_key": uuid.uuid4().hex})


@pytest.mark.asyncio
@pytest.mark.parametrize("n_words", [50, 100, 150, 190, economy_config.BMD_MAX_INPUT_WORDS])
async def test_slow_generation_up_to_the_limit_is_planned_on_the_first_model_and_charged_once(slow_gemini, n_words):
    uid, headers = make_user(prefix="bmd-slow")
    async with client() as ac:
        await ac.get("/api/v1/ai/status", headers=headers)
        before = _shields(uid)
        res = await _plan(ac, headers, _dump(n_words))
    assert res.status_code == 200, res.text
    assert len(slow_gemini) == 1, f"one attempt should finish the plan, got {slow_gemini}"
    assert slow_gemini[0]["timeout"] > settings.GEMINI_REQUEST_TIMEOUT_SECONDS  # the attempt may use the deadline
    assert _shields(uid) == before - economy_config.SHIELD_COST_BUILD_MY_DAY


@pytest.mark.asyncio
async def test_one_word_over_the_limit_never_reaches_gemini_or_charges(slow_gemini):
    uid, headers = make_user(prefix="bmd-over")
    async with client() as ac:
        await ac.get("/api/v1/ai/status", headers=headers)
        before = _shields(uid)
        res = await _plan(ac, headers, _dump(economy_config.BMD_MAX_INPUT_WORDS + 1))
    assert res.status_code == 422
    assert res.json()["failure_code"] == "input_too_long"
    assert slow_gemini == []
    assert _shields(uid) == before


@pytest.mark.asyncio
async def test_generation_longer_than_the_whole_deadline_is_a_bounded_refunded_timeout(slow_gemini, monkeypatch):
    monkeypatch.setattr(settings, "AI_REQUEST_DEADLINE_SECONDS", 0.5)  # shorter than GENERATION_SECONDS
    uid, headers = make_user(prefix="bmd-dead")
    async with client() as ac:
        await ac.get("/api/v1/ai/status", headers=headers)
        before = _shields(uid)
        started = time.monotonic()
        res = await _plan(ac, headers, _dump(economy_config.BMD_MAX_INPUT_WORDS))
        elapsed = time.monotonic() - started
    assert res.status_code == 502 and res.json()["failure_code"] == "timeout"
    assert elapsed < 1.5, f"deadline not enforced: {elapsed:.2f}s"
    assert _shields(uid) == before


def test_attempt_timeout_outside_a_deadline_keeps_the_per_call_cap(slow_gemini):
    """Without a gateway deadline (no request bound), one attempt is still capped at GEMINI_REQUEST_TIMEOUT_SECONDS."""
    with pytest.raises(Exception):
        AIService._gemini_generate("p", "k", request_id="r")
    assert all(c["timeout"] <= settings.GEMINI_REQUEST_TIMEOUT_SECONDS for c in slow_gemini)


def test_fast_failure_still_falls_back_within_the_deadline(slow_gemini, monkeypatch):
    """A 503 answers immediately, so the fallback model still gets the remaining deadline."""
    token = ai_limits.request_deadline.set(time.monotonic() + settings.AI_REQUEST_DEADLINE_SECONDS)
    monkeypatch.setattr(settings, "GEMINI_BACKOFF_BASE_SECONDS", 0.0)
    replies = iter([httpx.Response(503, json={"error": {}}, request=httpx.Request("POST", "https://x"))])
    real_post = httpx.Client.post

    def post(self, url, **kw):
        try:
            return next(replies)
        except StopIteration:
            return real_post(self, url, **kw)

    try:
        with patch("httpx.Client.post", post):
            out = AIService._gemini_generate("p", "k", request_id="r")
    finally:
        ai_limits.request_deadline.reset(token)
    assert json.loads(out)["tasks"]
