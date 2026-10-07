"""Replan: compound natural language, fixed blocks are never violated, early-completed tasks render sanely.

Regressions from the manual test of 2026-10-04:
  * "I underestimated ... Move the Flowstate work later today, keep the college observations as the priority,
    and leave the 6:30 to 8:30 outing untouched." was refused (one intent per message).
  * Replan placed Gym inside the 6:30-8:30 outing.
  * A task completed before its slot rendered as a seconds-long block (or a negative interval).
"""
from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi import HTTPException

from app.services.calendar_service import CalendarService
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import NOW, apply, at, get, replan, seed

svc = CalendarService()
TODAY = date(2026, 10, 5)
COMPOUND = ("I underestimated how long the observations would take. Move the Flowstate work later today, "
            "keep the college observations as the priority, and leave the 6:30 to 8:30 outing untouched.")
OUT_S, OUT_E = at(18, 30), at(20, 30)


def ops(msg):
    return svc.parse_replan_instruction(msg)


# ── parser: compound ────────────────────────────────────────────────────────
def test_compound_message_yields_three_operations():
    got = ops(COMPOUND)
    kinds = [o.op for o in got]
    assert kinds == ["move_later", "prioritize", "protect_block"], kinds
    assert got[0].task_query == "flowstate work"
    assert got[1].task_query == "college observations"
    assert (got[2].block_start, got[2].block_end) == ("18:30", "20:30")


@pytest.mark.parametrize("msg,expected", [
    ("skip gym and push essay to friday", [("move_task_date", "gym"), ("move_task_date", "essay")]),
    ("I'm running 30 min late, skip gym", [("delay_remaining_schedule", None), ("move_task_date", "gym")]),
    ("defer gym. move groceries to monday", [("move_task_date", "gym"), ("move_task_date", "groceries")]),
])
def test_compound_pairs(msg, expected):
    got = [(o.op, o.task_query) for o in ops(msg)]
    assert got == expected


@pytest.mark.parametrize("msg,op,query,target", [
    ("skip gym", "move_task_date", "gym", "tomorrow"),
    ("defer gym", "move_task_date", "gym", "tomorrow"),
    ("postpone gym", "move_task_date", "gym", "tomorrow"),
    ("push gym to tomorrow", "move_task_date", "gym", "tomorrow"),
    ("move groceries to Monday", "move_task_date", "groceries", "monday"),
    ("reschedule essay to Friday", "move_task_date", "essay", "friday"),
])
def test_single_intents_still_work(msg, op, query, target):
    got = ops(msg)
    assert len(got) == 1 and got[0].op == op and got[0].task_query == query and got[0].target_date == target


def test_running_late_and_missed_and_redo_still_work():
    late = ops("I'm running 30 min late")
    assert late[0].op == "delay_remaining_schedule" and late[0].delay_minutes == 30
    assert ops("I missed gym")[0].op == "redo_task" and ops("I missed gym")[0].task_query == "gym"
    assert ops("redo gym")[0].op == "redo_task"


@pytest.mark.parametrize("msg", ["do gym first", "gym", "reorder everything", "hmm what about the thing"])
def test_nonsense_is_still_refused(msg):
    with pytest.raises(HTTPException) as e:
        ops(msg)
    assert e.value.detail["errors"][0]["code"] == "unrecognized_instruction"


def test_context_only_sentence_is_ignored_but_not_everything_is_context():
    with pytest.raises(HTTPException):
        ops("I underestimated how long the observations would take.")


# ── end to end ──────────────────────────────────────────────────────────────
def _overlaps(a_s, a_e, b_s, b_e):
    return a_s < b_e and b_s < a_e


def _parse(dt):
    return datetime.fromisoformat(dt)


def _seed_outing_day(uid, *, outing_row=True, project=True):
    ids = {}
    if outing_row:
        ids["out"] = seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True)
    ids["obs"] = seed(uid, "Write college observations", at(13, 15), 150, planned_date=TODAY)
    ids["flow"] = seed(uid, "Work on Flowstate app deployment", at(16, 45), 90, planned_date=TODAY)
    ids["mom"] = seed(uid, "Call mom", at(18, 15), 15, planned_date=TODAY)
    ids["gym"] = seed(uid, "Gym", at(19, 15), 60, planned_date=TODAY, priority="low")
    if project:
        ids["proj"] = seed(uid, "Work on college project", at(20, 45), 120, planned_date=TODAY)
    return ids


@pytest.mark.asyncio
async def test_compound_replan_never_places_anything_inside_the_outing():
    uid, h = make_user()
    ids = _seed_outing_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, COMPOUND)
    assert diff["after_schedule"], diff
    for it in diff["after_schedule"]:
        if it["task_id"] == ids["out"]:
            continue
        assert not _overlaps(_parse(it["start_time"]), _parse(it["end_time"]), OUT_S, OUT_E), it
    for t in diff["apply_request"]["task_updates"]:
        if t["scheduled_start"]:
            s = _parse(t["scheduled_start"]); e = _parse(t["scheduled_end"])
            assert not _overlaps(s, e, OUT_S, OUT_E), t
    # the outing itself is untouched
    assert get(ids["out"]).scheduled_start.astimezone(timezone.utc) == OUT_S.astimezone(timezone.utc)


@pytest.mark.asyncio
async def test_protect_block_holds_even_without_a_saved_outing_row():
    uid, h = make_user()
    _seed_outing_day(uid, outing_row=False)
    async with client() as ac:
        diff = await replan(ac, h, COMPOUND)
    for it in diff["after_schedule"]:
        assert not _overlaps(_parse(it["start_time"]), _parse(it["end_time"]), OUT_S, OUT_E), it
    for t in diff["apply_request"]["task_updates"]:
        if t["scheduled_start"]:
            assert not _overlaps(_parse(t["scheduled_start"]), _parse(t["scheduled_end"]), OUT_S, OUT_E), t


@pytest.mark.asyncio
async def test_prioritized_task_keeps_a_slot_and_flowstate_moves_later():
    uid, h = make_user()
    ids = _seed_outing_day(uid, project=False)
    async with client() as ac:
        diff = await replan(ac, h, COMPOUND)
    after = {i["task_id"]: i for i in diff["after_schedule"]}
    assert ids["obs"] in after
    flow = next((t for t in diff["apply_request"]["task_updates"] if t["task_id"] == ids["flow"]), None)
    assert flow is not None and _parse(flow["scheduled_start"]) >= at(16, 45) + timedelta(minutes=1)


@pytest.mark.asyncio
async def test_flowstate_work_resolves_by_tokens():
    uid, h = make_user()
    _seed_outing_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move the flowstate work later today")
    assert not any("couldn't find" in c for c in diff["conflicts"]), diff["conflicts"]


@pytest.mark.asyncio
async def test_unmatched_clause_is_reported_not_fatal():
    uid, h = make_user()
    _seed_outing_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "skip gym and defer zzzqq")
    assert any("zzzqq" in c for c in diff["conflicts"]), diff["conflicts"]


# ── completed early (RC3) ───────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_task_completed_before_its_slot_renders_once_with_positive_duration():
    uid, h = make_user()
    done_at = at(13, 15).astimezone(timezone.utc)
    seed(uid, "Send college observations to professor", at(16, 15), 15, planned_date=TODAY,
         status="completed", completed_at=done_at)
    seed(uid, "Gym", at(17, 0), 60, planned_date=TODAY)
    now = at(13, 20)
    async with client() as ac:
        diff = await replan(ac, h, "skip gym", now=now)
    rows_ = [i for i in diff["after_schedule"] if i["title"].startswith("Send college")]
    assert len(rows_) == 1
    s, e = _parse(rows_[0]["start_time"]), _parse(rows_[0]["end_time"])
    assert e > s and (e - s) >= timedelta(minutes=5), (s, e)
    assert e == done_at.astimezone(IST) or abs((e - done_at).total_seconds()) < 1


@pytest.mark.asyncio
async def test_move_later_with_no_room_is_explained_never_silent():
    uid, h = make_user()
    ids = _seed_outing_day(uid)  # the project already fills the evening
    async with client() as ac:
        diff = await replan(ac, h, COMPOUND)
    placed = {i["task_id"] for i in diff["after_schedule"]}
    unsched = {t["task_id"] for t in diff["unscheduled_tasks"]}
    assert ids["flow"] in placed | unsched
    if ids["flow"] in unsched:
        assert any("Flowstate" in c for c in diff["conflicts"]), diff["conflicts"]


# ── missed-task history survives a compound replan ──────────────────────────
@pytest.mark.asyncio
async def test_compound_replan_keeps_one_missed_deviation_and_the_original_slot():
    from app.db.session import SessionLocal
    from app.models.task_deviation import TaskDeviation

    uid, h = make_user()
    gym = seed(uid, "Gym", at(8), 60, planned_date=TODAY)
    seed(uid, "Groceries", at(17), 45, planned_date=TODAY)
    now = at(15)
    async with client() as ac:
        diff = await replan(ac, h, "I missed gym, move groceries later today", now=now)
        assert not any("couldn't find" in c for c in diff["conflicts"]), diff["conflicts"]
        req = diff["apply_request"]
        assert (await apply(ac, h, req, now=now)).status_code == 200
        await apply(ac, h, req, now=now)  # replayed apply: no duplicate history
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": "2026-10-05", "timezone": "Asia/Kolkata", "current_local_time": now.isoformat()})).json()
    db = SessionLocal()
    try:
        devs = db.query(TaskDeviation).filter(TaskDeviation.user_id == uid, TaskDeviation.task_id == gym).all()
    finally:
        db.close()
    assert [(d.kind, d.original_start.astimezone(IST).hour) for d in devs] == [("missed", 8)]
    assert any(i["task_id"] == gym and i["start_time"].startswith("2026-10-05T08:00") for i in view["deviations"] + view["timeline"])
    new_gym = [i for i in view["timeline"] if i["task_id"] == gym]
    assert new_gym and _parse(new_gym[0]["start_time"]) >= now  # the new occurrence is in the future, not the missed slot


# ── manual-test regressions (2026-10-04 evening) ────────────────────────────
def _all_diff_items(diff):
    return {k: diff[k] for k in ("moved_tasks", "newly_scheduled_tasks", "unchanged_tasks", "skipped_immutable")}


@pytest.mark.asyncio
async def test_college_observations_resolves_to_write_two_observations():
    uid, h = make_user()
    obs = seed(uid, "Write two observations", at(20, 30), 135, planned_date=TODAY)
    seed(uid, "Make progress on project", None, 120, planned_date=TODAY)
    seed(uid, "Finish remaining Flowstate work and deploy app", None, 180, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "keep the college observations as the priority")
    assert not any("couldn't find" in c or "More than one" in c for c in diff["conflicts"]), diff["conflicts"]
    assert obs in {i["task_id"] for i in diff["after_schedule"]}


@pytest.mark.asyncio
async def test_task_category_counts_toward_a_natural_language_match():
    uid, h = make_user()
    obs = seed(uid, "Write two observations", at(20, 30), 135, planned_date=TODAY, category="College")
    seed(uid, "Gym", at(12), 60, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "prioritize my college observations")
    assert not any("couldn't find" in c for c in diff["conflicts"]), diff["conflicts"]
    assert obs in {i["task_id"] for i in diff["after_schedule"]}


@pytest.mark.asyncio
async def test_ambiguous_natural_language_still_asks_which_one():
    uid, h = make_user()
    seed(uid, "Write two observations", at(20, 30), 135, planned_date=TODAY)
    seed(uid, "Work on college project", at(12), 120, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "keep the college observations as the priority")
    assert any("More than one task matches" in c for c in diff["conflicts"]), diff["conflicts"]


@pytest.mark.asyncio
async def test_unrelated_words_never_match_a_task():
    uid, h = make_user()
    seed(uid, "Write two observations", at(20, 30), 135, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "prioritize the dentist")
    assert any("couldn't find" in c for c in diff["conflicts"]), diff["conflicts"]


@pytest.mark.asyncio
async def test_locked_commitment_keeps_its_full_interval_in_the_preview():
    uid, h = make_user()
    c = seed(uid, "Going out", at(18, 30), 120, planned_date=TODAY, time_locked=True, is_commitment=True)
    seed(uid, "Gym", at(11), 60, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "skip gym")
    row = next(t for t in diff["unchanged_tasks"] if t["task_id"] == c)
    assert row["time_locked"] is True and row["is_commitment"] is True
    assert _parse(row["new_start"]) == OUT_S and _parse(row["new_end"]) == OUT_E
    assert row["old_time_range"] == row["new_time_range"] == "6:30 PM – 8:30 PM"
    after = next(i for i in diff["after_schedule"] if i["task_id"] == c)
    assert _parse(after["start_time"]) == OUT_S and _parse(after["end_time"]) == OUT_E
    assert after["is_commitment"] is True and after["state"] == "commitment"
    assert all(u["task_id"] != c for u in diff["apply_request"]["task_updates"])


@pytest.mark.asyncio
async def test_every_diff_row_has_a_positive_interval_even_for_early_completions():
    uid, h = make_user()
    done_at = at(13, 15, ).astimezone(timezone.utc) + timedelta(seconds=8)
    obs = seed(uid, "Write college observations", at(13, 15), 150, planned_date=TODAY,
               status="completed", completed_at=done_at)
    seed(uid, "Gym", at(17), 60, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "skip gym", now=at(14))
    prot = next(t for t in diff["skipped_immutable"] if t["task_id"] == obs)
    assert prot["old_time_range"] == "10:45 AM – 1:15 PM", prot
    for rows_ in _all_diff_items(diff).values():
        for t in rows_:
            if t.get("new_start") and t.get("new_end"):
                assert _parse(t["new_end"]) > _parse(t["new_start"]), t
    done_after = next(i for i in diff["after_schedule"] if i["task_id"] == obs)
    assert _parse(done_after["end_time"]) > _parse(done_after["start_time"])
