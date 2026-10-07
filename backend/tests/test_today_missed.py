"""
/today must apply the same derived missed/failed rule as the Calendar and Flutter
(shared/task_state_vectors.json): a task whose slot already ended unstarted is never the recommendation,
yet it stays in the day (nothing is deleted or reordered) and an in-progress task is never "missed".
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
    uid = f"today-missed-{uuid.uuid4().hex[:8]}"
    with SessionLocal() as db:
        db.add(User(id=uid, email=f"{uid}@flowstate.local", name="T"))
        db.commit()
    return uid, {"Authorization": f"Bearer {create_access_token({'sub': uid, 'email': f'{uid}@flowstate.local'})}"}


def _task(uid, title, *, start_offset_h, minutes=60, priority=TaskPriority.medium, status=TaskStatus.todo):
    now = datetime.now(timezone.utc)
    start = now + timedelta(hours=start_offset_h)
    with SessionLocal() as db:
        t = Task(user_id=uid, title=title, task_type=TaskType.deep_work, priority=priority, estimated_minutes=minutes,
                 scheduled_start=start, scheduled_end=start + timedelta(minutes=minutes), status=status,
                 planned_date=now.date(), started_at=now if status == TaskStatus.in_progress else None)
        db.add(t)
        db.commit()
        return str(t.id)


async def _today(uid_headers):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/today?timezone=UTC", headers=uid_headers)
    assert res.status_code == 200
    return res.json()


@pytest.mark.asyncio
async def test_a_missed_task_is_never_recommended_even_when_it_is_the_most_urgent():
    uid, h = _user()
    missed = _task(uid, "Missed urgent", start_offset_h=-4, priority=TaskPriority.urgent)   # slot ended 3h ago
    future = _task(uid, "Upcoming calm", start_offset_h=2, priority=TaskPriority.low)
    data = await _today(h)
    rec = (data["current_recommendation"] or {}).get("task") or {}
    assert rec.get("id") == future, "the recommendation must be the task that can still be done"
    assert rec.get("id") != missed


@pytest.mark.asyncio
async def test_only_missed_tasks_means_no_recommendation_and_no_start_with_copy():
    uid, h = _user()
    _task(uid, "Missed one", start_offset_h=-4)
    data = await _today(h)
    assert data["current_recommendation"] is None
    assert "start with" not in data["ai_brief"]["message"].lower()


@pytest.mark.asyncio
async def test_a_missed_task_stays_in_the_day_at_its_own_time_slot():
    uid, h = _user()
    missed = _task(uid, "Stays put", start_offset_h=-4)
    _task(uid, "Later", start_offset_h=2)
    data = await _today(h)
    titles = [i["title"] for i in data["upcoming_timeline"]]
    assert "Stays put" in titles and "Later" in titles
    assert titles.index("Stays put") < titles.index("Later"), "chronological order is preserved, nothing is pinned"


@pytest.mark.asyncio
async def test_an_in_progress_task_with_a_past_slot_is_active_not_missed():
    uid, h = _user()
    running = _task(uid, "Still working", start_offset_h=-4, status=TaskStatus.in_progress)
    data = await _today(h)
    assert (data["active_task"] or {}).get("id") == running
