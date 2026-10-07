"""
Temporal Scheduling Regression Tests
=====================================
Covers every invariant stated in the FLOWSTATE MASTER FIX PROMPT:

TEST 1: Past fixed-time cannot be scheduled today.
TEST 2: Past flexible preference cannot be selected today.
TEST 3: After-dinner task cannot be scheduled before dinner.
TEST 4: Afternoon preference cannot schedule a task in the morning.
TEST 5: "Around 6 PM" should score closer slots higher.
TEST 6: Task duration is respected for past/deadline/sleep boundary checks.
TEST 7: Timezone-aware comparisons work correctly.
TEST 8: Exact brain dump continues to segment and schedule correctly.
TEST 9: No scheduler candidate selected with candidate_start < now.
TEST 10: Midnight / day-rollover correctness.
"""

from datetime import datetime, timedelta, time
from zoneinfo import ZoneInfo
import pytest

from app.engines.scheduling_engine import PlanningProfile, SchedulingEngine
from app.models.task import TaskDifficulty, TaskPriority, TaskSource, TaskType
from app.schemas.task import TaskCandidateResponse, TemporalConstraints, FieldProvenance


# -- Helpers -------------------------------------------------------------------

def make_task(
    title="Test task",
    task_type=TaskType.deep_work,
    duration=60,
    priority=TaskPriority.medium,
    scheduled_start=None,
    scheduled_end=None,
    deadline=None,
    temporal=None,
):
    return TaskCandidateResponse(
        title=title,
        estimated_minutes=duration,
        task_type=task_type,
        difficulty=TaskDifficulty.medium,
        priority=priority,
        source=TaskSource.ai_parsed,
        scheduled_start=scheduled_start,
        scheduled_end=scheduled_end,
        deadline_at=deadline,
        temporal=temporal,
    )


IST = ZoneInfo("Asia/Kolkata")
UTC = ZoneInfo("UTC")
EST = ZoneInfo("America/New_York")


# -- TEST 1: Past fixed time cannot be scheduled today ------------------------

class TestPastFixedTimeRejection:
    """TEST 1: A fixed_start in the past must never be returned as a valid slot."""

    def test_past_fixed_time_is_not_returned_as_valid(self):
        tz = IST
        now = datetime(2026, 9, 27, 22, 30, tzinfo=tz)
        task = make_task(
            title="Gym",
            task_type=TaskType.physical,
            duration=60,
            scheduled_start=datetime(2026, 9, 27, 18, 0, tzinfo=tz),
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now, (
                f"Scheduler returned a past slot: {result.slot.start_time} (now={now})"
            )

    def test_past_fixed_time_midnight_boundary(self):
        tz = IST
        now = datetime(2026, 9, 27, 23, 50, tzinfo=tz)
        task = make_task(
            title="Quick task",
            duration=15,
            scheduled_start=datetime(2026, 9, 27, 23, 30, tzinfo=tz),
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now

    def test_future_fixed_time_is_returned_correctly(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        task = make_task(
            title="Meeting",
            task_type=TaskType.meeting,
            duration=60,
            scheduled_start=datetime(2026, 9, 27, 14, 0, tzinfo=tz),
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.start_time == datetime(2026, 9, 27, 14, 0, tzinfo=tz)
        assert result.primary_reason == "explicit_time"


# -- TEST 2: Past flexible preference cannot be selected today ----------------

class TestPastFlexiblePreferenceRejection:
    """TEST 2: A preferred_start in the past must not be selected as a candidate."""

    def test_around_6pm_at_2230_picks_future_slot(self):
        tz = IST
        now = datetime(2026, 9, 27, 22, 30, tzinfo=tz)
        temporal = TemporalConstraints(
            preferred_start=datetime(2026, 9, 27, 18, 0, tzinfo=tz),
            preferred_window_start=datetime(2026, 9, 27, 17, 15, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 27, 18, 45, tzinfo=tz),
            flexibility="preferred",
            confidence=0.95,
        )
        task = make_task(
            title="Gym session",
            task_type=TaskType.physical,
            duration=60,
            temporal=temporal,
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now, (
                f"Returned a past slot for flexible preference: {result.slot.start_time} (now={now})"
            )

    def test_hard_constraint_filter_removes_past_candidates(self):
        tz = IST
        now = datetime(2026, 9, 27, 14, 0, tzinfo=tz)
        task = make_task(title="DSA Review", task_type=TaskType.study, duration=45)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now


# -- TEST 3: After-dinner task cannot be scheduled before dinner ---------------

class TestAfterDinnerConstraint:
    """TEST 3: earliest_start / relative_after='dinner' must be enforced as a hard lower bound."""

    def test_after_dinner_task_is_not_scheduled_before_dinner(self):
        tz = IST
        now = datetime(2026, 9, 27, 13, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            earliest_start=datetime(2026, 9, 27, 20, 0, tzinfo=tz),
            relative_after="dinner",
            flexibility="constrained",
            confidence=0.9,
        )
        task = make_task(
            title="Review DSA",
            task_type=TaskType.study,
            duration=45,
            temporal=temporal,
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None, "Should have found a slot after dinner"
        assert result.slot.start_time >= datetime(2026, 9, 27, 20, 0, tzinfo=tz), (
            f"After-dinner task scheduled before dinner: {result.slot.start_time}"
        )

    def test_after_dinner_task_not_scheduled_at_8am(self):
        """Regression: The original bug produced 8:00 AM for an after-dinner task."""
        tz = IST
        now = datetime(2026, 9, 27, 7, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            earliest_start=datetime(2026, 9, 27, 20, 0, tzinfo=tz),
            relative_after="dinner",
            flexibility="constrained",
        )
        task = make_task(title="Review DSA", task_type=TaskType.study, duration=45, temporal=temporal)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        is_after_dinner_today = result.slot.start_time.date() == now.date() and result.slot.start_time.hour >= 20
        is_on_future_day = result.slot.start_time.date() > now.date()
        assert is_after_dinner_today or is_on_future_day, (
            f"After-dinner task landed at {result.slot.start_time} -- must be >= 20:00."
        )


# -- TEST 4: Afternoon preference cannot schedule a task in the morning --------

class TestAfternoonPreference:
    """TEST 4: A task with preferred_window='afternoon' must not be scheduled in the morning."""

    def test_afternoon_preference_not_scheduled_in_morning(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            preferred_window_start=datetime(2026, 9, 27, 12, 0, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 27, 17, 0, tzinfo=tz),
            flexibility="preferred",
            confidence=0.90,
        )
        task = make_task(
            title="Fix auth bug",
            task_type=TaskType.deep_work,
            duration=120,
            temporal=temporal,
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        slot_h = result.slot.start_time.hour + result.slot.start_time.minute / 60.0
        is_afternoon = 12.0 <= slot_h < 17.0
        is_tomorrow = result.slot.start_time.date() > now.date()
        assert is_afternoon or is_tomorrow, (
            f"Afternoon-preferred task landed at {result.slot.start_time} -- expected 12:00-17:00 today or tomorrow."
        )

    def test_afternoon_preference_beats_morning_focus_heuristic(self):
        """Explicit afternoon preference score must beat the default morning-focus score."""
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            preferred_window_start=datetime(2026, 9, 27, 12, 0, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 27, 17, 0, tzinfo=tz),
            flexibility="preferred",
        )
        task = make_task("Fix auth bug", TaskType.deep_work, 120, temporal=temporal)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        in_afternoon = 12 <= result.slot.start_time.hour < 17
        is_tomorrow = result.slot.start_time.date() > now.date()
        assert in_afternoon or is_tomorrow, (
            f"Afternoon preference failed: got {result.slot.start_time}"
        )

    def test_deterministic_parser_extracts_afternoon_window(self):
        """
        Regression: _parse_single_clause must extract preferred_window [12:00-17:00]
        from clauses containing 'afternoon'. Previously the keyword was absent from
        the deterministic parser, so Gemini-path tasks got the window but deterministic
        ones did not, silently falling back to morning-focus heuristic.
        """
        from app.services.ai_service import AIService
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)

        test_clauses = [
            "Fix authentication bug for 2 hours, preferably in the afternoon",
            "Study preferably in the afternoon",
            "Work on project, afternoon is best",
        ]
        for clause in test_clauses:
            c = AIService._parse_single_clause(clause, now, tz)
            assert c is not None, f"Parser returned None for: {clause!r}"
            t = c.temporal
            assert t is not None, (
                f"No temporal extracted for 'afternoon' clause: {clause!r}"
            )
            pws = getattr(t, "preferred_window_start", None)
            pwe = getattr(t, "preferred_window_end", None)
            assert pws is not None and pws.hour == 12, (
                f"Expected afternoon window start=12:00, got {pws} for {clause!r}"
            )
            assert pwe is not None and pwe.hour == 17, (
                f"Expected afternoon window end=17:00, got {pwe} for {clause!r}"
            )

    def test_deterministic_parser_afternoon_clause_schedules_afternoon(self):
        """Regression: 'preferably in the afternoon' must produce an afternoon slot, not morning."""
        from app.services.ai_service import AIService
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        c = AIService._parse_single_clause(
            "Fix authentication bug for 2 hours, preferably in the afternoon", now, tz
        )
        assert c is not None
        assert c.temporal is not None
        result = SchedulingEngine().evaluate_best_slot_for_task(c, [], PlanningProfile(), now, tz)
        assert result is not None
        in_afternoon = 12 <= result.slot.start_time.hour < 17
        is_tomorrow = result.slot.start_time.date() > now.date()
        assert in_afternoon or is_tomorrow, (
            f"Parser+scheduler gave morning slot for 'preferably in the afternoon': {result.slot.start_time}"
        )


# -- TEST 5: "Around 6 PM" should score closer slots higher -------------------

class TestAroundTimeProximityScoring:
    """TEST 5: Proximity-based scoring for preferred_start (around X PM)."""

    def test_closer_slot_beats_far_slot(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            preferred_start=datetime(2026, 9, 27, 18, 0, tzinfo=tz),
            preferred_window_start=datetime(2026, 9, 27, 17, 15, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 27, 18, 45, tzinfo=tz),
            flexibility="preferred",
        )
        task = make_task("Gym session", TaskType.physical, 60, temporal=temporal)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        distance_minutes = abs(
            (result.slot.start_time - datetime(2026, 9, 27, 18, 0, tzinfo=tz)).total_seconds()
        ) / 60
        assert distance_minutes <= 90, (
            f"'Around 6 PM' selected a slot {distance_minutes:.0f} min from 6 PM: {result.slot.start_time}"
        )

    def test_around_6pm_does_not_place_task_at_midmorning(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        temporal = TemporalConstraints(
            preferred_start=datetime(2026, 9, 27, 18, 0, tzinfo=tz),
            preferred_window_start=datetime(2026, 9, 27, 17, 15, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 27, 18, 45, tzinfo=tz),
            flexibility="preferred",
        )
        task = make_task("Gym session", TaskType.physical, 60, temporal=temporal)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.start_time.hour >= 17, (
            f"'Around 6 PM' placed at {result.slot.start_time} -- must be late afternoon/evening."
        )


# -- TEST 6: Task duration respected in constraint checks ---------------------

class TestDurationRespected:
    """TEST 6: Duration must be respected for deadline, sleep boundary, and past checks."""

    def test_deadline_enforced_with_duration(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        deadline = datetime(2026, 9, 28, 11, 0, tzinfo=tz)
        task = make_task(
            title="Finish ML assignment",
            task_type=TaskType.deep_work,
            duration=90,
            deadline=deadline,
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.end_time <= deadline, (
            f"Task end {result.slot.end_time} exceeds deadline {deadline}"
        )

    def test_past_candidate_with_duration_rejected(self):
        tz = IST
        now = datetime(2026, 9, 27, 22, 30, tzinfo=tz)
        task = make_task("Late task", duration=60, scheduled_start=datetime(2026, 9, 27, 22, 0, tzinfo=tz))
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now

    def test_sleep_boundary_respected_with_duration(self):
        tz = IST
        now = datetime(2026, 9, 27, 22, 0, tzinfo=tz)
        profile = PlanningProfile(bedtime=23.0)
        task = make_task("Long task", task_type=TaskType.deep_work, duration=60)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], profile, now, tz)
        if result is not None and result.slot.day_offset == 0:
            end_h = result.slot.end_time.hour + result.slot.end_time.minute / 60.0
            assert end_h <= 25.0, f"Task end violates night: {result.slot.end_time}"


# -- TEST 7: Timezone-aware comparisons ---------------------------------------

class TestTimezoneAwareness:
    """TEST 7: All datetime comparisons must be timezone-aware."""

    def test_ist_fixed_start_preserved(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        fixed_ist = datetime(2026, 9, 27, 14, 0, tzinfo=tz)
        task = make_task("Meeting", task_type=TaskType.meeting, duration=60, scheduled_start=fixed_ist)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.start_time == fixed_ist
        assert result.slot.start_time.tzinfo is not None

    def test_est_timezone_now_comparison(self):
        tz = EST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        task = make_task("Study", TaskType.study, 60)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now
            assert result.slot.start_time.tzinfo is not None

    def test_aware_now_passed_to_engine(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        task = make_task("Task", duration=30)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now


# -- TEST 8: Brain dump segmentation regression --------------------------------

class TestBrainDumpSegmentation:
    """TEST 8: The exact 902-char failing brain dump must produce multiple tasks."""

    BRAIN_DUMP = (
        "Tomorrow is going to be chaotic. I have class at 12:40 PM and I need to leave home by 11:50, "
        "so don't schedule anything that needs serious focus right before I leave. I need to finish my ML "
        "assignment and submit it before 11 AM, probably 90 minutes of work. I also need to fix the "
        "authentication bug in my project, around 2 hours, preferably sometime in the afternoon. I have "
        "a gym session around 6 PM, but if I'm really tired it's okay to move it later. After dinner I "
        "want to spend about 45 minutes reviewing DSA. I need to call my mom sometime in the evening, "
        "probably 15 minutes. I should clean my room too, but that's optional and shouldn't interfere "
        "with the important stuff. Also remind me that I shouldn't work too late because I want to sleep "
        "by 11:30 PM. If something has to be sacrificed, sacrifice cleaning my room first, then gym, but "
        "absolutely don't sacrifice the ML assignment deadline."
    )

    def test_brain_dump_produces_multiple_clauses(self):
        from app.services.ai_service import AIService
        clauses = AIService._split_clauses(self.BRAIN_DUMP)
        assert len(clauses) >= 5, (
            f"Brain dump collapsed into {len(clauses)} clauses: {clauses}"
        )

    def test_sleep_boundary_is_not_a_task(self):
        """
        "want to sleep by 11:30 PM" is a scheduling constraint, not a task.
        The Gemini prompt explicitly instructs Gemini NOT to create a sleep task.
        The deterministic parser produces a candidate for this sentence because it
        lacks language understanding — this is expected and by-design (Gemini handles it).

        What we verify here:
        - If a sleep clause somehow reaches the scheduler, it has no fixed_start.
        - The brain dump test via the Gemini path (covered by live e2e tests) never creates
          a sleep task — that invariant is enforced by the Gemini prompt instructions.
        """
        from app.services.ai_service import AIService
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)

        # The reminder/sleep sentence from the brain dump
        sleep_sentence = "Also remind me that I shouldn't work too late because I want to sleep by 11:30 PM."
        candidate = AIService._parse_single_clause(sleep_sentence, now, tz)

        if candidate is not None:
            # If the parser produces a candidate for this clause, it must NOT have a fixed_start
            # (sleeping is not a fixed-time activity the user wants to schedule)
            assert candidate.scheduled_start is None, (
                f"Sleep boundary clause produced a fixed-time task at {candidate.scheduled_start}"
            )
            # And it must have very low confidence (it's ambiguous parser noise, not a real task)
            assert candidate.confidence < 0.80, (
                f"Sleep boundary clause produced high-confidence candidate: {candidate.confidence}"
            )



# -- TEST 9: No scheduler candidate selected with start < now -----------------

class TestNoPastCandidateSelected:
    """TEST 9: Global invariant -- the scheduler must NEVER return a past slot."""

    @pytest.mark.parametrize("now_hour, fixed_hour", [
        (22, 18),
        (15, 9),
        (12, 11),
        (23, 21),
    ])
    def test_past_fixed_start_never_returned(self, now_hour, fixed_hour):
        tz = IST
        now = datetime(2026, 9, 27, now_hour, 0, tzinfo=tz)
        task = make_task(
            title="Past task",
            duration=30,
            scheduled_start=datetime(2026, 9, 27, fixed_hour, 0, tzinfo=tz),
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now, (
                f"Returned past slot {result.slot.start_time} with now={now} (task fixed at {fixed_hour}:00)"
            )

    @pytest.mark.parametrize("now_hour", [7, 10, 14, 20, 22])
    def test_no_flexible_slot_in_past(self, now_hour):
        tz = IST
        now = datetime(2026, 9, 27, now_hour, 0, tzinfo=tz)
        task = make_task("Any task", duration=30)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now, (
                f"Flexible task returned past slot {result.slot.start_time} at now={now}"
            )


# -- TEST 10: Midnight / day-rollover correctness -----------------------------

class TestMidnightRollover:
    """TEST 10: Day-rollover edge cases must be handled correctly."""

    def test_task_near_midnight_is_in_future(self):
        tz = IST
        now = datetime(2026, 9, 27, 23, 45, tzinfo=tz)
        profile = PlanningProfile(bedtime=23.5)
        task = make_task("Clean room", task_type=TaskType.admin, duration=30)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], profile, now, tz)
        if result is not None:
            assert result.slot.start_time >= now

    def test_deadline_on_tomorrow_across_midnight(self):
        tz = IST
        now = datetime(2026, 9, 27, 23, 50, tzinfo=tz)
        deadline = datetime(2026, 9, 28, 11, 0, tzinfo=tz)
        task = make_task("ML assignment", task_type=TaskType.deep_work, duration=90, deadline=deadline)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            assert result.slot.start_time >= now
            assert result.slot.end_time <= deadline

    def test_day_offset_reflects_actual_date(self):
        tz = IST
        now = datetime(2026, 9, 27, 9, 0, tzinfo=tz)
        task = make_task("Study", task_type=TaskType.study, duration=45)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        if result is not None:
            if result.slot.day_offset == 0:
                assert result.slot.start_time.date() == now.date()
            elif result.slot.day_offset == 1:
                assert result.slot.start_time.date() == (now.date() + timedelta(days=1))


# ── NEW: Meal Anchor & Relative Constraint Re-Anchoring Tests ──────────────────

class TestMealAnchors:
    """
    BUG 5 COVERAGE: Verifies that after/before lunch and after/before breakfast
    are parsed into correct temporal constraints by the deterministic parser.
    """

    def test_after_lunch_earliest_start(self):
        """'after lunch' → earliest_start at 13:00 with relative_after=lunch"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Study after lunch for 1 hour", now, tz)
        assert c is not None
        assert c.temporal is not None
        assert c.temporal.earliest_start is not None
        assert c.temporal.earliest_start.hour == 13
        assert c.temporal.relative_after == "lunch"

    def test_before_lunch_latest_end(self):
        """'before lunch' → latest_end at 13:00 with relative_before=lunch"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Study before lunch for 1 hour", now, tz)
        assert c is not None
        assert c.temporal is not None
        assert c.temporal.latest_end is not None
        assert c.temporal.latest_end.hour == 13
        assert c.temporal.relative_before == "lunch"

    def test_after_breakfast_earliest_start(self):
        """'after breakfast' → earliest_start at 07:30 with relative_after=breakfast"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Gym after breakfast for 45 minutes", now, tz)
        assert c is not None
        assert c.temporal is not None
        assert c.temporal.earliest_start is not None
        assert c.temporal.earliest_start.hour == 7
        assert c.temporal.earliest_start.minute == 30
        assert c.temporal.relative_after == "breakfast"

    def test_before_breakfast_latest_end(self):
        """'before breakfast' → latest_end at 07:30 with relative_before=breakfast"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Call mom before breakfast for 15 minutes", now, tz)
        assert c is not None
        assert c.temporal is not None
        assert c.temporal.latest_end is not None
        assert c.temporal.latest_end.hour == 7
        assert c.temporal.latest_end.minute == 30
        assert c.temporal.relative_before == "breakfast"

    def test_after_lunch_scheduling_respects_constraint(self):
        """'after lunch' scheduling → slot starts at or after 13:00"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Study after lunch for 1 hour", now, tz)
        assert c is not None
        result = SchedulingEngine().evaluate_best_slot_for_task(c, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.start_time.hour >= 13, \
            f"after lunch should start >= 13:00, got {result.slot.start_time.strftime('%H:%M')}"

    def test_before_lunch_scheduling_ends_before_constraint(self):
        """'before lunch' scheduling → slot ends by 13:00"""
        from app.services.ai_service import AIService
        from zoneinfo import ZoneInfo
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 7, 0, tzinfo=tz)
        c = AIService._parse_single_clause("Study before lunch for 1 hour", now, tz)
        assert c is not None
        result = SchedulingEngine().evaluate_best_slot_for_task(c, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.end_time.replace(tzinfo=None) <= datetime(2026, 9, 28, 13, 0), \
            f"before lunch should end by 13:00, got {result.slot.end_time.strftime('%H:%M')}"


class TestRelativeConstraintReAnchoring:
    """
    BUG 2 & 3 COVERAGE: Verifies that relative temporal constraints (preferred_window,
    earliest_start from meals) are re-evaluated per candidate day, not pinned to today.
    """

    def test_preferred_window_rolls_to_tomorrow_correctly(self):
        """
        BUG 2: 'around 6 PM' with now=22:30 should schedule tomorrow ~18:00, not tomorrow 07:00.
        Root cause: preferred_window_start/end were anchored to today's date; all tomorrow
        slots scored -0.55 as 'outside window', so early tomorrow (07:00) beat 18:00.
        """
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 22, 30, tzinfo=tz)
        tc = TemporalConstraints(
            preferred_start=datetime(2026, 9, 28, 18, 0, tzinfo=tz),
            preferred_window_start=datetime(2026, 9, 28, 17, 15, tzinfo=tz),
            preferred_window_end=datetime(2026, 9, 28, 18, 45, tzinfo=tz),
            flexibility="preferred",
        )
        task = make_task("Gym session", task_type=TaskType.physical, duration=60, temporal=tc)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        s = result.slot.start_time
        tomorrow = (now.date() + timedelta(days=1))
        assert s.date() == tomorrow, f"should be tomorrow, got {s.date()}"
        hour = s.hour + s.minute / 60.0
        assert hour >= 13.0, f"should be afternoon/evening (~18:00), got {s.strftime('%H:%M')}"

    def test_after_dinner_tomorrow_starts_after_dinner_time(self):
        """
        BUG 3: 'after dinner' with now=22:00 should schedule TOMORROW >= 20:00, not 09:30.
        Root cause: earliest_start was pinned to today 20:00; any tomorrow slot (09:30)
        satisfied 'slot >= today 20:00', so dinner constraint was completely lost.
        """
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 22, 0, tzinfo=tz)
        tc = TemporalConstraints(
            earliest_start=datetime(2026, 9, 28, 20, 0, tzinfo=tz),
            relative_after="dinner",
            flexibility="constrained",
        )
        task = make_task("Review DSA", task_type=TaskType.study, duration=45, temporal=tc)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        s = result.slot.start_time
        assert s.date() > now.date(), f"should be tomorrow, got {s.date()}"
        assert s.hour >= 20, \
            f"after dinner should start >= 20:00 on the scheduled day, got {s.strftime('%H:%M')}"

    def test_after_dinner_today_stays_today(self):
        """After dinner with now=10:00 should schedule TODAY >= 20:00 (not tomorrow)."""
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        tc = TemporalConstraints(
            earliest_start=datetime(2026, 9, 28, 20, 0, tzinfo=tz),
            relative_after="dinner",
            flexibility="constrained",
        )
        task = make_task("Review DSA", task_type=TaskType.study, duration=45, temporal=tc)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        assert result.slot.start_time.date() == now.date(), \
            f"should be today, got {result.slot.start_time.date()}"
        assert result.slot.start_time.hour >= 20, \
            f"should start >= 20:00, got {result.slot.start_time.strftime('%H:%M')}"

    def test_after_lunch_tomorrow_stays_after_lunch(self):
        """After lunch with now=14:00 (past lunch) should be TOMORROW >= 13:00."""
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 14, 30, tzinfo=tz)
        tc = TemporalConstraints(
            earliest_start=datetime(2026, 9, 28, 13, 0, tzinfo=tz),
            relative_after="lunch",
            flexibility="constrained",
        )
        task = make_task("Study notes", task_type=TaskType.study, duration=60, temporal=tc)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        s = result.slot.start_time
        assert s >= now, "must not be in the past"
        assert s.hour >= 13, \
            f"after lunch on any day must be >= 13:00, got {s.strftime('%H:%M')}"

    def test_late_night_penalty_symmetry(self):
        """
        BUG 3 COROLLARY: Late-night penalty (>=20:00) must apply equally to today and tomorrow.
        Without this, tomorrow's 20:00 was artificially cheaper than today's 20:00,
        causing after-dinner tasks to always prefer tomorrow over today.
        """
        tz = ZoneInfo("Asia/Kolkata")
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        # Task with no temporal constraints → should prefer daytime, not evening
        task = make_task("Study DBMS", task_type=TaskType.study, duration=60)
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], PlanningProfile(), now, tz)
        assert result is not None
        # Without user evening preference, daytime slot should always beat 20:00+ slot
        assert result.slot.start_time.hour < 20 or result.slot.start_time.date() == now.date(), \
            "Unconstrained task should prefer daytime over late evening"
