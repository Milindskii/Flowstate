"""PostgreSQL-only: real multi-connection contention on the AI gateway, and catalog checks (RLS, indexes).

Skipped on SQLite. Run with FLOWSTATE_TEST_DATABASE_URL pointing at a disposable database whose name contains "test".
"""
import threading
import time
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import text

from app.core.economy_config import SHIELD_COST_BUILD_MY_DAY
from app.db.session import SessionLocal, engine
from app.models.ai_usage import AIRequest, AIUsagePeriod, AIUsageRecord
from app.models.flow_progression import FlowProfile
from app.services import ai_gateway
from app.services.ai_economy_service import AIEconomyService

from .plan_helpers import make_user

pytestmark = pytest.mark.skipif(engine.dialect.name != "postgresql", reason="PostgreSQL-only contention tests")

N = 40


def _race(fn, n=N):
    """Run fn(i) in n threads released together; returns the list of results/exceptions in thread order."""
    barrier, out = threading.Barrier(n), [None] * n

    def run(i):
        barrier.wait()
        try:
            out[i] = fn(i)
        except Exception as e:  # noqa: BLE001 - collected for assertions
            out[i] = e

    threads = [threading.Thread(target=run, args=(i,)) for i in range(n)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    return out


def _usage(uid):
    with SessionLocal() as db:
        u = db.query(AIUsageRecord).filter(AIUsageRecord.user_id == uid).one()
        return u.free_uses_consumed, u.shield_uses_consumed, u.total_ai_uses


def _begin(uid, key, shield=False):
    with SessionLocal() as db:
        return ai_gateway.begin(db, user_id=uid, idempotency_key=key, fingerprint="f", consume_shield=shield)


@pytest.fixture(autouse=True)
def _generous_rate_limit(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_FREE", 10_000)
    monkeypatch.setattr(settings, "AI_RATE_LIMIT_PER_HOUR_PRO", 10_000)


def test_40_way_race_for_one_users_free_trial_yields_exactly_one_reservation():
    uid, _ = make_user()
    results = _race(lambda i: _begin(uid, f"k{i}"))
    tickets = [r for r in results if isinstance(r, ai_gateway.Ticket)]
    refusals = [r for r in results if isinstance(r, ai_gateway.GatewayError)]
    unexpected = [r for r in results if not isinstance(r, (ai_gateway.Ticket, ai_gateway.GatewayError))]
    assert len(tickets) == 1 and not unexpected, (len(tickets), unexpected[:2])
    assert {r.code for r in refusals} <= {"another_request_in_flight", "request_in_progress"}
    assert _usage(uid)[0] == 1


def test_40_way_race_on_one_idempotency_key_yields_exactly_one_reservation():
    uid, _ = make_user()
    results = _race(lambda i: _begin(uid, "same-key"))
    assert sum(isinstance(r, ai_gateway.Ticket) for r in results) == 1
    assert all(isinstance(r, (ai_gateway.Ticket, ai_gateway.GatewayError)) for r in results)
    assert _usage(uid)[0] == 1
    with SessionLocal() as db:
        assert db.query(AIRequest).filter(AIRequest.user_id == uid).count() == 1


def test_conditional_charge_never_overspends_the_free_trial_or_shields():
    uid, _ = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_usage(db, uid)
        AIEconomyService.get_or_create_profile(db, uid).shields_available = 3 * SHIELD_COST_BUILD_MY_DAY + 1
        db.commit()

    def charge(_i):
        with SessionLocal() as db:
            try:
                src, _units = ai_gateway._charge(db, uid, False, True, datetime.now(timezone.utc).date())
                db.commit()
                return src
            except ai_gateway.QuotaExceeded:
                db.rollback()
                return "none"

    got = _race(charge)
    assert got.count("free") == 1 and got.count("shield") == 3 and got.count("none") == N - 4, got
    with SessionLocal() as db:
        # 3 whole prices were taken; the odd leftover Shield is never taken as a partial price, nor driven negative
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == 1
    assert _usage(uid)[0] == 1


def test_pro_caps_are_exact_under_contention(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "AI_PRO_DAILY_CAP", 7)
    uid, _ = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_usage(db, uid)

    def charge(_i):
        with SessionLocal() as db:
            try:
                ai_gateway._charge(db, uid, True, False, datetime.now(timezone.utc).date())
                db.commit()
                return True
            except ai_gateway.QuotaExceeded:
                db.rollback()
                return False

    got = _race(charge)
    assert got.count(True) == 7
    with SessionLocal() as db:
        rows = {r.period_kind: r.used for r in db.query(AIUsagePeriod).filter(AIUsagePeriod.user_id == uid)}
    assert rows == {"day": 7, "month": 7}, "a refused day unit must not leave a month unit spent"


def test_refund_happens_exactly_once_under_contention():
    uid, _ = make_user()
    ticket = _begin(uid, "refund-me")
    assert _usage(uid)[0] == 1

    def fail(_i):
        with SessionLocal() as db:
            return ai_gateway.fail(db, ticket, "provider_unavailable")

    got = _race(fail)
    assert got.count(True) == 1 and got.count(False) == N - 1
    assert _usage(uid)[0] == 0, "refunded once, never negative"


def test_success_and_failure_racing_settle_consistently():
    uid, _ = make_user()
    ticket = _begin(uid, "settle")

    def settle(i):
        with SessionLocal() as db:
            return ("ok", ai_gateway.succeed(db, ticket, {"tasks": []})) if i % 2 == 0 \
                else ("fail", ai_gateway.fail(db, ticket, "timeout"))

    got = _race(settle, 20)
    winners = [g for g in got if g[1] is True]
    assert len(winners) == 1
    free, _shield, total = _usage(uid)
    assert (free, total) == ((1, 1) if winners[0][0] == "ok" else (0, 0))
    with SessionLocal() as db:
        assert db.query(AIRequest).filter(AIRequest.user_id == uid).one().status in ("succeeded", "failed")


def test_stale_reservation_sweep_refunds_exactly_once_under_contention():
    uid, _ = make_user()
    _begin(uid, "stuck")
    with SessionLocal() as db:
        db.query(AIRequest).filter(AIRequest.user_id == uid).update(
            {"deadline_at": datetime.now(timezone.utc) - timedelta(seconds=1)})
        db.commit()

    def sweep(_i):
        with SessionLocal() as db:
            return ai_gateway.expire_stale(db, uid)

    got = _race(sweep, 20)
    assert sum(got) == 1 and _usage(uid)[0] == 0


def test_rate_limit_counter_is_gap_free_for_50_connections():
    got = _race(lambda _i: _hit("rl:test"), 50)
    assert sorted(got) == list(range(1, 51))


def _hit(bucket):
    with SessionLocal() as db:
        return ai_gateway.hit_window(db, bucket, 3600)


def test_unique_partial_index_blocks_second_inflight_row_at_the_database():
    uid, _ = make_user()
    _begin(uid, "first")
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key="sneaky", request_sha256="x", status="reserved",
                         charge_source="none", deadline_at=datetime.now(timezone.utc) + timedelta(minutes=1)))
        with pytest.raises(Exception, match="uq_ai_requests_one_inflight"):
            db.commit()


# ---- catalog: indexes and row level security -------------------------------------------------------------------

def test_indexes_exist_with_the_expected_definitions():
    with engine.connect() as c:
        defs = {r[0]: r[1] for r in c.execute(text(
            "select indexname, indexdef from pg_indexes where schemaname='public' "
            "and tablename in ('ai_requests','ai_usage_periods','rate_limit_windows')"))}
    inflight = defs["uq_ai_requests_one_inflight"].lower()
    assert "unique" in inflight and "(user_id)" in inflight and "status" in inflight and "reserved" in inflight
    assert "ix_ai_requests_user_id" in defs
    assert "uq_ai_requests_user_key" in defs and "(user_id, idempotency_key)" in defs["uq_ai_requests_user_key"]
    assert any("(user_id, period_kind, period_start)" in d for d in defs.values())
    assert any("(bucket_key, window_start)" in d for d in defs.values())


def test_rls_is_enabled_on_new_tables_and_every_public_table():
    with engine.connect() as c:
        rows = c.execute(text(
            "select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace "
            "where n.nspname='public' and c.relkind='r' and c.relname <> 'alembic_version'")).all()
    by_name = dict(rows)
    for t in ("ai_requests", "ai_usage_periods", "rate_limit_windows"):
        assert by_name[t] is True, f"RLS missing on {t}"
    missing = sorted(n for n, rls in by_name.items() if not rls)
    assert not missing, f"tables without row level security: {missing}"


def test_unprivileged_role_cannot_read_gateway_tables():
    """With RLS enabled and no policies, a non-owner role (like Supabase's anon/authenticated) sees nothing."""
    with engine.begin() as c:
        c.execute(text("do $$ begin if not exists (select 1 from pg_roles where rolname='flowstate_test_anon') "
                       "then create role flowstate_test_anon nologin; end if; end $$"))
        c.execute(text("grant usage on schema public to flowstate_test_anon"))
        c.execute(text("grant select on ai_requests, ai_usage_periods, rate_limit_windows to flowstate_test_anon"))
    uid, _ = make_user()
    _begin(uid, "visible-to-owner-only")
    try:
        with engine.begin() as c:
            c.execute(text("set local role flowstate_test_anon"))
            counts = [c.execute(text(f"select count(*) from {t}")).scalar()
                      for t in ("ai_requests", "ai_usage_periods", "rate_limit_windows")]
        assert counts == [0, 0, 0], counts
    finally:
        with engine.begin() as c:
            c.execute(text("revoke all on ai_requests, ai_usage_periods, rate_limit_windows from flowstate_test_anon"))
            c.execute(text("revoke usage on schema public from flowstate_test_anon"))
            c.execute(text("drop role if exists flowstate_test_anon"))


def test_40_way_race_for_exactly_one_price_of_shields_has_one_winner_and_never_goes_negative():
    uid, _ = make_user()
    with SessionLocal() as db:
        usage = AIEconomyService.get_or_create_usage(db, uid)
        usage.free_uses_consumed = usage.free_uses_total
        AIEconomyService.get_or_create_profile(db, uid).shields_available = SHIELD_COST_BUILD_MY_DAY
        db.commit()

    got = _race(lambda i: _begin(uid, f"shield-race-{i}", shield=True))
    winners = [g for g in got if isinstance(g, ai_gateway.Ticket)]
    assert len(winners) == 1 and winners[0].charge_source == "shield" and winners[0].charge_units == SHIELD_COST_BUILD_MY_DAY
    assert all(isinstance(g, Exception) for g in got if g not in winners), "every loser is refused, none gets AI"
    with SessionLocal() as db:
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == 0
        assert db.query(AIRequest).filter(AIRequest.user_id == uid, AIRequest.status == "reserved").count() == 1

    with SessionLocal() as db:  # the winner's failure gives the whole price back once, however often it is reported
        assert [ai_gateway.fail(db, winners[0], "timeout") for _ in range(3)] == [True, False, False]
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == SHIELD_COST_BUILD_MY_DAY


def test_40_way_race_for_one_replan_shield_has_one_winner_and_refunds_exactly_once():
    from app.core.economy_config import SHIELD_COST_AI_REPLAN

    uid, _ = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_usage(db, uid)
        AIEconomyService.get_or_create_profile(db, uid).shields_available = SHIELD_COST_AI_REPLAN
        db.commit()

    def begin_replan(i):
        with SessionLocal() as db:
            return ai_gateway.begin_replan(db, user_id=uid, idempotency_key=f"rp-race-{i}", fingerprint="f")

    got = _race(begin_replan)
    winners = [g for g in got if isinstance(g, ai_gateway.Ticket)]
    assert len(winners) == 1 and winners[0].charge_source == ai_gateway.REPLAN_SHIELD
    assert all(isinstance(g, Exception) for g in got if g not in winners), "every loser is refused, none gets AI"
    with SessionLocal() as db:
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == 0
        assert db.query(AIUsagePeriod).filter(AIUsagePeriod.user_id == uid, AIUsagePeriod.period_kind == "replan_day").one().used == 1

    with SessionLocal() as db:  # a failure gives back the Shield AND the budget unit, once
        assert [ai_gateway.fail(db, winners[0], "no_understanding") for _ in range(3)] == [True, False, False]
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == SHIELD_COST_AI_REPLAN
        assert db.query(AIUsagePeriod).filter(AIUsagePeriod.user_id == uid, AIUsagePeriod.period_kind == "replan_day").one().used == 0
