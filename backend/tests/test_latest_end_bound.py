"""Finding 4: a user's latest_end was overwritten by the per-day limit variable."""
from datetime import datetime, timedelta
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app.engines.scheduling_engine import PlanningProfile, SchedulingEngine

IST = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)


def task(**temporal):
    return SimpleNamespace(id="t", title="Task", estimated_minutes=45, priority="medium", task_type="admin",
                           deadline_at=None, scheduled_start=None, status="todo",
                           temporal=SimpleNamespace(**temporal))


def at(h, m=0, day=5):
    return datetime(2026, 10, day, h, m, tzinfo=IST)


def best(t, busy=()):
    return SchedulingEngine().evaluate_best_slot_for_task(t, list(busy), PlanningProfile(), NOW, IST)


def test_latest_end_is_hard_bound():
    busy = [(at(9), at(12))]
    assert best(task(latest_end=at(12)), busy) is None  # only post-12:00 slots remain -> none allowed


def test_latest_end_respected_when_a_slot_exists():
    res = best(task(latest_end=at(12)))
    assert res is not None and res.slot.end_time <= at(12)


def test_latest_end_with_multi_day_candidates():
    # deadline on day 2 makes the engine generate several days; the bound must still apply on all of them
    t = task(latest_end=at(11))
    t.deadline_at = at(20, day=6)
    res = best(t)
    assert res is not None and res.slot.end_time <= at(11)


def test_availability_window_bounds_all_candidates():
    t = task(earliest_start=at(9, 30), latest_end=at(17, 30))
    for busy_end in (9, 12, 15):
        res = best(t, [(at(9), at(busy_end))])
        assert res is None or (res.slot.start_time >= at(9, 30) and res.slot.end_time <= at(17, 30))


def test_explicit_past_time_returns_reason_not_a_flexible_slot():
    t = SimpleNamespace(id="t", title="Call", estimated_minutes=30, priority="medium", task_type="admin",
                        deadline_at=None, scheduled_start=at(7), status="todo", temporal=None)
    res, reason = SchedulingEngine().evaluate_best_slot_with_reason(t, [], PlanningProfile(), NOW, IST)
    assert res is None and reason == "explicit_time_in_past"
