"""Seeded property tests over EVERY planner input dimension (integrity-review follow-up).

The first property test (test_planner_contract.py) varied items, statuses, locks and deadlines. This one adds the
dimensions it missed: temporal bounds (target_date / earliest_start / latest_end / preferred window), planned_date,
dependencies (including cycles), yield_to_fixed, pinned items, extra busy time, ranks, and both modes with a replan
scope. A failure prints the seed, so any case can be reproduced with `plan(**scenario(seed))`.
"""
import random
from dataclasses import replace
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.engines.planner import PlanItem, PlanTemporal, check_invariants, plan
from app.engines.scheduling_engine import PlanningProfile

TZ = ZoneInfo("Asia/Kolkata")
DAY = date(2026, 10, 5)


def at(day_offset, h, m=0):
    return datetime(2026, 10, 5, h, m, tzinfo=TZ) + timedelta(days=day_offset)


def scenario(seed):
    rnd = random.Random(seed)
    now = at(0, rnd.choice([6, 8, 9, 12, 15, 18, 21, 22]), rnd.choice([0, 7, 30, 52]))
    mode = rnd.choice(["build", "replan"])
    items, new_ids = [], []
    for n in range(rnd.randint(2, 11)):
        iid = f"i{n}"
        kind = rnd.choice(["new", "new", "new", "flex", "locked", "locked_new", "yielding", "done", "prog", "pinned"])
        start = at(rnd.choice([0, 0, 0, 1, 2]), rnd.randint(7, 21), rnd.choice([0, 15, 30, 45]))
        m = rnd.choice([15, 30, 45, 60, 90, 120])
        common = dict(id=iid, title=f"T{n}", estimated_minutes=m, priority=rnd.choice(["low", "medium", "high", "urgent"]),
                      task_type=rnd.choice(["deep_work", "admin", "study", "physical", "meeting"]))
        if rnd.random() < 0.25:
            common["deadline_at"] = now + timedelta(hours=rnd.choice([1, 3, 6, 10, 30, 80]))
        if rnd.random() < 0.15:
            common["rank"] = rnd.randint(0, 3)
        if kind == "new":
            temporal_kwargs = {}
            if rnd.random() < 0.20:
                temporal_kwargs["target_date"] = DAY + timedelta(days=rnd.choice([0, 1, 2]))
            if rnd.random() < 0.20:
                temporal_kwargs["earliest_start"] = now + timedelta(hours=rnd.choice([1, 3, 6, 20, 30]))
            if rnd.random() < 0.20:
                temporal_kwargs["latest_end"] = now + timedelta(hours=rnd.choice([2, 5, 9, 14, 26]))
            if rnd.random() < 0.10:
                p0 = now + timedelta(hours=rnd.choice([2, 6]))
                temporal_kwargs.update(preferred_start=p0, preferred_window_start=p0 - timedelta(minutes=45),
                                       preferred_window_end=p0 + timedelta(minutes=45))
            if temporal_kwargs:
                common["temporal"] = PlanTemporal(**temporal_kwargs)
            if rnd.random() < 0.15:
                common["planned_date"] = DAY + timedelta(days=rnd.choice([-1, 0, 1, 2]))
            items.append(PlanItem(is_new=True, **common))
            new_ids.append(iid)
        elif kind == "flex":
            items.append(PlanItem(start=start, end=start + timedelta(minutes=m), **common))
        elif kind == "locked":
            items.append(PlanItem(start=start, end=start + timedelta(minutes=m), time_locked=True, **common))
        elif kind == "locked_new":
            items.append(PlanItem(start=start, end=start + timedelta(minutes=m), time_locked=True, is_new=True, **common))
        elif kind == "yielding":
            items.append(PlanItem(start=start, end=start + timedelta(minutes=m), time_locked=True, is_new=True,
                                  yield_to_fixed=True, **common))
        elif kind == "done":
            items.append(PlanItem(status="completed", start=start, completed_at=start + timedelta(minutes=m), **common))
        elif kind == "prog":
            items.append(PlanItem(status="in_progress", start=start, started_at=start, **common))
        elif kind == "pinned":
            items.append(PlanItem(start=start, end=start + timedelta(minutes=m), pinned=True, **common))
    # dependencies among new flexible items, occasionally cyclic
    for iid in new_ids:
        if rnd.random() < 0.25 and len(new_ids) > 1:
            other = rnd.choice([x for x in new_ids if x != iid])
            idx = next(k for k, it in enumerate(items) if it.id == iid)
            items[idx] = replace(items[idx], depends_on=(other,))
    extra = []
    for _ in range(rnd.choice([0, 0, 1, 2, 3])):
        s = at(rnd.choice([0, 0, 1]), rnd.randint(7, 20), rnd.choice([0, 30]))
        extra.append((s, s + timedelta(minutes=rnd.choice([30, 60, 120]))))
    # new items must have unique ids and "new" kind items above were appended with is_new
    return dict(
        items=items, now_local=now, tz=TZ, profile=PlanningProfile(), mode=mode,
        scope_date=DAY if mode == "replan" and rnd.random() < 0.7 else None,
        extra_busy=tuple(extra), extra_buffer_minutes=rnd.choice([0, 0, 5]),
    )


def _overlap(a, b):
    return a[0] < b[1] and a[1] > b[0]


@pytest.mark.parametrize("seed", range(400))
def test_every_dimension_respects_the_contract(seed):
    sc = scenario(seed)
    items, now = sc["items"], sc["now_local"]
    if not items:
        pytest.skip("empty scenario")
    res = plan(**sc)           # plan() itself raises PlanInvariantError on any contract violation
    by_id = {i.id: i for i in items}

    # conservation + invariants, re-checked independently of plan()'s internal check
    assert check_invariants(items, res, now_local=now, tz=TZ, extra_busy=sc["extra_busy"]) == [], seed
    ids = [p.item_id for p in res.placements] + [i.item_id for i in res.immutable] + [u.item_id for u in res.unscheduled]
    assert sorted(ids) == sorted(by_id), seed

    placed = {p.item_id: p for p in res.placements}
    imm = {i.item_id: i for i in res.immutable}

    for p in res.placements:
        it = by_id[p.item_id]
        t = it.temporal
        # extra busy time is never used
        for b in sc["extra_busy"]:
            assert not _overlap((p.start, p.end), b), (seed, "placed inside extra busy time", p.item_id)
        assert p.start >= now - timedelta(seconds=60), (seed, p.item_id)
        assert p.start.second == 0 and p.start.microsecond == 0 or p.primary_reason == "kept_in_place", (seed, p.item_id)
        if it.deadline_at is not None:
            assert p.end <= it.deadline_at, (seed, "deadline", p.item_id)
        if t is not None:
            if t.target_date is not None:
                assert p.start.astimezone(TZ).date() == t.target_date, (seed, "target_date", p.item_id)
            if t.earliest_start is not None:
                assert p.start >= t.earliest_start, (seed, "earliest_start", p.item_id)
            if t.latest_end is not None:
                assert p.end <= t.latest_end, (seed, "latest_end", p.item_id)
        if it.planned_date is not None and it.planned_date >= DAY and not (t and t.target_date):
            assert p.start.astimezone(TZ).date() == it.planned_date, (seed, "planned_date", p.item_id)
        # dependencies: a placed successor never starts before its placed predecessor ends
        for dep in it.depends_on:
            if dep in placed and by_id[dep].depends_on != (it.id,):          # ignore 2-cycles
                assert p.start >= placed[dep].end, (seed, "dependency", dep, p.item_id)

    # user-fixed times of items that already existed never move; pinned items never move in any mode
    for it in items:
        if it.time_locked and not it.is_new and it.status in ("todo", "postponed") and it.id in imm:
            assert imm[it.id].start == it.start, (seed, "locked item moved", it.id)
        if it.pinned and it.status in ("todo", "postponed"):
            assert it.id in imm and imm[it.id].kind == "existing" and imm[it.id].start == it.start, (seed, "pinned moved", it.id)
        if it.status in ("completed", "in_progress"):
            assert it.id not in placed and it.id in imm, (seed, "protected item treated as movable", it.id)

    # yield_to_fixed: a yielding item never overlaps a completed / in-progress / existing-locked interval
    fixed = [(i.start, i.end) for i in res.immutable
             if i.kind in ("completed", "in_progress") or (i.kind == "locked" and not by_id[i.item_id].is_new)]
    for it in items:
        if it.yield_to_fixed and it.id in imm and imm[it.id].kind == "locked":
            for f in fixed:
                assert not _overlap((imm[it.id].start, imm[it.id].end), f), (seed, "yielding item kept a clash", it.id)
        if it.yield_to_fixed and it.id in placed:
            for f in fixed:
                assert not _overlap((placed[it.id].start, placed[it.id].end), f), (seed, "yielded item overlaps fixed", it.id)

    # replan scope: items outside the scope date are left exactly where they were
    if sc["mode"] == "replan" and sc["scope_date"] is not None:
        for it in items:
            if (it.status in ("todo", "postponed") and not it.is_new and not it.force_replace and not it.pinned
                    and not it.time_locked and it.start is not None and it.start.astimezone(TZ).date() != sc["scope_date"]):
                assert imm[it.id].kind == "out_of_scope" and imm[it.id].start == it.start, (seed, "out-of-scope item touched", it.id)

    # roll-over suggestions are proposals that still honour every hard rule
    occupied = [(p.start, p.end) for p in res.placements] + [(i.start, i.end) for i in res.immutable if i.start and i.end] + list(sc["extra_busy"])
    for u in res.unscheduled:
        if u.suggestion is not None:
            s = u.suggestion
            assert s.start >= now - timedelta(seconds=60), (seed, "suggestion in the past", u.item_id)
            dl = by_id[u.item_id].deadline_at
            assert dl is None or s.end <= dl, (seed, "suggestion after deadline", u.item_id)
            for o in occupied:
                assert not _overlap((s.start, s.end), o), (seed, "suggestion overlaps", u.item_id)


@pytest.mark.parametrize("seed", range(0, 400, 7))
def test_planning_is_deterministic_for_every_dimension(seed):
    sc = scenario(seed)
    if not sc["items"]:
        pytest.skip("empty scenario")
    assert plan(**sc) == plan(**sc)


def test_generator_actually_exercises_every_dimension():
    """Guard against a generator that silently stops producing a dimension (a vacuous property test)."""
    seen = dict(target=0, earliest=0, latest=0, preferred=0, planned=0, deps=0, yielding=0, pinned=0, extra=0, replan_scope=0,
                cycle=0, locked=0, prog=0, done=0, deadline=0, rank=0)
    for seed in range(400):
        sc = scenario(seed)
        by = {i.id: i for i in sc["items"]}
        if sc["extra_busy"]:
            seen["extra"] += 1
        if sc["mode"] == "replan" and sc["scope_date"]:
            seen["replan_scope"] += 1
        for it in sc["items"]:
            t = it.temporal
            if t:
                seen["target"] += bool(t.target_date)
                seen["earliest"] += bool(t.earliest_start)
                seen["latest"] += bool(t.latest_end)
                seen["preferred"] += bool(t.preferred_start)
            seen["planned"] += bool(it.planned_date)
            seen["deps"] += bool(it.depends_on)
            seen["cycle"] += any(by.get(d) and it.id in by[d].depends_on for d in it.depends_on)
            seen["yielding"] += it.yield_to_fixed
            seen["pinned"] += it.pinned
            seen["locked"] += it.time_locked
            seen["prog"] += it.status == "in_progress"
            seen["done"] += it.status == "completed"
            seen["deadline"] += it.deadline_at is not None
            seen["rank"] += it.rank is not None
    missing = [k for k, v in seen.items() if v < 5]
    assert not missing, f"generator never/rarely produces: {missing} ({seen})"
