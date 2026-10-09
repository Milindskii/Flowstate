"""Onboarding Shields: a brand-new account holds 2 Shields without claiming anything, exactly once, ledgered.

"Shields pay for Noya's AI planning": one Build My Day plan costs 1 Shield, there is no separate free trial plan,
and the client can neither grant itself Shields nor replay the onboarding grant.
"""
import asyncio
import uuid
from unittest.mock import patch

import pytest
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.economy_config import INITIAL_SHIELDS, ONBOARDING_SHIELDS_EVENT, ONBOARDING_WELCOME_SEEN_EVENT
from app.db.session import SessionLocal
from app.models.flow_progression import FlowEconomicEvent, FlowProfile
from app.services.ai_economy_service import AIEconomyService
from app.services.ai_service import AIService, GeminiFailure
from tests.plan_helpers import client, make_user
from tests.test_ai_gateway import _ok, _post, _shields, _slow, _usage

EXTRACT = (AIService, "extract_structured_plan_with_gemini")


@pytest.fixture(autouse=True)
def _high_rate_limit(monkeypatch):
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 1000)


def _events(uid, kind):
    with SessionLocal() as db:
        return db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                  FlowEconomicEvent.event_type == kind).count()


async def _status(ac, headers):
    return (await ac.get("/api/v1/ai/status", headers=headers)).json()


# ── the grant ────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_a_new_account_holds_exactly_two_shields_with_no_claim_and_one_ledger_row():
    uid, h = make_user()
    async with client() as ac:
        st = await _status(ac, h)
    assert INITIAL_SHIELDS == 2
    assert st["shields_available"] == 2 and st["shield_max"] == 3
    assert _events(uid, ONBOARDING_SHIELDS_EVENT) == 1
    with SessionLocal() as db:
        ev = db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid).filter(
            FlowEconomicEvent.event_type == ONBOARDING_SHIELDS_EVENT).one()
        assert ev.idempotency_key == f"{ONBOARDING_SHIELDS_EVENT}-{uid}"


@pytest.mark.asyncio
async def test_shield_price_and_rule_are_one_simple_model():
    _, h = make_user()
    async with client() as ac:
        st = await _status(ac, h)
    assert st["shield_cost"] == 1 and st["can_afford_shield_plan"] is True
    assert st["free_use_available"] is False and st["free_uses_total"] == 0, "no second 'free plan' rule"
    assert st["requires_shield"] is True


@pytest.mark.asyncio
async def test_restart_login_and_other_devices_never_grant_again():
    uid, h = make_user()
    async with client() as first_device:
        await _status(first_device, h)
        await first_device.get("/api/v1/flow/overview", headers=h)
    for _ in range(3):  # restart / logout + login / second device: fresh clients, same account
        async with client() as ac:
            await _status(ac, h)
            await ac.get("/api/v1/flow/overview", headers=h)
    assert _shields(uid) == 2
    assert _events(uid, ONBOARDING_SHIELDS_EVENT) == 1


@pytest.mark.asyncio
async def test_spent_shields_are_not_given_back_by_a_later_login():
    uid, h = make_user()
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()):
            assert (await _post(ac, h, consume_shield=True)).status_code == 200
        assert _shields(uid) == 1
    async with client() as relogin:
        st = await _status(relogin, h)
        await relogin.get("/api/v1/flow/overview", headers=h)
    assert st["shields_available"] == 1 and _shields(uid) == 1
    assert _events(uid, ONBOARDING_SHIELDS_EVENT) == 1


@pytest.mark.asyncio
async def test_concurrent_first_requests_grant_once():
    uid, h = make_user()
    async with client() as ac:
        results = await asyncio.gather(
            *[ac.get("/api/v1/ai/status", headers=h) for _ in range(4)],
            *[ac.get("/api/v1/flow/overview", headers=h) for _ in range(4)],
            return_exceptions=True)
    assert any(getattr(r, "status_code", None) == 200 for r in results)
    assert _shields(uid) == 2, "never 4 or 6"
    assert _events(uid, ONBOARDING_SHIELDS_EVENT) == 1


def test_the_ledger_refuses_a_second_onboarding_grant_for_the_same_account():
    uid, _ = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid)
    with SessionLocal() as db:
        db.add(FlowEconomicEvent(user_id=uid, idempotency_key=f"replay-{uuid.uuid4().hex}",
                                 event_type=ONBOARDING_SHIELDS_EVENT, reference_id=uid))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
    assert _events(uid, ONBOARDING_SHIELDS_EVENT) == 1 and _shields(uid) == 2


def test_repeating_profile_creation_cannot_grant_again():
    from app.models.user import User
    from app.services.flow_service import FlowService

    uid, _ = make_user()
    with SessionLocal() as db:
        user = db.query(User).filter(User.id == uid).one()
        FlowService().get_or_create_flow_profile(db, user)
        db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available = 0  # spent
        db.commit()
        FlowService().get_or_create_flow_profile(db, user)  # login again
    assert _shields(uid) == 0 and _events(uid, ONBOARDING_SHIELDS_EVENT) == 1


@pytest.mark.asyncio
async def test_accounts_are_isolated():
    a, ha = make_user()
    b, hb = make_user()
    async with client() as ac:
        await _status(ac, ha)
        with patch.object(*EXTRACT, return_value=_ok()):
            assert (await _post(ac, ha, consume_shield=True)).status_code == 200
        sb = await _status(ac, hb)
    assert _shields(a) == 1 and sb["shields_available"] == 2 and _shields(b) == 2
    assert _events(a, ONBOARDING_SHIELDS_EVENT) == _events(b, ONBOARDING_SHIELDS_EVENT) == 1


@pytest.mark.asyncio
async def test_the_client_cannot_grant_itself_shields():
    uid, h = make_user()
    async with client() as ac:
        await _status(ac, h)
        attempts = [
            ac.post("/api/v1/ai/shield-welcome/seen", headers=h, json={"shields_available": 3, "shields": 3}),
            ac.post("/api/v1/ai/plan", headers=h, json={"raw_text": "x y", "shields_available": 99, "consume_shield": False}),
            ac.patch("/api/v1/flow/profile", headers=h, json={"shields_available": 3}),
            ac.put("/api/v1/flow/profile", headers=h, json={"shields_available": 3}),
            ac.post("/api/v1/flow/shields", headers=h, json={"shields_available": 3}),
        ]
        for coro in attempts:
            await coro
    assert _shields(uid) == 2


# ── the one-time welcome ────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_welcome_is_pending_once_per_account_across_devices_and_restarts():
    uid, h = make_user()
    async with client() as ac:
        assert (await _status(ac, h))["shield_welcome_pending"] is True
        assert (await _status(ac, h))["shield_welcome_pending"] is True, "reading never dismisses it"
        first = await ac.post("/api/v1/ai/shield-welcome/seen", headers=h)
        again = await ac.post("/api/v1/ai/shield-welcome/seen", headers=h)  # double tap / retry
    assert (first.status_code, again.status_code) == (204, 204)
    for _ in range(2):  # restart / second device
        async with client() as ac:
            assert (await _status(ac, h))["shield_welcome_pending"] is False
    assert _events(uid, ONBOARDING_WELCOME_SEEN_EVENT) == 1
    assert _shields(uid) == 2, "dismissing grants and spends nothing"


@pytest.mark.asyncio
async def test_welcome_belongs_to_the_account_that_dismissed_it():
    a, ha = make_user()
    b, hb = make_user()
    async with client() as ac:
        await _status(ac, ha)
        await ac.post("/api/v1/ai/shield-welcome/seen", headers=ha)
        assert (await _status(ac, hb))["shield_welcome_pending"] is True


@pytest.mark.asyncio
async def test_an_account_without_the_onboarding_grant_never_gets_the_welcome():
    uid, h = make_user()
    with SessionLocal() as db:  # a profile that predates the ledger event
        db.add(FlowProfile(user_id=uid, shields_available=2))
        db.commit()
    async with client() as ac:
        assert (await _status(ac, h))["shield_welcome_pending"] is False


@pytest.mark.asyncio
async def test_dismiss_needs_a_signed_in_account():
    async with client() as ac:
        res = await ac.post("/api/v1/ai/shield-welcome/seen")
    assert res.status_code in (401, 403)


# ── spending: exactly 1, once ───────────────────────────────────────────────

@pytest.mark.asyncio
async def test_two_plans_cost_one_shield_each_and_the_third_is_refused():
    uid, h = make_user()
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            r1 = await _post(ac, h, consume_shield=True)
            after_first = _shields(uid)
            r2 = await _post(ac, h, consume_shield=True)
            after_second = _shields(uid)
            r3 = await _post(ac, h, consume_shield=True)
    assert (r1.status_code, r1.json()["shield_consumed"], r1.json()["usage"]["shields_available"]) == (200, True, 1)
    assert (r2.status_code, r2.json()["usage"]["shields_available"]) == (200, 0)
    assert (after_first, after_second) == (1, 0)
    assert r3.status_code == 403 and r3.json()["failure_code"] == "insufficient_shields"
    assert extract.call_count == 2 and _usage(uid)[1] == 2


@pytest.mark.asyncio
async def test_duplicate_taps_with_one_request_id_spend_one_shield():
    uid, h = make_user()
    key = f"k-{uuid.uuid4().hex}"
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            codes = [(await _post(ac, h, key=key, consume_shield=True)).status_code for _ in range(4)]
    assert codes == [200] * 4 and extract.call_count == 1 and _shields(uid) == 1


@pytest.mark.asyncio
async def test_simultaneous_taps_spend_one_shield():
    uid, h = make_user()
    key = f"k-{uuid.uuid4().hex}"
    calls = []
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=_slow(0.3, calls)):
            await asyncio.gather(*[_post(ac, h, key=key, consume_shield=True) for _ in range(5)])
    assert len(calls) == 1 and _shields(uid) == 1


@pytest.mark.asyncio
async def test_a_provider_failure_keeps_the_shield_and_says_it_was_not_charged():
    uid, h = make_user()
    async with client() as ac:
        with patch.object(*EXTRACT, side_effect=GeminiFailure("timeout", "x")):
            res = await _post(ac, h, consume_shield=True)
        st = await _status(ac, h)
    body = res.json()
    assert res.status_code == 502 and body["failure_code"] == "timeout"
    assert "Your Shield was not charged" in body["detail"]
    assert "out of Shields" not in body["detail"] and "insufficient" not in body["failure_code"]
    assert _shields(uid) == 2 and st["shields_available"] == 2


@pytest.mark.asyncio
async def test_running_out_is_a_different_answer_from_a_provider_failure():
    uid, h = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid).shields_available = 0
        db.commit()
    async with client() as ac:
        with patch.object(*EXTRACT, return_value=_ok()) as extract:
            res = await _post(ac, h, consume_shield=True)
    assert res.status_code == 403 and res.json()["failure_code"] == "insufficient_shields"
    assert "out of Shields" in res.json()["detail"] and extract.call_count == 0
