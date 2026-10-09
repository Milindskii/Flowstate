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


@pytest.mark.asyncio
async def test_quick_add_with_recommended_start_time_persists_exact_slot():
    uid, h = make_user()
    async with client() as ac:
        r = await _replan_raw(ac, h, {
            "quick_add": {
                "title": "Noya recommended task",
                "duration_minutes": 45,
                "start_time": "14:00",
                "is_preferred": True,
            }
        })
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]
        new_items = diff["newly_scheduled_tasks"]
        assert len(new_items) == 1
        assert new_items[0]["title"] == "Noya recommended task"
        assert new_items[0]["duration_minutes"] == 45
        assert "2:00 PM" in new_items[0]["new_time"]

        ap = await apply(ac, h, diff["apply_request"])
        assert ap.status_code == 200, ap.text

    saved = next(t for t in rows(uid) if t.title == "Noya recommended task")
    assert saved.estimated_minutes == 45
    assert saved.scheduled_start.astimezone(NOW.tzinfo) == at(14, 0)
    assert saved.status.value == "todo"


@pytest.mark.asyncio
async def test_quick_add_with_start_time_yielding_to_fixed_commitment_preserves_commitment():
    uid, h = make_user()
    commit_start = at(14, 0)
    # Seed a fixed commitment at 14:00 (Doctor appointment)
    commit_id = seed(uid, "Doctor appointment", commit_start, 60, planned_date=TODAY, time_locked=True, is_commitment=True)

    async with client() as ac:
        # User tries to place a task at 14:00
        r = await _replan_raw(ac, h, {
            "quick_add": {
                "title": "Urgent review",
                "duration_minutes": 30,
                "start_time": "14:00",
                "is_preferred": True,
            }
        })
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]

        # Doctor appointment commitment remains untouched
        doctor = next(i for i in diff["after_schedule"] if i["task_id"] == commit_id)
        assert _parse(doctor["start_time"]) == commit_start

        # New task yields to the commitment and is placed at a non-overlapping time
        new_item = diff["newly_scheduled_tasks"][0]
        new_s = _parse(new_item["new_start"])
        new_e = _parse(new_item["new_end"])
        # Should not collide with doctor appointment [14:00, 15:00]
        assert not _overlaps(new_s, new_e, commit_start, commit_start + (at(1, 0) - at(0, 0)))

        # Apply succeeds and both are preserved
        ap = await apply(ac, h, diff["apply_request"])
        assert ap.status_code == 200, ap.text

    saved_tasks = rows(uid)
    doc_row = next(t for t in saved_tasks if t.id == commit_id)
    assert doc_row.scheduled_start.astimezone(NOW.tzinfo) == commit_start
    urgent_row = next(t for t in saved_tasks if t.title == "Urgent review")
    assert urgent_row.scheduled_start is not None
    assert urgent_row.scheduled_start != doc_row.scheduled_start


@pytest.mark.asyncio
async def test_quick_add_with_explicit_fixed_start_time_persists_exact_slot_and_locks():
    uid, h = make_user()
    async with client() as ac:
        r = await _replan_raw(ac, h, {
            "quick_add": {
                "title": "Morning standup",
                "duration_minutes": 45,
                "start_time": "08:30",
                "constraint_type": "fixed_start",
            }
        }, now=at(8, 0))
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]
        new_items = diff["newly_scheduled_tasks"]
        assert len(new_items) == 1
        assert new_items[0]["title"] == "Morning standup"
        assert new_items[0]["duration_minutes"] == 45
        assert "8:30 AM" in new_items[0]["new_time"]
        assert new_items[0]["is_fixed"] is True
        assert new_items[0]["time_locked"] is True

        ap = await apply(ac, h, diff["apply_request"], now=at(8, 0))
        assert ap.status_code == 200, ap.text

    saved = next(t for t in rows(uid) if t.title == "Morning standup")
    assert saved.estimated_minutes == 45
    assert saved.scheduled_start.astimezone(NOW.tzinfo) == at(8, 30)
    assert saved.time_locked is True
    assert saved.status.value == "todo"


@pytest.mark.asyncio
async def test_quick_add_fixed_time_clashing_with_movable_task_does_not_move_fixed_task():
    uid, h = make_user()
    # Seed a movable task at 08:30
    movable_id = seed(uid, "Flexible task", at(8, 30), 45, planned_date=TODAY, time_locked=False)

    async with client() as ac:
        r = await _replan_raw(ac, h, {
            "quick_add": {
                "title": "Fixed urgent meeting",
                "duration_minutes": 45,
                "start_time": "08:30",
                "constraint_type": "fixed_start",
            }
        }, now=at(8, 0))
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]

        # The new fixed task stays exactly at 08:30
        fixed_node = next(i for i in diff["after_schedule"] if i["title"] == "Fixed urgent meeting")
        assert _parse(fixed_node["start_time"]) == at(8, 30)

        # The flexible task gets moved around it
        movable_node = next(i for i in diff["after_schedule"] if i["task_id"] == movable_id)
        assert _parse(movable_node["start_time"]) != at(8, 30)

        ap = await apply(ac, h, diff["apply_request"], now=at(8, 0))
        assert ap.status_code == 200, ap.text

    saved_tasks = rows(uid)
    fixed_row = next(t for t in saved_tasks if t.title == "Fixed urgent meeting")
    assert fixed_row.scheduled_start.astimezone(NOW.tzinfo) == at(8, 30)
    assert fixed_row.time_locked is True


