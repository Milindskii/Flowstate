"""Shields are a server-authoritative economy: nothing the app sends can create, reset or re-claim one.

Covers the final polish pass: the streak Shield activation is once per day and visible as such (a second tap, a retry,
a restart or another device gets nothing), every grant is capped and audited, and the API surface offers no way to
set a balance.
"""
import asyncio
import threading
from datetime import timedelta

import pytest

from app.core.economy_config import MAX_FREE_SHIELDS
from app.db.session import SessionLocal
from app.main import app
from app.models.flow_progression import FlowEconomicEvent, FlowProfile
from app.services import shield_ledger
from app.services.flow_service import FlowService
from tests.plan_helpers import client, make_user
from tests.test_shield_refill import T0, _row, _set, _sync


def _events(uid, kind):
    with SessionLocal() as db:
        return db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                  FlowEconomicEvent.event_type == kind).count()


@pytest.mark.asyncio
async def test_activation_is_reported_active_and_a_second_tap_restart_or_device_gets_nothing():
    uid, h = make_user()
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        _set(uid, 3)
        before = (await ac.get("/api/v1/flow/overview", headers=h)).json()["profile"]
        assert before["shield_active_today"] is False
        first = await ac.post("/api/v1/flow/shields/use", headers=h)
        assert first.status_code == 200 and first.json()["shield_active_today"] is True
        for _ in range(3):  # repeated taps / retries
            assert (await ac.post("/api/v1/flow/shields/use", headers=h)).status_code == 400
    async with client() as other_device:  # a fresh client: app restart or a second device, same account
        again = await other_device.post("/api/v1/flow/shields/use", headers=h)
        overview = (await other_device.get("/api/v1/flow/overview", headers=h)).json()["profile"]
    assert again.status_code == 400
    assert overview["shield_active_today"] is True
    assert overview["shields_available"] == 2, "exactly one Shield was spent"
    assert _events(uid, "shield_used") == 1


@pytest.mark.asyncio
async def test_concurrent_activations_have_one_winner():
    uid, h = make_user()
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        _set(uid, 3)
        results = await asyncio.gather(*[ac.post("/api/v1/flow/shields/use", headers=h) for _ in range(6)])
    assert sorted(r.status_code for r in results).count(200) == 1
    assert _row(uid)[0] == 2


@pytest.mark.asyncio
async def test_one_account_never_sees_or_spends_another_accounts_activation():
    a, ha = make_user()
    b, hb = make_user()
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=ha)
        await ac.get("/api/v1/flow/overview", headers=hb)
        _set(a, 3)
        _set(b, 3)
        assert (await ac.post("/api/v1/flow/shields/use", headers=ha)).status_code == 200
        b_profile = (await ac.get("/api/v1/flow/overview", headers=hb)).json()["profile"]
        assert (await ac.post("/api/v1/flow/shields/use", headers=hb)).status_code == 200
    assert b_profile["shield_active_today"] is False
    assert _row(a)[0] == 2 and _row(b)[0] == 2


def test_every_free_refill_leaves_one_audit_row_and_replays_add_none():
    uid, _ = make_user()
    _set(uid, 0, refill_at=T0)
    assert _sync(uid, T0 + timedelta(minutes=1)).granted
    assert not _sync(uid, T0 + timedelta(minutes=2)).granted
    assert _events(uid, "shield_refill") == 1


def test_parallel_refill_claims_write_one_audit_row():
    uid, _ = make_user()
    _set(uid, 1, refill_at=T0)
    barrier = threading.Barrier(6)

    def claim():
        barrier.wait()
        with SessionLocal() as db:
            shield_ledger.sync_refill(db, uid, T0 + timedelta(seconds=5))

    threads = [threading.Thread(target=claim) for _ in range(6)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert _row(uid)[0] == 2
    assert _events(uid, "shield_refill") == 1


def test_streak_award_is_capped_and_once_per_day():
    uid, _ = make_user()
    _set(uid, MAX_FREE_SHIELDS)
    svc = FlowService()
    with SessionLocal() as db:
        assert svc._mark_once(db, uid, "shield_streak_award", "2026-10-08")
        assert shield_ledger.grant_capped(db, uid, 1) == 0, "never past the maximum"
        assert not svc._mark_once(db, uid, "shield_streak_award", "2026-10-08"), "a replay of the day pays nothing"
        db.commit()
    assert _row(uid)[0] == MAX_FREE_SHIELDS


@pytest.mark.asyncio
async def test_client_supplied_balances_are_ignored():
    uid, h = make_user()
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        _set(uid, 1)
        await ac.post("/api/v1/flow/shields/use", headers=h,
                      json={"shields_available": 3, "shield_refill_at": None, "last_shield_used_date": None})
        await ac.post("/api/v1/flow/shields/use", headers=h, json={"shields_available": 3})
    assert _row(uid)[0] == 0


def test_no_endpoint_can_set_or_reset_a_balance_and_no_debug_routes_exist():
    paths = app.openapi()["paths"]
    mutating = {p for p, ops in paths.items() if set(ops) & {"post", "put", "patch", "delete"}}
    shield_routes = sorted(p for p in mutating if "shield" in p.lower())
    assert shield_routes == ["/api/v1/ai/shield-welcome/seen", "/api/v1/flow/shields/use",
                             "/api/v1/shields/ads/sessions", "/api/v1/shields/purchases/verify"], (
        "the only Shield routes are: spend one, dismiss the welcome card, register an ad showing (pays only from "
        "Google's signed callback) and submit a store token (pays only once Google Play verifies it); none can set "
        "or add a balance (tests/test_shield_rewards.py)")
    # the one legitimate "reset" is the user's own personalization history (privacy), which never touches the economy
    allowed = {"/api/v1/personalization/reset"}
    for p in paths:
        if p in allowed:
            continue
        assert not any(w in p.lower() for w in ("debug", "reset", "/test", "grant", "set-shield", "set_shield")), p
