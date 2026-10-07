"""AI Replan economy: the Shield decision happens BEFORE the model is called.

Rules-only Replan = 0 Shields. A message only the language model can read = SHIELD_COST_AI_REPLAN Shield for a Basic
user, confirmed by the user first and taken atomically by the backend (the same primitive as Build My Day). Pro keeps
the fair-use budget and never pays Shields. The deterministic planner stays the authority; the model only returns
structured intents.
"""
import asyncio
import time
import uuid
from datetime import timedelta

import pytest

from app.core.config import settings
from app.core.economy_config import SHIELD_COST_AI_REPLAN
from app.db.session import SessionLocal
from app.models.ai_usage import AIRequest, AIUsagePeriod
from app.models.flow_progression import FlowProfile
from app.models.task import TaskStatus
from app.services import ai_gateway, replan_ai
from app.services.ai_economy_service import AIEconomyService
from tests.plan_helpers import IST, client, make_user
from tests.test_ai_gateway import _make_pro
from tests.test_apply_replan_semantics import at, get, seed
from tests.test_replan_ai import NOW, Model, op, ops, ref
from tests.test_replan_compound_and_fixed_blocks import TODAY

# the rules cannot read this one: the model is needed
AI_MESSAGE = "scrap the evening plans with friends"
RULES_MESSAGE = "skip gym"
COST = SHIELD_COST_AI_REPLAN


@pytest.fixture(autouse=True)
def _fresh_minute_guard():
    replan_ai.reset_rate_limit()
    yield
    replan_ai.reset_rate_limit()


def _day(uid):
    return {
        "out": seed(uid, "Going out", at(18, 30), 60, planned_date=TODAY, time_locked=True, is_commitment=True),
        "ml": seed(uid, "ML assignment", at(11, 0), 60, planned_date=TODAY),
        "flow": seed(uid, "Work on Flowstate app", at(13, 30), 60, planned_date=TODAY),
        "gym": seed(uid, "Gym", at(17, 0), 60, planned_date=TODAY),
        "dsa": seed(uid, "DSA practice", at(21, 0), 60, planned_date=TODAY),
        "done": seed(uid, "Morning run", at(10, 30), 30, planned_date=TODAY, status=TaskStatus.completed),
    }


def _user(shields=2):
    uid, h = make_user()
    with SessionLocal() as db:
        AIEconomyService.get_or_create_profile(db, uid).shields_available = shields
        db.commit()
    return uid, h


def _shields(uid):
    with SessionLocal() as db:
        return db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available


def _rows(uid):
    with SessionLocal() as db:
        return [(r.kind, r.status, r.charge_source, r.charge_units)
                for r in db.query(AIRequest).filter(AIRequest.user_id == uid).order_by(AIRequest.created_at)]


def _budget(uid):
    with SessionLocal() as db:
        return sum(r.used for r in db.query(AIUsagePeriod).filter(
            AIUsagePeriod.user_id == uid, AIUsagePeriod.period_kind == "replan_day"))


async def _post(ac, h, message, consent=False, key=None, **extra):
    body = {"selected_date": "2026-10-05", "user_message": message, "current_local_time": NOW.isoformat(),
            "timezone": "Asia/Kolkata", "ai_consent": consent, **extra}
    if key:
        body["idempotency_key"] = key
    return await ac.post("/api/v1/ai/replan", headers=h, json=body)


def _is_paid(r):
    return r.status_code == 200 and r.json()["ai_required"] is None


def _paid(rs):
    return sum(_is_paid(r) for r in rs)


def _safe_loser(r):
    """Refused (another AI request in flight) or told it needs a Shield it no longer has: nothing was taken."""
    return r.status_code == 409 or (r.status_code == 200 and r.json()["ai_required"]["can_afford"] is False)


def _cancel_going_out(p):
    return ops(op("cancel_task", ref(p, "Going out")))


# ── 1. rules-only Replan is free ─────────────────────────────────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("shields", [0, 2])
async def test_rules_only_replan_costs_nothing_and_never_calls_the_model(monkeypatch, shields):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(shields)
    _day(uid)
    async with client() as ac:
        r = await _post(ac, h, RULES_MESSAGE, consent=True)
    assert r.status_code == 200, r.text
    assert r.json()["ai_required"] is None
    assert model.calls == [] and _shields(uid) == shields and _rows(uid) == [] and _budget(uid) == 0


# ── 2-3. AI needed: ask first; cancel = nothing happened ─────────────────────

@pytest.mark.asyncio
async def test_ai_needed_without_consent_asks_first_and_touches_nothing(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(2)
    _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=False)
    body = r.json()
    assert r.status_code == 200, r.text
    assert body["ai_required"] == {"kind": "shield", "shield_cost": COST, "shields_available": 2, "can_afford": True}
    assert body["plan_diff"]["apply_request"]["task_updates"] == [] and body["plan_diff"]["moved_tasks"] == []
    assert model.calls == [], "no model call before the user confirms"
    assert _shields(uid) == 2 and _rows(uid) == [] and _budget(uid) == 0, "cancelling here costs nothing"


# ── 4. confirm = exactly one Shield ──────────────────────────────────────────

@pytest.mark.asyncio
async def test_confirmed_ai_replan_takes_exactly_one_shield_and_one_model_call(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(2)
    ids = _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=True)
    assert r.status_code == 200, r.text
    assert r.json()["ai_required"] is None
    assert [c["task_id"] for c in r.json()["plan_diff"]["cancelled_tasks"]] == [ids["out"]]
    assert len(model.calls) == 1
    assert _shields(uid) == 2 - COST
    assert _rows(uid) == [("replan", "succeeded", "replan_shield", COST)]
    assert _budget(uid) == 1, "the daily fair-use budget is spent in the same transaction"
    assert get(ids["out"]).status != TaskStatus.cancelled, "a Replan proposal never writes"


# ── 5. insufficient Shields ──────────────────────────────────────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("consent", [False, True])
async def test_no_shield_means_no_model_call_no_charge_and_the_text_is_not_lost(monkeypatch, consent):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(0)
    _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=consent)
    assert r.status_code == 200, r.text
    assert r.json()["ai_required"] == {"kind": "shield", "shield_cost": COST, "shields_available": 0, "can_afford": False}
    assert model.calls == [] and _shields(uid) == 0 and _rows(uid) == [] and _budget(uid) == 0


# ── 6. failure = exact refund ────────────────────────────────────────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("answer", [lambda p: "not json at all", lambda p: RuntimeError("boom"),
                                    lambda p: ops(), lambda p: ops(op("cancel_task", "t99"))])
async def test_a_failed_ai_replan_gives_the_shield_and_the_budget_back(monkeypatch, answer):
    model = Model(monkeypatch, answer)
    uid, h = _user(2)
    _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=True)
    assert r.status_code in (200, 422), r.text
    assert len(model.calls) == 1
    assert _shields(uid) == 2, "nothing usable came back: the whole price is refunded"
    assert _budget(uid) == 0
    assert [row[:3] for row in _rows(uid)] == [("replan", "failed", "replan_shield")]


@pytest.mark.asyncio
async def test_a_crash_after_the_charge_refunds_it(monkeypatch):
    Model(monkeypatch, _cancel_going_out)
    from app.services import calendar_service

    def boom(*a, **k):
        raise RuntimeError("scheduler blew up")

    monkeypatch.setattr(calendar_service, "plan", boom)  # the deterministic scheduler, AFTER the model answered
    uid, h = _user(2)
    _day(uid)
    async with client() as ac:
        with pytest.raises(RuntimeError):
            await _post(ac, h, AI_MESSAGE, consent=True)
    assert _shields(uid) == 2 and _budget(uid) == 0
    assert [row[:3] for row in _rows(uid)] == [("replan", "failed", "replan_shield")]


@pytest.mark.asyncio
async def test_a_clarifying_answer_is_free_but_still_uses_the_fair_use_budget(monkeypatch):
    clar = {"question": "Which task do you mean?", "task_ref": None,
            "options": [{"label": "Gym", "message": "skip gym"}]}
    Model(monkeypatch, lambda p: ops(confidence=0.9, clarification=clar))
    uid, h = _user(2)
    _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=True)
    assert r.status_code == 200 and r.json()["plan_diff"]["clarification"]["question"] == "Which task do you mean?"
    assert _shields(uid) == 2 and _budget(uid) == 1
    assert _rows(uid)[0][:3] == ("replan", "failed", "replan_shield")


# ── 7. duplicates and retries never double-charge ───────────────────────────

@pytest.mark.asyncio
async def test_the_same_request_id_twice_charges_once_and_calls_the_model_once(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(3)
    _day(uid)
    key = f"rp-{uuid.uuid4().hex}"
    async with client() as ac:
        a = await _post(ac, h, AI_MESSAGE, consent=True, key=key)
        b = await _post(ac, h, AI_MESSAGE, consent=True, key=key)
    assert a.status_code == b.status_code == 200
    assert [c["title"] for c in a.json()["plan_diff"]["cancelled_tasks"]] == ["Going out"]
    assert [c["title"] for c in b.json()["plan_diff"]["cancelled_tasks"]] == ["Going out"]
    assert len(model.calls) == 1 and _shields(uid) == 3 - COST and _budget(uid) == 1


@pytest.mark.asyncio
async def test_a_failed_then_retried_request_id_pays_once_in_total(monkeypatch):
    state = {"fail": True}

    def answer(p):
        return "not json at all" if state["fail"] else _cancel_going_out(p)

    model = Model(monkeypatch, answer)
    uid, h = _user(2)
    _day(uid)
    key = f"rp-{uuid.uuid4().hex}"
    async with client() as ac:
        await _post(ac, h, AI_MESSAGE, consent=True, key=key)
        assert _shields(uid) == 2
        state["fail"] = False
        ok = await _post(ac, h, AI_MESSAGE, consent=True, key=key)
    assert ok.status_code == 200 and len(model.calls) == 2
    assert _shields(uid) == 2 - COST and _budget(uid) == 1


@pytest.mark.asyncio
async def test_a_request_id_cannot_be_reused_for_a_different_message(monkeypatch):
    Model(monkeypatch, _cancel_going_out)
    uid, h = _user(3)
    _day(uid)
    key = f"rp-{uuid.uuid4().hex}"
    async with client() as ac:
        await _post(ac, h, AI_MESSAGE, consent=True, key=key)
        other = await _post(ac, h, "the evening plans with friends are off", consent=True, key=key)
    assert other.status_code == 422
    assert _shields(uid) == 3 - COST


# ── 8. concurrency ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_two_simultaneous_ai_replans_with_one_shield_have_one_winner(monkeypatch):
    def slow(p):
        time.sleep(0.5)
        return _cancel_going_out(p)

    model = Model(monkeypatch, slow)
    uid, h = _user(COST)
    _day(uid)
    async with client() as ac:
        a, b = await asyncio.gather(_post(ac, h, AI_MESSAGE, consent=True, key="k-a"),
                                    _post(ac, h, AI_MESSAGE, consent=True, key="k-b"))
    assert _paid([a, b]) == 1 and all(_safe_loser(r) for r in (a, b) if not _is_paid(r))
    assert len(model.calls) == 1, "the loser never reaches the model"
    assert _shields(uid) == 0
    assert [row[1] for row in _rows(uid)] == ["succeeded"]


@pytest.mark.asyncio
async def test_many_simultaneous_ai_replans_never_overdraw(monkeypatch):
    def slow(p):
        time.sleep(0.3)
        return _cancel_going_out(p)

    model = Model(monkeypatch, slow)
    uid, h = _user(COST)
    _day(uid)
    async with client() as ac:
        rs = await asyncio.gather(*[_post(ac, h, AI_MESSAGE, consent=True, key=f"k-{i}") for i in range(6)])
    assert _paid(rs) == 1 and all(_safe_loser(r) for r in rs if not _is_paid(r))
    assert len(model.calls) == 1 and _shields(uid) == 0


@pytest.mark.asyncio
async def test_build_my_day_and_ai_replan_still_share_the_one_in_flight_slot(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(2)
    _day(uid)
    with SessionLocal() as db:
        db.add(AIRequest(user_id=uid, idempotency_key=f"other-{uuid.uuid4().hex}", kind="plan", status="reserved",
                         request_sha256="x", deadline_at=ai_gateway._utcnow() + timedelta(minutes=5)))
        db.commit()
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=True)
    assert r.status_code == 409 and model.calls == []
    assert _shields(uid) == 2 and _budget(uid) == 0, "a refused request takes nothing"


# ── daily fair-use budget and Pro ────────────────────────────────────────────

@pytest.mark.asyncio
async def test_shields_cannot_buy_past_the_daily_fair_use_ceiling(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    monkeypatch.setattr(replan_ai, "FREE_REPLAN_AI_PER_DAY", 1)
    uid, h = _user(3)
    _day(uid)
    async with client() as ac:
        first = await _post(ac, h, AI_MESSAGE, consent=True)
        second = await _post(ac, h, AI_MESSAGE, consent=True)
    assert first.status_code == 200
    assert second.status_code in (200, 422) and (second.status_code == 422 or second.json()["ai_required"] is None)
    assert len(model.calls) == 1 and _shields(uid) == 3 - COST, "no Shield is taken past the ceiling"


@pytest.mark.asyncio
async def test_pro_keeps_the_fair_use_path_and_never_pays_or_is_asked_for_shields(monkeypatch):
    model = Model(monkeypatch, _cancel_going_out)
    uid, h = _user(0)
    _make_pro(uid)
    ids = _day(uid)
    async with client() as ac:
        r = await _post(ac, h, AI_MESSAGE, consent=False)
    assert r.status_code == 200, r.text
    assert r.json()["ai_required"] is None
    assert [c["task_id"] for c in r.json()["plan_diff"]["cancelled_tasks"]] == [ids["out"]]
    assert len(model.calls) == 1 and _shields(uid) == 0 and _budget(uid) == 1
    assert _rows(uid) == [("replan", "succeeded", "none", 1)]


@pytest.mark.asyncio
async def test_status_reports_the_replan_price(monkeypatch):
    uid, h = _user(2)
    async with client() as ac:
        body = (await ac.get("/api/v1/ai/status", headers=h)).json()
    assert body["replan_shield_cost"] == COST


# ── multi-action, reference resolution, completed work, windows ─────────────

# Not readable by the rules (no instruction verbs they know), so the model is asked: several intents in one message.
MULTI = ("Plans blew up: gym is a no-go today, ML needs one more hour, the outing is now 7 to 9 pm, "
         "DSA is better tomorrow, and Flowstate stays put.")


def _multi_answer(p):
    return ops(
        op("defer_task", ref(p, "Gym"), target_date="tomorrow"),
        op("change_duration", ref(p, "ML assignment"), minutes=60),
        op("move_task", ref(p, "Going out"), target_time="19:00", end_time="21:00", time_mode="at"),
        op("defer_task", ref(p, "DSA practice"), target_date="tomorrow"),
        op("preserve_commitment", ref(p, "Work on Flowstate app")),
        confidence=0.92)


async def _multi(monkeypatch, answer=_multi_answer, shields=2):
    model = Model(monkeypatch, answer)
    uid, h = _user(shields)
    ids = _day(uid)
    async with client() as ac:
        r = await _post(ac, h, MULTI, consent=True)
    assert r.status_code == 200, r.text
    return model, uid, ids, r.json()["plan_diff"]


@pytest.mark.asyncio
async def test_multi_action_message_becomes_one_charge_one_call_and_every_intent(monkeypatch):
    model, uid, ids, diff = await _multi(monkeypatch)
    assert len(model.calls) == 1 and _shields(uid) == 2 - COST
    names = {v: k for k, v in ids.items()}
    moved = {names[m["task_id"]]: m for m in diff["moved_tasks"]}
    # defer to tomorrow (two tasks, named loosely: "gym", "DSA")
    assert moved["gym"]["new_date"] == "Tomorrow" and moved["dsa"]["new_date"] == "Tomorrow"
    updates = {names[u["task_id"]]: u for u in diff["apply_request"]["task_updates"]}
    # duration extension: "ML" resolved to "ML assignment", +60
    assert updates["ml"]["estimated_minutes"] == 120
    # commitment window "7 PM until 9 PM": start AND length change
    assert updates["out"]["scheduled_start"].startswith("2026-10-05T19:00")
    assert updates["out"]["scheduled_end"].startswith("2026-10-05T21:00")
    assert updates["out"]["estimated_minutes"] == 120
    # "keep Flowstate today": still today, not touched
    assert "flow" not in moved and (("flow" not in updates) or updates["flow"]["scheduled_start"].startswith("2026-10-05"))
    # completed work is never in the proposal
    assert "done" not in moved and "done" not in updates
    gym = get(ids["gym"]).scheduled_start.astimezone(IST)  # a proposal only: nothing is written before Apply
    assert (gym.day, gym.hour) == (5, 17) and get(ids["ml"]).estimated_minutes == 60


@pytest.mark.asyncio
async def test_completed_tasks_stay_untouched_even_if_the_model_names_one(monkeypatch):
    def answer(p):
        assert "Morning run" not in p, "completed work is never offered to the model"
        return ops(op("defer_task", "t99", target_date="tomorrow"), op("defer_task", ref(p, "Gym"), target_date="tomorrow"))

    model, uid, ids, diff = await _multi(monkeypatch, answer)
    touched = {m["task_id"] for m in diff["moved_tasks"]} | {u["task_id"] for u in diff["apply_request"]["task_updates"]}
    assert ids["done"] not in touched and ids["gym"] in touched


@pytest.mark.asyncio
async def test_one_unresolved_reference_does_not_destroy_the_valid_actions(monkeypatch):
    def answer(p):
        return ops(op("defer_task", "t99", target_date="tomorrow"),
                   op("defer_task", ref(p, "Gym"), target_date="tomorrow"),
                   op("change_duration", ref(p, "ML assignment"), minutes=60))

    model, uid, ids, diff = await _multi(monkeypatch, answer)
    assert ids["gym"] in {m["task_id"] for m in diff["moved_tasks"]}
    assert any(u["task_id"] == ids["ml"] and u["estimated_minutes"] == 120 for u in diff["apply_request"]["task_updates"])
    assert any("couldn't match everything" in c for c in diff["conflicts"])
    assert _shields(uid) == 2 - COST, "usable intents: the charge stands"


@pytest.mark.asyncio
async def test_a_missing_detail_on_one_intent_is_reported_beside_the_clear_ones(monkeypatch):
    def answer(p):
        return ops(op("defer_task", ref(p, "Gym"), target_date="tomorrow"),
                   op("move_task", ref(p, "DSA practice")))  # "move DSA" with no time or day

    model, uid, ids, diff = await _multi(monkeypatch, answer)
    assert ids["gym"] in {m["task_id"] for m in diff["moved_tasks"]}
    assert diff["clarification"] is None
    assert any("DSA practice" in c for c in diff["conflicts"]), diff["conflicts"]


@pytest.mark.asyncio
async def test_a_window_must_be_something_the_user_said(monkeypatch):
    def answer(p):  # the model invents a 22:00 end: the user never said it
        return ops(op("move_task", ref(p, "Going out"), target_time="19:00", end_time="22:00", time_mode="at"))

    model, uid, ids, diff = await _multi(monkeypatch, answer)
    out = next(u for u in diff["apply_request"]["task_updates"] if u["task_id"] == ids["out"])
    assert out["scheduled_start"].startswith("2026-10-05T19:00")
    assert out["scheduled_end"].startswith("2026-10-05T20:00"), "unsaid end ignored: the length is kept"


# ── the same message handled by rules alone is free ──────────────────────────

REAL_MESSAGE = ("My day changed. Move gym to tomorrow, add another hour to ML, move going out to 7 PM until 9 PM, "
                "and push DSA to tomorrow. Keep Flowstate today and don't move completed tasks.")


@pytest.mark.asyncio
async def test_the_everyday_multi_action_message_is_understood_by_rules_for_free(monkeypatch):
    model = Model(monkeypatch, lambda p: ops())
    uid, h = _user(0)
    ids = _day(uid)
    async with client() as ac:
        r = await _post(ac, h, REAL_MESSAGE, consent=False)
    assert r.status_code == 200 and r.json()["ai_required"] is None
    diff = r.json()["plan_diff"]
    assert model.calls == [] and _shields(uid) == 0 and _rows(uid) == []
    names = {v: k for k, v in ids.items()}
    moved = {names[m["task_id"]] for m in diff["moved_tasks"]}
    assert {"gym", "dsa"} <= moved
    assert not any("didn't act" in c for c in diff["conflicts"]), diff["conflicts"]
    updates = {names[u["task_id"]]: u for u in diff["apply_request"]["task_updates"]}
    assert updates["ml"]["estimated_minutes"] == 120, "'add another hour to ML' extends ML; it is not a new task"
    assert diff["apply_request"]["new_tasks"] == []
