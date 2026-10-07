"""Replan: structured quick-add (the "Urgent work arrived" sheet), editable new tasks, and the Flow-3 phrase table."""
import pytest

from app.services.calendar_service import CalendarService
from tests.plan_helpers import client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, rows, seed
from tests.test_replan_compound_and_fixed_blocks import OUT_E, OUT_S, TODAY, _overlaps, _parse

svc = CalendarService()
NOW = at(9, 0)


async def _replan_raw(ac, h, body, now=NOW):
    r = await ac.post("/api/v1/ai/replan", headers=h, json={
        "selected_date": "2026-10-05", "current_local_time": now.isoformat(), "timezone": "Asia/Kolkata", **body})
    return r


@pytest.mark.asyncio
async def test_quick_add_uses_the_exact_typed_title_and_duration():
    uid, h = make_user()
    async with client() as ac:
        r = await _replan_raw(ac, h, {"quick_add": {"title": "Finish API security testing", "duration_minutes": 60}})
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]
        new = diff["newly_scheduled_tasks"]
        assert [n["title"] for n in new] == ["Finish API security testing"]
        assert new[0]["duration_minutes"] == 60 and new[0]["apply_index"] == 0 and new[0]["needs_title"] is False
        ap = await apply(ac, h, diff["apply_request"])
        assert ap.status_code == 200, ap.text
    made = [t for t in rows(uid) if t.title == "Finish API security testing"]
    assert len(made) == 1 and made[0].estimated_minutes == 60


@pytest.mark.asyncio
async def test_edited_new_task_payload_is_what_gets_saved():
    uid, h = make_user()
    async with client() as ac:
        diff = (await _replan_raw(ac, h, {"quick_add": {"title": "Urgent thing", "duration_minutes": 60}})).json()["plan_diff"]
        req = diff["apply_request"]
        nt = req["new_tasks"][diff["newly_scheduled_tasks"][0]["apply_index"]]
        start = at(15, 0)
        nt.update(title="Renamed API review", estimated_minutes=45,
                  scheduled_start=start.isoformat(), scheduled_end=at(15, 45).isoformat())
        ap = await apply(ac, h, req)
        assert ap.status_code == 200, ap.text
    t = next(t for t in rows(uid) if t.title == "Renamed API review")
    assert t.estimated_minutes == 45 and t.scheduled_start.astimezone(start.tzinfo) == start


@pytest.mark.asyncio
async def test_bare_urgent_message_asks_for_a_name():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "I just got urgent work")
    assert diff["newly_scheduled_tasks"][0]["needs_title"] is True


@pytest.mark.asyncio
async def test_quick_add_validation_is_a_422_not_a_crash():
    uid, h = make_user()
    async with client() as ac:
        r = await _replan_raw(ac, h, {"quick_add": {"title": "", "duration_minutes": 60}})
        assert r.status_code == 422
        r = await _replan_raw(ac, h, {"quick_add": {"title": "x", "duration_minutes": 1}})
        assert r.status_code == 422


def _day(uid):
    ids = {
        "gym": seed(uid, "Gym", at(10, 0), 60, planned_date=TODAY),
        "flow": seed(uid, "Work on Flowstate app", at(11, 0), 60, planned_date=TODAY),
        "out": seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True),
    }
    return ids


@pytest.mark.asyncio
async def test_move_flowstate_to_tonight_lands_in_the_evening_outside_the_outing():
    uid, h = make_user()
    ids = _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, "move Flowstate to tonight")
    assert not any("understand" in c for c in diff["conflicts"]), diff["conflicts"]
    flow = next(i for i in diff["after_schedule"] if i["task_id"] == ids["flow"])
    s, e = _parse(flow["start_time"]), _parse(flow["end_time"])
    assert s >= at(18, 0) and not _overlaps(s, e, OUT_S, OUT_E), (s, e)


@pytest.mark.asyncio
@pytest.mark.parametrize("msg", [
    "skip gym", "defer gym", "push gym to tomorrow", "I missed gym", "redo gym", "running 30 minutes late",
    "skip gym and move flowstate to tonight", "I'm running 30 min late, skip gym",
])
async def test_flow3_phrases_resolve_without_errors(msg):
    uid, h = make_user()
    _day(uid)
    async with client() as ac:
        diff = await replan(ac, h, msg, now=at(10, 30) if "missed" in msg or "redo" in msg else NOW)
    assert not any(("couldn't find" in c) or ("didn't act" in c) or ("understand" in c) for c in diff["conflicts"]), diff["conflicts"]
