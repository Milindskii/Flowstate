from datetime import datetime, date, time
from zoneinfo import ZoneInfo
import pytest
from app.services.ai_service import AIService
from app.engines.scheduling_engine import SchedulingEngine, PlanningProfile
from app.schemas.task import TaskCandidateResponse

tz = ZoneInfo("Asia/Kolkata")
# Tuesday, September 29, 2026
ref_now = datetime(2026, 9, 29, 14, 0, 0, tzinfo=tz)


def test_1_dentist_appointment_on_friday_at_9_pm():
    task = AIService._parse_single_clause("dentist appointment on Friday at 9 PM", ref_now, tz)
    assert task is not None
    assert task.target_date == date(2026, 10, 2)
    assert task.fixed_start == "21:00"
    assert task.scheduled_start == datetime(2026, 10, 2, 21, 0, tzinfo=tz)
    assert task.deadline_at is None
    assert task.deadline is None
    assert task.temporal is not None
    assert task.temporal.target_date == date(2026, 10, 2)
    assert task.temporal.fixed_start == datetime(2026, 10, 2, 21, 0, tzinfo=tz)

    scheduler = SchedulingEngine()
    slot_res = scheduler.evaluate_best_slot_for_task(task, [], PlanningProfile(), ref_now, tz)
    assert slot_res is not None
    assert slot_res.slot.day_offset == 3  # Tuesday -> Friday is 3 days
    assert slot_res.slot.start_time == datetime(2026, 10, 2, 21, 0, tzinfo=tz)


def test_2_dentist_appointment_friday_at_5_pm():
    task = AIService._parse_single_clause("dentist appointment Friday at 5 PM", ref_now, tz)
    assert task is not None
    assert task.target_date == date(2026, 10, 2)
    assert task.fixed_start == "17:00"
    assert task.scheduled_start == datetime(2026, 10, 2, 17, 0, tzinfo=tz)
    assert task.deadline_at is None
    assert task.deadline is None


def test_3_dentist_appointment_tomorrow_at_9_pm():
    task = AIService._parse_single_clause("dentist appointment tomorrow at 9 PM", ref_now, tz)
    assert task is not None
    assert task.target_date == date(2026, 9, 30)
    assert task.fixed_start == "21:00"
    assert task.scheduled_start == datetime(2026, 9, 30, 21, 0, tzinfo=tz)
    assert task.deadline_at is None


def test_4_dentist_appointment_today_at_9_pm():
    task = AIService._parse_single_clause("dentist appointment today at 9 PM", ref_now, tz)
    assert task is not None
    assert task.target_date == date(2026, 9, 29)
    assert task.fixed_start == "21:00"
    assert task.scheduled_start == datetime(2026, 9, 29, 21, 0, tzinfo=tz)
    assert task.deadline_at is None


def test_5_dentist_appointment_at_9_pm_no_target_date():
    task = AIService._parse_single_clause("dentist appointment at 9 PM", ref_now, tz)
    assert task is not None
    assert task.fixed_start == "21:00"
    assert task.target_date is None  # no explicit target date mentioned
    assert task.scheduled_start == datetime(2026, 9, 29, 21, 0, tzinfo=tz)
    assert task.deadline_at is None


def test_6_dentist_appointment_by_friday():
    task = AIService._parse_single_clause("dentist appointment by Friday", ref_now, tz)
    assert task is not None
    assert task.fixed_start is None
    assert task.scheduled_start is None
    assert task.deadline_at is not None
    assert task.deadline_at.date() == date(2026, 10, 2)
    assert task.deadline == "2026-10-02"


def test_7_dentist_appointment_due_friday():
    task = AIService._parse_single_clause("dentist appointment due Friday", ref_now, tz)
    assert task is not None
    assert task.fixed_start is None
    assert task.scheduled_start is None
    assert task.deadline_at is not None
    assert task.deadline_at.date() == date(2026, 10, 2)
    assert task.deadline == "2026-10-02"
