import pytest
from datetime import datetime, date, time, timedelta, timezone
from zoneinfo import ZoneInfo
from app.engines.scheduling_engine import SchedulingEngine, PlanningProfile
from app.services.ai_service import AIService
from app.schemas.readiness import ReadinessOnboardingRequest
from app.services.readiness_service import ReadinessService
from app.db.session import SessionLocal, Base, engine as db_engine
import app.models
from app.models.user import User

class MockTask:
    def __init__(self, title, task_type="deep_work", priority="medium", estimated_minutes=45, deadline_at=None, scheduled_start=None, scheduled_end=None):
        self.id = "mock-" + title.lower().replace(" ", "-")
        self.title = title
        self.task_type = task_type
        self.type = task_type
        self.priority = priority
        self.estimated_minutes = estimated_minutes
        self.deadline_at = deadline_at
        self.scheduled_start = scheduled_start
        self.scheduled_end = scheduled_end
        self.status = "todo"

def test_planning_profile_fields_and_aliases():
    """Verify PlanningProfile exposes all required attributes and property aliases."""
    profile = PlanningProfile(
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        preferred_dip_start=14.0,
        preferred_dip_end=15.5,
        weekday_wake_time=7.0,
        weekend_wake_time=8.5,
        bedtime=23.0,
        warmup_minutes=60,
        high_energy_task_types=["coding", "problem_solving", "deep_work"],
        tired_behavior="distracted",
        routine_shift_preference="slower_tempo",
    )

    # Required attributes and aliases
    assert profile.wake_time == 7.0
    assert profile.weekend_wake_time == 8.5
    assert profile.bedtime == 23.0
    assert profile.peak_window_start == 8.5
    assert profile.peak_window_end == 12.0
    assert profile.warmup_minutes == 60
    assert "coding" in profile.high_energy_task_types
    assert profile.tired_behavior == "distracted"
    assert profile.routine_shift_preference == "slower_tempo"

def test_case_1_sleep_protection_low_priority_cleaning():
    """
    CASE 1
    Profile: Wake 7 AM, Peak 8:30 AM–12 PM, Bed 11 PM
    Current: 10:15 PM
    Task: Low priority cleaning, No deadline
    Expected: Do not schedule tonight.
    """
    profile = PlanningProfile(
        weekday_wake_time=7.0,
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        bedtime=23.0,
        warmup_minutes=30,
    )
    tz = timezone.utc
    # Set current time to today at 10:15 PM (22:15)
    base_date = date(2026, 10, 5) # Monday
    now_local = datetime.combine(base_date, time(22, 15), tzinfo=tz)

    task = MockTask(
        title="clean desk",
        task_type="admin",
        priority="low",
        estimated_minutes=20,
        deadline_at=None,
    )

    engine = SchedulingEngine()
    result = engine.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    # Must NOT be scheduled tonight (day_offset == 0)
    assert result.slot.day_offset == 1, f"Expected tomorrow, got day_offset={result.slot.day_offset} at {result.slot.start_time}"
    assert result.slot.start_time.date() > base_date

def test_case_2_important_coding_future_peak_window():
    """
    CASE 2
    Profile: Wake 7 AM, Peak 8:30 AM–12 PM, Bed 11 PM
    Current: 10:15 PM
    Task: Important coding work, No deadline
    Expected: Prefer an appropriate future strong work window (tomorrow during peak 8:30 AM - 12 PM).
    """
    profile = PlanningProfile(
        weekday_wake_time=7.0,
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        bedtime=23.0,
        warmup_minutes=30,
    )
    tz = timezone.utc
    base_date = date(2026, 10, 5) # Monday
    now_local = datetime.combine(base_date, time(22, 15), tzinfo=tz)

    task = MockTask(
        title="Important coding work",
        task_type="deep_work",
        priority="high",
        estimated_minutes=60,
        deadline_at=None,
    )

    engine = SchedulingEngine()
    result = engine.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    assert result.slot.day_offset == 1, "Expected scheduled tomorrow in peak window"
    # Expected start inside tomorrow's peak window (8:30 AM - 12:00 PM)
    slot_h = result.slot.start_time.hour + result.slot.start_time.minute / 60.0
    assert 8.5 <= slot_h <= 12.0, f"Expected in peak window 8:30-12:00, got {result.slot.start_time}"
    assert result.primary_reason == "peak_window"

def test_case_3_deadline_safety_overrides_sleep_protection():
    """
    CASE 3
    Profile: Wake 7 AM, Peak 8:30 AM–12 PM, Bed 11 PM
    Current: 10:15 PM
    Task: Important assignment, Deadline tomorrow 8 AM
    Expected: Deadline safety overrides normal preference when necessary (scheduled tonight before bedtime).
    """
    profile = PlanningProfile(
        weekday_wake_time=7.0,
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        bedtime=23.0,
        warmup_minutes=30,
    )
    tz = timezone.utc
    base_date = date(2026, 10, 5)
    now_local = datetime.combine(base_date, time(22, 15), tzinfo=tz)
    tomorrow_deadline = datetime.combine(base_date + timedelta(days=1), time(8, 0), tzinfo=tz)

    task = MockTask(
        title="Important assignment",
        task_type="deep_work",
        priority="high",
        estimated_minutes=30,
        deadline_at=tomorrow_deadline,
    )

    engine = SchedulingEngine()
    result = engine.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    # Must be scheduled TONIGHT (day_offset == 0) before 11:00 PM bedtime
    assert result.slot.day_offset == 0, f"Expected tonight to protect deadline, got day_offset={result.slot.day_offset}"
    assert result.slot.start_time.date() == base_date
    assert result.slot.end_time <= datetime.combine(base_date, time(23, 0), tzinfo=tz)
    assert result.primary_reason == "deadline_imminent"
    assert "deadline_safety_overrides_sleep" in result.secondary_reasons

def test_case_4_cognitive_warmup_protection():
    """
    CASE 4
    Profile: Wake 7 AM, Warmup 60 min, Peak 8:30 AM–12 PM
    Task: Coding
    Expected: Do not schedule at 7 AM. Prefer a strong post-warmup window (e.g. 8:30 AM).
    """
    profile = PlanningProfile(
        weekday_wake_time=7.0,
        warmup_minutes=60, # 7 AM to 8 AM is cognitive warmup
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        bedtime=23.0,
    )
    tz = timezone.utc
    base_date = date(2026, 10, 5)
    now_local = datetime.combine(base_date, time(6, 45), tzinfo=tz) # Early morning before wake

    task = MockTask(
        title="Coding",
        task_type="deep_work",
        priority="medium",
        estimated_minutes=45,
        deadline_at=None,
    )

    engine = SchedulingEngine()
    result = engine.evaluate_best_slot_for_task(
        task=task,
        existing_busy=[],
        profile=profile,
        now_local=now_local,
        tz=tz,
    )

    assert result is not None
    start_h = result.slot.start_time.hour + result.slot.start_time.minute / 60.0
    # Must NOT be 7:00 AM (warmup is 7:00-8:00 AM)
    assert start_h >= 8.0, f"Expected post-warmup slot (>= 8.0), got {result.slot.start_time}"
    assert start_h == 8.5, f"Expected peak window start (8:30 AM), got {result.slot.start_time}"
    assert result.primary_reason == "peak_window"

def test_case_5_independent_tasks_fit_around_meetings():
    """
    CASE 5
    Tasks: Gym, Important coding work, Emails, Three meetings
    Expected: Treat them as independent tasks and fit them around the meetings,
    using task-type fit and personal work window.
    """
    profile = PlanningProfile(
        weekday_wake_time=7.0,
        preferred_peak_start=8.5,
        preferred_peak_end=12.0,
        preferred_dip_start=14.0,
        preferred_dip_end=15.5,
        bedtime=23.0,
    )
    tz = timezone.utc
    base_date = date(2026, 10, 5)
    now_local = datetime.combine(base_date, time(7, 0), tzinfo=tz)

    # 3 Meetings (Fixed/anchored times)
    m1 = MockTask("Morning Standup", task_type="meeting", scheduled_start="10:00", estimated_minutes=30)
    m2 = MockTask("Client Sync", task_type="meeting", scheduled_start="13:00", estimated_minutes=45)
    m3 = MockTask("Team Retro", task_type="meeting", scheduled_start="15:30", estimated_minutes=30)

    # Flexible tasks
    t_gym = MockTask("Gym", task_type="physical", priority="medium", estimated_minutes=60)
    t_coding = MockTask("Important coding work", task_type="deep_work", priority="high", estimated_minutes=60)
    t_emails = MockTask("Emails", task_type="admin", priority="low", estimated_minutes=30)

    all_tasks = [m1, m2, m3, t_gym, t_coding, t_emails]

    engine = SchedulingEngine()
    schedule = engine.generate_schedule(
        tasks=all_tasks,
        now_local=now_local,
        tz=tz,
    )

    assert len(schedule) == 6
    titles = [s["title"] for s in schedule]
    assert "Gym" in titles
    assert "Important coding work" in titles
    assert "Emails" in titles

    # Verify no overlaps between any scheduled items
    for i in range(len(schedule) - 1):
        assert schedule[i]["end_time"] <= schedule[i + 1]["start_time"], (
            f"Collision: {schedule[i]['title']} ({schedule[i]['end_time']}) overlaps {schedule[i+1]['title']} ({schedule[i+1]['start_time']})"
        )

    # Coding should get peak morning focus (before or around meetings)
    coding_slot = next(s for s in schedule if s["title"] == "Important coding work")
    coding_h = coding_slot["start_time"].hour + coding_slot["start_time"].minute / 60.0
    assert 8.0 <= coding_h <= 12.0, f"Expected coding in morning peak window, got {coding_slot['start_time']}"

    # Emails should be scheduled in afternoon or between meetings
    emails_slot = next(s for s in schedule if s["title"] == "Emails")
    assert emails_slot["type"] == "admin"

def test_case_6_clause_splitting_not_one_combined_task():
    """
    CASE 6
    Input: "gym work assignment"
    Expected: Gym, Work, Assignment — NOT one combined task.
    """
    candidates = AIService.parse_task_dump("gym work assignment")
    titles = [c.title for c in candidates]
    assert len(candidates) == 3, f"Expected 3 tasks, got {len(candidates)}: {titles}"
    assert "Gym" in titles
    assert "Work" in titles
    assert "Assignment" in titles

def test_data_path_onboarding_to_planning_profile_to_scheduler():
    """
    Trace the complete data path:
    Questionnaire payload -> ReadinessService.submit_onboarding_answers -> DB -> PlanningProfile -> SchedulingEngine
    """
    Base.metadata.create_all(bind=db_engine)
    db = SessionLocal()
    try:
        # Create test user
        import uuid
        test_user_id = str(uuid.uuid4())
        user = User(
            id=test_user_id,
            email=f"audit_{test_user_id[:8]}@example.com",
            name="Audit User",
        )
        db.add(user)
        db.commit()

        service = ReadinessService()
        req = ReadinessOnboardingRequest(
            preferred_peak_start="08:30",
            preferred_peak_end="11:30",
            weekday_wake_time="06:30",
            weekend_wake_time="08:00",
            bedtime="22:30",
            sleep_inertia_minutes=45,
            draining_work_types=["coding", "problem_solving", "thesis"],
            fatigue_symptom="procrastinate",
            routine_shift_preference="slower_tempo",
            preferred_session_minutes=50,
        )

        resp = service.submit_onboarding_answers(db, test_user_id, req)
        assert resp is not None

        # Read back from DB
        db_profile = service.repo.get_profile(db, test_user_id)
        assert db_profile is not None
        assert db_profile.weekday_wake_time == "06:30"
        assert db_profile.weekend_wake_time == "08:00"
        assert db_profile.bedtime == "22:30"
        assert db_profile.sleep_inertia_minutes == 45
        assert db_profile.draining_work_types == "coding,problem_solving,thesis"
        assert db_profile.fatigue_symptom == "procrastinate"
        assert db_profile.routine_shift_preference == "slower_tempo"

        # Construct PlanningProfile from DB record
        plan_profile = PlanningProfile.from_user_context(readiness_profile=db_profile)
        assert plan_profile.wake_time == 6.5
        assert plan_profile.weekend_wake_time == 8.0
        assert plan_profile.bedtime == 22.5
        assert plan_profile.peak_window_start == 8.5
        assert plan_profile.peak_window_end == 11.5
        assert plan_profile.warmup_minutes == 45
        assert "thesis" in plan_profile.high_energy_task_types
        assert plan_profile.tired_behavior == "procrastinate"
        assert plan_profile.routine_shift_preference == "slower_tempo"

        # Verify scheduling engine uses this profile
        engine = SchedulingEngine()
        tz = timezone.utc
        now = datetime.combine(date(2026, 10, 5), time(6, 30), tzinfo=tz) # exactly at wake time 6:30 AM
        coding_task = MockTask("Write thesis code", task_type="deep_work", estimated_minutes=45)

        slot_res = engine.evaluate_best_slot_for_task(
            task=coding_task,
            existing_busy=[],
            profile=plan_profile,
            now_local=now,
            tz=tz,
        )
        assert slot_res is not None
        # Warmup ends at 6:30 + 45m = 7:15 AM
        # Peak window starts at 8:30 AM
        start_h = slot_res.slot.start_time.hour + slot_res.slot.start_time.minute / 60.0
        assert start_h >= 7.25, f"Expected start after 7:15 AM warmup, got {slot_res.slot.start_time}"
        assert start_h == 8.5, f"Expected start at peak window 8:30 AM, got {slot_res.slot.start_time}"

    finally:
        db.close()
