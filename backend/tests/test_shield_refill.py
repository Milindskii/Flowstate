"""Account-level free Shield refill (3-day cooldown) and the Shield quest reward.

The clock is the SERVER's (`flow_profiles.shield_refill_at`). Nothing a client sends can start, skip or repeat it;
every grant is one compare-and-set UPDATE, so a retry, a restart, a second device or a parallel request cannot
claim the same refill twice.
"""
import threading
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import update

from app.core.economy_config import MAX_FREE_SHIELDS, SHIELD_REFILL_DAYS, weekly_quest_reward_shields
from app.db.session import SessionLocal
from app.models.flow_progression import FlowChallenge, FlowEconomicEvent, FlowProfile
from app.models.user import User
from app.services import shield_ledger
from app.services.ai_economy_service import AIEconomyService
from tests.plan_helpers import client, make_user

DAYS = timedelta(days=SHIELD_REFILL_DAYS)
T0 = datetime(2026, 10, 8, 12, 0, tzinfo=timezone.utc)


def _set(uid, shields, refill_at=None):
    with SessionLocal() as db:
        p = AIEconomyService.get_or_create_profile(db, uid)
        p.shields_available = shields
        p.shield_refill_at = refill_at
        db.commit()


def _row(uid):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        at = p.shield_refill_at
        if at is not None and at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        return p.shields_available, at


def _sync(uid, now):
    with SessionLocal() as db:
        return shield_ledger.sync_refill(db, uid, now)


def test_cooldown_is_three_days():
    assert SHIELD_REFILL_DAYS == 3


def test_a_balance_below_the_cap_starts_a_server_clock_and_grants_nothing_yet():
    uid, _ = make_user()
    _set(uid, 0)
    st = _sync(uid, T0)
    assert st.balance == 0 and not st.granted
    assert st.next_refill_at == T0 + DAYS
    assert st.seconds_until_refill == int(DAYS.total_seconds())
    assert _row(uid) == (0, T0 + DAYS)


def test_the_clock_is_not_reset_by_later_reads_logins_or_restarts():
    uid, _ = make_user()
    _set(uid, 0)
    _sync(uid, T0)
    for later in (T0 + timedelta(hours=5), T0 + timedelta(days=2), T0 + timedelta(days=2, hours=23)):
        st = _sync(uid, later)  # every read after a "login"/"restart" sees the SAME stored instant
        assert st.next_refill_at == T0 + DAYS
        assert st.balance == 0 and not st.granted


def test_the_refill_is_granted_once_when_the_server_clock_reaches_it():
    uid, _ = make_user()
    _set(uid, 0)
    _sync(uid, T0)
    assert _sync(uid, T0 + DAYS - timedelta(seconds=1)).balance == 0
    st = _sync(uid, T0 + DAYS)
    assert st.granted and st.balance == 1
    assert st.next_refill_at == T0 + DAYS + DAYS   # the clock restarts from the grant
    # reading again at the same instant, or just after, grants nothing more
    again = _sync(uid, T0 + DAYS + timedelta(seconds=5))
    assert not again.granted and again.balance == 1


def test_a_long_absence_grants_one_shield_not_a_backlog():
    uid, _ = make_user()
    _set(uid, 0)
    _sync(uid, T0)
    st = _sync(uid, T0 + timedelta(days=30))
    assert st.balance == 1 and st.granted
    assert not _sync(uid, T0 + timedelta(days=30)).granted


def test_the_balance_never_passes_the_maximum_and_the_clock_stops_there():
    uid, _ = make_user()
    _set(uid, MAX_FREE_SHIELDS - 1)
    _sync(uid, T0)
    st = _sync(uid, T0 + DAYS)
    assert st.balance == MAX_FREE_SHIELDS and st.next_refill_at is None
    assert _row(uid) == (MAX_FREE_SHIELDS, None)
    assert _sync(uid, T0 + DAYS * 5).balance == MAX_FREE_SHIELDS


def test_a_full_wallet_has_no_clock_and_spending_starts_one_fresh():
    uid, _ = make_user()
    _set(uid, MAX_FREE_SHIELDS, refill_at=T0 - timedelta(days=9))   # a stale, long-expired clock
    assert _sync(uid, T0).next_refill_at is None                   # cleared, nothing granted
    with SessionLocal() as db:
        res = db.execute(update(FlowProfile).where(FlowProfile.user_id == uid, FlowProfile.shields_available >= 2)
                         .values(**shield_ledger.debit_values(2, now=T0)))
        db.commit()
        assert res.rowcount == 1
    assert _row(uid) == (MAX_FREE_SHIELDS - 2, T0 + DAYS)   # spending from full never inherits an old clock


def test_spending_with_a_clock_already_running_keeps_that_clock():
    uid, _ = make_user()
    _set(uid, 2, refill_at=T0 + timedelta(days=1))
    with SessionLocal() as db:
        db.execute(update(FlowProfile).where(FlowProfile.user_id == uid).values(**shield_ledger.debit_values(1, now=T0)))
        db.commit()
    assert _row(uid) == (1, T0 + timedelta(days=1))


def test_parallel_claims_of_one_due_refill_grant_exactly_one_shield():
    uid, _ = make_user()
    _set(uid, 0, refill_at=T0)
    results, barrier = [], threading.Barrier(8)

    def claim():
        barrier.wait()
        with SessionLocal() as db:
            results.append(shield_ledger.sync_refill(db, uid, T0 + timedelta(minutes=1)).granted)

    threads = [threading.Thread(target=claim) for _ in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert sum(results) == 1
    assert _row(uid)[0] == 1


@pytest.mark.asyncio
async def test_status_endpoint_reports_the_server_clock_and_the_device_clock_changes_nothing():
    uid, headers = make_user()
    _set(uid, 0)
    async with client() as ac:
        first = (await ac.get("/api/v1/ai/status", headers=headers)).json()
        # A client that lies about its clock (header, query, body) cannot move the stored server timestamp.
        lying = {**headers, "X-Device-Time": "2099-01-01T00:00:00Z", "Date": "Fri, 01 Jan 2100 00:00:00 GMT"}
        second = (await ac.get("/api/v1/ai/status?now=2099-01-01T00:00:00Z", headers=lying)).json()
    assert first["shields_available"] == 0 and second["shields_available"] == 0
    assert first["next_shield_refill_at"] == second["next_shield_refill_at"] is not None
    assert first["shield_max"] == MAX_FREE_SHIELDS and first["server_now"]


@pytest.mark.asyncio
async def test_balance_and_clock_are_account_scoped_and_survive_logout_login():
    a, ha = make_user(prefix="shield-a")
    b, hb = make_user(prefix="shield-b")
    _set(a, 0)
    _set(b, 2)
    async with client() as ac:
        a1 = (await ac.get("/api/v1/ai/status", headers=ha)).json()
        b1 = (await ac.get("/api/v1/ai/status", headers=hb)).json()
        # "logout/login/restart" = brand new requests with a fresh token: same persisted state
        a2 = (await ac.get("/api/v1/ai/status", headers=ha)).json()
        flow_a = (await ac.get("/api/v1/flow", headers=ha)).json()["profile"]
    assert (a1["shields_available"], b1["shields_available"]) == (0, 2)
    assert a2["shields_available"] == 0 and a2["next_shield_refill_at"] == a1["next_shield_refill_at"]
    assert flow_a["shields_available"] == 0 and flow_a["shield_refill_at"] == a1["next_shield_refill_at"]
    assert b1["shields_available"] == 2 and _row(b)[0] == 2   # B was never touched by A's reads


@pytest.mark.asyncio
async def test_flow_overview_grants_a_due_refill_exactly_once():
    uid, headers = make_user()
    _set(uid, 1, refill_at=datetime.now(timezone.utc) - timedelta(minutes=1))
    async with client() as ac:
        first = (await ac.get("/api/v1/flow", headers=headers)).json()["profile"]
        second = (await ac.get("/api/v1/flow", headers=headers)).json()["profile"]
    assert first["shields_available"] == 2 and second["shields_available"] == 2
    assert second["shield_refill_at"] is not None


# ── quest reward ───────────────────────────────────────────────────────────────────────────────────────────────

def _complete_weekly(uid):
    with SessionLocal() as db:
        q = db.query(FlowChallenge).filter(FlowChallenge.user_id == uid, FlowChallenge.challenge_type == "priority_tasks").one()
        q.current_count, q.is_completed = q.target_count, True
        db.commit()
        return q.id


def test_the_weekly_priority_quest_pays_one_shield():
    assert weekly_quest_reward_shields("priority_tasks") == 1
    assert weekly_quest_reward_shields("focus_minutes") == 0


@pytest.mark.asyncio
async def test_quest_shield_reward_is_paid_once_per_occurrence_whatever_the_retries():
    uid, headers = make_user()
    _set(uid, 0)
    async with client() as ac:
        await ac.get("/api/v1/flow", headers=headers)  # creates this week's quests
        qid = _complete_weekly(uid)
        first = await ac.post(f"/api/v1/flow/challenge/{qid}/claim", headers=headers)
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["shields_awarded"] == 1 and body["shields_available"] == 1
        for _ in range(3):  # double tap, retry, app restart + retry
            again = await ac.post(f"/api/v1/flow/challenge/{qid}/claim", headers=headers)
            assert again.status_code in (400, 409)
    assert _row(uid)[0] == 1
    with SessionLocal() as db:
        n = db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                               FlowEconomicEvent.event_type == "challenge_claim").count()
    assert n == 1


@pytest.mark.asyncio
async def test_quest_reward_respects_the_maximum():
    uid, headers = make_user()
    _set(uid, MAX_FREE_SHIELDS)
    async with client() as ac:
        await ac.get("/api/v1/flow", headers=headers)
        qid = _complete_weekly(uid)
        res = (await ac.post(f"/api/v1/flow/challenge/{qid}/claim", headers=headers)).json()
    assert res["shields_awarded"] == 0 and res["shields_available"] == MAX_FREE_SHIELDS


@pytest.mark.asyncio
async def test_another_account_cannot_claim_my_quest():
    a, ha = make_user(prefix="q-a")
    b, hb = make_user(prefix="q-b")
    async with client() as ac:
        await ac.get("/api/v1/flow", headers=ha)
        qid = _complete_weekly(a)
        stolen = await ac.post(f"/api/v1/flow/challenge/{qid}/claim", headers=hb)
    assert stolen.status_code == 404
