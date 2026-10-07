"""Replan My Day semantics v2.

- Every defer/skip verb maps to a reschedule. Unrecognized text is refused (422) and never becomes a new task.
- Skipping or deferring keeps today's history: the task's planned_date moves forward, and today's day view
  still shows it at its old slot, flagged `deviation` ("skipped"/"deferred"), display-only.
- If the destination day is full, the move is not silent: the task is unslotted onto that day.
- The learning signal separates what the user asked for from collateral planner moves.
"""
from datetime import date

import pytest
from fastapi import HTTPException

from app.db.session import SessionLocal
from app.models.recommendation import RecommendationOutcome
from app.models.task_deviation import TaskDeviation
from app.services.calendar_service import CalendarService
from tests.plan_helpers import client, make_user
from tests.test_apply_replan_semantics import NOW, apply, at, get, replan, seed

calendar_service = CalendarService()
TODAY = date(2026, 10, 5)
TOMORROW = date(2026, 10, 6)


def outcomes(uid):
    db = SessionLocal()
    try:
        return [(o.task_id, o.user_action) for o in db.query(RecommendationOutcome).filter(RecommendationOutcome.user_id == uid)]
    finally:
        db.close()


def deviations(uid):
    db = SessionLocal()
    try:
        return db.query(TaskDeviation).filter(TaskDeviation.user_id == uid).all()
    finally:
        db.close()


async def day(ac, h, d="2026-10-05"):
    r = await ac.get("/api/v1/calendar/day", headers=h, params={
        "date": d, "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()


# ── parser ─────────────────────────────────────────────────────────────────
@pytest.mark.parametrize("msg,query,target", [
    ("skip gym", "gym", "tomorrow"),
    ("skip the gym for today please", "gym", "tomorrow"),
    ("defer gym", "gym", "tomorrow"),
    ("postpone my essay", "essay", "tomorrow"),
    ("push gym to tomorrow", "gym", "tomorrow"),
    ("push essay to friday", "essay", "friday"),
    ("reschedule essay to friday", "essay", "friday"),
    ("defer gym to next monday", "gym", "monday"),
])
def test_defer_verbs_map_to_move_task_date(msg, query, target):
    ops = calendar_service.parse_replan_instruction(msg)
    assert len(ops) == 1 and ops[0].op == "move_task_date"
    assert ops[0].task_query == query and ops[0].target_date == target


@pytest.mark.parametrize("msg,intent", [("skip gym", "skipped"), ("defer gym", "deferred"),
                                        ("postpone gym", "deferred"), ("move gym to tomorrow", "rescheduled")])
def test_parser_tags_the_user_intent(msg, intent):
    assert calendar_service.parse_replan_instruction(msg)[0].intent == intent


@pytest.mark.parametrize("msg", ["do gym first", "hmm what about the thing", "gym", "reorder everything"])
def test_unrecognized_instruction_is_refused_not_added_as_a_task(msg):
    with pytest.raises(HTTPException) as e:
        calendar_service.parse_replan_instruction(msg)
    assert e.value.status_code == 422
    assert e.value.detail["errors"][0]["code"] == "unrecognized_instruction"


@pytest.mark.parametrize("msg", ["urgent report needs 1 hour", "i have a call at 6pm", "add groceries 30 min",
                                 "please add laundry"])
def test_add_signals_still_create_tasks(msg):
    assert calendar_service.parse_replan_instruction(msg)[0].op == "add_task"


# ── skip keeps today's history ─────────────────────────────────────────────
@pytest.mark.asyncio
async def test_skip_keeps_a_skipped_node_on_today_and_a_normal_task_tomorrow():
    uid, h = make_user()
    seed(uid, "Alpha", at(10), 60, planned_date=TODAY)
    b = seed(uid, "Bravo", at(12), 60, planned_date=TODAY)
    seed(uid, "Charlie", at(14), 60, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "skip bravo")
        r = await apply(ac, h, diff["apply_request"])
        assert r.status_code == 200, r.text
        today = await day(ac, h)
        tomorrow = await day(ac, h, "2026-10-06")

    assert get(b).planned_date == TOMORROW
    ghost = [i for i in today["deviations"] if i["task_id"] == b]
    assert len(ghost) == 1 and ghost[0]["deviation"] == "skipped" and ghost[0]["is_skipped"] is True
    assert ghost[0]["start_time"].startswith("2026-10-05T12:00")
    # display-only: separate list, never in the live timeline / remaining / planned minutes
    assert {i["title"] for i in today["timeline"]} == {"Alpha", "Charlie"}
    assert today["total_planned_minutes"] == 120
    assert [i["deviation"] for i in tomorrow["timeline"] if i["task_id"] == b] == [None]
    assert tomorrow["deviations"] == []


@pytest.mark.asyncio
async def test_defer_is_recorded_as_deferred_and_replay_adds_no_second_record():
    uid, h = make_user()
    g = seed(uid, "Gym", at(18), 60, planned_date=TODAY)
    async with client() as ac:
        req = (await replan(ac, h, "defer gym"))["apply_request"]
        await apply(ac, h, req)
        await apply(ac, h, req)
    devs = deviations(uid)
    assert [(d.task_id, d.kind, d.deviation_date, d.moved_to_date) for d in devs] == [(g, "deferred", TODAY, TOMORROW)]


@pytest.mark.asyncio
async def test_skipped_slot_is_free_for_replanning_today():
    uid, h = make_user()
    b = seed(uid, "Bravo", at(12), 60, planned_date=TODAY)
    async with client() as ac:
        await apply(ac, h, (await replan(ac, h, "skip bravo"))["apply_request"])
        diff = await replan(ac, h, "i have a call at 12pm")
    assert not diff["conflicts"], diff["conflicts"]
    assert all(m["task_id"] != b for m in diff["moved_tasks"])


@pytest.mark.asyncio
async def test_skipped_node_stays_on_today_when_the_task_moves_again():
    uid, h = make_user()
    b = seed(uid, "Bravo", at(12), 60, planned_date=TODAY)
    async with client() as ac:
        await apply(ac, h, (await replan(ac, h, "skip bravo"))["apply_request"])
        await apply(ac, h, (await replan(ac, h, "move bravo to monday", day="2026-10-06"))["apply_request"])
        today = await day(ac, h)
    assert [i["deviation"] for i in today["deviations"] if i["task_id"] == b] == ["skipped"]


# ── a full destination day never makes the move silent ───────────────────
@pytest.mark.asyncio
async def test_skip_into_a_full_day_unslots_the_task_onto_that_day():
    uid, h = make_user()
    b = seed(uid, "Bravo", at(12), 60, planned_date=TODAY)
    for hr in range(6, 24):
        seed(uid, f"Block {hr}", at(hr, day=6), 60, planned_date=TOMORROW, time_locked=True)
    async with client() as ac:
        diff = await replan(ac, h, "skip bravo")
        r = await apply(ac, h, diff["apply_request"])
        assert r.status_code == 200, r.text
        today = await day(ac, h)
    row = get(b)
    assert row.planned_date == TOMORROW and row.scheduled_start is None
    assert [i["deviation"] for i in today["deviations"] if i["task_id"] == b] == ["skipped"]


# ── learning signal: intent vs collateral ─────────────────────────────────
@pytest.mark.asyncio
async def test_signal_separates_the_requested_move_from_collateral_moves():
    uid, h = make_user()
    g = seed(uid, "Gym", at(18), 60, planned_date=TODAY)
    async with client() as ac:
        req = (await replan(ac, h, "skip gym"))["apply_request"]
        req["intents"] = {**req.get("intents", {}), "forged-id": "skipped"}
        r = await apply(ac, h, req)
    assert r.status_code == 200, r.text
    acts = outcomes(uid)
    assert (g, "replan_skipped") in acts
    assert all(a in ("replan_skipped", "replan_collateral") for _, a in acts)
    assert all(t != "forged-id" for t, _ in acts)


@pytest.mark.asyncio
async def test_running_late_marks_shifted_tasks_as_delayed():
    uid, h = make_user()
    e = seed(uid, "Essay", at(11), 60, planned_date=TODAY)
    async with client() as ac:
        r = await apply(ac, h, (await replan(ac, h, "running 30 min late"))["apply_request"])
    assert r.status_code == 200, r.text
    assert (e, "replan_delayed") in outcomes(uid)
