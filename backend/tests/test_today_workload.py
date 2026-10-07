"""
Today's workload = what can still be done. A task whose slot already ended unstarted is MISSED: its minutes leave the
remaining (actionable) workload but stay available as missed_minutes for history/analytics. Same rule as the Calendar
and Flutter (shared/task_state_vectors.json). Slots are placed relative to the real clock.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.task import Task, TaskPriority, TaskStatus, TaskType
from app.models.user import User


def _user():
    uid = f"workload-{uuid.uuid4().hex[:8]}"
    with SessionLocal() as db:
        db.add(User(id=uid, email=f"{uid}@flowstate.local", name="W"))
        db.commit()
    return uid, {"Authorization": f"Bearer {create_access_token({'sub': uid, 'email': f'{uid}@flowstate.local'})}"}


def _task(uid, title, *, start_offset_min, minutes, status=TaskStatus.todo):
    now = datetime.now(timezone.utc)
    start = now + timedelta(minutes=start_offset_min)
    with SessionLocal() as db:
        t = Task(user_id=uid, title=title, task_type=TaskType.deep_work, priority=TaskPriority.medium, estimated_minutes=minutes,
                 scheduled_start=start, scheduled_end=start + timedelta(minutes=minutes), status=status,
                 planned_date=now.date(), started_at=now if status == TaskStatus.in_progress else None,
                 completed_at=now if status == TaskStatus.completed else None)
        db.add(t)
        db.commit()
        return str(t.id)


async def _workload(headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/today?timezone=UTC", headers=headers)
    assert res.status_code == 200
    return res.json()["workload_summary"]


@pytest.mark.asyncio
async def test_a_scheduled_task_inside_its_slot_counts_as_remaining():
    uid, h = _user()
    _task(uid, "In its slot", start_offset_min=-10, minutes=60)
    w = await _workload(h)
    assert w["planned_minutes"] == 60 and w["missed_minutes"] == 0 and w["missed_count"] == 0


@pytest.mark.asyncio
async def test_a_completed_task_does_not_count():
    uid, h = _user()
    _task(uid, "Done", start_offset_min=-120, minutes=45, status=TaskStatus.completed)
    w = await _workload(h)
    assert w["planned_minutes"] == 0 and w["missed_minutes"] == 0


@pytest.mark.asyncio
async def test_a_missed_task_does_not_inflate_remaining_but_is_kept_as_missed_minutes():
    uid, h = _user()
    _task(uid, "Slipped", start_offset_min=-180, minutes=45)       # ended ~2h15m ago
    w = await _workload(h)
    assert w["planned_minutes"] == 0, "missed time is not remaining workload"
    assert w["missed_minutes"] == 45 and w["missed_count"] == 1, "its duration stays available for history/analytics"
    assert w["formatted_workload"] == "0m planned"
    assert w["message"] != "Let's build your day.", "tasks exist, so the day is not empty"
    assert "missed" in w["message"].lower()


@pytest.mark.asyncio
async def test_a_future_task_counts():
    uid, h = _user()
    _task(uid, "Later", start_offset_min=180, minutes=30)
    w = await _workload(h)
    assert w["planned_minutes"] == 30 and w["missed_minutes"] == 0


@pytest.mark.asyncio
async def test_remaining_and_missed_are_separated_in_a_mixed_day():
    uid, h = _user()
    _task(uid, "Slipped", start_offset_min=-180, minutes=45)
    _task(uid, "In its slot", start_offset_min=-10, minutes=60)
    _task(uid, "Later", start_offset_min=180, minutes=30)
    _task(uid, "Done", start_offset_min=-240, minutes=20, status=TaskStatus.completed)
    w = await _workload(h)
    assert (w["planned_minutes"], w["missed_minutes"], w["missed_count"]) == (90, 45, 1)
    assert w["formatted_workload"] == "1h 30m planned"


@pytest.mark.asyncio
async def test_an_in_progress_task_with_a_past_slot_is_still_remaining_work():
    uid, h = _user()
    _task(uid, "Still going", start_offset_min=-180, minutes=45, status=TaskStatus.in_progress)
    w = await _workload(h)
    assert w["planned_minutes"] == 45 and w["missed_minutes"] == 0


@pytest.mark.asyncio
async def test_a_rescheduled_missed_task_counts_again_at_its_new_occurrence():
    uid, h = _user()
    tid = _task(uid, "Recovered", start_offset_min=-180, minutes=45)
    before = await _workload(h)
    assert (before["planned_minutes"], before["missed_minutes"]) == (0, 45)
    new_start = datetime.now(timezone.utc) + timedelta(minutes=120)
    with SessionLocal() as db:                                    # what Replan/Redo does: a new active slot
        t = db.get(Task, tid)
        t.scheduled_start, t.scheduled_end = new_start, new_start + timedelta(minutes=45)
        db.commit()
    after = await _workload(h)
    assert (after["planned_minutes"], after["missed_minutes"], after["missed_count"]) == (45, 0, 0)


@pytest.mark.asyncio
async def test_overload_is_judged_on_remaining_work_only():
    uid, h = _user()
    for i in range(3):                                            # 3 x 200 = 600 min missed (> 390 available)
        _task(uid, f"Slipped {i}", start_offset_min=-400 - i, minutes=200)
    _task(uid, "Later", start_offset_min=240, minutes=30)
    w = await _workload(h)
    assert w["planned_minutes"] == 30 and w["is_overloaded"] is False
    assert w["missed_minutes"] == 600
