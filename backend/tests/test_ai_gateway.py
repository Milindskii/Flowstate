"""AI gateway: atomic reservation, idempotency, refunds, deadlines, circuit breaker, admission, entitlement."""
import asyncio
import json
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import httpx
import pytest
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from app.core import ai_limits
from app.core.ai_limits import CircuitBreaker
from app.core.config import settings
from app.db.session import SessionLocal, engine
from app.models.ai_usage import AIRequest, AIUsagePeriod, AIUsageRecord
from app.models.flow_progression import FlowProfile
from app.schemas.task import (FieldProvenance, TaskCandidateResponse, TaskDifficulty, TaskPriority, TaskSource,
                              TaskType)
from app.services import ai_gateway
from app.services.ai_economy_service import AIEconomyService
from app.services.ai_service import AIService, GeminiFailure

from .plan_helpers import client, make_user


def _ok():
    task = TaskCandidateResponse(
        title="Finish report", estimated_minutes=60, task_type=TaskType.deep_work, difficulty=TaskDifficulty.medium,
        priority=TaskPriority.high, category="Work", confidence=0.9, source=TaskSource.ai_parsed,
        field_provenance={"priority": FieldProvenance(source="explicit", confidence=1.0)},
    )
    return [task], [], False


def _key():
    return f"k-{uuid.uuid4().hex}"


def _post(ac, headers, text="Finish the report", key=None, **extra):
    return ac.post("/api/v1/ai/plan", headers=headers, json={"raw_text": text, "idempotency_key": key or _key(), **extra})


def _usage(uid):
    with SessionLocal() as db:
        u = db.query(AIUsageRecord).filter(AIUsageRecord.user_id == uid).one()
        return u.free_uses_consumed, u.shield_uses_consumed, u.total_ai_uses


def _shields(uid):
    with SessionLocal() as db:
        return db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available


def _requests(uid):
    with SessionLocal() as db:
        return [(r.status, r.charge_source, r.error_code)
                for r in db.query(AIRequest).filter(AIRequest.user_id == uid).order_by(AIRequest.created_at)]


def _period_used(uid, kind):
    with SessionLocal() as db:
        rows = db.query(AIUsagePeriod).filter(AIUsagePeriod.user_id == uid, AIUsagePeriod.period_kind == kind).all()
        return sum(r.used for r in rows)


def _make_pro(uid, expires_at=None):
    with SessionLocal() as db:
        usage = AIEconomyService.get_or_create_usage(db, uid)
        usage.is_pro, usage.subscription_tier, usage.subscription_status = True, "flowstate_pro_monthly", "active"
        usage.subscription_expires_at = expires_at
        db.commit()


def _exhaust_free(uid):
    with SessionLocal() as db:
        usage = AIEconomyService.get_or_create_usage(db, uid)
        usage.free_uses_consumed = usage.free_uses_total
        db.commit()


def _slow(seconds=0.4, calls=None):
    def fn(*a, **k):
        if calls is not None:
            calls.append(1)
        time.sleep(seconds)
        return _ok()
    return fn


@pytest.fixture
def high_rate_limit(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1000)
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_PRO", 1000)


# ---- concurrency / race tests -----------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_concurrent_requests_spend_the_single_free_use_exactly_once(high_rate_limit):
    uid, headers = make_user()
    calls = []
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=_slow(0.4, calls)):
            results = await asyncio.gather(*[_post(ac, headers) for _ in range(8)])
    codes = sorted(r.status_code for r in results)
    assert codes.count(200) == 1, codes
    assert all(c in (200, 409) for c in codes), codes  # the rest are refused while one is in flight
    assert len(calls) == 1, "only one request may reach the provider"
    assert _usage(uid) == (1, 0, 1)
    assert [s for s, *_ in _requests(uid)].count("succeeded") == 1


@pytest.mark.asyncio
async def test_concurrent_requests_never_double_spend_a_shield(high_rate_limit):
    uid, headers = make_user()
    _exhaust_free(uid)
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid).shields_available = 1
        db.commit()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=_slow(0.3)):
            results = await asyncio.gather(*[_post(ac, headers, consume_shield=True) for _ in range(6)])
    codes = [r.status_code for r in results]
    assert codes.count(200) == 1, codes
    assert _shields(uid) == 0, "shields must never go negative or be spent twice"
    assert _usage(uid)[1] == 1


@pytest.mark.asyncio
async def test_concurrent_pro_requests_are_serialised_per_user(high_rate_limit):
    uid, headers = make_user()
    _make_pro(uid)
    calls = []
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=_slow(0.3, calls)):
            results = await asyncio.gather(*[_post(ac, headers) for _ in range(5)])
    assert [r.status_code for r in results].count(200) == len(calls) == _period_used(uid, "day")
    assert len(calls) < 5, "overlapping requests from one user must be refused, not all run"


def test_consume_period_is_atomic_across_threads():
    uid, _ = make_user()
    wins, lock = [], threading.Lock()

    def worker():
        with SessionLocal() as db:
            ok = ai_gateway.consume_period(db, uid, "day", cap=5)
            db.commit()
        with lock:
            wins.append(ok)

    threads = [threading.Thread(target=worker) for _ in range(20)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert wins.count(True) == 5 and wins.count(False) == 15
    assert _period_used(uid, "day") == 5


def test_hit_window_counts_atomically_across_threads():
    results, lock = [], threading.Lock()

    def worker():
        with SessionLocal() as db:
            n = ai_gateway.hit_window(db, "test:bucket", 3600)
        with lock:
            results.append(n)

    threads = [threading.Thread(target=worker) for _ in range(15)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sorted(results) == list(range(1, 16)), "every hit gets a unique, gap-free count"


def test_database_admits_only_one_inflight_request_per_user():
    uid, _ = make_user()
    far = datetime.now(timezone.utc) + timedelta(minutes=5)
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key="a", request_sha256="x", deadline_at=far, status="reserved"))
        db.commit()
        db.add(AIRequest(user_id=uid, idempotency_key="b", request_sha256="x", deadline_at=far, status="reserved"))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        db.add(AIRequest(user_id=uid, idempotency_key="c", request_sha256="x", deadline_at=far, status="failed"))
        db.commit()  # finished rows do not count


# ---- idempotency ------------------------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_concurrent_duplicate_key_calls_the_provider_once():
    uid, headers = make_user()
    key, calls = _key(), []
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=_slow(0.4, calls)):
            results = await asyncio.gather(*[_post(ac, headers, key=key) for _ in range(4)])
    assert len(calls) == 1
    assert sorted(r.status_code for r in results).count(200) == 1
    assert all(r.status_code in (200, 409) for r in results)
    assert _usage(uid) == (1, 0, 1)


@pytest.mark.asyncio
async def test_replay_after_success_is_free_and_returns_the_same_plan():
    uid, headers = make_user()
    key = _key()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            first = await _post(ac, headers, key=key)
            again = await _post(ac, headers, key=key)
    assert first.status_code == again.status_code == 200
    assert first.json()["tasks"] == again.json()["tasks"]
    assert extract.call_count == 1 and _usage(uid) == (1, 0, 1)


@pytest.mark.asyncio
async def test_replays_do_not_consume_the_rate_limit(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 2)
    uid, headers = make_user()
    key = _key()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            codes = [(await _post(ac, headers, key=key)).status_code for _ in range(6)]
    assert codes == [200] * 6


@pytest.mark.asyncio
async def test_same_key_with_a_different_body_is_rejected():
    uid, headers = make_user()
    key = _key()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            assert (await _post(ac, headers, key=key, text="plan A")).status_code == 200
            res = await _post(ac, headers, key=key, text="plan B")
    assert res.status_code == 422 and res.json()["failure_code"] == "idempotency_key_reused"
    assert extract.call_count == 1


# ---- failure / refund -------------------------------------------------------------------------------------------

@pytest.mark.asyncio
@pytest.mark.parametrize("code", ["provider_unavailable", "timeout", "network", "provider_quota", "malformed"])
async def test_failed_provider_call_refunds_free_use(code):
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=GeminiFailure(code, "x")):
            res = await _post(ac, headers)
    assert res.status_code == 502 and res.json()["failure_code"] == code
    assert _usage(uid) == (0, 0, 0)
    assert _requests(uid) == [("failed", "free", code)]


@pytest.mark.asyncio
async def test_failed_provider_call_refunds_the_shield():
    uid, headers = make_user()
    _exhaust_free(uid)
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=GeminiFailure("provider_unavailable", "x")):
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 502
    assert _shields(uid) == 2 and _usage(uid)[1] == 0
    assert _requests(uid)[0][:2] == ("failed", "shield")


@pytest.mark.asyncio
async def test_failed_provider_call_refunds_pro_counters():
    uid, headers = make_user()
    _make_pro(uid)
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=RuntimeError("boom")):
            res = await _post(ac, headers)
        assert res.status_code == 502
        assert _period_used(uid, "day") == 0 and _period_used(uid, "month") == 0
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            assert (await _post(ac, headers)).status_code == 200
    assert _period_used(uid, "day") == 1 and _period_used(uid, "month") == 1


@pytest.mark.asyncio
async def test_empty_result_is_refunded():
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=([], [], False)):
            res = await _post(ac, headers)
    assert res.status_code == 422 and _usage(uid) == (0, 0, 0)


@pytest.mark.asyncio
async def test_a_refunded_attempt_can_be_retried_with_the_same_key():
    uid, headers = make_user()
    key = _key()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=GeminiFailure("timeout", "x")):
            assert (await _post(ac, headers, key=key)).status_code == 502
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            assert (await _post(ac, headers, key=key)).status_code == 200
    assert _usage(uid) == (1, 0, 1)
    assert _requests(uid) == [("succeeded", "free", None)]


def test_stale_reservation_is_refunded_exactly_once():
    uid, _ = make_user()
    with SessionLocal() as db:
        usage = AIEconomyService.get_or_create_usage(db, uid)
        usage.free_uses_consumed = 1  # charged at reservation time
        db.add(AIRequest(user_id=uid, idempotency_key="stuck", request_sha256="x", status="reserved",
                         charge_source="free", deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
    with SessionLocal() as db:
        assert ai_gateway.expire_stale(db, uid) == 1
        assert ai_gateway.expire_stale(db, uid) == 0
    assert _usage(uid)[0] == 0
    assert _requests(uid) == [("expired", "free", "expired")]


@pytest.mark.asyncio
async def test_a_crashed_request_does_not_block_the_user_after_its_deadline():
    uid, headers = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_usage(db, uid).free_uses_consumed = 1
        db.add(AIRequest(user_id=uid, idempotency_key="stuck", request_sha256="x", status="reserved",
                         charge_source="free", deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            res = await _post(ac, headers)
    assert res.status_code == 200 and res.json()["free_consumed"] is True
    assert _usage(uid) == (1, 0, 1)


def test_success_after_expiry_does_not_double_count():
    uid, _ = make_user()
    with SessionLocal() as db:
        ticket = ai_gateway.begin(db, user_id=uid, idempotency_key="late", fingerprint="f", consume_shield=False)
        db.execute(update(AIRequest).where(AIRequest.id == ticket.request_id)
                   .values(deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
        assert ai_gateway.expire_stale(db, uid) == 1
        assert ai_gateway.succeed(db, ticket, {"tasks": []}) is False
    assert _usage(uid) == (0, 0, 0), "refunded once; the late success is not charged again"


# ---- provider timeout / 503 through the real transport ----------------------------------------------------------

def _resp(status, body=None, headers=None):
    return httpx.Response(status, json=body if body is not None else {"error": {"status": "X"}}, headers=headers,
                          request=httpx.Request("POST", "https://generativelanguage.googleapis.com/x"))


_GOOD_BODY = {"candidates": [{"content": {"parts": [{"text": json.dumps({"tasks": [{
    "title": "Buy groceries", "type": "physical", "estimated_minutes": 45, "difficulty": "light", "priority": "low",
    "priority_source": "explicit", "deadline": None, "fixed_start": None, "confidence": 0.95,
    "needs_confirmation": False}], "ambiguities": []})}]}}]}


@pytest.fixture
def real_transport(monkeypatch):
    monkeypatch.setattr(settings, "GEMINI_API_KEY", "test-key")
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1000)


@pytest.mark.asyncio
async def test_provider_503_everywhere_is_bounded_refunded_and_never_crashes_the_api(real_transport):
    uid, headers = make_user()
    async with client() as ac:
        with patch("httpx.Client.post", side_effect=[_resp(503)] * 10) as post:
            res = await _post(ac, headers, text="Buy groceries")
        assert res.status_code == 502 and res.json()["failure_code"] == "provider_unavailable"
        assert post.call_count <= settings.GEMINI_MAX_ATTEMPTS, "attempts are bounded"
        assert _usage(uid) == (0, 0, 0)
        assert (await ac.get("/health")).status_code == 200  # the API is still healthy


@pytest.mark.asyncio
async def test_503_then_success_on_the_fallback_charges_once(real_transport):
    uid, headers = make_user()
    async with client() as ac:
        with patch("httpx.Client.post", side_effect=[_resp(503), _resp(200, _GOOD_BODY)]) as post:
            res = await _post(ac, headers, text="Buy groceries")
    assert res.status_code == 200 and post.call_count == 2
    assert _usage(uid) == (1, 0, 1)


@pytest.mark.asyncio
async def test_total_deadline_bounds_a_hanging_provider(real_transport, monkeypatch):
    monkeypatch.setattr(settings, "AI_REQUEST_DEADLINE_SECONDS", 0.6)
    uid, headers = make_user()

    def hang(*a, **k):
        time.sleep(0.4)
        raise httpx.ReadTimeout("slow")

    async with client() as ac:
        started = time.monotonic()
        with patch("httpx.Client.post", side_effect=hang):
            res = await _post(ac, headers, text="Buy groceries")
        elapsed = time.monotonic() - started
    assert res.status_code == 502 and res.json()["failure_code"] == "timeout"
    assert elapsed < 1.5, f"deadline not enforced: {elapsed:.2f}s"
    assert _usage(uid) == (0, 0, 0)


def test_request_sends_a_token_limit_and_a_per_call_timeout(monkeypatch):
    seen = {}

    def spy(self, url, **kw):
        seen.update(kw)
        return _resp(200, _GOOD_BODY)

    with patch("httpx.Client.post", spy):
        AIService._gemini_generate("p", "k", request_id="r")
    assert seen["json"]["generationConfig"]["maxOutputTokens"] == settings.GEMINI_MAX_OUTPUT_TOKENS
    assert 0 < seen["timeout"] <= settings.GEMINI_REQUEST_TIMEOUT_SECONDS


def test_backoff_never_sleeps_past_the_deadline(monkeypatch):
    monkeypatch.setattr(settings, "GEMINI_BACKOFF_BASE_SECONDS", 5.0)
    token = ai_limits.request_deadline.set(time.monotonic() + 0.8)
    slept = []
    try:
        with patch("httpx.Client.post", side_effect=[_resp(503)] * 4), \
                patch("app.services.ai_service.clock.sleep", side_effect=slept.append):
            with pytest.raises(GeminiFailure):
                AIService._gemini_generate("p", "k", request_id="r")
    finally:
        ai_limits.request_deadline.reset(token)
    assert all(s <= 0.8 for s in slept)


# ---- circuit breaker --------------------------------------------------------------------------------------------

def test_breaker_state_machine():
    b = CircuitBreaker()
    for i in range(settings.AI_BREAKER_FAILURE_THRESHOLD):
        assert b.allow(now=i)
        b.record_failure(now=i)
    assert b.state == "open" and not b.allow(now=10)
    later = settings.AI_BREAKER_FAILURE_THRESHOLD + settings.AI_BREAKER_OPEN_SECONDS + 1
    assert b.allow(now=later) and b.state == "half_open"
    assert not b.allow(now=later), "only one probe at a time"
    b.record_failure(now=later)
    assert b.state == "open"
    assert b.allow(now=later + settings.AI_BREAKER_OPEN_SECONDS + 1)
    b.record_success()
    assert b.state == "closed" and b.allow(now=0)


def test_breaker_ignores_old_failures_and_resets_on_success():
    b = CircuitBreaker()
    for i in range(settings.AI_BREAKER_FAILURE_THRESHOLD - 1):
        b.record_failure(now=i)
    b.record_success()
    b.record_failure(now=100)
    assert b.state == "closed"
    b2 = CircuitBreaker()
    for i in range(settings.AI_BREAKER_FAILURE_THRESHOLD - 1):
        b2.record_failure(now=i * 100)  # spread wider than the window
    assert b2.state == "closed"


@pytest.mark.asyncio
async def test_repeated_provider_failures_open_the_breaker_and_shed_load(high_rate_limit):
    async with client() as ac:
        for _ in range(settings.AI_BREAKER_FAILURE_THRESHOLD):
            uid, headers = make_user()
            with patch.object(AIService, "extract_structured_plan_with_gemini",
                              side_effect=GeminiFailure("provider_unavailable", "x")):
                assert (await _post(ac, headers)).status_code == 502
        uid, headers = make_user()
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()) as extract:
            res = await _post(ac, headers)
    assert res.status_code == 503 and res.json()["failure_code"] == "ai_busy"
    assert int(res.headers["retry-after"]) >= 1
    assert extract.call_count == 0, "an open breaker must not touch the provider"
    assert _usage(uid) == (0, 0, 0), "shed requests are refunded"


@pytest.mark.asyncio
async def test_content_problems_do_not_open_the_breaker(high_rate_limit):
    async with client() as ac:
        for _ in range(settings.AI_BREAKER_FAILURE_THRESHOLD + 2):
            uid, headers = make_user()
            with patch.object(AIService, "extract_structured_plan_with_gemini",
                              side_effect=GeminiFailure("malformed", "x")):
                assert (await _post(ac, headers)).status_code == 502
    assert ai_limits.breaker.state == "closed"


# ---- admission / global concurrency ----------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_global_concurrency_limit_sheds_excess_with_503_and_refund(monkeypatch):
    monkeypatch.setattr(settings, "AI_MAX_CONCURRENCY", 1)
    monkeypatch.setattr(settings, "AI_QUEUE_WAIT_SECONDS", 0.05)
    users = [make_user() for _ in range(3)]
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=_slow(0.5)):
            results = await asyncio.gather(*[_post(ac, h) for _, h in users])
    codes = sorted(r.status_code for r in results)
    assert codes == [200, 503, 503], codes
    for (uid, _), res in zip(users, results):
        if res.status_code == 503:
            assert res.json()["failure_code"] == "ai_busy" and "retry-after" in res.headers
            assert _usage(uid) == (0, 0, 0)
        else:
            assert _usage(uid) == (1, 0, 1)


@pytest.mark.asyncio
async def test_no_database_connection_is_held_during_the_provider_call():
    uid, headers = make_user()
    checked_out = []

    def provider(*a, **k):
        checked_out.append(engine.pool.checkedout())
        return _ok()

    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", side_effect=provider):
            assert (await _post(ac, headers)).status_code == 200
    assert checked_out == [0], f"pool connections held across the provider call: {checked_out}"


# ---- rate limits ------------------------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_rate_limit_is_per_user_and_pro_gets_a_higher_ceiling(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 2)
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_PRO", 4)
    monkeypatch.setattr(settings, "AI_PRO_DAILY_CAP", 100)
    monkeypatch.setattr(settings, "AI_BREAKER_FAILURE_THRESHOLD", 1000)  # not what this test is about
    free_uid, free_h = make_user()
    pro_uid, pro_h = make_user()
    other_uid, other_h = make_user()
    _make_pro(pro_uid)
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini",
                          side_effect=GeminiFailure("timeout", "x")):
            free = [(await _post(ac, free_h)).status_code for _ in range(3)]
            pro = [(await _post(ac, pro_h)).status_code for _ in range(5)]
            other = (await _post(ac, other_h)).status_code
    assert free == [502, 502, 429]
    assert pro == [502, 502, 502, 502, 429]
    assert other == 502, "one user's limit never affects another"


# ---- Pro vs Free entitlement ------------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_free_user_flow_trial_then_shield_then_blocked(high_rate_limit):
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            r1 = await _post(ac, headers)
            r2 = await _post(ac, headers)  # no consent to spend a shield
            r3 = await _post(ac, headers, consume_shield=True)
            r4 = await _post(ac, headers, consume_shield=True)
            r5 = await _post(ac, headers, consume_shield=True)  # 2 shields only
    assert (r1.status_code, r1.json()["free_consumed"]) == (200, True)
    assert r2.status_code == 402 and r2.json()["failure_code"] == "quota_exhausted"
    assert r3.status_code == r4.status_code == 200 and r3.json()["shield_consumed"] is True
    assert r5.status_code == 403
    assert _shields(uid) == 0 and _usage(uid)[:2] == (1, 2)


@pytest.mark.asyncio
async def test_pro_user_never_touches_trial_or_shields_and_hits_the_daily_cap(monkeypatch, high_rate_limit):
    monkeypatch.setattr(settings, "AI_PRO_DAILY_CAP", 3)
    uid, headers = make_user()
    _make_pro(uid)
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            codes = [(await _post(ac, headers)).status_code for _ in range(5)]
            blocked = await _post(ac, headers)
    assert codes == [200, 200, 200, 402, 402]
    assert blocked.json()["failure_code"] == "pro_cap_day"
    assert _usage(uid) == (0, 0, 3) and _shields(uid) == 2


@pytest.mark.asyncio
async def test_pro_monthly_cap(monkeypatch, high_rate_limit):
    monkeypatch.setattr(settings, "AI_PRO_MONTHLY_CAP", 2)
    uid, headers = make_user()
    _make_pro(uid)
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            codes = [(await _post(ac, headers)).status_code for _ in range(3)]
            res = await _post(ac, headers)
    assert codes == [200, 200, 402] and res.json()["failure_code"] == "pro_cap_month"
    assert _period_used(uid, "day") == 2, "a month-cap refusal must not leave a day unit spent"


@pytest.mark.asyncio
async def test_expired_pro_falls_back_to_free_rules_but_grace_keeps_pro():
    expired_uid, expired_h = make_user()
    grace_uid, grace_h = make_user()
    _make_pro(expired_uid, expires_at=datetime.now(timezone.utc) - timedelta(days=settings.PRO_GRACE_DAYS + 1))
    _make_pro(grace_uid, expires_at=datetime.now(timezone.utc) - timedelta(days=1))
    async with client() as ac:
        assert (await ac.get("/api/v1/ai/status", headers=expired_h)).json()["is_pro"] is False
        assert (await ac.get("/api/v1/ai/status", headers=grace_h)).json()["is_pro"] is True
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            expired = await _post(ac, expired_h)
            grace = await _post(ac, grace_h)
    assert expired.json()["free_consumed"] is True, "expired Pro is charged as a free user"
    assert grace.json()["free_consumed"] is False and _period_used(grace_uid, "day") == 1


@pytest.mark.asyncio
async def test_client_cannot_claim_pro():
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(AIService, "extract_structured_plan_with_gemini", return_value=_ok()):
            res = await ac.post("/api/v1/ai/plan", headers=headers,
                                json={"raw_text": "Finish the report", "idempotency_key": _key(), "is_pro": True, "free_uses_total": 99})
    assert res.status_code == 200 and res.json()["free_consumed"] is True
    assert _period_used(uid, "day") == 0


# ---- Postgres dialect safety (no Postgres server needed) --------------------------------------------------------

def test_atomic_statements_compile_for_postgresql():
    from sqlalchemy.dialects import postgresql
    from sqlalchemy.dialects.postgresql import insert as pg_insert

    from app.models.ai_usage import RateLimitWindow

    stmt = pg_insert(RateLimitWindow).values(bucket_key="b", window_start=1, count=1).on_conflict_do_update(
        index_elements=["bucket_key", "window_start"], set_={"count": RateLimitWindow.count + 1}
    ).returning(RateLimitWindow.count)
    sql = str(stmt.compile(dialect=postgresql.dialect()))
    assert "ON CONFLICT (bucket_key, window_start) DO UPDATE" in sql and "RETURNING" in sql
    upd = update(AIUsageRecord).where(AIUsageRecord.free_uses_consumed < AIUsageRecord.free_uses_total) \
        .values(free_uses_consumed=AIUsageRecord.free_uses_consumed + 1)
    assert "free_uses_consumed < ai_usage_records.free_uses_total" in str(upd.compile(dialect=postgresql.dialect()))
