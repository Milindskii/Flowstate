"""Replan understands what a message names in TODAY's plan (task/commitment resolution), proposes the one obvious
operation, asks for a missing detail instead of guessing, and offers options specific to the recognised task."""
import pytest

from app.models.task import TaskStatus
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, seed
from tests.test_replan_compound_and_fixed_blocks import OUT_S, TODAY

NOW = at(10, 0)


def _day(uid):
    out = seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True)
    gym = seed(uid, "Gym", at(17, 0), 60, planned_date=TODAY)
    essay = seed(uid, "Essay", at(21, 0), 60, planned_date=TODAY)
    flow = seed(uid, "Work on Flowstate app", at(12, 0), 60, planned_date=TODAY)
    return {"out": out, "gym": gym, "essay": essay, "flow": flow}


def labels(diff):
    return [o["label"] for o in diff["clarification"]["options"]]


@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["i wont be able to go out", "I won't be able to go out", "cancel going out",
                                     "I can't make it to going out"])
async def test_cannot_attend_a_commitment_proposes_cancelling_it_without_deleting(message):
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, message, now=NOW)
        assert diff.get("clarification") is None
        assert [c["task_id"] for c in diff["cancelled_tasks"]] == [ids["out"]], diff["issues"]
        # proposal only: nothing is written until the user applies it
        assert get(ids["out"]).status == TaskStatus.todo
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200 and r.json()["cancelled_count"] == 1
    row = get(ids["out"])  # the row is kept (history), only its status changes
    assert row.status == TaskStatus.cancelled and row.title == "Going out"


@pytest.mark.asyncio
async def test_move_commitment_without_destination_asks_and_does_not_guess():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move going out", now=NOW)
    c = diff["clarification"]
    assert c["question"] == "Sure. What time should I move Going out to?"
    assert c["task_id"] == ids["out"]
    assert not diff["moved_tasks"] and not diff["cancelled_tasks"]
    assert diff["apply_request"] is None
    assert labels(diff) == ["Move to a time", "Move to tomorrow", "Cancel Going out"]
    # options are specific to this task and re-submittable
    assert {o["label"]: o["message"] for o in c["options"] if o["message"]} == {
        "Move to tomorrow": "move Going out to tomorrow", "Cancel Going out": "cancel Going out"}
    assert next(o for o in c["options"] if o["label"] == "Move to a time")["prefill"] == "move Going out to "


@pytest.mark.asyncio
async def test_options_differ_per_task():
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        a = await replan(ac, h, "move going out", now=NOW)
        b = await replan(ac, h, "move gym", now=NOW)
    assert labels(a) != labels(b)
    assert "Cancel Gym" in labels(b) and "Move later today" in labels(b)
    assert "Move later today" not in labels(a)  # a commitment is not "moved later"


@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["going out needs to move", "move going out please"])
async def test_phrasings_of_move_ask_for_the_time(message):
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, message, now=NOW)
    assert diff["clarification"]["task_title"] == "Going out"


@pytest.mark.asyncio
async def test_move_commitment_to_a_time_updates_window_across_midnight_and_persists():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move going out to 10:30 pm", now=NOW)
        assert diff.get("clarification") is None
        m = diff["moved_tasks"][0]
        assert m["task_id"] == ids["out"] and m["is_commitment"] is True
        assert m["new_time_range"] == "10:30 PM – 12:30 AM", m
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200 and r.json()["updated_count"] == 1, r.text
    row = get(ids["out"])
    assert row.is_commitment and row.time_locked
    assert row.scheduled_start.astimezone(IST).hour == 22 and row.scheduled_start.astimezone(IST).minute == 30
    assert row.scheduled_end.astimezone(IST).day == 6 and row.scheduled_end.astimezone(IST).hour == 0
    assert row.scheduled_end.astimezone(IST).minute == 30


@pytest.mark.asyncio
async def test_move_task_to_bare_hour_picks_the_next_occurrence_not_a_past_morning():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move gym to 9", now=NOW)  # it is 10 AM: 9 means 9 PM
        assert diff.get("clarification") is None, diff["explanation"]
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200, r.text
    assert get(ids["gym"]).scheduled_start.astimezone(IST).hour == 21


@pytest.mark.asyncio
async def test_cannot_do_a_task_today_skips_it_to_tomorrow_with_history():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "can't do gym today", now=NOW)
        assert [m["task_id"] for m in diff["moved_tasks"]] == [ids["gym"]]
        assert diff["moved_tasks"][0]["new_date"] == "Tomorrow"
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200
    assert get(ids["gym"]).scheduled_start.astimezone(IST).day == 6


@pytest.mark.asyncio
async def test_takes_longer_without_amount_asks_how_much():
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "essay is going to take longer", now=NOW)
    assert diff["clarification"]["question"] == "How much longer will Essay take?"
    assert labels(diff) == ["+15 min", "+30 min", "+1 hour"]


@pytest.mark.asyncio
async def test_takes_longer_with_amount_persists_the_new_duration():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "essay will take 30 minutes longer", now=NOW)
        assert diff.get("clarification") is None, diff["explanation"]
        assert diff["apply_request"]["task_updates"][0]["estimated_minutes"] == 90
        r = await apply(ac, h, diff["apply_request"], now=NOW)
    assert r.status_code == 200, r.text
    assert get(ids["essay"]).estimated_minutes == 90


@pytest.mark.asyncio
async def test_named_flowstate_work_resolves_by_alias():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "push Flowstate work later", now=NOW)
    assert ids["flow"] in [m["task_id"] for m in diff["moved_tasks"]] or ids["flow"] in [
        u["task_id"] for u in diff["apply_request"]["task_updates"]]


@pytest.mark.asyncio
async def test_unknown_task_with_an_action_offers_real_tasks_not_a_generic_error():
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move the dentist", now=NOW)
    assert diff["clarification"]["question"] == "Which task should I move?"
    assert "Gym" in labels(diff)


@pytest.mark.asyncio
async def test_unrelated_text_still_gets_the_generic_message():
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        r = await ac.post("/api/v1/ai/replan", headers=h, json={
            "selected_date": "2026-10-05", "user_message": "the weather is nice", "current_local_time": NOW.isoformat(),
            "timezone": "Asia/Kolkata"})
    assert r.status_code == 422
    assert "didn't understand" in r.text


@pytest.mark.asyncio
async def test_move_onto_a_fixed_commitment_is_reported_not_proposed():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move gym to 7 pm", now=NOW)
    assert not diff["moved_tasks"] and diff["apply_request"]["task_updates"] == []
    assert any("Going out is fixed" in c for c in diff["conflicts"]), diff["conflicts"]
    assert get(ids["gym"]).scheduled_start.astimezone(IST).hour == 17
