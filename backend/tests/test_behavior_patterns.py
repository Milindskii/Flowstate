"""Behavioural learning (no ML): patterns need enough evidence and recency, and below the threshold the answer is
an honest "learning" state with no invented number."""
from datetime import date, datetime, timedelta

from app.engines import behavior_patterns as bp
from app.engines.behavior_patterns import RatingFact, TaskFact

TODAY = date(2026, 10, 8)  # a Thursday


def tuesday(weeks_ago: int) -> date:
    this_tue = TODAY - timedelta(days=TODAY.weekday() - 1)
    return this_tue - timedelta(weeks=weeks_ago)


def gym(day: date, hh=19, mm=0, outcome="completed", title="Gym"):
    return TaskFact(title=title, category="Exercise", day=day, outcome=outcome,
                    start_local=datetime(day.year, day.month, day.day, hh, mm), planned_minutes=60)


def test_tuesday_gym_routine_is_learned_with_evidence_and_recency():
    facts = [gym(tuesday(w)) for w in (0, 1, 2, 4)] + [gym(tuesday(3), 19, 20, title="go to the gym")]
    r = bp.weekly_routines(facts, TODAY)
    assert len(r) == 1
    assert r[0]["weekday"] == "Tuesday" and r[0]["start_label"] == "7:00 PM"
    assert r[0]["weeks_seen"] == 5 and r[0]["weeks_span"] == 5
    assert "Gym · Tuesday · 7:00 PM" in r[0]["label"]
    assert bp.routine_for(r, "gym", 1) is not None
    assert bp.routine_for(r, "gym", 2) is None  # a Tuesday habit says nothing about Wednesday


def test_two_weeks_is_not_a_routine():
    assert bp.weekly_routines([gym(tuesday(0)), gym(tuesday(1))], TODAY) == []


def test_stale_habit_is_not_a_routine():
    facts = [gym(tuesday(w)) for w in (4, 5, 6, 7)]  # stopped a month ago
    assert bp.weekly_routines(facts, TODAY) == []


def test_inconsistent_habit_is_not_a_routine():
    facts = [gym(tuesday(w)) for w in (0, 3, 7)]  # 3 of 8 weeks
    assert bp.weekly_routines(facts, TODAY) == []


def test_different_times_do_not_merge_into_one_routine():
    facts = [gym(tuesday(0), 7), gym(tuesday(1), 19), gym(tuesday(2), 7), gym(tuesday(3), 19)]
    assert bp.weekly_routines(facts, TODAY) == []


def test_skipped_and_missed_occurrences_are_not_evidence():
    facts = [gym(tuesday(w), outcome="skipped") for w in range(5)]
    assert bp.weekly_routines(facts, TODAY) == []


def test_completion_trend_learning_then_ready():
    few = [gym(TODAY - timedelta(days=1))]
    out = bp.completion_trend(few, TODAY)
    assert out["status"] == "learning" and "this_week" not in out and out["needed"] == 2
    week = TODAY - timedelta(days=TODAY.weekday())
    facts = [gym(week + timedelta(days=i), outcome=o) for i, o in enumerate(["completed", "completed", "missed", "completed"])]
    facts += [gym(week - timedelta(days=7 - i), outcome="completed" if i % 2 else "skipped") for i in range(4)]
    out = bp.completion_trend(facts, TODAY)
    assert out["status"] == "ready" and out["this_week"] == 0.75 and out["last_week"] == 0.5 and out["change_pts"] == 25


def test_open_future_tasks_never_lower_the_rate():
    week = TODAY - timedelta(days=TODAY.weekday())
    facts = [gym(week + timedelta(days=i)) for i in range(3)] + [gym(TODAY, outcome="open")]
    assert bp.completion_trend(facts, TODAY)["this_week"] == 1.0


def test_duration_ratio_needs_real_timestamps_per_category():
    def t(actual, cat="Admin"):
        return TaskFact("Email", cat, TODAY, "completed", planned_minutes=30, actual_minutes=actual)
    out = bp.duration_by_category([t(30), t(45), t(None), t(None)])
    assert out["status"] == "learning"  # only two timed completions
    out = bp.duration_by_category([t(30), t(45), t(600)])  # 600 min = 20x: rejected as noise
    assert out["status"] == "learning"
    out = bp.duration_by_category([t(30), t(45), t(60)])
    assert out["status"] == "ready" and out["categories"][0] == {"category": "Admin", "ratio": 1.5, "sample_size": 3}


def test_focus_windows_only_claim_a_best_window_that_stands_out():
    def r(h, f):
        return RatingFact(start_local=datetime(2026, 10, 1, h), focus=f)
    assert bp.focus_windows([r(9, 5)] * 3)["status"] == "learning"
    out = bp.focus_windows([r(9, 5), r(10, 4), r(9, 5), r(15, 3), r(14, 3), r(16, 2)])
    assert out["status"] == "ready" and out["best"] == "morning"
    flat = bp.focus_windows([r(9, 4), r(10, 4), r(9, 4), r(15, 4), r(14, 4), r(16, 4)])
    assert flat["best"] is None  # no window really stands out: nothing is claimed


def test_postponement_by_category():
    facts = [TaskFact("Taxes", "Admin", TODAY, o) for o in ["deferred", "deferred", "completed", "skipped", "completed"]]
    out = bp.postponement(facts)
    assert out["status"] == "ready"
    assert out["categories"][0]["category"] == "Admin" and out["categories"][0]["rate"] == 0.6


def test_summary_for_a_new_user_is_all_learning():
    s = bp.summarize([], [], TODAY)
    assert all(section["status"] == "learning" for section in s.values())
    assert all("needed" in section for section in s.values())


# ── learned routines in Build My Day: suggestions only ──────────────────────

import pytest  # noqa: E402

from tests.plan_helpers import IST, cand, client, fixed_cand, make_user, post_plan, stub_extraction  # noqa: E402
from tests.test_insights_summary_history import _seed_completed  # noqa: E402


def _seed_tuesday_gym(uid, now):
    from datetime import time as _t
    for weeks_ago in range(1, 5):
        d = (now - timedelta(weeks=weeks_ago)).date()
        _seed_completed(uid, "Gym", datetime.combine(d, _t(19, 0), tzinfo=IST))


@pytest.mark.asyncio
async def test_build_my_day_suggests_the_learned_gym_time_for_an_untimed_gym(monkeypatch):
    now = datetime(2026, 10, 6, 8, 0, tzinfo=IST)  # a Tuesday morning
    uid, h = make_user()
    _seed_tuesday_gym(uid, now)
    stub_extraction(monkeypatch, [cand("Gym", 60), cand("Write report", 60)])
    async with client() as ac:
        body = (await post_plan(ac, h, now)).json()
    gym_t = next(t for t in body["tasks"] if t["title"] == "Gym")
    start = datetime.fromisoformat(gym_t["recommended_slot_start"].replace("Z", "+00:00")).astimezone(IST)
    assert 18 * 60 + 30 <= start.hour * 60 + start.minute <= 20 * 60, start
    assert gym_t["learned_hint"] == "Usually Tuesday 7:00 PM"
    assert next(t for t in body["tasks"] if t["title"] == "Write report")["learned_hint"] is None


@pytest.mark.asyncio
async def test_an_explicit_time_always_beats_the_learned_routine(monkeypatch):
    now = datetime(2026, 10, 6, 8, 0, tzinfo=IST)
    uid, h = make_user()
    _seed_tuesday_gym(uid, now)
    stub_extraction(monkeypatch, [fixed_cand("Gym", datetime(2026, 10, 6, 9, 0, tzinfo=IST), 60)])
    async with client() as ac:
        body = (await post_plan(ac, h, now)).json()
    gym_t = body["tasks"][0]
    start = datetime.fromisoformat(gym_t["recommended_slot_start"].replace("Z", "+00:00")).astimezone(IST)
    assert (start.hour, start.minute) == (9, 0)
    assert gym_t["learned_hint"] is None


@pytest.mark.asyncio
async def test_no_routine_on_another_weekday(monkeypatch):
    now = datetime(2026, 10, 7, 8, 0, tzinfo=IST)  # Wednesday: the habit is Tuesdays
    uid, h = make_user()
    _seed_tuesday_gym(uid, datetime(2026, 10, 6, 8, 0, tzinfo=IST))
    stub_extraction(monkeypatch, [cand("Gym", 60)])
    async with client() as ac:
        body = (await post_plan(ac, h, now)).json()
    assert body["tasks"][0]["learned_hint"] is None
