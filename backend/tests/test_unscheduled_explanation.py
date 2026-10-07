"""
"Not scheduled" must say why, honestly. Placement is unchanged (see test_planner_contract.py); only the
explanation of a task that cannot be placed inside a limit the user stated is checked here.

Real case this was written from: on Sunday 12:04 the day already held ~8 tasks and a fixed commitment, the
user said "today", and two long tasks could not fit. The old text blamed "the time limits you set".
"""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from app.engines.planner import PlanItem, PlanTemporal, plan
from app.engines.scheduling_engine import PlanningProfile

IST = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 10, 4, 12, 4, tzinfo=IST)  # Sunday 12:04


def at(h, m=0, day=4):
    return datetime(2026, 10, day, h, m, tzinfo=IST)


def _busy_day():
    """Already-booked day: fixed 12:30-22:30, leaving only a 30 minute sliver before bedtime."""
    return PlanItem(id="busy", title="Booked", estimated_minutes=600, start=at(12, 30), end=at(22, 30), time_locked=True)


def _run(item):
    res = plan([_busy_day(), item], now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")
    return next(u for u in res.unscheduled if u.item_id == item.id)


def _new(**kw):
    return PlanItem(id="t", title="Write report", estimated_minutes=120, is_new=True, **kw)


def test_today_target_explains_there_is_no_free_time_today():
    u = _run(_new(temporal=PlanTemporal(target_date=NOW.date())))
    assert u.reason == "bound_infeasible"
    assert "free time" in u.message and "today" in u.message
    assert "Write report" in u.message and "120 min" in u.message
    assert "time limits you set" not in u.message


def test_tomorrow_and_later_target_dates_are_named():
    tomorrow = (NOW + timedelta(days=1)).date()
    busy = PlanItem(id="busy", title="Booked", estimated_minutes=1290, start=at(0, 0, day=5), end=at(21, 30, day=5), time_locked=True)
    res = plan([busy, _new(temporal=PlanTemporal(target_date=tomorrow))], now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")
    u = next(u for u in res.unscheduled if u.item_id == "t")
    assert "tomorrow" in u.message and "free time" in u.message


def test_latest_end_names_the_cutoff_time():
    u = _run(_new(temporal=PlanTemporal(latest_end=at(17, 0))))
    assert u.reason == "bound_infeasible"
    assert "before 5:00 PM" in u.message and "free time" in u.message
