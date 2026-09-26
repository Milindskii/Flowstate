import pytest
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo
from app.services.ai_service import AIService
from app.engines.scheduling_engine import SchedulingEngine, PlanningProfile, CandidateSlot
from app.models.task import TaskType, TaskPriority, TaskDifficulty
from app.schemas.task import TaskCandidateResponse

def test_task_segmentation_independent_activities():
    """Requirement 2: 'gym work assignment' must become 3 separate tasks: Gym, Work, Assignment."""
    text = "gym work assignment"
    clauses = AIService._split_clauses(text)
    assert len(clauses) == 3
    assert [c.lower() for c in clauses] == ["gym", "work", "assignment"]

def test_task_segmentation_single_outcome_preserved():
    """Requirement 2: 'finish my work assignment' must remain 1 task."""
    text = "finish my work assignment"
    clauses = AIService._split_clauses(text)
    assert len(clauses) == 1
    assert "assignment" in clauses[0].lower()

def test_task_segmentation_compound_clause_with_pronoun_preserved():
    """Requirement 2: 'finish my Python assignment and submit it' remains 1 task."""
    text = "finish my Python assignment and submit it"
    clauses = AIService._split_clauses(text)
    assert len(clauses) == 1
    assert "submit it" in clauses[0].lower()

def test_current_time_past_peak_recommends_tomorrow():
    """
    Requirement 11:
    Current time = 18:22.
    Important work, no deadline. User strongest window = 09:30-11:45.
    Recommended: Tomorrow morning in peak window (e.g. 09:30).
    Reason: past preferred productive window today, tomorrow contains strong uninterrupted block.
    """
    tz = timezone.utc
    # 2026-09-26 18:22 UTC
    now_local = datetime(2026, 9, 26, 18, 22, tzinfo=tz)

    profile = PlanningProfile(
        preferred_peak_start=9.5,   # 09:30
        preferred_peak_end=11.75,   # 11:45
        bedtime=23.0,
    )

    task = TaskCandidateResponse(
        title="Important work",
        estimated_minutes=90,
        task_type=TaskType.deep_work,
        difficulty=TaskDifficulty.high,
        priority=TaskPriority.high,
        deadline_at=None,
    )

    scheduler = SchedulingEngine()
    result = scheduler.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    assert result.slot.day_offset == 1, "Should recommend Tomorrow since user is past peak window today"
    assert result.slot.start_time.hour == 9
    assert result.slot.start_time.minute == 30
    assert "Tomorrow" in result.explanation
    assert result.primary_reason in ("peak_window", "fresh_start_tomorrow")

def test_imminent_deadline_overrides_preferred_peak_window():
    """
    Requirement 11:
    Current time = 18:22.
    Important work DUE TOMORROW AT 08:00 AM.
    Recommended: TODAY.
    Reason: Deadline urgency overrides preferred productivity window.
    """
    tz = timezone.utc
    now_local = datetime(2026, 9, 26, 18, 22, tzinfo=tz)

    # Deadline is tomorrow morning at 08:00 AM
    tomorrow_deadline = datetime(2026, 9, 27, 8, 0, tzinfo=tz)

    profile = PlanningProfile(
        preferred_peak_start=9.5,
        preferred_peak_end=11.75,
        bedtime=23.0,
    )

    task = TaskCandidateResponse(
        title="Important work",
        estimated_minutes=90,
        task_type=TaskType.deep_work,
        difficulty=TaskDifficulty.high,
        priority=TaskPriority.high,
        deadline_at=tomorrow_deadline,
    )

    scheduler = SchedulingEngine()
    result = scheduler.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    assert result.slot.day_offset == 0, "Must be scheduled TODAY to beat the 08:00 AM deadline tomorrow"
    assert result.slot.end_time <= tomorrow_deadline
    assert result.primary_reason == "deadline_imminent"

def test_hard_constraints_eliminate_busy_meeting_collision():
    """Requirement 12: Hard constraints eliminate meetings / busy intervals."""
    tz = timezone.utc
    now_local = datetime(2026, 9, 26, 9, 0, tzinfo=tz)

    # Busy meeting from 09:30 to 11:00 AM
    meeting_start = datetime(2026, 9, 26, 9, 30, tzinfo=tz)
    meeting_end = datetime(2026, 9, 26, 11, 0, tzinfo=tz)
    busy = [(meeting_start, meeting_end)]

    profile = PlanningProfile(preferred_peak_start=9.5, preferred_peak_end=11.75)

    task = TaskCandidateResponse(
        title="Deep work project",
        estimated_minutes=60,
        task_type=TaskType.deep_work,
    )

    scheduler = SchedulingEngine()
    result = scheduler.evaluate_best_slot_for_task(
        task=task,
        existing_busy=busy,
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    # Must NOT collide with 09:30 - 11:00
    assert not (result.slot.start_time < meeting_end and result.slot.end_time > meeting_start)

def test_explanation_engine_produces_deterministic_reasons():
    """Requirement 21: Explanation Engine produces structured reason codes and user explanations without LLM."""
    tz = timezone.utc
    now_local = datetime(2026, 9, 26, 9, 0, tzinfo=tz)

    profile = PlanningProfile(preferred_peak_start=9.5, preferred_peak_end=11.75)
    task = TaskCandidateResponse(
        title="Thesis analysis",
        estimated_minutes=60,
        task_type=TaskType.deep_work,
        priority=TaskPriority.high,
    )

    scheduler = SchedulingEngine()
    result = scheduler.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result.primary_reason in ("peak_window", "available_slot")
    assert isinstance(result.secondary_reasons, list)
    assert len(result.explanation) > 10
    assert "strongest focus" in result.explanation or "feasible slot" in result.explanation
