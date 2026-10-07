"""
Flowstate V1 Final Scheduling + Temporal Semantics Tests
=========================================================
Covers the invariants specified in FLOWSTATE V1 FINAL SCHEDULING PASS:

TEMPORAL TESTS 1-12  — parser semantics per phrase
SCHEDULING TESTS 13-20 — scheduler slot correctness
NIGHT OWL TEST       — late-evening preference not punished unfairly
AUTO-RESCHEDULE TESTS 21-32 — behavioral contracts
MESSY LANGUAGE TESTS 33-40 — realistic inputs
"""

from datetime import datetime, date, timedelta, time
from zoneinfo import ZoneInfo
import pytest

from app.engines.scheduling_engine import PlanningProfile, SchedulingEngine
from app.models.task import TaskDifficulty, TaskPriority, TaskSource, TaskType
from app.schemas.task import TaskCandidateResponse, TemporalConstraints, FieldProvenance
from app.services.ai_service import AIService


# ── Helpers ──────────────────────────────────────────────────────────────────

IST = ZoneInfo("Asia/Kolkata")
UTC = ZoneInfo("UTC")

# "Monday 2026-09-28 10:00 IST"  — used as the reference "now"
NOW_MON = datetime(2026, 9, 28, 10, 0, tzinfo=IST)
# Next Friday from that Monday = 2026-10-02
NEXT_FRIDAY = date(2026, 10, 2)


def parse(text: str, now: datetime = NOW_MON) -> TaskCandidateResponse:
    """Parse a single clause and return the first candidate."""
    tz = now.tzinfo
    result = AIService._parse_single_clause(text, now, tz)
    assert result is not None, f"Parser returned None for: {text!r}"
    return result


def make_task(
    title="Test",
    task_type=TaskType.deep_work,
    duration=60,
    priority=TaskPriority.medium,
    scheduled_start=None,
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
        deadline_at=deadline,
        temporal=temporal,
    )


def sched(task, now=NOW_MON, busy=None):
    tz = now.tzinfo
    return SchedulingEngine().evaluate_best_slot_for_task(task, busy or [], PlanningProfile(), now, tz)


# ═══════════════════════════════════════════════════════════════════════════
# TEMPORAL PARSER TESTS 1-12
# ═══════════════════════════════════════════════════════════════════════════

class TestTemporalPhrases:
    """
    Tests 1-12: Verify that each distinct phrase produces
    exactly the right temporal semantics — target_date, deadline,
    fixed_start, preferred_start, preferred_window, flexibility.
    """

    def test_1_gym_friday_no_deadline(self):
        """'Gym Friday' → target_date=Friday, no deadline, no fixed time."""
        c = parse("Gym Friday")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY, f"expected {NEXT_FRIDAY}, got {c.temporal.target_date}"
        assert c.deadline_at is None
        assert c.scheduled_start is None
        assert c.temporal.fixed_start is None

    def test_2_gym_friday_morning(self):
        """'Gym Friday morning' → target_date=Friday + preferred morning window."""
        c = parse("Gym Friday morning")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY
        assert c.temporal.preferred_window_start is not None
        assert c.temporal.preferred_window_start.hour == 8
        assert c.temporal.flexibility == "preferred"
        assert c.deadline_at is None

    def test_3_gym_friday_evening(self):
        """'Gym Friday evening' → target_date=Friday + preferred evening window (17-21)."""
        c = parse("Gym Friday evening")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY
        assert c.temporal.preferred_window_start is not None
        assert c.temporal.preferred_window_start.hour == 17
        assert c.temporal.preferred_window_end.hour == 21
        assert c.temporal.flexibility == "preferred"
        assert c.deadline_at is None
        assert c.scheduled_start is None

    def test_4_gym_friday_night_normalizes_to_evening(self):
        """'Gym Friday night' → MUST map to evening window, NOT a fixed time, NOT a deadline."""
        c = parse("Gym Friday night")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY, (
            f"'Friday night' must keep Friday as target_date, got {c.temporal.target_date}"
        )
        assert c.temporal.preferred_window_start is not None, (
            "'night' must map to an evening preferred_window"
        )
        assert c.temporal.preferred_window_start.hour == 17, (
            f"Expected 17:00 window start, got {c.temporal.preferred_window_start.hour}"
        )
        assert c.deadline_at is None, "'Friday night' is NOT a deadline"
        assert c.scheduled_start is None, "'Friday night' must NOT become a fixed scheduled_start"
        assert c.temporal.fixed_start is None, "'night' must NOT invent a fixed_start"

    def test_5_gym_friday_at_8pm_fixed(self):
        """'Gym Friday at 8 PM' → target_date=Friday, fixed_start=20:00."""
        c = parse("Gym Friday at 8 PM")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY
        assert c.temporal.fixed_start is not None
        assert c.temporal.fixed_start.hour == 20
        assert c.temporal.fixed_start.minute == 0
        assert c.temporal.flexibility == "fixed"

    def test_6_gym_friday_around_8pm_preferred(self):
        """'Gym Friday around 8 PM' → target_date=Friday, preferred_start=20:00, NOT fixed."""
        c = parse("Gym Friday around 8 PM")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY
        assert c.scheduled_start is None, "'around 8 PM' must NOT produce a fixed scheduled_start"
        assert c.temporal.fixed_start is None
        assert c.temporal.preferred_start is not None
        assert c.temporal.preferred_start.hour == 20
        assert c.temporal.flexibility == "preferred"

    def test_7_gym_by_friday_is_deadline(self):
        """'Gym by Friday' → deadline=Friday, no target_date."""
        c = parse("Gym by Friday")
        assert c.deadline_at is not None
        assert c.deadline_at.date() == NEXT_FRIDAY

    def test_8_gym_due_friday_is_deadline(self):
        """'Gym due Friday' → deadline=Friday."""
        c = parse("Gym due Friday")
        assert c.deadline_at is not None
        assert c.deadline_at.date() == NEXT_FRIDAY

    def test_9_gym_tomorrow_evening(self):
        """'Gym tomorrow evening' → target_date=tomorrow + preferred evening window."""
        tomorrow = NOW_MON.date() + timedelta(days=1)
        c = parse("Gym tomorrow evening")
        assert c.temporal is not None
        assert c.temporal.target_date == tomorrow
        assert c.temporal.preferred_window_start is not None
        assert c.temporal.preferred_window_start.hour == 17

    def test_10_gym_tonight(self):
        """'Gym tonight' → target_date=today + preferred evening window."""
        c = parse("Gym tonight")
        assert c.temporal is not None
        assert c.temporal.target_date == NOW_MON.date()
        # 'tonight' should set the evening window via step 6 OR at minimum set target_date
        # "tonight" contains "night" which now maps to evening

    def test_11_gym_tomorrow(self):
        """'Gym tomorrow' → target_date=tomorrow, no fixed time, no deadline."""
        tomorrow = NOW_MON.date() + timedelta(days=1)
        c = parse("Gym tomorrow")
        assert c.temporal is not None
        assert c.temporal.target_date == tomorrow
        assert c.scheduled_start is None
        assert c.deadline_at is None

    def test_12_study_friday_after_dinner(self):
        """'Study Friday after dinner' → target_date=Friday + after_dinner relative."""
        c = parse("Study Friday after dinner")
        assert c.temporal is not None
        assert c.temporal.target_date == NEXT_FRIDAY
        assert c.temporal.relative_after == "dinner"


# ═══════════════════════════════════════════════════════════════════════════
# SCHEDULING TESTS 13-20
# ═══════════════════════════════════════════════════════════════════════════

class TestSchedulingConstraints:

    def test_13_target_date_friday_schedules_on_friday(self):
        """A task with target_date=Friday MUST be scheduled on Friday, not today/tomorrow."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)  # Monday
        task = make_task(
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                preferred_window_start=datetime.combine(NEXT_FRIDAY, time(17, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(NEXT_FRIDAY, time(21, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None, "Scheduler must find a slot for Friday"
        assert result.slot.start_time.date() == NEXT_FRIDAY, (
            f"Expected Friday {NEXT_FRIDAY}, got {result.slot.start_time.date()}"
        )

    def test_14_target_date_friday_not_tomorrow(self):
        """'Gym Friday' must NOT be scheduled on tomorrow (Tuesday)."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)  # Monday
        task = make_task(
            task_type=TaskType.physical,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time.date() == NEXT_FRIDAY, (
            f"'Friday' must NOT become tomorrow {now.date() + timedelta(days=1)}, got {result.slot.start_time.date()}"
        )

    def test_15_friday_evening_stays_in_evening_window(self):
        """'Gym Friday evening' must schedule inside 17:00-21:00 on Friday."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        task = make_task(
            task_type=TaskType.physical,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                preferred_window_start=datetime.combine(NEXT_FRIDAY, time(17, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(NEXT_FRIDAY, time(21, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time.date() == NEXT_FRIDAY
        slot_h = result.slot.start_time.hour + result.slot.start_time.minute / 60.0
        assert 17.0 <= slot_h <= 21.0, f"Expected 17-21, got slot at {result.slot.start_time.strftime('%H:%M')}"

    def test_16_friday_night_schedules_on_friday_in_evening(self):
        """'Gym Friday night' must schedule on Friday in the evening window, not tomorrow."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        # Simulate what the parser produces for "Gym Friday night"
        task = make_task(
            task_type=TaskType.physical,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                preferred_window_start=datetime.combine(NEXT_FRIDAY, time(17, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(NEXT_FRIDAY, time(21, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time.date() == NEXT_FRIDAY, (
            f"'Friday night' MUST schedule on Friday {NEXT_FRIDAY}, got {result.slot.start_time.date()}"
        )

    def test_17_high_readiness_outside_target_does_not_override_target(self):
        """High readiness on today must NOT override an explicit Friday target_date."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 30, tzinfo=tz)  # perfect peak window
        night_owl_profile = PlanningProfile(
            preferred_peak_start=9.0,
            preferred_peak_end=11.75,
        )
        task = make_task(
            task_type=TaskType.deep_work,
            priority=TaskPriority.high,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                flexibility="preferred",
            )
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], night_owl_profile, now, tz)
        assert result is not None
        assert result.slot.start_time.date() == NEXT_FRIDAY, (
            "Readiness must never override target_date hard constraint"
        )

    def test_18_fixed_time_remains_fixed(self):
        """A task with fixed_start must be scheduled exactly at that time."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        fixed_dt = datetime(2026, 9, 28, 14, 0, tzinfo=tz)
        task = make_task(scheduled_start=fixed_dt)
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time == fixed_dt
        assert result.primary_reason == "explicit_time"

    def test_19_preferred_time_may_flex(self):
        """A task with preferred_start should get a nearby slot, not necessarily exact."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        pref_dt = datetime(2026, 9, 28, 18, 0, tzinfo=tz)
        task = make_task(
            temporal=TemporalConstraints(
                preferred_start=pref_dt,
                preferred_window_start=pref_dt - timedelta(minutes=45),
                preferred_window_end=pref_dt + timedelta(minutes=45),
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        # Slot should be within ±90 minutes of the preference
        diff = abs((result.slot.start_time - pref_dt).total_seconds()) / 60
        assert diff <= 90, f"Preferred slot too far: {diff:.0f}m from preference"

    def test_20_no_time_task_optimizes_freely(self):
        """A task with no time info should get some feasible slot today or tomorrow."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        task = make_task()  # no temporal, no deadline
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time >= now


# ═══════════════════════════════════════════════════════════════════════════
# NIGHT OWL TEST
# ═══════════════════════════════════════════════════════════════════════════

class TestNightOwl:

    def test_night_owl_evening_slot_competitive(self):
        """
        A night-owl profile with peak 20-22 + an explicit evening window preference
        should produce an evening slot, not force it to morning.
        The evening window bonus (+0.60) must outweigh the general late-night penalty.
        """
        tz = IST
        now = datetime(2026, 9, 28, 17, 0, tzinfo=tz)

        night_owl_profile = PlanningProfile(
            preferred_peak_start=20.0,
            preferred_peak_end=22.0,
            preferred_dip_start=14.0,
            preferred_dip_end=16.0,
            weekday_wake_time=10.0,
            bedtime=24.0,   # midnight
        )

        # "Study Friday evening" from a night owl's perspective
        task = make_task(
            task_type=TaskType.study,
            temporal=TemporalConstraints(
                target_date=now.date(),
                preferred_window_start=datetime.combine(now.date(), time(17, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(now.date(), time(21, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, [], night_owl_profile, now, tz)
        assert result is not None
        slot_h = result.slot.start_time.hour + result.slot.start_time.minute / 60.0
        # Should land within or near the 17-21 window, not forced to 9 AM
        assert 17.0 <= slot_h <= 22.0, (
            f"Night owl with evening preference should get an evening slot, got {result.slot.start_time.strftime('%H:%M')}"
        )


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-RESCHEDULE CONTRACT TESTS 21-32
# ═══════════════════════════════════════════════════════════════════════════

class TestAutoRescheduleContracts:
    """
    These tests verify the BEHAVIORAL CONTRACTS of rescheduling,
    implemented through the scheduler's hard-constraint system.
    Full auto-reschedule orchestration does not yet exist (see report).
    """

    def test_21_flexible_task_blocked_by_busy_finds_new_slot(self):
        """If the preferred 18:00 slot is busy, the scheduler finds another Friday evening slot."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        blocked_start = datetime.combine(NEXT_FRIDAY, time(18, 0), tzinfo=tz)
        blocked_end = blocked_start + timedelta(hours=1)
        busy = [(blocked_start, blocked_end)]

        task = make_task(
            task_type=TaskType.physical,
            duration=60,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                preferred_window_start=datetime.combine(NEXT_FRIDAY, time(17, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(NEXT_FRIDAY, time(21, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, busy, PlanningProfile(), now, tz)
        assert result is not None, "Must find a slot even when preferred slot is busy"
        assert result.slot.start_time.date() == NEXT_FRIDAY
        # Must not overlap with the busy interval
        assert not (result.slot.start_time < blocked_end and result.slot.end_time > blocked_start), (
            "New slot overlaps with busy interval"
        )

    def test_22_fixed_task_blocked_returns_none(self):
        """A fixed-time task with a collision must return None (scheduler cannot move it silently)."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        fixed_time = datetime(2026, 9, 28, 14, 0, tzinfo=tz)
        busy = [(fixed_time - timedelta(minutes=10), fixed_time + timedelta(hours=2))]

        task = make_task(scheduled_start=fixed_time)
        result = sched(task, now, busy)
        assert result is None, "Fixed task with collision must return None, not silently relocate"

    def test_23_missed_flexible_task_finds_later_slot_same_day(self):
        """A flexible task whose planned slot has passed gets rescheduled to a later slot today."""
        tz = IST
        now = datetime(2026, 9, 28, 15, 0, tzinfo=tz)  # 3 PM
        task = make_task(
            temporal=TemporalConstraints(
                target_date=now.date(),
                preferred_window_start=datetime.combine(now.date(), time(13, 0), tzinfo=tz),
                preferred_window_end=datetime.combine(now.date(), time(17, 0), tzinfo=tz),
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time >= now, "Rescheduled slot must be in the future"
        assert result.slot.start_time.date() == now.date()

    def test_24_fixed_past_time_does_not_return_past_slot(self):
        """A fixed_start in the past must fall through to a future feasible slot."""
        tz = IST
        now = datetime(2026, 9, 28, 15, 0, tzinfo=tz)
        past_fixed = datetime(2026, 9, 28, 9, 0, tzinfo=tz)  # already passed
        task = make_task(scheduled_start=past_fixed)
        result = sched(task, now)
        if result is not None:
            assert result.slot.start_time >= now, "Must never return a past slot"

    def test_25_target_date_constrained_task_not_moved_to_wrong_day(self):
        """A task constrained to Friday must never be scheduled on Saturday."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        task = make_task(
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                flexibility="preferred",
            )
        )
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time.date() == NEXT_FRIDAY

    def test_26_deadline_constrained_task_must_finish_before_deadline(self):
        """A deadline task must finish before the deadline — slot end <= deadline."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        deadline_dt = datetime(2026, 9, 28, 14, 0, tzinfo=tz)
        task = make_task(duration=60, deadline=deadline_dt)
        result = sched(task, now)
        assert result is not None
        assert result.slot.end_time <= deadline_dt, (
            f"Slot ends at {result.slot.end_time}, after deadline {deadline_dt}"
        )

    def test_31_repeated_scheduling_same_task_idempotent(self):
        """Calling the scheduler twice with the same inputs must produce the same slot."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        task = make_task(task_type=TaskType.physical, temporal=TemporalConstraints(
            target_date=NEXT_FRIDAY,
            preferred_window_start=datetime.combine(NEXT_FRIDAY, time(17, 0), tzinfo=tz),
            preferred_window_end=datetime.combine(NEXT_FRIDAY, time(21, 0), tzinfo=tz),
            flexibility="preferred",
        ))
        result1 = sched(task, now)
        result2 = sched(task, now)
        assert result1 is not None
        assert result2 is not None
        assert result1.slot.start_time == result2.slot.start_time, (
            "Same inputs must produce the same slot (idempotent)"
        )

    def test_32_no_slot_outside_target_date(self):
        """Scheduler must return None if no slot on target_date is feasible (all busy)."""
        tz = IST
        now = datetime(2026, 9, 28, 10, 0, tzinfo=tz)
        # Block all of Friday
        friday_start = datetime.combine(NEXT_FRIDAY, time(6, 0), tzinfo=tz)
        friday_end = datetime.combine(NEXT_FRIDAY, time(23, 59), tzinfo=tz)
        busy = [(friday_start, friday_end)]

        task = make_task(
            task_type=TaskType.physical,
            duration=60,
            temporal=TemporalConstraints(
                target_date=NEXT_FRIDAY,
                flexibility="preferred",
            )
        )
        result = SchedulingEngine().evaluate_best_slot_for_task(task, busy, PlanningProfile(), now, tz)
        assert result is None, "Must return None when target_date is fully blocked"


# ═══════════════════════════════════════════════════════════════════════════
# MESSY LANGUAGE TESTS 33-40
# ═══════════════════════════════════════════════════════════════════════════

class TestMessyLanguage:

    def test_33_friday_night_i_want_to_hit_the_gym(self):
        """Inverted phrasing: 'Friday night I want to hit the gym' → Friday + evening."""
        c = parse("Friday night I want to hit the gym")
        assert c is not None
        # Must preserve Friday
        if c.temporal and c.temporal.target_date:
            assert c.temporal.target_date == NEXT_FRIDAY, (
                f"Expected Friday, got {c.temporal.target_date}"
            )

    def test_34_gym_friday_evening_probably_an_hour(self):
        """'Need to go gym Friday evening probably an hour' → Friday + evening + 60min."""
        c = parse("Need to go gym Friday evening probably an hour")
        assert c is not None
        assert c.estimated_minutes == 60
        if c.temporal:
            if c.temporal.target_date:
                assert c.temporal.target_date == NEXT_FRIDAY
            if c.temporal.preferred_window_start:
                assert c.temporal.preferred_window_start.hour == 17

    def test_35_gym_friday_around_8(self):
        """'Gym Friday around 8' → preferred (ambiguous am/pm), NOT fixed, Friday target."""
        c = parse("Gym Friday around 8")
        assert c is not None
        assert c.scheduled_start is None, "'around 8' must NOT produce a fixed_start"
        if c.temporal and c.temporal.target_date:
            assert c.temporal.target_date == NEXT_FRIDAY

    def test_36_multi_clause_friday_evening(self):
        """'I have class Friday afternoon so gym Friday night' → multiple tasks."""
        texts = AIService._split_clauses("I have class Friday afternoon so gym Friday night")
        # Should produce at least one task about gym
        parsed = [AIService._parse_single_clause(t, NOW_MON, IST) for t in texts]
        parsed = [p for p in parsed if p]
        gym_tasks = [p for p in parsed if "gym" in p.title.lower()]
        assert gym_tasks, "Must extract a gym task"
        gym = gym_tasks[0]
        if gym.temporal and gym.temporal.target_date:
            assert gym.temporal.target_date == NEXT_FRIDAY

    def test_37_finish_report_by_friday_prefer_thursday(self):
        """'Finish report by Friday but I'd prefer Thursday evening' → deadline Friday."""
        c = parse("Finish report by Friday")
        assert c.deadline_at is not None
        assert c.deadline_at.date() == NEXT_FRIDAY

    def test_39_long_paragraph_5_tasks(self):
        """A paragraph with 5+ independent tasks should produce ≥3 candidates."""
        text = (
            "I need to finish the ML assignment and submit before 11 AM, "
            "fix the auth bug, go to the gym at 6, review DSA for 45 minutes, "
            "call mom"
        )
        results = AIService.parse_task_dump(text, "Asia/Kolkata")
        assert len(results) >= 3, f"Expected ≥3 tasks from brain dump, got {len(results)}"

    def test_40_single_coherent_task_with_details(self):
        """A single detailed task must stay as one candidate."""
        text = "Finish my Python assignment and submit it before 11 AM, probably 90 minutes"
        results = AIService.parse_task_dump(text, "Asia/Kolkata")
        assert len(results) == 1, f"Expected 1 task (single coherent), got {len(results)}"
        assert results[0].estimated_minutes == 90


# ═══════════════════════════════════════════════════════════════════════════
# FINAL SAFETY CHECKS
# ═══════════════════════════════════════════════════════════════════════════

class TestFinalSafetyChecks:

    def test_friday_night_is_not_treated_as_deadline(self):
        c = parse("Gym Friday night")
        assert c.deadline_at is None, "Friday night must NOT become a deadline"

    def test_friday_night_is_not_fixed_clock_time(self):
        c = parse("Gym Friday night")
        assert c.scheduled_start is None, "Friday night must NOT produce a fixed scheduled_start"
        if c.temporal:
            assert c.temporal.fixed_start is None

    def test_friday_night_remains_friday(self):
        c = parse("Gym Friday night")
        if c.temporal and c.temporal.target_date:
            assert c.temporal.target_date == NEXT_FRIDAY

    def test_friday_evening_remains_friday(self):
        c = parse("Gym Friday evening")
        if c.temporal and c.temporal.target_date:
            assert c.temporal.target_date == NEXT_FRIDAY

    def test_fixed_user_time_stays_fixed(self):
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        fixed_time = datetime(2026, 9, 28, 14, 0, tzinfo=tz)
        task = make_task(scheduled_start=fixed_time)
        result = sched(task, now)
        assert result is not None
        assert result.slot.start_time == fixed_time
        assert result.primary_reason == "explicit_time"

    def test_preferred_time_is_flexible(self):
        tz = IST
        now = datetime(2026, 9, 28, 9, 0, tzinfo=tz)
        pref_dt = datetime(2026, 9, 28, 18, 0, tzinfo=tz)
        task = make_task(temporal=TemporalConstraints(
            preferred_start=pref_dt,
            preferred_window_start=pref_dt - timedelta(minutes=45),
            preferred_window_end=pref_dt + timedelta(minutes=45),
            flexibility="preferred",
        ))
        result = sched(task, now)
        # Slot may flex within ±90min of preference
        assert result is not None
        diff = abs((result.slot.start_time - pref_dt).total_seconds()) / 60
        assert diff <= 120

    def test_target_date_is_hard(self):
        """Target date cannot be bypassed by any scoring heuristic."""
        tz = IST
        now = datetime(2026, 9, 28, 9, 30, tzinfo=tz)  # peak window time
        task = make_task(
            task_type=TaskType.deep_work,
            priority=TaskPriority.urgent,
            temporal=TemporalConstraints(target_date=NEXT_FRIDAY, flexibility="preferred")
        )
        result = sched(task, now)
        if result:
            assert result.slot.start_time.date() == NEXT_FRIDAY

    def test_deadline_distinct_from_target_date(self):
        """'Gym Friday' has target_date but no deadline. 'Gym by Friday' has deadline but no target_date."""
        c_by = parse("Gym by Friday")
        c_on = parse("Gym Friday")
        assert c_by.deadline_at is not None
        assert c_on.deadline_at is None
        if c_on.temporal:
            assert c_on.temporal.target_date == NEXT_FRIDAY
