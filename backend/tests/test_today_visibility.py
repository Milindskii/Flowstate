"""Every open task that belongs to today must be visible on Today (regression: unscheduled tasks were dropped).

Regression root cause: `/today` built `upcoming_timeline` from the Calendar day view's `timeline` only and discarded
`unscheduled_tasks`, so an open task planned for today that had no slot and no capacity left appeared in
`/tasks/today` and in the workload minutes but nowhere on Today. planned_date semantics are untouched.
"""
import uuid
from datetime import datetime, timezone

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.task import Task, TaskPriority, TaskStatus, TaskType
from app.models.user import User


def _user():
    uid = f"today-vis-{uuid.uuid4().hex[:8]}"
    with SessionLocal() as db:
        db.add(User(id=uid, email=f"{uid}@flowstate.local", name="T"))
        db.commit()
    return uid, {"Authorization": f"Bearer {create_access_token({'sub': uid, 'email': f'{uid}@flowstate.local'})}"}


def _unslotted(uid, title, minutes, priority=TaskPriority.medium):
    """An open task planned for today with no stored slot (planned_date is today's UTC date)."""
    with SessionLocal() as db:
        t = Task(user_id=uid, title=title, task_type=TaskType.deep_work, priority=priority,
                 estimated_minutes=minutes, status=TaskStatus.todo, planned_date=datetime.now(timezone.utc).date())
        db.add(t)
        db.commit()
        return str(t.id)


async def _get(h, path):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get(path, headers=h)
    assert res.status_code == 200, res.text
    return res.json()


def _visible_titles(today):
    titles = {i["title"] for i in today["upcoming_timeline"]}
    for key in ("current_recommendation", "active_task"):
        block = today.get(key) or {}
        task = block.get("task") if key == "current_recommendation" else block
        if task and task.get("title"):
            titles.add(task["title"])
    return titles


@pytest.mark.asyncio
async def test_open_tasks_that_cannot_be_placed_today_are_still_listed_on_today():
    uid, h = _user()
    # Far longer than any day has room for: guaranteed to be unscheduled whatever time the suite runs.
    for title in ("Huge task one", "Huge task two", "Huge task three"):
        _unslotted(uid, title, 900)

    todays_tasks = await _get(h, "/api/v1/tasks/today?timezone=UTC")
    today = await _get(h, "/api/v1/today?timezone=UTC")

    expected = {t["title"] for t in todays_tasks if t["status"] != "completed"}
    assert expected == {"Huge task one", "Huge task two", "Huge task three"}
    missing = expected - _visible_titles(today)
    assert not missing, f"open tasks for today missing from /today: {sorted(missing)}"


@pytest.mark.asyncio
async def test_unscheduled_items_are_flagged_and_carry_no_fake_time():
    uid, h = _user()
    for title in ("Huge task one", "Huge task two", "Huge task three"):
        _unslotted(uid, title, 900)
    today = await _get(h, "/api/v1/today?timezone=UTC")
    unscheduled = [i for i in today["upcoming_timeline"] if i.get("tag_text") == "UNSCHEDULED"]
    assert unscheduled, "unplaceable tasks must be flagged UNSCHEDULED in the Today timeline"
    assert all(i["time"] == "--:--" for i in unscheduled)
    assert len({i["id"] for i in today["upcoming_timeline"]}) == len(today["upcoming_timeline"]), "no duplicate rows"


@pytest.mark.asyncio
async def test_completed_and_other_days_tasks_are_not_added_to_today():
    uid, h = _user()
    with SessionLocal() as db:
        from datetime import timedelta
        today_date = datetime.now(timezone.utc).date()
        db.add(Task(user_id=uid, title="Done already", task_type=TaskType.admin, priority=TaskPriority.low,
                    estimated_minutes=900, status=TaskStatus.completed, planned_date=today_date,
                    completed_at=datetime.now(timezone.utc)))
        db.add(Task(user_id=uid, title="Planned for next week", task_type=TaskType.admin, priority=TaskPriority.low,
                    estimated_minutes=900, status=TaskStatus.todo, planned_date=today_date + timedelta(days=7)))
        db.commit()
    today = await _get(h, "/api/v1/today?timezone=UTC")
    titles = _visible_titles(today)
    assert "Done already" not in titles and "Planned for next week" not in titles


# ── Tomorrow section (manual verification 2026-10-06) ────────────────────────
# Today stays today's execution view. Tomorrow's open tasks are a separate `tomorrow_tasks` list: not in
# `upcoming_timeline`, never completed/cancelled work, never a duplicate of a today task.

def _task(uid, title, *, planned, status=TaskStatus.todo, start=None, minutes=30, **kw):
    from datetime import timedelta
    with SessionLocal() as db:
        t = Task(user_id=uid, title=title, task_type=TaskType.admin, priority=TaskPriority.medium,
                 estimated_minutes=minutes, status=status, planned_date=planned,
                 scheduled_start=start, scheduled_end=(start + timedelta(minutes=minutes)) if start else None, **kw)
        db.add(t)
        db.commit()
        return str(t.id)


@pytest.mark.asyncio
async def test_tomorrow_section_lists_only_open_tomorrow_tasks():
    from datetime import timedelta
    uid, h = _user()
    today_date = datetime.now(timezone.utc).date()
    tomorrow = today_date + timedelta(days=1)
    at_ten = datetime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0, tzinfo=timezone.utc)
    slotted = _task(uid, "Tomorrow slotted", planned=tomorrow, start=at_ten)
    unslotted = _task(uid, "Tomorrow unslotted", planned=tomorrow)
    _task(uid, "Tomorrow done", planned=tomorrow, status=TaskStatus.completed, completed_at=datetime.now(timezone.utc))
    _task(uid, "Tomorrow cancelled", planned=tomorrow, status=TaskStatus.cancelled)
    _task(uid, "Next week", planned=today_date + timedelta(days=7))
    _unslotted(uid, "Today task", 20)

    today = await _get(h, "/api/v1/today?timezone=UTC")
    tomorrow_tasks = today["tomorrow_tasks"]
    assert [t["title"] for t in tomorrow_tasks] == ["Tomorrow slotted", "Tomorrow unslotted"]  # timed first
    assert {t["id"] for t in tomorrow_tasks} == {slotted, unslotted}
    assert tomorrow_tasks[0]["start_time"].startswith(at_ten.strftime("%Y-%m-%dT10:00:00"))
    assert tomorrow_tasks[1]["start_time"] is None
    # nothing of tomorrow leaks into today's execution view, and today's task is not duplicated
    assert not {t["title"] for t in tomorrow_tasks} & _visible_titles(today)
    assert "Today task" in _visible_titles(today)
    assert "Today task" not in {t["title"] for t in tomorrow_tasks}

    # persisted, not computed on the client: a fresh request (an app restart) returns the same list
    again = await _get(h, "/api/v1/today?timezone=UTC")
    assert again["tomorrow_tasks"] == tomorrow_tasks


@pytest.mark.asyncio
async def test_tomorrow_section_is_empty_when_tomorrow_has_no_open_tasks():
    from datetime import timedelta
    uid, h = _user()
    tomorrow = datetime.now(timezone.utc).date() + timedelta(days=1)
    _task(uid, "Tomorrow done", planned=tomorrow, status=TaskStatus.completed, completed_at=datetime.now(timezone.utc))
    _task(uid, "Tomorrow cancelled", planned=tomorrow, status=TaskStatus.cancelled)
    today = await _get(h, "/api/v1/today?timezone=UTC")
    assert today["tomorrow_tasks"] == []


@pytest.mark.asyncio
async def test_tomorrow_tasks_are_scoped_to_the_user():
    from datetime import timedelta
    uid, h = _user()
    other, _ = _user()
    _task(other, "Someone else's tomorrow", planned=datetime.now(timezone.utc).date() + timedelta(days=1))
    today = await _get(h, "/api/v1/today?timezone=UTC")
    assert today["tomorrow_tasks"] == []
