"""Streak restore: the server decides eligibility and price, and spending + restoring is one atomic, idempotent step.

Covers: the overview reports eligibility and cost; a broken streak is restored for exactly the server's cost; a stale
price, an unbroken streak, a second restore the same day and an unaffordable restore are refused without charging; a
replayed key charges nothing; concurrent taps (same key or different keys) restore once; and the legacy
/flow/shields/use no longer moves the qualifying day backwards.
"""
import asyncio
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from app.core.economy_config import SHIELD_COST_STREAK_RESTORE
from app.db.session import SessionLocal
from app.models.flow_progression import FlowEconomicEvent, FlowProfile
from tests.plan_helpers import client, make_user

IST = ZoneInfo("Asia/Kolkata")
COST = SHIELD_COST_STREAK_RESTORE


def _day(offset: int) -> str:
    return (datetime.now(timezone.utc).astimezone(IST) + timedelta(days=offset)).strftime("%Y-%m-%d")


def _profile(uid, **values):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        for k, v in values.items():
            setattr(p, k, v)
        db.commit()


def _row(uid):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        return p.shields_available, p.current_streak, p.last_qualifying_date, p.last_shield_used_date


def _events(uid, kind="streak_restore"):
    with SessionLocal() as db:
        return db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                  FlowEconomicEvent.event_type == kind).count()


async def _broken_user(ac, shields=2, streak=6, last=-3):
    uid, h = make_user()
    await ac.get("/api/v1/flow/overview", headers=h)
    _profile(uid, shields_available=shields, current_streak=streak, longest_streak=streak,
             last_qualifying_date=_day(last), last_shield_used_date=None)
    return uid, h


def _restore(ac, h, key=None, cost=COST):
    return ac.post("/api/v1/flow/streak/restore", headers=h,
                   json={"idempotency_key": key or uuid.uuid4().hex, "expected_cost": cost})


@pytest.mark.asyncio
async def test_overview_reports_eligibility_and_the_server_cost():
    async with client() as ac:
        uid, h = await _broken_user(ac)
        rec = (await ac.get("/api/v1/flow/overview", headers=h)).json()["streak_recovery"]
        assert rec == {**rec, "eligible": True, "streak": 6, "missed_days": 2, "cost": COST, "can_afford": True}
        alone = (await ac.get("/api/v1/flow/streak/recovery", headers=h)).json()
        assert alone["eligible"] is True and alone["cost"] == COST


@pytest.mark.asyncio
async def test_restore_spends_exactly_the_cost_and_keeps_the_streak_alive():
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=2)
        res = await _restore(ac, h)
        assert res.status_code == 200, res.text
        body = res.json()
        assert body["restored"] and not body["replayed"] and body["shields_spent"] == COST
        assert body["shields_available"] == 2 - COST and body["current_streak"] == 6
        assert _row(uid) == (2 - COST, 6, _day(-1), _day(0))
        after = (await ac.get("/api/v1/flow/overview", headers=h)).json()
        assert after["streak_recovery"]["eligible"] is False
        assert after["profile"]["shields_available"] == 2 - COST
        # the next qualifying session continues the restored streak
        sid = (await ac.post("/api/v1/flow/session/start", headers=h, json={})).json()["session_id"]
        done = (await ac.post(f"/api/v1/flow/session/{sid}/complete?test_mode=true", headers=h,
                              json={"task_completed": True})).json()
        assert done["current_streak"] == 7
    assert _events(uid) == 1


@pytest.mark.asyncio
async def test_a_replayed_key_returns_the_first_result_and_charges_nothing():
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=3)
        key = uuid.uuid4().hex
        first = (await _restore(ac, h, key)).json()
        second = await _restore(ac, h, key)
    assert second.status_code == 200 and second.json()["replayed"] is True
    assert second.json()["shields_available"] == first["shields_available"] == 3 - COST
    assert _row(uid)[0] == 3 - COST and _events(uid) == 1


@pytest.mark.asyncio
async def test_concurrent_taps_with_one_key_or_many_restore_once():
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=3)
        key = uuid.uuid4().hex
        same = await asyncio.gather(*[_restore(ac, h, key) for _ in range(5)])
        other = await asyncio.gather(*[_restore(ac, h) for _ in range(3)])
    assert all(r.status_code == 200 for r in same)
    assert sum(1 for r in same if not r.json()["replayed"]) == 1
    assert all(r.status_code == 409 for r in other), "a different key the same day restores nothing more"
    assert _row(uid)[0] == 3 - COST and _events(uid) == 1


@pytest.mark.asyncio
async def test_a_stale_price_is_refused_before_any_spend():
    async with client() as ac:
        uid, h = await _broken_user(ac)
        res = await _restore(ac, h, cost=COST + 1)
        res0 = await _restore(ac, h, cost=0)
    assert res.status_code == 409 and res0.status_code == 409
    assert "Nothing was charged" in res.json()["detail"]
    assert _row(uid)[0] == 2 and _events(uid) == 0


@pytest.mark.asyncio
async def test_unbroken_streak_and_no_streak_are_not_restorable():
    async with client() as ac:
        uid, h = await _broken_user(ac, last=-1)  # qualified yesterday: not broken
        assert (await _restore(ac, h)).status_code == 409
        uid2, h2 = await _broken_user(ac, streak=0)
        assert (await _restore(ac, h2)).status_code == 409
    assert _row(uid)[0] == 2 and _row(uid2)[0] == 2


@pytest.mark.asyncio
async def test_without_enough_shields_nothing_changes():
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=0)
        rec = (await ac.get("/api/v1/flow/streak/recovery", headers=h)).json()
        res = await _restore(ac, h)
    assert rec["eligible"] is True and rec["can_afford"] is False
    assert res.status_code == 402
    assert _row(uid) == (0, 6, _day(-3), None)


@pytest.mark.asyncio
async def test_the_daily_streak_shield_and_a_restore_share_one_use_per_day():
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=3)
        assert (await ac.post("/api/v1/flow/shields/use", headers=h)).status_code == 200
        res = await _restore(ac, h)
    assert res.status_code == 409
    assert _row(uid)[0] == 2


@pytest.mark.asyncio
async def test_legacy_shield_use_never_moves_the_qualifying_day_backwards():
    """Spending the daily Shield after already qualifying today used to rewind the day to yesterday, so the next
    session today counted the streak a second time."""
    async with client() as ac:
        uid, h = await _broken_user(ac, shields=3, streak=4, last=0)
        assert (await ac.post("/api/v1/flow/shields/use", headers=h)).status_code == 200
        assert _row(uid)[2] == _day(0)
        sid = (await ac.post("/api/v1/flow/session/start", headers=h, json={})).json()["session_id"]
        done = (await ac.post(f"/api/v1/flow/session/{sid}/complete?test_mode=true", headers=h,
                              json={"task_completed": True})).json()
    assert done["current_streak"] == 4, "already qualified today: no second increment"


@pytest.mark.asyncio
async def test_restore_needs_a_signed_in_user_and_ignores_client_balances():
    async with client() as ac:
        assert (await ac.post("/api/v1/flow/streak/restore",
                              json={"idempotency_key": "x" * 10, "expected_cost": COST})).status_code in (401, 403)
        uid, h = await _broken_user(ac, shields=1)
        res = await ac.post("/api/v1/flow/streak/restore", headers=h, json={
            "idempotency_key": uuid.uuid4().hex, "expected_cost": COST, "shields_available": 50, "cost": 0})
    assert res.status_code == 200
    assert _row(uid)[0] == 1 - COST
