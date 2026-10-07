"""Replan semantic understanding (language model) - manual verification 2026-10-06.

The model only translates a message into intents about tasks that are really in today's plan; the server validates
every intent, the deterministic planner builds the proposal, and nothing is written before Apply. The transport seam
(`AIService._gemini_generate`) is stubbed: no network in tests.
"""
import json
import re
from datetime import timedelta

import pytest

from app.core.ai_limits import AIBusy
from app.core.config import settings
from app.models.task import TaskStatus
from app.services import replan_ai
from app.services.ai_service import AIService, GeminiFailure
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, seed
from tests.test_replan_compound_and_fixed_blocks import OUT_S, TODAY

NOW = at(10, 0)


def _day(uid):
    return {
        "out": seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True),
        "clean": seed(uid, "Clean room", at(11, 0), 45, planned_date=TODAY),
        "obs": seed(uid, "Write two observations", at(12, 0), 60, planned_date=TODAY),
        "flow": seed(uid, "Work on Flowstate app", at(13, 30), 60, planned_date=TODAY),
        "gym": seed(uid, "Gym", at(17, 0), 60, planned_date=TODAY),
        "dsa": seed(uid, "DSA practice", at(21, 0), 60, planned_date=TODAY),
    }


def ref(prompt: str, title: str) -> str:
    m = re.search(rf'(t\d+): "{re.escape(title)}"', prompt)
    assert m, f"{title} not offered to the model:\n{prompt}"
    return m.group(1)


class Model:
    """Stub of the transport seam. `answer(prompt)` builds the model's JSON from the refs in the prompt."""

    def __init__(self, monkeypatch, answer):
        self.calls = []
        model = self

        def fake(cls, prompt, api_key, *, request_id, temperature=0.1):
            model.calls.append(prompt)
            out = answer(prompt)
            if isinstance(out, Exception):
                raise out
            return out if isinstance(out, str) else json.dumps(out)

        monkeypatch.setattr(AIService, "_gemini_generate", classmethod(fake))
        monkeypatch.setattr(settings, "REPLAN_AI_ENABLED", True)
        monkeypatch.setattr(settings, "GEMINI_API_KEY", "test-key")


def ops(*items, confidence=0.9, clarification=None):
    return {"operations": list(items), "clarification": clarification, "confidence": confidence}


def op(kind, task_ref=None, **kw):
    return {"op": kind, "task_ref": task_ref, **kw}


async def _replan_raw(ac, h, message):
    return await ac.post("/api/v1/ai/replan", headers=h, json={
        "selected_date": "2026-10-05", "user_message": message, "current_local_time": NOW.isoformat(),
        "timezone": "Asia/Kolkata"})


# ── deterministic first: obvious messages never reach the model ──────────────

@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["move gym to 8", "i wont be able to go out", "i dont have time for cleaning my room",
                                     "move Clean room to after 10.30", "move going out",
                                     "the observations are taking longer than expected",
                                     "i'm running 20 min late, keep observations priority and leave going out untouched"])
async def test_messages_the_rules_understand_never_call_the_model(monkeypatch, message):
    model = Model(monkeypatch, lambda p: ops())
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        await replan(ac, h, message, now=NOW)
    assert model.calls == []


# ── the user's real-device phrases (deterministic, model off) ───────────────

@pytest.mark.asyncio
async def test_no_time_for_cleaning_defers_clean_room_and_writes_nothing():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "i dont have time for cleaning my room", now=NOW)
    assert [m["task_id"] for m in diff["moved_tasks"]] == [ids["clean"]]
    assert diff["moved_tasks"][0]["new_date"] == "Tomorrow"
    assert get(ids["clean"]).scheduled_start.astimezone(IST).day == 5  # proposal only


@pytest.mark.asyncio
async def test_move_to_after_a_time_is_a_lower_bound():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move Clean room to after 14.30", now=NOW)
        assert diff.get("clarification") is None, diff["explanation"]
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200, r.text
    start = get(ids["clean"]).scheduled_start.astimezone(IST)
    assert (start.hour, start.minute) >= (14, 30)


@pytest.mark.asyncio
async def test_taking_longer_without_an_amount_asks_about_the_named_task_not_a_list():
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "the observations are taking longer than expected", now=NOW)
    c = diff["clarification"]
    assert c["task_title"] == "Write two observations"
    assert [o["label"] for o in c["options"]] == ["+15 min", "+30 min", "+1 hour"]
    assert diff["apply_request"] is None


@pytest.mark.asyncio
async def test_compound_keep_first_and_dont_touch_without_an_amount_delays_nothing():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "I'm running late. Keep observations first, move Flowstate later, "
                                   "and don't touch going out.", now=NOW)
    moved = {m["task_id"] for m in diff["moved_tasks"]}
    assert ids["out"] not in moved and ids["obs"] not in moved and ids["gym"] not in moved
    assert ids["flow"] in moved or ids["flow"] in {u["task_id"] for u in diff["apply_request"]["task_updates"]}
    assert not any("didn't act" in c for c in diff["conflicts"]), diff["conflicts"]


# ── semantic layer ──────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_model_cancels_a_named_commitment_as_a_proposal_only(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "scrap the evening plans with friends", now=NOW)
        assert len(model.calls) == 1
        assert [c["task_id"] for c in diff["cancelled_tasks"]] == [ids["out"]]
        assert get(ids["out"]).status == TaskStatus.todo  # nothing persisted before Apply
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200 and get(ids["out"]).status == TaskStatus.cancelled


@pytest.mark.asyncio
async def test_model_moves_a_named_task_to_a_time_the_user_said(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("move_task", ref(p, "Gym"), target_time="21:00", time_mode="at")))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "gym should happen at 9 in the evening", now=NOW)
    assert len(model.calls) == 1  # not turned into a new task called "Gym should happen..."
    assert diff["apply_request"]["new_tasks"] == []
    m = next(m for m in diff["moved_tasks"] if m["task_id"] == ids["gym"])
    assert m["new_time_range"].startswith("9:00 PM"), m


@pytest.mark.asyncio
async def test_move_without_destination_asks_with_entity_specific_options(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("move_task", ref(p, "Going out"))))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "honestly the going out thing needs a new slot", now=NOW)
    c = diff["clarification"]
    assert c["task_id"] == ids["out"]
    assert [o["label"] for o in c["options"]] == ["Move to a time", "Move to tomorrow", "Cancel Going out"]
    assert diff["apply_request"] is None and not diff["moved_tasks"]


@pytest.mark.asyncio
async def test_options_differ_per_entity(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("move_task", ref(p, "Gym"))))
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "gym needs a different slot", now=NOW)
    labels = [o["label"] for o in diff["clarification"]["options"]]
    assert "Cancel Gym" in labels and "Move later today" in labels


@pytest.mark.asyncio
async def test_invented_time_is_never_used(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("move_task", ref(p, "Gym"), target_time="21:00", time_mode="at")))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "gym needs a different slot tonight", now=NOW)
    assert diff["clarification"]["task_id"] == ids["gym"]
    assert not diff["moved_tasks"]


@pytest.mark.asyncio
async def test_takes_longer_without_amount_and_invented_amount_both_ask(monkeypatch):
    answers = iter([
        lambda p: ops(op("change_duration", ref(p, "Write two observations"))),
        lambda p: ops(op("change_duration", ref(p, "Write two observations"), minutes=25)),
    ])
    Model(monkeypatch, lambda p: next(answers)(p))
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        for _ in range(2):
            diff = await replan(ac, h, "the observation write-up is dragging on", now=NOW)
            assert diff["clarification"]["question"] == "How much longer will Write two observations take?"
            assert diff["apply_request"] is None


@pytest.mark.asyncio
async def test_compound_skip_and_move_tomorrow_becomes_two_validated_operations(monkeypatch):
    Model(monkeypatch, lambda p: ops(
        op("skip_task", ref(p, "Gym")),
        op("move_task", ref(p, "DSA practice"), target_date="tomorrow", part_of_day="morning")))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "Skip gym and move DSA to tomorrow morning", now=NOW)
    moved = {m["task_id"]: m for m in diff["moved_tasks"]}
    assert moved[ids["gym"]]["new_date"] == "Tomorrow"
    assert moved[ids["dsa"]]["new_date"] == "Tomorrow"


@pytest.mark.asyncio
async def test_delay_keeps_the_protected_commitment_untouched(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("delay_task", minutes=20), op("preserve_commitment", ref(p, "Going out"))))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "running 20 behind, leave going out alone", now=NOW)
    moved = {m["task_id"] for m in diff["moved_tasks"]}
    assert ids["out"] not in moved
    assert ids["clean"] in moved


@pytest.mark.asyncio
async def test_running_late_without_amount_is_not_a_delay(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("delay_task")))  # no minutes
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        r = await _replan_raw(ac, h, "ugh behind schedule again")
    assert r.status_code == 422  # nothing usable: the friendly message, never a guessed delay


@pytest.mark.asyncio
async def test_move_onto_a_fixed_commitment_is_a_conflict(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("move_task", ref(p, "Gym"), target_time="19:00", time_mode="at")))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "gym at 7 in the evening please", now=NOW)
    assert any("Going out is fixed" in c for c in diff["conflicts"]), diff["conflicts"]
    assert get(ids["gym"]).scheduled_start.astimezone(IST).hour == 17


@pytest.mark.asyncio
async def test_unknown_task_reference_is_ignored(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("cancel_task", "t99")))
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        r = await _replan_raw(ac, h, "the dentist thing is off")
    assert r.status_code == 422
    assert "Gemini" not in r.text and "provider" not in r.text.lower()


@pytest.mark.asyncio
async def test_low_confidence_asks_instead_of_acting(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Gym")), confidence=0.3))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "gym hmm maybe not", now=NOW)
    assert diff["clarification"]["task_id"] == ids["gym"]
    assert not diff["cancelled_tasks"]


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", [GeminiFailure("provider_quota", "quota exceeded"), AIBusy("circuit_open"),
                                     GeminiFailure("timeout"), "not json at all"])
async def test_model_failure_falls_back_to_a_friendly_answer(monkeypatch, failure):
    Model(monkeypatch, lambda p: failure)
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        r = await _replan_raw(ac, h, "the weather is nice")
    assert r.status_code == 422
    body = r.text.lower()
    assert "didn't understand" in body
    for leak in ("gemini", "quota", "provider", "circuit", "traceback"):
        assert leak not in body


@pytest.mark.asyncio
async def test_model_failure_keeps_a_deterministic_clarification(monkeypatch):
    Model(monkeypatch, lambda p: GeminiFailure("network"))
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move the dentist", now=NOW)
    assert diff["clarification"]["question"] == "Which task should I move?"
    assert "Going out" not in [o["label"] for o in diff["clarification"]["options"]]


@pytest.mark.asyncio
async def test_daily_budget_is_enforced(monkeypatch):
    model = Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out"))))
    monkeypatch.setattr(replan_ai, "FREE_REPLAN_AI_PER_DAY", 1)
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        await replan(ac, h, "scrap the evening plans with friends", now=NOW)
        r = await _replan_raw(ac, h, "scrap the evening plans with friends")
    assert len(model.calls) == 1
    assert r.status_code == 200  # over budget: the deterministic answer ("which task?") stands


def test_validation_rejects_malformed_payloads():
    from app.engines.planner import PlanItem

    refs = [("t1", PlanItem(id="g", title="Gym", start=NOW + timedelta(hours=7)))]
    for payload in (None, [], "x", {"operations": "nope"}, {"operations": [{"op": "explode", "task_ref": "t1"}]},
                    {"operations": [{"op": "cancel_task", "task_ref": "t7"}], "confidence": 1}):
        assert replan_ai.validate(payload, "cancel gym", refs, NOW, IST) is None


def test_numbers_said_cover_digits_dot_times_and_words():
    said = replan_ai.numbers_in("move it to after 10.30 for half an hour, twenty more")
    assert {10, 30, 20} <= said


# ── commitments are protected from model proposals (2026-10-07 polish pass) ──

@pytest.mark.asyncio
async def test_model_cannot_touch_a_commitment_the_user_did_not_name(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("cancel_task", ref(p, "Going out")), op("skip_task", ref(p, "Gym"))))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "ugh my evening is a mess, bail on the workout", now=NOW)
    assert ids["out"] not in [c["task_id"] for c in diff["cancelled_tasks"]]
    assert ids["out"] not in [m["task_id"] for m in diff["moved_tasks"]]


@pytest.mark.asyncio
async def test_model_skip_of_a_named_commitment_asks_instead_of_moving_it(monkeypatch):
    Model(monkeypatch, lambda p: ops(op("skip_task", ref(p, "Going out"))))
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "bail on going out", now=NOW)
    c = diff["clarification"]
    assert c is not None and c["task_id"] == ids["out"] and "cancel" in c["question"].lower()
    assert diff["apply_request"] is None and not diff["moved_tasks"]
    assert get(ids["out"]).status == TaskStatus.todo


@pytest.mark.asyncio
async def test_prompt_carries_commitment_rule_and_examples(monkeypatch):
    model = Model(monkeypatch, lambda p: ops())
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        await _replan_raw(ac, h, "bail on the workout thing")
    assert model.calls and "Never change a fixed commitment the user did not mention" in model.calls[0]
    assert '"Going out" (fixed commitment' in model.calls[0]
