"""Shared scheduling contract C1-C11 against the pure planner (spec sections 2 and 4)."""
import random
from dataclasses import replace
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.engines.planner import PlanItem, PlanTemporal, check_invariants, plan
from app.engines.scheduling_engine import PlanningProfile

IST = ZoneInfo("Asia/Kolkata")
LA = ZoneInfo("America/Los_Angeles")
NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)  # Monday 09:00


def at(h, m=0, day=5, tz=IST):
    return datetime(2026, 10, day, h, m, tzinfo=tz)


def run(items, mode="build", now=NOW, tz=IST, **kw):
    return plan(items, now_local=now, tz=tz, profile=PlanningProfile(), mode=mode, **kw)


def placement(res, item_id):
    return next((p for p in res.placements if p.item_id == item_id), None)


def unplaced(res, item_id):
    return next((u for u in res.unscheduled if u.item_id == item_id), None)


def new(id_, title="Task", m=45, **kw):
    return PlanItem(id=id_, title=title, estimated_minutes=m, is_new=True, **kw)


def locked(id_, start, m=60, **kw):
    return PlanItem(id=id_, title=kw.pop("title", id_), estimated_minutes=m, start=start,
                    end=start + timedelta(minutes=m), time_locked=True, **kw)


def flex(id_, start, m=45, **kw):
    return PlanItem(id=id_, title=kw.pop("title", id_), estimated_minutes=m, start=start,
                    end=start + timedelta(minutes=m), **kw)


# ── C4: no overlaps ──────────────────────────────────────────────────────────
def test_locked_overlap_reported_not_moved():
    a, b = locked("a", at(15)), locked("b", at(15, 30))
    res = run([a, b])
    assert {i.item_id for i in res.immutable} == {"a", "b"}
    assert any(c.code == "locked_overlap" and c.item_ids == ("a", "b") for c in res.conflicts)
    kinds = {i.item_id: (i.start, i.end) for i in res.immutable}
    assert kinds["a"] == (a.start, a.end) and kinds["b"] == (b.start, b.end)


def test_no_placement_overlaps_any_busy():
    items = [locked("L", at(10), 120)] + [new(f"n{i}", m=60) for i in range(5)]
    res = run(items)
    spans = [(p.start, p.end) for p in res.placements] + [(at(10), at(12))]
    for i, a in enumerate(spans):
        for b in spans[i + 1:]:
            assert not (a[0] < b[1] and a[1] > b[0])
    assert check_invariants(items, res, now_local=NOW, tz=IST) == []


# ── finding 16: locked/explicit processed before flexible ─────────────────────
def test_explicit_time_candidate_not_displaced_by_earlier_flexible_candidate():
    items = [new("flex", "Write report", 60), locked("fixed", at(10), 60, title="Call mom", is_new=True)]
    res = run(items)
    fixed = next(i for i in res.immutable if i.item_id == "fixed")
    assert fixed.start == at(10)
    p = placement(res, "flex")
    assert p is not None and not (p.start < at(10) + timedelta(hours=1) and p.end > at(10))


# ── C5: past ─────────────────────────────────────────────────────────────────
def test_nothing_placed_before_now():
    now = at(14, 7)
    res = run([new("a"), new("b")], now=now)
    assert res.placements and all(p.start >= now for p in res.placements)


def test_slots_have_zero_seconds():
    now = datetime(2026, 10, 5, 9, 15, 42, 123456, tzinfo=IST)
    res = run([new("a"), new("b")], now=now)
    for p in res.placements:
        assert p.start.second == 0 and p.start.microsecond == 0 and p.start.minute % 15 == 0
        assert p.start >= now


def test_missed_flexible_replaced_in_replan():
    missed = flex("m", at(8), 45)  # slot already passed, not started
    res = run([missed], mode="replan", scope_date=date(2026, 10, 5))
    p = placement(res, "m")
    assert p is not None and p.start >= NOW and p.moved and p.previous_start == at(8)


def test_now_near_end_of_day_rolls_over_or_is_unscheduled():
    now = at(22, 40)
    res = run([new("a", m=60)], now=now, mode="replan", scope_date=date(2026, 10, 5))
    assert placement(res, "a") is None
    u = unplaced(res, "a")
    assert u is not None and u.reason == "no_capacity"
    assert u.suggestion is not None and u.suggestion.start.date() == date(2026, 10, 6)


def test_fallback_never_past_bedtime_or_deadline():
    # day fully busy; the legacy fallback used to invent an out-of-hours slot
    items = [locked("L", at(9, 15), 14 * 60 - 15)] + [new("a", m=60)]
    res = run(items, now=NOW)
    p = placement(res, "a")
    if p is not None:
        assert p.end <= at(23, 0) or p.start.date() > date(2026, 10, 5)
    assert check_invariants(items, res, now_local=NOW, tz=IST) == []


# ── C6: deadlines ────────────────────────────────────────────────────────────
def test_deadline_never_exceeded():
    items = [new("a", m=60, deadline_at=at(13), priority="urgent"), new("b", m=60, deadline_at=at(15))]
    res = run(items)
    for pid, dl in (("a", at(13)), ("b", at(15))):
        p = placement(res, pid)
        assert p is not None and p.end <= dl


def test_deadline_infeasible_unscheduled_with_reason():
    items = [locked("L", at(9, 15), 120), new("a", m=60, deadline_at=at(11))]
    res = run(items)
    assert placement(res, "a") is None
    u = unplaced(res, "a")
    assert u.reason == "deadline_infeasible" and u.suggestion is None


# ── C7: bounds ───────────────────────────────────────────────────────────────
def test_latest_end_is_hard_bound_in_planner():
    t = PlanTemporal(latest_end=at(12))
    items = [locked("L", at(9, 15), 165), new("a", m=45, temporal=t)]   # busy 09:15-12:00
    res = run(items)
    assert placement(res, "a") is None
    assert unplaced(res, "a").reason == "bound_infeasible"


# ── D6: explicit time in the past ────────────────────────────────────────────
def test_past_explicit_time_new_item_is_unscheduled_not_moved():
    items = [locked("p", at(7), 30, is_new=True, title="Call mom")]
    res = run(items)
    u = unplaced(res, "p")
    assert u is not None and u.reason == "explicit_time_in_past" and u.suggestion is None
    assert not res.placements
    assert any(c.code == "explicit_time_in_past" for c in res.conflicts)


def test_skew_tolerance_60s():
    items = [locked("p", NOW - timedelta(seconds=30), 30, is_new=True)]
    res = run(items)
    assert unplaced(res, "p") is None and any(i.item_id == "p" for i in res.immutable)


# ── C1: completed immutable & busy ──────────────────────────────────────────
def test_completed_never_moved_and_is_busy():
    done = PlanItem(id="d", title="Done", status="completed", estimated_minutes=60, start=at(9, 30),
                    completed_at=at(10, 30))
    res = run([done, new("a", m=60)], now=at(9, 0))
    assert [i for i in res.immutable if i.item_id == "d"][0].kind == "completed"
    p = placement(res, "a")
    assert not (p.start < at(10, 30) and p.end > at(9, 30))
    assert placement(res, "d") is None


# ── C2 / D7: in-progress ─────────────────────────────────────────────────────
def _ip(start, m, **kw):
    return PlanItem(id="ip", title="Doing", status="in_progress", estimated_minutes=m, start=start,
                    started_at=kw.pop("started_at", start), **kw)


def _ip_interval(res):
    i = next(i for i in res.immutable if i.item_id == "ip")
    return i.start, i.end


def test_T_C2_a_planned_end_later_than_now_busy_to_planned_end():
    res = run([_ip(at(9), 90)], now=at(9, 30))
    assert _ip_interval(res) == (at(9), at(10, 30))


def test_T_C2_b_overrun_busy_until_now():
    res = run([_ip(at(9), 30)], now=at(10, 20))
    assert _ip_interval(res) == (at(9), at(10, 20))


def test_T_C2_c_started_at_earlier_than_scheduled_start_uses_started_at():
    ip = _ip(at(10), 60, started_at=at(9, 30))
    res = run([ip], now=at(10, 0))
    assert _ip_interval(res) == (at(9, 30), at(10, 30))


def test_T_C2_d_no_start_fields_busy_now_plus_estimate():
    ip = PlanItem(id="ip", title="Doing", status="in_progress", estimated_minutes=40)
    res = run([ip], now=at(11, 0))
    assert _ip_interval(res) == (at(11, 0), at(11, 40))


def test_T_C2_e_later_placements_start_at_or_after_busy_end():
    items = [_ip(at(9), 30), new("a", m=30), new("b", m=30)]
    res = run(items, now=at(10, 20))
    assert res.placements and all(p.start >= at(10, 20) for p in res.placements)


def test_T_C2_f_replan_never_moves_or_selects_in_progress():
    items = [_ip(at(9), 60), flex("f", at(10), 45)]
    res = run(items, mode="replan", now=at(9, 30), scope_date=date(2026, 10, 5))
    assert placement(res, "ip") is None
    assert _ip_interval(res) == (at(9), at(10))
    p = placement(res, "f")
    assert p is not None and not (p.start < at(10) and p.end > at(9))


def test_T_C2_h_running_late_style_replace_shifts_later_tasks_without_overlap():
    ip = _ip(at(9), 90)  # overrun keeps it busy to 10:30 (planned end)
    later = flex("later", at(10), 45, force_replace=True)
    res = run([ip, later], mode="replan", now=at(9, 30), scope_date=date(2026, 10, 5))
    p = placement(res, "later")
    assert p.start >= at(10, 30)


# ── C3 / C11: replan stability, displacement, scope ──────────────────────────
def test_unchanged_tasks_not_moved():
    items = [flex("a", at(11), 45), flex("b", at(14), 45)]
    res = run(items, mode="replan", scope_date=date(2026, 10, 5))
    for pid, st in (("a", at(11)), ("b", at(14))):
        p = placement(res, pid)
        assert p.start == st and not p.moved


def test_unlocked_persisted_task_can_be_moved_but_locked_cannot():
    lk = locked("lk", at(15), 60)
    fl = flex("fl", at(15), 60)    # overlaps the locked one -> must move
    res = run([lk, fl], mode="replan", scope_date=date(2026, 10, 5))
    assert next(i for i in res.immutable if i.item_id == "lk").start == at(15)
    p = placement(res, "fl")
    assert p.moved and not (p.start < at(16) and p.end > at(15))


def test_urgent_displaces_lowest_priority_first():
    now = at(21, 0)  # only ~1h45 until bedtime
    low = flex("low", at(21, 15), 45, priority="low")
    high = flex("high", at(22, 15), 45, priority="high")
    urgent = new("urgent", "Urgent", 60, priority="urgent")
    res = run([low, high, urgent], mode="replan", now=now, scope_date=date(2026, 10, 5))
    assert placement(res, "urgent") is not None
    assert placement(res, "high") is not None, "higher-priority task must not be displaced before the low one"
    # whoever lost is the low-priority task
    lost = {u.item_id for u in res.unscheduled}
    assert lost <= {"low"}
    assert check_invariants([low, high, urgent], res, now_local=now, tz=IST) == []


def test_other_dates_untouched():
    tomorrow = flex("t", at(9, 0, day=6), 60)
    res = run([tomorrow, new("a")], mode="replan", scope_date=date(2026, 10, 5))
    kind = next(i for i in res.immutable if i.item_id == "t")
    assert kind.kind == "out_of_scope" and kind.start == at(9, 0, day=6)


def test_multiple_conflicts_all_accounted_for():
    items = [locked("L1", at(10), 60), locked("L2", at(10, 30), 60),
             flex("f1", at(10, 15), 45), flex("f2", at(11), 45), new("n", m=45, priority="urgent")]
    res = run(items, mode="replan", scope_date=date(2026, 10, 5))
    assert check_invariants(items, res, now_local=NOW, tz=IST) == []
    assert any(c.code == "locked_overlap" for c in res.conflicts)


def test_insufficient_time_lists_unscheduled_and_rollover():
    now = at(20, 0)
    items = [new(f"n{i}", m=60) for i in range(4)]
    res = run(items, mode="replan", now=now, scope_date=date(2026, 10, 5))
    assert res.unscheduled, "four hours cannot fit before bedtime"
    for u in res.unscheduled:
        assert u.reason == "no_capacity"
        assert u.suggestion is None or u.suggestion.start.date() == date(2026, 10, 6)
    assert check_invariants(items, res, now_local=now, tz=IST) == []


def test_move_to_tomorrow_target_date_is_hard():
    t = PlanTemporal(target_date=date(2026, 10, 6))
    res = run([flex("g", at(17), 45, force_replace=True, temporal=t)], mode="replan", scope_date=date(2026, 10, 5))
    p = placement(res, "g")
    assert p is not None and p.start.date() == date(2026, 10, 6) and p.moved


def test_planned_date_is_respected():
    res = run([new("a", planned_date=date(2026, 10, 7))])
    assert placement(res, "a").start.date() == date(2026, 10, 7)


def test_dependency_orders_successor_after_predecessor():
    items = [new("second", "Submit", 30, depends_on=("first",)), new("first", "Draft", 60)]
    res = run(items)
    assert placement(res, "second").start >= placement(res, "first").end


def test_stated_rank_orders_placement():
    items = [new("a", "A", 60), new("b", "B", 60, rank=0)]
    res = run(items)
    assert placement(res, "b").start < placement(res, "a").start


# ── timezone / date-boundary ────────────────────────────────────────────────
def test_replan_scope_uses_user_local_date_not_utc():
    # 23:40 IST on Oct 5 is 18:10 UTC Oct 5; but 00:10 IST Oct 6 is 18:40 UTC Oct 5.
    now = datetime(2026, 10, 6, 0, 10, tzinfo=IST)
    res = run([new("a", m=30)], now=now, mode="replan", scope_date=date(2026, 10, 6))
    p = placement(res, "a")
    assert p is not None and p.start.astimezone(IST).date() == date(2026, 10, 6)


def test_los_angeles_user_gets_local_hours():
    now = datetime(2026, 10, 5, 8, 0, tzinfo=LA)
    res = run([new("a", m=60)], now=now, tz=LA)
    p = placement(res, "a")
    local = p.start.astimezone(LA)
    assert 7 <= local.hour < 23


# ── C9: conservation (property test) ─────────────────────────────────────────
@pytest.mark.parametrize("seed", range(200))
def test_conservation_and_invariants_property(seed):
    rnd = random.Random(seed)
    now = at(rnd.choice([6, 9, 13, 18, 21, 22]), rnd.choice([0, 7, 30, 45]))
    items = []
    for n in range(rnd.randint(1, 9)):
        kind = rnd.choice(["new", "new", "flex", "locked", "done", "prog"])
        start = at(rnd.randint(7, 22), rnd.choice([0, 15, 30, 45]))
        m = rnd.choice([15, 30, 45, 60, 90])
        pri = rnd.choice(["low", "medium", "high", "urgent"])
        dl = at(rnd.randint(10, 23)) if rnd.random() < 0.25 else None
        if kind == "new":
            items.append(new(f"i{n}", m=m, priority=pri, deadline_at=dl))
        elif kind == "flex":
            items.append(flex(f"i{n}", start, m, priority=pri, deadline_at=dl))
        elif kind == "locked":
            items.append(locked(f"i{n}", start, m, is_new=rnd.random() < 0.5, priority=pri))
        elif kind == "done":
            items.append(PlanItem(id=f"i{n}", title="d", status="completed", estimated_minutes=m, start=start,
                                  completed_at=start + timedelta(minutes=m)))
        else:
            items.append(PlanItem(id=f"i{n}", title="p", status="in_progress", estimated_minutes=m, start=start, started_at=start))
    mode = rnd.choice(["build", "replan"])
    res = run(items, mode=mode, now=now, scope_date=date(2026, 10, 5) if mode == "replan" else None)
    # every id in exactly one bucket (plan() already asserts; re-check independently)
    ids = [p.item_id for p in res.placements] + [i.item_id for i in res.immutable] + [u.item_id for u in res.unscheduled]
    assert sorted(ids) == sorted(i.id for i in items)
    assert check_invariants(items, res, now_local=now, tz=IST) == []
    # completed and in-progress never appear as placements (C1/C2)
    protected = {i.id for i in items if i.status in ("completed", "in_progress")}
    assert not protected & {p.item_id for p in res.placements}
    # locked non-new items keep their exact time (C3)
    for it in items:
        if it.time_locked and not it.is_new:
            im = next(i for i in res.immutable if i.item_id == it.id)
            assert im.start == it.start


# ── yield_to_fixed / origin_start / pinned / validate_placements ──────────────
def test_new_explicit_time_yields_to_existing_locked_item_and_reports_conflict():
    fixed = locked("dentist", at(18), 45, title="Dentist")
    urgent = replace(locked("urgent", at(18), 60, title="Urgent", is_new=True), yield_to_fixed=True)
    res = run([fixed, urgent], mode="replan", scope_date=date(2026, 10, 5))
    assert next(i for i in res.immutable if i.item_id == "dentist").start == at(18)      # fixed item untouched
    p = placement(res, "urgent")
    assert p is not None and not (p.start < at(18, 45) and p.end > at(18))              # moved off the clash
    assert any(c.code == "explicit_time_conflicts_with_fixed" and "dentist" in c.item_ids for c in res.conflicts)


def test_new_explicit_time_without_clash_stays_locked_exactly():
    urgent = replace(locked("urgent", at(15), 60, is_new=True), yield_to_fixed=True)
    res = run([urgent], mode="replan", scope_date=date(2026, 10, 5))
    im = next(i for i in res.immutable if i.item_id == "urgent")
    assert im.kind == "locked" and im.start == at(15) and not res.conflicts


def test_proposed_slot_reports_origin_as_previous_and_is_kept_when_valid():
    it = replace(flex("a", at(16, 30), 45), origin_start=at(16, 0))   # "running late": persisted 16:00, proposal 16:30
    res = run([it], mode="replan", scope_date=date(2026, 10, 5))
    p = placement(res, "a")
    assert p.start == at(16, 30) and p.previous_start == at(16, 0) and p.moved


def test_pinned_items_never_move_even_in_replan():
    clash = replace(flex("pinned", at(11), 60), pinned=True)
    mover = flex("other", at(11, 15), 30)
    res = run([clash, mover], mode="replan", scope_date=date(2026, 10, 5))
    assert next(i for i in res.immutable if i.item_id == "pinned").start == at(11)
    p = placement(res, "other")
    assert not (p.start < at(12) and p.end > at(11))


def test_validate_placements_catches_past_overlap_deadline_and_allows_locked_pairs():
    from app.engines.planner import validate_placements

    other = flex("o", at(11), 60)
    now = at(9)
    v = validate_placements([flex("c1", at(7), 30)], [other], now_local=now)
    assert [x.code for x in v] == ["start_in_past"]
    v = validate_placements([flex("c2", at(11, 30), 30)], [other], now_local=now)
    assert [x.code for x in v] == ["overlap"]
    v = validate_placements([flex("c3", at(19), 30, deadline_at=at(19, 15))], [other], now_local=now)
    assert [x.code for x in v] == ["after_deadline"]
    lk_other, lk_changed = locked("lo", at(12), 60), locked("lc", at(12, 30), 60)
    assert validate_placements([lk_changed], [lk_other], now_local=now) == []           # two user-fixed times may overlap
    prog = PlanItem(id="p", title="Doing", status="in_progress", estimated_minutes=90, start=at(8, 30), started_at=at(8, 30))
    v = validate_placements([flex("c4", at(9, 30), 30)], [prog], now_local=at(9, 20))   # in-progress busy until 10:00 (planned end)
    assert [x.code for x in v] == ["overlap"]
    assert validate_placements([flex("c5", at(10, 0), 30)], [prog], now_local=at(9, 20)) == []


def test_earliest_start_is_an_absolute_instant_never_reanchored_onto_another_day():
    """Regression (found while routing "Later" through the planner): 'not before tomorrow 09:30' used to
    allow TODAY after 09:30, so a postponed task could land earlier than the time the user pushed it to."""
    t = PlanTemporal(earliest_start=at(9, 30, day=6))          # tomorrow 09:30
    res = run([new("later", m=45, temporal=t, task_type="admin")], now=at(10))
    p = placement(res, "later")
    assert p is not None and p.start >= at(9, 30, day=6), p
    # and when tomorrow is completely taken it is NOT squeezed into today
    wall = locked("wall", at(6, 0, day=6), 17 * 60 + 30)
    res = run([wall, new("later", m=45, temporal=t, task_type="admin")], now=at(10))
    assert placement(res, "later") is None
    assert unplaced(res, "later") is not None


def test_meal_relative_bounds_are_still_per_day():
    """The one case that IS re-anchored per day: 'after dinner' means 20:00 on whichever day is considered."""
    t = PlanTemporal(relative_after="dinner", target_date=date(2026, 10, 6))
    res = run([new("dinner-task", m=30, temporal=t)], now=at(10))
    p = placement(res, "dinner-task")
    assert p is not None and p.start.date() == date(2026, 10, 6) and p.start.hour >= 20
