"""Replan: "I'm running late" is context when it carries no amount; prioritised work is never blanket-delayed;
"leave <commitment> untouched" is reported as protected.

Regression from the manual test of 2026-10-04 (observations moved instead of Flowstate, and the explanation
claimed the protected outing was ignored).
"""
from datetime import timedelta

import pytest

from app.services.calendar_service import CalendarService
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import at, replan, seed
from tests.test_replan_compound_and_fixed_blocks import OUT_E, OUT_S, TODAY, _overlaps, _parse

svc = CalendarService()
MSG = ("I'm running late. Move the Flowstate work later, keep the observations as the priority, "
       "and leave the 6:30 to 8:30 outing untouched.")
NOW = at(16, 0)


def _seed_day(uid):
    ids = {
        "flow": seed(uid, "Work on Flowstate app", at(16, 0), 60, planned_date=TODAY),
        "out": seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True),
        "obs": seed(uid, "Write two observations", at(21, 0), 60, planned_date=TODAY, category="College"),
        "proj": seed(uid, "College project", at(22, 0), 60, planned_date=TODAY),
    }
    return ids


def test_bare_running_late_is_context_when_other_instructions_exist():
    got = [o.op for o in svc.parse_replan_instruction(MSG)]
    assert got == ["move_later", "prioritize", "protect_block"], got


def test_numbered_delay_and_lone_running_late_still_shift_the_day():
    assert [o.op for o in svc.parse_replan_instruction("I'm running late")] == ["delay_remaining_schedule"]
    got = svc.parse_replan_instruction("I'm running 30 min late, skip gym")
    assert [o.op for o in got] == ["delay_remaining_schedule", "move_task_date"]


@pytest.mark.asyncio
async def test_exact_message_moves_flowstate_keeps_observations_and_the_outing():
    uid, h = make_user()
    ids = _seed_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, MSG, now=NOW)
    after = {i["task_id"]: i for i in diff["after_schedule"]}
    updates = {t["task_id"]: t for t in diff["apply_request"]["task_updates"]}
    unsched = {t["task_id"] for t in diff["unscheduled_tasks"]}
    print("\nPROPOSED:", sorted((i["start_time"][11:16], i["end_time"][11:16], i["title"]) for i in after.values()),
          "\nUNSCHEDULED:", unsched, "\nCONFLICTS:", diff["conflicts"])

    # Flowstate is the moved task; the observations are not
    assert ids["flow"] in updates and ids["obs"] not in updates
    assert _parse(updates[ids["flow"]]["scheduled_start"]) > at(16, 0)
    # observations stay prioritised: still placed at 9:00 PM
    assert ids["obs"] in after and _parse(after[ids["obs"]]["start_time"]) == at(21, 0)
    # Going out untouched at 6:30-8:30
    assert ids["out"] not in updates
    assert (_parse(after[ids["out"]]["start_time"]), _parse(after[ids["out"]]["end_time"])) == (OUT_S, OUT_E)
    # no overlap anywhere
    spans = sorted((_parse(i["start_time"]), _parse(i["end_time"])) for i in after.values())
    for (s1, e1), (s2, e2) in zip(spans, spans[1:]):
        assert e1 <= s2, spans
    # nothing unscheduled while there is room in the day
    assert not unsched, unsched
    # explanation never claims the protected block was ignored
    assert not any("didn't act" in c for c in diff["conflicts"]), diff["conflicts"]
    assert "didn't act" not in diff["explanation"]


@pytest.mark.asyncio
async def test_leave_commitment_by_name_is_protected_not_ignored():
    uid, h = make_user()
    _seed_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move the flowstate work later, leave going out untouched", now=NOW)
    assert not any("didn't act" in c for c in diff["conflicts"]), diff["conflicts"]
    assert not any("couldn't find" in c for c in diff["conflicts"]), diff["conflicts"]
