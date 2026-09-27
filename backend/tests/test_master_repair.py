import pytest
from datetime import datetime, timedelta, time
from zoneinfo import ZoneInfo
from app.services.ai_service import AIService
from app.engines.scheduling_engine import SchedulingEngine, PlanningProfile
from app.models.task import TaskType, TaskPriority, TaskDifficulty, TaskSource
from app.schemas.task import TaskCandidateResponse

def test_master_repair_scenario_1_segmentation():
    """
    TEST 1:
    Input: "I have gym work and assignments"
    Expected:
    - 3 independent tasks (Gym, Work, Assignments/Assignment)
    - No invented fixed times (scheduled_start is None)
    - No invented user priority (priority provenance is unspecified)
    - No combined title
    - Independent task types: Gym is physical, Work is deep_work/admin, Assignment is deep_work/study
    """
    raw_input = "I have gym work and assignments"
    tasks = AIService.parse_task_dump(raw_input)

    assert len(tasks) == 3, f"Expected 3 tasks but got {len(tasks)}: {[t.title for t in tasks]}"
    
    titles = [t.title.lower() for t in tasks]
    assert "gym" in titles
    assert "work" in titles
    assert any("assign" in t for t in titles)

    gym_task = next(t for t in tasks if t.title.lower() == "gym")
    work_task = next(t for t in tasks if t.title.lower() == "work")
    assign_task = next(t for t in tasks if "assign" in t.title.lower())

    # Independent types
    assert gym_task.task_type == TaskType.physical
    assert work_task.task_type in (TaskType.deep_work, TaskType.admin)
    assert assign_task.task_type in (TaskType.deep_work, TaskType.study)

    # No invented fixed times
    assert gym_task.scheduled_start is None
    assert work_task.scheduled_start is None
    assert assign_task.scheduled_start is None

    # No invented user priority
    for t in tasks:
        prio_src = t.field_provenance["priority"].source if t.field_provenance and "priority" in t.field_provenance else "unspecified"
        assert prio_src == "unspecified", f"Task {t.title} had priority source {prio_src}"

def test_master_repair_scenario_2_independence():
    """
    TEST 2:
    Input: "gym at 6, important assignment tomorrow, work for 90 minutes"
    Expected:
    - Gym: fixed = 6 PM
    - Important assignment: deadline = tomorrow, priority = high (explicit)
    - Work: duration = 90m
    - Each must be independent
    """
    raw_input = "gym at 6, important assignment tomorrow, work for 90 minutes"
    tasks = AIService.parse_task_dump(raw_input)

    assert len(tasks) == 3, f"Expected 3 tasks but got {len(tasks)}: {[t.title for t in tasks]}"

    gym_task = next(t for t in tasks if "gym" in t.title.lower())
    assign_task = next(t for t in tasks if "assign" in t.title.lower())
    work_task = next(t for t in tasks if "work" in t.title.lower())

    # Gym has fixed start
    assert gym_task.scheduled_start is not None

    # Assignment has deadline tomorrow and explicit priority
    assert assign_task.deadline_at is not None
    assert assign_task.priority in (TaskPriority.high, TaskPriority.urgent)
    assert assign_task.field_provenance["priority"].source == "explicit"

    # Work has 90 min duration
    assert work_task.estimated_minutes == 90
    assert work_task.field_provenance["duration"].source == "explicit"

def test_master_repair_scenario_3_current_time_1015_pm():
    """
    TEST 3:
    Current time: 10:15 PM
    Input: "I have important work"
    Expected:
    - Reasonable future slot (Tomorrow morning)
    - NOT 10:15 PM fixed time
    """
    tz = ZoneInfo("Asia/Kolkata")
    now_local = datetime(2026, 9, 26, 22, 15, tzinfo=tz) # 10:15 PM

    task = TaskCandidateResponse(
        title="Work",
        task_type=TaskType.deep_work,
        estimated_minutes=45,
        difficulty=TaskDifficulty.medium,
        priority=TaskPriority.high,
        category="Work",
        source=TaskSource.ai_parsed,
    )

    scheduler = SchedulingEngine()
    profile = PlanningProfile()
    res = scheduler.evaluate_best_slot_for_task(task, [], profile, now_local, tz)

    assert res is not None
    # Must NOT be today 10:15 PM!
    assert res.slot.day_offset == 1, f"Expected tomorrow (day_offset=1) but got day_offset={res.slot.day_offset}, start={res.slot.start_time}"
    assert res.slot.start_time.hour in (9, 10, 11)

def test_master_repair_scenario_4_deadline_safety():
    """
    TEST 4:
    Current time: 10:15 PM
    Input: "important assignment due tomorrow at 8 AM"
    Expected:
    - Deadline-safe scheduling
    - Must finish BEFORE 8:00 AM tomorrow
    - Do NOT blindly push to tomorrow at 9 AM
    """
    tz = ZoneInfo("Asia/Kolkata")
    now_local = datetime(2026, 9, 26, 22, 15, tzinfo=tz) # 10:15 PM
    tmw_8am = datetime(2026, 9, 27, 8, 0, tzinfo=tz)

    task = TaskCandidateResponse(
        title="Assignment",
        task_type=TaskType.deep_work,
        estimated_minutes=60,
        difficulty=TaskDifficulty.high,
        priority=TaskPriority.urgent,
        deadline_at=tmw_8am,
        category="College",
        source=TaskSource.ai_parsed,
    )

    scheduler = SchedulingEngine()
    profile = PlanningProfile()
    res = scheduler.evaluate_best_slot_for_task(task, [], profile, now_local, tz)

    assert res is not None
    assert res.slot.end_time <= tmw_8am, f"Slot {res.slot.start_time} - {res.slot.end_time} violates deadline {tmw_8am}!"
