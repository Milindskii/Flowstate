"""
Calendar & Replan My Day Comprehensive Backend Test Suite
=========================================================
Tests all 11 required scenarios:
1. Dentist at 6 PM. New urgent 1-hour task conflicts with 6 PM. Dentist remains fixed.
2. Current time 4 PM. Replan must never schedule something at 2 PM (in the past).
3. "I am running 30 minutes late." Remaining schedule changes, completed tasks untouched.
4. "Move gym to tomorrow." Gym target date changes.
5. "Move gym to evening." Evening preference preserved.
6. "Push report after dinner." Earliest_start/relative constraint preserved.
7. "Cancel gym today." Gym removed/cancelled for today.
8. Impossible 3-hour task with no feasible capacity. Reported as conflict/unscheduled, never invent a slot.
9. Future selected date Friday. Friday schedule, not today's schedule.
10. Generate replan. Database is unchanged.
11. Apply replan. Database reflects the exact confirmed diff.
"""

import pytest
import uuid
from datetime import datetime, timezone, timedelta, time
from zoneinfo import ZoneInfo
from httpx import AsyncClient, ASGITransport

from app.main import app
from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.models.user import User
from app.models.task import Task, TaskStatus, TaskType, TaskPriority

TZ = ZoneInfo("Asia/Kolkata")


def _t8():
    """Deterministic client clock: 08:00 today (IST). These tests used the wall clock before, which made
    their outcome depend on the time of day they were run."""
    return datetime.combine(datetime.now(TZ).date(), time(8, 0), tzinfo=TZ).isoformat()

@pytest.fixture
def test_user_session():
    user_id = f"user-cal-{uuid.uuid4().hex[:8]}"
    email = f"{user_id}@flowstate.local"
    db = SessionLocal()
    user = User(id=user_id, email=email, name="Calendar Tester")
    db.add(user)
    db.commit()

    token = create_access_token({"sub": user_id, "email": email})
    headers = {"Authorization": f"Bearer {token}"}
    yield {"user_id": user_id, "headers": headers, "db": db}

    db.close()


@pytest.mark.asyncio
async def test_1_dentist_at_6_pm_remains_fixed_when_urgent_work_conflicts(test_user_session):
    """
    TEST 1:
    Existing: 6:00 PM Dentist (fixed).
    User adds: "Urgent work needs 1 hour at 6."
    Expected: Conflict detected. Dentist remains fixed at 6 PM.
    Urgent work placed in another feasible slot. No silent movement of dentist.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_str = datetime.now(TZ).strftime("%Y-%m-%d")
    dentist_start = datetime.combine(datetime.now(TZ).date(), time(18, 0), tzinfo=TZ)
    dentist_end = dentist_start + timedelta(minutes=45)

    dentist_task = Task(
        user_id=user_id,
        title="Dentist appointment",
        estimated_minutes=45,
        scheduled_start=dentist_start.astimezone(timezone.utc),
        scheduled_end=dentist_end.astimezone(timezone.utc),
        status=TaskStatus.todo,
        time_locked=True,  # a fixed appointment: since finding 2, a bare scheduled_start no longer implies "fixed"
    )
    db.add(dentist_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "I need to do this urgent work needs 1 hour at 6 PM",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        plan_diff = data["plan_diff"]

        # Conflict must be detected referencing Dentist
        assert len(plan_diff["conflicts"]) > 0
        assert any("dentist" in c.lower() for c in plan_diff["conflicts"])

        # Dentist MUST remain at 6:00 PM in after_schedule
        dentist_after = next((item for item in plan_diff["after_schedule"] if "dentist" in item["title"].lower()), None)
        assert dentist_after is not None
        assert dentist_after["is_fixed"] is True
        assert dentist_after["time"] == "6:00"
        assert dentist_after["period"] == "PM"

        # Urgent work must NOT overwrite 6 PM
        urgent_after = next((item for item in plan_diff["after_schedule"] if "urgent" in item["title"].lower()), None)
        assert urgent_after is not None
        assert not (urgent_after["time"] == "6:00" and urgent_after["period"] == "PM")


@pytest.mark.asyncio
async def test_2_current_time_4_pm_never_schedules_in_past(test_user_session):
    """
    TEST 2:
    Current time 4 PM (16:00).
    Replan must never schedule something at 2 PM (in the past).
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]

    today_str = datetime.now(TZ).strftime("%Y-%m-%d")
    now_4pm = datetime.combine(datetime.now(TZ).date(), time(16, 0), tzinfo=TZ)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Add a 45 min review task today",
                "current_local_time": now_4pm.isoformat(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        data = res.json()
        plan_diff = data["plan_diff"]

        for item in plan_diff["after_schedule"]:
            start_dt = datetime.fromisoformat(item["start_time"])
            if start_dt.tzinfo is None:
                start_dt = start_dt.replace(tzinfo=TZ)
            # Newly scheduled tasks must be >= 16:00
            if "review" in item["title"].lower():
                assert start_dt >= now_4pm, f"Task was scheduled at {start_dt} which is in the past!"


@pytest.mark.asyncio
async def test_3_running_30_minutes_late_shifts_remaining_protects_completed(test_user_session):
    """
    TEST 3:
    "I'm running 30 minutes late."
    Remaining schedule shifts by 30 mins, completed tasks remain untouched.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    # Completed task at 10 AM
    comp_start = datetime.combine(today_date, time(10, 0), tzinfo=TZ)
    comp_end = comp_start + timedelta(minutes=45)
    t_comp = Task(
        user_id=user_id,
        title="Morning Sync",
        estimated_minutes=45,
        scheduled_start=comp_start.astimezone(timezone.utc),
        scheduled_end=comp_end.astimezone(timezone.utc),
        completed_at=comp_end.astimezone(timezone.utc),
        status=TaskStatus.completed,
    )

    # Future task at 16:30
    fut_start = datetime.combine(today_date, time(16, 30), tzinfo=TZ)
    fut_end = fut_start + timedelta(minutes=45)
    t_fut = Task(
        user_id=user_id,
        title="Code Review",
        estimated_minutes=45,
        scheduled_start=fut_start.astimezone(timezone.utc),
        scheduled_end=fut_end.astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(t_comp)
    db.add(t_fut)
    db.commit()

    now_15 = datetime.combine(today_date, time(15, 0), tzinfo=TZ)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "I'm running 30 minutes late.",
                "current_local_time": now_15.isoformat(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        # Completed task remains at 10:00 AM
        comp_item = next(it for it in plan_diff["after_schedule"] if it["title"] == "Morning Sync")
        assert comp_item["time"] == "10:00"
        assert comp_item["period"] == "AM"
        assert comp_item["is_completed"] is True

        # Future task moved forward by 30 mins (from 4:30 PM to 5:00 PM)
        fut_item = next(it for it in plan_diff["after_schedule"] if it["title"] == "Code Review")
        assert fut_item["time"] == "5:00"
        assert fut_item["period"] == "PM"


@pytest.mark.asyncio
async def test_4_move_gym_to_tomorrow(test_user_session):
    """
    TEST 4:
    "Move gym to tomorrow."
    Gym target date changes / moved from today's schedule.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    gym_start = datetime.combine(today_date, time(17, 0), tzinfo=TZ)
    gym_task = Task(
        user_id=user_id,
        title="Gym workout",
        estimated_minutes=60,
        scheduled_start=gym_start.astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(gym_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Move gym to tomorrow.",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        # Gym should be in moved_tasks targeting tomorrow
        assert any("gym" in m["title"].lower() and "tomorrow" in (m["new_date"] or "").lower() for m in plan_diff["moved_tasks"])
        # Gym should no longer be in after_schedule for today
        assert not any("gym" in it["title"].lower() for it in plan_diff["after_schedule"])


@pytest.mark.asyncio
async def test_5_move_gym_to_evening_preserves_evening_window(test_user_session):
    """
    TEST 5:
    "Move gym to evening."
    Evening preference preserved (18:00 - 21:00).
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    gym_start = datetime.combine(today_date, time(10, 0), tzinfo=TZ)
    gym_task = Task(
        user_id=user_id,
        title="Gym workout",
        estimated_minutes=60,
        scheduled_start=gym_start.astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(gym_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Move gym to evening.",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        gym_item = next(it for it in plan_diff["after_schedule"] if "gym" in it["title"].lower())
        start_dt = datetime.fromisoformat(gym_item["start_time"])
        # Evening window is >= 18:00
        assert start_dt.hour >= 18


@pytest.mark.asyncio
async def test_6_push_report_after_dinner_preserves_dinner_boundary(test_user_session):
    """
    TEST 6:
    "Push the report after dinner."
    Report starts after dinner boundary (20:00).
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    report_start = datetime.combine(today_date, time(14, 0), tzinfo=TZ)
    report_task = Task(
        user_id=user_id,
        title="Project Report",
        estimated_minutes=60,
        scheduled_start=report_start.astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(report_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Push the report after dinner.",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        report_item = next(it for it in plan_diff["after_schedule"] if "report" in it["title"].lower())
        start_dt = datetime.fromisoformat(report_item["start_time"])
        # Dinner anchor is 20:00
        assert start_dt.hour >= 20


@pytest.mark.asyncio
async def test_7_cancel_gym_today(test_user_session):
    """
    TEST 7:
    "Cancel gym today."
    Gym cancelled / removed from today's schedule.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    gym_task = Task(
        user_id=user_id,
        title="Gym workout",
        estimated_minutes=60,
        scheduled_start=datetime.combine(today_date, time(17, 0), tzinfo=TZ).astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    study_task = Task(
        user_id=user_id,
        title="Study math",
        estimated_minutes=60,
        scheduled_start=datetime.combine(today_date, time(14, 0), tzinfo=TZ).astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(gym_task)
    db.add(study_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Cancel gym today.",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        assert any("gym" in c["title"].lower() for c in plan_diff["cancelled_tasks"])
        assert not any("gym" in it["title"].lower() for it in plan_diff["after_schedule"])
        # Study math remains
        assert any("study" in it["title"].lower() for it in plan_diff["after_schedule"])


@pytest.mark.asyncio
async def test_8_impossible_task_reports_conflict_and_never_invents_slot(test_user_session):
    """
    TEST 8:
    User requests an impossible 3-hour task late in the evening (e.g. at 22:30 with bedtime at 23:00).
    Expected: Conflict / unscheduled result. NEVER invent a slot.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")
    now_late = datetime.combine(today_date, time(22, 15), tzinfo=TZ)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "I need to fit an urgent 3 hour task today",
                "current_local_time": now_late.isoformat(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200
        plan_diff = res.json()["plan_diff"]

        # Conflict must be flagged
        assert len(plan_diff["conflicts"]) > 0 or len(plan_diff["unscheduled_tasks"]) > 0
        # Task must NOT be placed in after_schedule
        assert not any("3 hour" in it["title"].lower() for it in plan_diff["after_schedule"])


@pytest.mark.asyncio
async def test_9_future_selected_date_friday_shows_friday_schedule(test_user_session):
    """
    TEST 9:
    Future selected date Friday.
    Calendar day API shows Friday's schedule, not today's schedule.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today = datetime.now(TZ).date()
    days_until_friday = (4 - today.weekday()) % 7
    if days_until_friday == 0:
        days_until_friday = 7
    friday_date = today + timedelta(days=days_until_friday)
    friday_str = friday_date.strftime("%Y-%m-%d")

    # Task for Friday
    friday_task = Task(
        user_id=user_id,
        title="Friday Project Presentation",
        estimated_minutes=60,
        scheduled_start=datetime.combine(friday_date, time(15, 0), tzinfo=TZ).astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    # Task for Today
    today_task = Task(
        user_id=user_id,
        title="Today Quick Call",
        estimated_minutes=30,
        scheduled_start=datetime.combine(today, time(11, 0), tzinfo=TZ).astimezone(timezone.utc),
        status=TaskStatus.todo,
    )
    db.add(friday_task)
    db.add(today_task)
    db.commit()

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get(f"/api/v1/calendar/day?date={friday_str}&timezone=Asia/Kolkata", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert data["date"] == friday_str
        assert data["is_today"] is False

        # Friday task is present
        assert any("friday project presentation" in it["title"].lower() for it in data["timeline"])
        # Today task is NOT present on Friday
        assert not any("today quick call" in it["title"].lower() for it in data["timeline"])


@pytest.mark.asyncio
async def test_10_generate_replan_does_not_mutate_database(test_user_session):
    """
    TEST 10:
    Calling POST /api/v1/ai/replan does NOT mutate the database.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    original_start = datetime.combine(today_date, time(14, 0), tzinfo=TZ).astimezone(timezone.utc)
    task = Task(
        user_id=user_id,
        title="Client meeting",
        estimated_minutes=60,
        scheduled_start=original_start,
        status=TaskStatus.todo,
    )
    db.add(task)
    db.commit()
    task_id = str(task.id)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post(
            "/api/v1/ai/replan",
            headers=headers,
            json={
                "selected_date": today_str,
                "user_message": "Cancel client meeting today.",
                "current_local_time": _t8(),
                "timezone": "Asia/Kolkata",
            },
        )
        assert res.status_code == 200

    # Query DB directly: task MUST still exist and status MUST still be todo!
    db_task = db.query(Task).filter(Task.id == task_id).first()
    assert db_task is not None
    assert db_task.status == TaskStatus.todo
    task_start = db_task.scheduled_start.replace(tzinfo=timezone.utc) if db_task.scheduled_start.tzinfo is None else db_task.scheduled_start
    assert task_start == original_start


@pytest.mark.asyncio
async def test_11_apply_replan_atomically_updates_database(test_user_session):
    """
    TEST 11:
    Calling POST /api/v1/calendar/apply-replan commits the exact confirmed diff.
    """
    user_id = test_user_session["user_id"]
    headers = test_user_session["headers"]
    db = test_user_session["db"]

    today_date = datetime.now(TZ).date()
    today_str = today_date.strftime("%Y-%m-%d")

    old_start = datetime.combine(today_date, time(14, 0), tzinfo=TZ).astimezone(timezone.utc)
    new_start = datetime.combine(today_date, time(16, 30), tzinfo=TZ).astimezone(timezone.utc)
    new_end = new_start + timedelta(minutes=45)

    task_to_move = Task(
        user_id=user_id,
        title="Flexible report",
        estimated_minutes=45,
        scheduled_start=old_start,
        status=TaskStatus.todo,
    )
    task_to_cancel = Task(
        user_id=user_id,
        title="Optional call",
        estimated_minutes=30,
        scheduled_start=old_start,
        status=TaskStatus.todo,
    )
    db.add(task_to_move)
    db.add(task_to_cancel)
    db.commit()

    move_id = str(task_to_move.id)
    cancel_id = str(task_to_cancel.id)

    apply_payload = {
        "plan_id": str(uuid.uuid4()),
        "selected_date": today_str,
        "task_updates": [
            {
                "task_id": move_id,
                "scheduled_start": new_start.isoformat(),
                "scheduled_end": new_end.isoformat(),
            }
        ],
        "new_tasks": [
            {
                "title": "Urgent bug fix",
                "estimated_minutes": 60,
                "task_type": "deep_work",
                "priority": "urgent",
                "scheduled_start": datetime.combine(today_date, time(17, 30), tzinfo=TZ).astimezone(timezone.utc).isoformat(),
                "scheduled_end": datetime.combine(today_date, time(18, 30), tzinfo=TZ).astimezone(timezone.utc).isoformat(),
            }
        ],
        "cancelled_task_ids": [cancel_id],
        "current_local_time": _t8(),
    }

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.post("/api/v1/calendar/apply-replan", headers=headers, json=apply_payload)
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["updated_count"] == 1
        assert data["created_count"] == 1
        assert data["cancelled_count"] == 1

    # Verify DB state directly
    db.expire_all()
    moved_db = db.query(Task).filter(Task.id == move_id).first()
    moved_start = moved_db.scheduled_start.replace(tzinfo=timezone.utc) if moved_db.scheduled_start.tzinfo is None else moved_db.scheduled_start
    moved_end = moved_db.scheduled_end.replace(tzinfo=timezone.utc) if moved_db.scheduled_end.tzinfo is None else moved_db.scheduled_end
    assert moved_start == new_start
    assert moved_end == new_end

    cancelled_db = db.query(Task).filter(Task.id == cancel_id).first()
    assert cancelled_db.status == TaskStatus.cancelled

    new_db = db.query(Task).filter(Task.user_id == user_id, Task.title == "Urgent bug fix").first()
    assert new_db is not None
    assert new_db.status == TaskStatus.todo
    assert new_db.priority == TaskPriority.urgent
