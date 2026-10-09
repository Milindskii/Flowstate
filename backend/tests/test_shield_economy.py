"""Shield economy (Build My Day): price, consent, atomic charge, exact refund, idempotency, concurrency.

Backend is the only authority: the client flag `consume_shield` is consent, never a balance or a price.
Postgres-only contention (40 connections) lives in test_ai_gateway_postgres.py; here the same invariants are
exercised through the API on whatever database the suite runs on.
"""
import asyncio
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pytest
from sqlalchemy import text, update
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.economy_config import SHIELD_COST_BUILD_MY_DAY
from app.db.session import SessionLocal
from app.models.ai_usage import AIRequest, AIUsageRecord
from app.models.flow_progression import FlowProfile
from app.services import ai_gateway
from app.services.ai_economy_service import AIEconomyService
from app.services.ai_service import AIService, GeminiFailure
from tests.plan_helpers import client, make_user
from tests.test_ai_gateway import _exhaust_free, _make_pro, _ok, _post, _requests, _shields, _slow, _usage

COST = SHIELD_COST_BUILD_MY_DAY
EXTRACT = (AIService, "extract_structured_plan_with_gemini")


@pytest.fixture(autouse=True)
def _high_rate_limit(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1000)
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_PRO", 1000)


def _set_shields(uid, n):
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid).shields_available = n
        db.commit()


def _poor_free_user(shields):
    uid, headers = make_user()
    _exhaust_free(uid)
    _set_shields(uid, shields)
    return uid, headers


def test_the_price_of_a_build_my_day_plan_is_one_shield():
    assert COST == 1


# ── 1. free allowance available ───────────────────────────────────────────────

@pytest.mark.asyncio
async def test_free_allowance_runs_ai_and_consumes_no_shield_even_with_consent_flag(one_free_plan):
    uid, headers = make_user()
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, headers, consume_shield=True)  # consent given, but the free use is spent first
    assert res.status_code == 200 and res.json()["free_consumed"] is True and res.json()["shield_consumed"] is False
    assert extract.call_count == 1
    assert _shields(uid) == 2 and _usage(uid) == (1, 0, 1)


# ── status tells the app the price (it never hard-codes it) ───────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("shields,affordable", [(0, False), (1, True), (2, True), (3, True)])
async def test_status_reports_server_owned_price_and_affordability(shields, affordable):
    uid, headers = _poor_free_user(shields)
    async with client() as ac:
        body = (await ac.get("/api/v1/ai/status", headers=headers)).json()
    assert body["shield_cost"] == COST and body["requires_shield"] is True
    assert body["shields_available"] == shields
    assert body["can_afford_shield_plan"] is affordable and body["can_use_ai"] is affordable


# ── 2-3. consent, exact price ─────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_confirmed_plan_consumes_exactly_the_price_and_records_the_units():
    uid, headers = _poor_free_user(3)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()):
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 200 and res.json()["shield_consumed"] is True
    assert _shields(uid) == 3 - COST
    with SessionLocal() as db:
        req = db.query(AIRequest).filter(AIRequest.user_id == uid).one()
        assert (req.status, req.charge_source, req.charge_units) == ("succeeded", "shield", COST)
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        assert profile.shields_used_count == COST


# ── 4. cancel / no consent ────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_without_consent_nothing_is_charged_and_the_provider_is_not_called():
    uid, headers = _poor_free_user(5)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, headers, consume_shield=False)
    assert res.status_code == 402 and res.json()["failure_code"] == "quota_exhausted"
    assert "1 Shield" in res.json()["detail"]
    assert extract.call_count == 0 and _shields(uid) == 5


# ── 5-6. insufficient Shields: no AI request, no charge ──────────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("shields", [0])
async def test_insufficient_shields_never_reach_the_provider_or_change_the_balance(shields):
    uid, headers = _poor_free_user(shields)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 403 and res.json()["failure_code"] == "insufficient_shields"
    assert "Shields" in res.json()["detail"] and "HTTP" not in res.json()["detail"]
    assert extract.call_count == 0
    assert _shields(uid) == shields, "a partial price must never be taken"
    assert _requests(uid) == [], "a refused request leaves no reservation behind"


# ── 7. Pro ────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_pro_never_pays_free_user_shields_even_when_the_flag_is_sent():
    uid, headers = make_user()
    _make_pro(uid)
    _exhaust_free(uid)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()):
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 200 and res.json()["shield_consumed"] is False
    assert _shields(uid) == 2
    assert _requests(uid)[0][:2] == ("succeeded", "pro")


@pytest.mark.asyncio
async def test_pro_is_still_rate_limited_by_the_backend(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_PRO", 2)
    uid, headers = make_user()
    _make_pro(uid)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()):
            codes = [(await _post(ac, headers)).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


# ── 8. provider failure: exact refund, nothing free ───────────────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [GeminiFailure("timeout", "x"), GeminiFailure("malformed", "x"),
                                     GeminiFailure("provider_unavailable", "x"), RuntimeError("boom")])
async def test_failed_paid_request_gives_the_whole_price_back_and_shows_a_neutral_message(failure):
    uid, headers = _poor_free_user(COST)
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=failure):
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 502
    detail = res.json()["detail"]
    assert "not charged" in detail and "Gemini" not in detail and "503" not in detail
    assert _shields(uid) == COST and _usage(uid)[1] == 0
    assert _requests(uid)[0][:2] == ("failed", "shield")
    with SessionLocal() as db:
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_used_count == 0


@pytest.mark.asyncio
async def test_a_failed_paid_request_does_not_leave_free_ai_behind():
    uid, headers = _poor_free_user(COST)
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=GeminiFailure("timeout", "x")):
            await _post(ac, headers, consume_shield=True)
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, headers, consume_shield=False)  # no consent now: still gated
    assert res.status_code == 402 and extract.call_count == 0
    assert _shields(uid) == COST


@pytest.mark.asyncio
async def test_empty_ai_answer_is_refunded_in_full():
    uid, headers = _poor_free_user(COST)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=([], [], False)):
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 422
    assert _shields(uid) == COST


# ── 9, 17, 18. repeated taps, duplicate keys, retries ────────────────────────

@pytest.mark.asyncio
async def test_repeated_taps_with_one_request_id_charge_once_and_call_the_provider_once():
    uid, headers = _poor_free_user(4)
    key = f"k-{uuid.uuid4().hex}"
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            codes = [(await _post(ac, headers, key=key, consume_shield=True)).status_code for _ in range(5)]
    assert codes == [200] * 5
    assert extract.call_count == 1
    assert _shields(uid) == 4 - COST and _usage(uid)[1] == 1


@pytest.mark.asyncio
async def test_simultaneous_taps_with_one_request_id_charge_once(monkeypatch):
    uid, headers = _poor_free_user(4)
    key = f"k-{uuid.uuid4().hex}"
    calls = []
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=_slow(0.3, calls)):
            results = await asyncio.gather(*[_post(ac, headers, key=key, consume_shield=True) for _ in range(6)])
    assert len(calls) == 1
    assert [r.status_code for r in results].count(200) >= 1
    assert _shields(uid) == 4 - COST


@pytest.mark.asyncio
async def test_failed_then_retried_request_with_the_same_key_pays_once_in_total():
    uid, headers = _poor_free_user(4)
    key = f"k-{uuid.uuid4().hex}"
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=GeminiFailure("timeout", "x")):
            assert (await _post(ac, headers, key=key, consume_shield=True)).status_code == 502
        assert _shields(uid) == 4
        with patch.object(*EXTRACT, return_value=_ok()):
            assert (await _post(ac, headers, key=key, consume_shield=True)).status_code == 200
            assert (await _post(ac, headers, key=key, consume_shield=True)).status_code == 200  # replay
    assert _shields(uid) == 4 - COST
    assert _requests(uid) == [("succeeded", "shield", None)]


@pytest.mark.asyncio
async def test_key_replayed_with_a_different_consent_is_rejected_not_recharged():
    uid, headers = _poor_free_user(4)
    key = f"k-{uuid.uuid4().hex}"
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            assert (await _post(ac, headers, key=key, consume_shield=True)).status_code == 200
            again = await _post(ac, headers, key=key, consume_shield=False)
    assert again.status_code == 422 and extract.call_count == 1
    assert _shields(uid) == 4 - COST


@pytest.mark.asyncio
async def test_another_users_key_is_never_replayed_or_charged_to_this_user():
    uid_a, ha = _poor_free_user(4)
    uid_b, hb = _poor_free_user(4)
    key = f"k-{uuid.uuid4().hex}"
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            assert (await _post(ac, ha, key=key, consume_shield=True)).status_code == 200
            assert (await _post(ac, hb, key=key, consume_shield=True)).status_code == 200
    assert extract.call_count == 2
    assert _shields(uid_a) == _shields(uid_b) == 4 - COST


# ── 10. concurrency ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_two_simultaneous_requests_with_exactly_the_price_have_one_winner():
    uid, headers = _poor_free_user(COST)
    calls = []
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=_slow(0.3, calls)):
            a, b = await asyncio.gather(_post(ac, headers, consume_shield=True),
                                        _post(ac, headers, consume_shield=True))
    assert {a.status_code, b.status_code} == {200, 409}
    assert [a.status_code, b.status_code].count(200) == 1
    assert len(calls) == 1, "the loser must never receive paid AI access"
    assert _shields(uid) == 0, "never -2, never -4"


def test_database_level_race_on_the_last_shields_has_one_winner():
    """Bypasses the in-flight slot: two sessions charging the same balance directly. The conditional UPDATE alone decides."""
    uid, _ = _poor_free_user(COST)
    results = []
    for _ in range(4):
        with SessionLocal() as db:
            try:
                results.append(ai_gateway._charge(db, uid, False, True, datetime.now(timezone.utc).date()))
                db.commit()
            except ai_gateway.QuotaExceeded as e:
                db.rollback()
                results.append(e.code)
    assert results == [("shield", COST), "insufficient_shields", "insufficient_shields", "insufficient_shields"]
    assert _shields(uid) == 0


def test_the_database_refuses_a_negative_balance():
    uid, _ = _poor_free_user(1)
    with SessionLocal() as db:
        with pytest.raises(IntegrityError):
            db.execute(update(FlowProfile).where(FlowProfile.user_id == uid).values(shields_available=-1))
            db.commit()
        db.rollback()
    assert _shields(uid) == 1


# ── refunds are exact and happen once ─────────────────────────────────────────

def test_stale_paid_reservation_refunds_its_full_price_exactly_once():
    uid, _ = make_user()
    _set_shields(uid, 0)  # the reservation already took both
    with SessionLocal() as db:
        AIEconomyService.get_or_create_usage(db, uid).free_uses_consumed = 1
        db.add(AIRequest(user_id=uid, idempotency_key="stuck", request_sha256="x", status="reserved",
                         charge_source="shield", charge_units=COST,
                         deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
    with SessionLocal() as db:
        assert ai_gateway.expire_stale(db, uid) == 1
        assert ai_gateway.expire_stale(db, uid) == 0
    assert _shields(uid) == COST


def test_a_legacy_one_unit_reservation_refunds_one_unit():
    uid, _ = make_user()
    _set_shields(uid, 0)
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key="old", request_sha256="x", status="reserved",
                         charge_source="shield", deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
    with SessionLocal() as db:
        ai_gateway.expire_stale(db, uid)
    assert _shields(uid) == 1


# ── streak Shield shares the balance: no lost updates, no overdraw ───────────

@pytest.mark.asyncio
async def test_streak_shield_and_ai_plan_cannot_spend_the_same_shields():
    uid, headers = _poor_free_user(COST)
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()):
            assert (await _post(ac, headers, consume_shield=True)).status_code == 200
        assert _shields(uid) == 0
        res = await ac.post("/api/v1/flow/shields/use", headers=headers)
    assert res.status_code == 400
    assert _shields(uid) == 0


@pytest.mark.asyncio
async def test_streak_shield_spends_one_and_a_second_tap_the_same_day_changes_nothing():
    uid, headers = _poor_free_user(3)
    async with client() as ac:
        first = await ac.post("/api/v1/flow/shields/use", headers=headers)
        second = await ac.post("/api/v1/flow/shields/use", headers=headers)
    assert first.status_code == 200 and first.json()["shields_available"] == 2
    assert second.status_code == 400
    assert _shields(uid) == 2


# ── Replan: this task does not charge it ─────────────────────────────────────

@pytest.mark.asyncio
async def test_rules_only_replan_never_touches_shields_or_ai_usage():
    from tests.test_replan_admission import RULES_MESSAGE, _body
    from tests.test_replan_ai import _day

    uid, h = _poor_free_user(3)
    _day(uid)
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(RULES_MESSAGE))
    assert r.status_code == 200, r.text
    assert _shields(uid) == 3
    with SessionLocal() as db:
        usage = db.query(AIUsageRecord).filter(AIUsageRecord.user_id == uid).one_or_none()
        assert usage is None or (usage.shield_uses_consumed, usage.total_ai_uses) == (0, 0)


@pytest.mark.asyncio
async def test_build_my_day_is_refused_with_no_charge_while_a_replan_holds_the_ai_slot():
    uid, headers = _poor_free_user(COST)
    ai_gateway.claim_slot(SessionLocal(), user_id=uid, kind="replan", fingerprint="x")
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, headers, consume_shield=True)
    assert res.status_code == 409
    assert extract.call_count == 0 and _shields(uid) == COST


# ── AI Replan Shield economy ─────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_ai_replan_charges_exactly_one_shield_on_success(monkeypatch):
    from tests.test_replan_admission import AI_MESSAGE, Model, _body, op, ops, ref
    from tests.test_replan_ai import _day

    Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    uid, h = _poor_free_user(2)
    _day(uid)
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    assert r.status_code == 200, r.text
    assert _shields(uid) == 1  # 2 - 1 = 1 shield


@pytest.mark.asyncio
async def test_ai_replan_refunds_shield_on_gemini_failure(monkeypatch):
    from tests.test_replan_admission import AI_MESSAGE, Model, _body
    from tests.test_replan_ai import _day

    Model(monkeypatch, lambda p: "not json at all")
    uid, h = _poor_free_user(2)
    _day(uid)
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    # Failure to understand refunds the reserved shield in full
    assert _shields(uid) == 2


@pytest.mark.asyncio
async def test_ai_replan_without_enough_shields_never_calls_gemini(monkeypatch):
    from tests.test_replan_admission import AI_MESSAGE, Model, _body
    from tests.test_replan_ai import _day

    model = Model(monkeypatch, lambda p: "should not be called")
    uid, h = _poor_free_user(0)  # 0 shields available
    _day(uid)
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    assert len(model.calls) == 0, "Gemini must not be called when user cannot afford shield"
    assert _shields(uid) == 0
