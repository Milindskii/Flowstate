from datetime import datetime, time
from zoneinfo import ZoneInfo

from app.engines.scheduling_engine import PlanningProfile, SchedulingEngine
from app.models.task import TaskDifficulty, TaskPriority, TaskSource, TaskType
from app.schemas.task import TaskCandidateResponse, TemporalConstraints
from app.services.ai_service import AIService


def test_dbms_deadline_and_later_chore_are_independent_without_inheritance():
    tz = ZoneInfo("Asia/Kolkata")
    now = datetime(2026, 9, 27, 10, 0, tzinfo=tz)

    tasks = [AIService._parse_single_clause(c, now, tz) for c in AIService._split_clauses(
        "Submit my DBMS assignment by 8 PM tomorrow, maybe clean my room later"
    )]
    assert len(tasks) == 2
    assignment, cleaning = tasks
    assert assignment.title.lower() == "submit my dbms assignment"
    assert assignment.deadline_at == datetime(2026, 9, 28, 20, 0, tzinfo=tz)
    assert cleaning.deadline_at is None
    assert cleaning.field_provenance["priority"].source == "unspecified"


def test_single_coherent_outcome_is_not_split():
    assert AIService._split_clauses("finish my assignment and submit it") == [
        "finish my assignment and submit it"
    ]


def test_around_time_is_a_preference_not_a_fixed_start():
    tz = ZoneInfo("Asia/Kolkata")
    candidate = AIService._parse_single_clause("Gym around 6 PM", datetime(2026, 9, 27, 10, tzinfo=tz), tz)
    assert candidate.scheduled_start is None
    assert candidate.temporal is not None
    assert candidate.temporal.flexibility == "preferred"
    assert candidate.temporal.preferred_start == datetime(2026, 9, 27, 18, 0, tzinfo=tz)


def test_scheduler_never_places_after_dinner_task_before_dinner():
    tz = ZoneInfo("Asia/Kolkata")
    now = datetime(2026, 9, 27, 13, 0, tzinfo=tz)
    task = TaskCandidateResponse(
        title="Fix login bug",
        estimated_minutes=60,
        task_type=TaskType.deep_work,
        difficulty=TaskDifficulty.high,
        priority=TaskPriority.medium,
        source=TaskSource.ai_parsed,
        temporal=TemporalConstraints(
            earliest_start=datetime(2026, 9, 27, 20, 0, tzinfo=tz),
            relative_after="dinner",
            flexibility="constrained",
        ),
    )
    result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
    assert result is not None
    assert result.slot.start_time >= datetime(2026, 9, 27, 20, 0, tzinfo=tz)


def test_critical_temporal_relationships_are_preserved():
    tz = ZoneInfo("Asia/Kolkata")
    now = datetime(2026, 9, 27, 12, 0, tzinfo=tz)
    tasks = AIService.parse_task_dump(
        "At 6 in the evening I want to go to the gym, then after dinner I need to spend about an hour fixing the login bug, and before I sleep I should probably review DSA for 30 minutes.",
        "Asia/Kolkata",
    )
    assert len(tasks) == 3
    gym = next(task for task in tasks if "gym" in task.title.lower())
    bug = next(task for task in tasks if "login" in task.title.lower())
    dsa = next(task for task in tasks if "dsa" in task.title.lower())
    # "At 6 in the evening" without explicit am/pm → ambiguous → preferred, not fixed.
    # The correct semantic is a preferred_start at 18:00, not a hard scheduled_start.
    assert gym.scheduled_start is None, "Ambiguous 'at 6' must NOT produce a fixed scheduled_start"
    assert gym.temporal is not None and gym.temporal.preferred_start is not None
    assert gym.temporal.preferred_start.hour == 18 and gym.temporal.preferred_start.minute == 0
    assert gym.temporal.flexibility == "preferred"
    assert bug.temporal is not None and bug.temporal.relative_after == "dinner"
    assert dsa.temporal is not None and dsa.temporal.relative_before == "bedtime"
