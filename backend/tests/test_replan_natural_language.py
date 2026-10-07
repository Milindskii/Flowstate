"""Natural-language Replan, deterministic path (AI off): compound requests are read clause by clause against
today's plan, nothing understood is lost, a recognised task missing a detail gets a clarification whose options
keep the other clauses, and missing times are never guessed."""
import pytest

from tests.plan_helpers import make_user, client
from tests.test_apply_replan_semantics import replan
from tests.test_replan_understanding import NOW, _day


def _moved(diff):
    return {m["task_id"]: m for m in diff["moved_tasks"]}


@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["can't go out, move gym to 8pm", "I can't go out and move gym to 8pm",
                                     "move gym to 8pm and I won't be able to go out"])
async def test_compound_cancel_commitment_and_move_task(message):
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, message, now=NOW)
    assert diff.get("clarification") is None, diff.get("clarification")
    assert [c["task_id"] for c in diff["cancelled_tasks"]] == [ids["out"]], diff["issues"]
    assert ids["gym"] in _moved(diff) and _moved(diff)[ids["gym"]]["new_time"] == "8:00 PM"


@pytest.mark.asyncio
async def test_compound_with_missing_time_asks_and_keeps_the_other_clause():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "can't go out, move gym", now=NOW)
    c = diff["clarification"]
    assert c is not None and c["task_id"] == ids["gym"]
    assert "Gym" in c["question"]
    assert diff["apply_request"] is None and not diff["moved_tasks"]  # never guesses the time
    by_label = {o["label"]: o for o in c["options"]}
    assert by_label["Move to tomorrow"]["message"] == "can't go out, move Gym to tomorrow"
    assert by_label["Move to a time"]["prefill"] == "can't go out, move Gym to "
    async with client() as ac:  # answering the clarification acts on BOTH clauses
        follow = await replan(ac, h, by_label["Move to tomorrow"]["message"], now=NOW)
    assert [x["task_id"] for x in follow["cancelled_tasks"]] == [ids["out"]]
    assert _moved(follow)[ids["gym"]]["new_date_iso"] == "2026-10-06"


@pytest.mark.asyncio
async def test_no_time_for_cleaning_and_move_clean_room_after():
    uid, h = make_user()
    ids = _day(uid)
    from tests.test_apply_replan_semantics import seed, at
    from tests.test_replan_compound_and_fixed_blocks import TODAY
    clean = seed(uid, "Clean room", at(10, 15), 30, planned_date=TODAY)
    async with client() as ac:
        a = await replan(ac, h, "move clean room to after 10:30", now=NOW)
        b = await replan(ac, h, "don't have time for cleaning", now=NOW)
        both = await replan(ac, h, "move gym to 3pm and I don't have time for cleaning", now=NOW)
    from datetime import datetime
    assert a.get("clarification") is None
    start = datetime.fromisoformat(_moved(a)[clean]["new_start"]).astimezone(at(0).tzinfo)
    assert (start.hour, start.minute) >= (10, 30)
    assert _moved(b)[clean]["new_date_iso"] == "2026-10-06"
    assert _moved(both)[ids["gym"]]["new_time"] == "3:00 PM"
    assert _moved(both)[clean]["new_date_iso"] == "2026-10-06"


@pytest.mark.asyncio
async def test_pure_context_clause_is_ignored_not_reported():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "I underestimated today. move gym to 3pm", now=NOW)
    assert _moved(diff)[ids["gym"]]["new_time"] == "3:00 PM"
    assert not [i for i in diff["issues"] if i["kind"] == "unparsed"]


@pytest.mark.asyncio
async def test_fully_rule_parsed_compound_is_unchanged_behaviour():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move gym to 3pm and move essay to tomorrow", now=NOW)
    assert _moved(diff)[ids["gym"]]["new_time"] == "3:00 PM"
    assert _moved(diff)[ids["essay"]]["new_date_iso"] == "2026-10-06"
