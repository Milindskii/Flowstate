"""Replan admission: one AI request in flight per user (shared with Build My Day, Postgres-backed) and a
distributed per-user burst limit on every Replan dry run (AI or deterministic)."""
import asyncio
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.ai_usage import AIRequest, AIUsagePeriod, RateLimitWindow
from app.services import ai_gateway, replan_ai
from tests.plan_helpers import client, make_user
from tests.test_replan_ai import NOW, Model, _day, op, ops, ref

AI_MESSAGE = "scrap the evening plans with friends"  # the deterministic rules cannot read it: the model is asked
RULES_MESSAGE = "move gym to 8"  # understood without the model


def _body(message):
    return {"selected_date": "2026-10-05", "user_message": message, "current_local_time": NOW.isoformat(),
            "timezone": "Asia/Kolkata", "ai_consent": True}


def _rows(uid):
    with SessionLocal() as db:
        return [(r.kind, r.status, r.charge_source)
                for r in db.query(AIRequest).filter(AIRequest.user_id == uid).order_by(AIRequest.created_at)]


def _replan_budget_used(uid):
    with SessionLocal() as db:
        return sum(r.used for r in db.query(AIUsagePeriod).filter(
            AIUsagePeriod.user_id == uid, AIUsagePeriod.period_kind == "replan_day"))


def _hold_inflight(uid, kind="plan"):
    """An in-flight AI request (e.g. Build My Day) for [uid], as another worker would have written it."""
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key=f"other-{uuid.uuid4().hex}", kind=kind, status="reserved",
                         request_sha256="x", deadline_at=datetime.now(timezone.utc) + timedelta(minutes=5)))
        db.commit()


@pytest.fixture(autouse=True)
def _fresh_minute_guard():
    replan_ai._RECENT.clear()
    yield
    replan_ai._RECENT.clear()


# ── one AI Replan in flight per user ─────────────────────────────────────────

@pytest.mark.asyncio
async def test_second_ai_replan_while_one_is_in_flight_is_refused_with_409(monkeypatch):
    entered, release = threading.Event(), threading.Event()

    def answer(prompt):
        entered.set()
        release.wait(5)
        return ops(op("cancel_task", ref(prompt, "Going out")))

    model = Model(monkeypatch, answer)
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        first = asyncio.create_task(ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE)))
        for _ in range(100):
            if entered.is_set():
                break
            await asyncio.sleep(0.05)
        assert entered.is_set(), "the first request never reached the model"
        second = await ac.post("/api/v1/ai/replan", headers=h, json=_body(AI_MESSAGE))
        release.set()
        first = await first
    assert first.status_code == 200, first.text
    assert second.status_code == 409, second.text
    assert second.json()["detail"]["code"] == "another_request_in_flight"
    assert second.headers.get("retry-after")
    assert len(model.calls) == 1, "only one request may reach the provider"
    assert _replan_budget_used(uid) == 1, "the refused request spends no budget"
    assert _rows(uid) == [("replan", "succeeded", "replan_shield")]


@pytest.mark.asyncio
async def test_ai_replan_is_refused_while_build_my_day_is_in_flight(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    uid, h = make_user()
    _day(uid)
    _hold_inflight(uid, kind="plan")
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    assert r.status_code == 409, r.text
    assert model.calls == []
    assert _replan_budget_used(uid) == 0


@pytest.mark.asyncio
async def test_deterministic_replan_never_needs_the_ai_slot(monkeypatch):
    model = Model(monkeypatch, lambda p: ops())
    uid, h = make_user()
    _day(uid)
    _hold_inflight(uid, kind="plan")  # Build My Day running: a rules-only Replan still answers
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(RULES_MESSAGE))
    assert r.status_code == 200, r.text
    assert model.calls == []
    assert [k for k, *_ in _rows(uid)] == ["plan"], "no reservation for a deterministic request"
    assert _replan_budget_used(uid) == 0


@pytest.mark.asyncio
async def test_build_my_day_is_refused_while_ai_replan_is_in_flight(monkeypatch):
    uid, h = make_user()
    _hold_inflight(uid, kind="replan")
    async with client() as ac:
        r = await ac.post("/api/v1/ai/plan", headers=h, json={"raw_text": "write report", "idempotency_key": "k1"})
    assert r.status_code == 409, r.text
    assert r.json()["failure_code"] == "another_request_in_flight"


@pytest.mark.asyncio
@pytest.mark.parametrize("answer", [lambda p: ops(op("cancel_task", ref(p, "Going out"))),
                                    lambda p: "not json at all"])
async def test_ai_replan_releases_its_slot_on_success_and_failure(monkeypatch, answer):
    Model(monkeypatch, answer)
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
        await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    statuses = [s for _, s, _ in _rows(uid)]
    assert len(statuses) == 2 and "reserved" not in statuses, statuses
    assert all(source == "replan_shield" for *_, source in _rows(uid)), "a Basic AI Replan pays with Shields only"


@pytest.mark.asyncio
async def test_over_budget_ai_replan_releases_its_slot(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    monkeypatch.setattr(replan_ai, "FREE_REPLAN_AI_PER_DAY", 1)
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
        r = await ac.post("/api/v1/calendar/replan", headers=h, json=_body(AI_MESSAGE))
    assert r.status_code == 200, r.text
    assert len(model.calls) == 1
    assert "reserved" not in [s for _, s, _ in _rows(uid)]


def test_claim_slot_admits_exactly_one_concurrent_claim():
    uid, _ = make_user()
    wins, refusals, lock = [], [], threading.Lock()
    barrier = threading.Barrier(8)

    def worker():
        barrier.wait()
        with SessionLocal() as db:
            try:
                rid = ai_gateway.claim_slot(db, user_id=uid, kind="replan", fingerprint="f")
                with lock:
                    wins.append(rid)
            except ai_gateway.GatewayError as e:
                with lock:
                    refusals.append((e.http_status, e.code))

    threads = [threading.Thread(target=worker) for _ in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert len(wins) == 1, (wins, refusals)
    assert refusals == [(409, "another_request_in_flight")] * 7


def test_a_crashed_claim_expires_and_frees_the_slot():
    uid, _ = make_user()
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key="crashed", kind="replan", status="reserved",
                         request_sha256="x", deadline_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
        db.commit()
        rid = ai_gateway.claim_slot(db, user_id=uid, kind="replan", fingerprint="f")
        ai_gateway.release_slot(db, rid, uid, ok=True)
    assert sorted(s for _, s, _ in _rows(uid)) == ["expired", "succeeded"]


# ── distributed burst limit on every Replan dry run ──────────────────────────

@pytest.mark.asyncio
async def test_deterministic_replan_burst_is_limited_per_user_across_both_routes(monkeypatch):
    model = Model(monkeypatch, lambda p: ops())
    monkeypatch.setattr(settings, "REPLAN_BURST_PER_MINUTE", 3)
    uid, h = make_user()
    other_uid, other_h = make_user()
    _day(uid)
    _day(other_uid)
    async with client() as ac:
        codes = []
        for path in ("/api/v1/calendar/replan", "/api/v1/ai/replan", "/api/v1/calendar/replan",
                     "/api/v1/ai/replan"):
            codes.append((await ac.post(path, headers=h, json=_body(RULES_MESSAGE))))
        other = await ac.post("/api/v1/calendar/replan", headers=other_h, json=_body(RULES_MESSAGE))
    assert [r.status_code for r in codes] == [200, 200, 200, 429], [r.text for r in codes]
    refused = codes[-1]
    assert refused.json()["detail"]["code"] == "rate_limited"
    assert refused.headers.get("retry-after")
    assert other.status_code == 200, "the limit is per user"
    assert model.calls == []
    assert _rows(uid) == [] and _replan_budget_used(uid) == 0, "no AI reservation or budget for deterministic work"


def test_burst_counter_lives_in_the_shared_rate_limit_table(monkeypatch):
    """The count is the Postgres/SQLite `rate_limit_windows` row every worker increments, not process memory."""
    uid, _ = make_user()
    with SessionLocal() as db:
        for _ in range(2):
            ai_gateway.admit_replan_burst(db, uid)
        rows = db.query(RateLimitWindow).filter(RateLimitWindow.bucket_key == f"replan:{uid}").all()
    assert sum(r.count for r in rows) == 2
