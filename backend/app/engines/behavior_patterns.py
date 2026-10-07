"""
Behavioural / statistical learning (no ML) over a user's real history.

Pure and deterministic: every function takes plain fact records and an explicit ``today`` and returns plain dicts.
Nothing here reads the database or the clock (see ``services/behavior_service.py`` for loading).

Honesty contract (the Insights and planner consumers rely on it):
  * every section carries ``status`` = "ready" | "learning", ``sample_size`` and, when ready, ``confidence``;
  * below its evidence threshold a section is "learning" with ``needed`` (how much more evidence) and NO number;
  * a learned pattern is a recommendation only: callers never let it override an explicit user request.
"""
from __future__ import annotations

import re
import statistics
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

# One part-of-day definition shared with the client (lib/models/insights_snapshot.dart mirrors it).
PARTS_OF_DAY: Tuple[Tuple[str, int, int], ...] = (
    ("morning", 5, 12), ("afternoon", 12, 17), ("evening", 17, 22), ("night", 22, 29))

MIN_WEEK_TASKS = 3            # planned tasks in a week before its completion rate is shown
MIN_CATEGORY_DURATIONS = 3    # timed completions per category for planned-vs-actual
MIN_FOCUS_RATINGS = 6         # reflections overall before focus windows are shown
MIN_FOCUS_PER_WINDOW = 3      # reflections inside a window before it can be "best"
MIN_POSTPONE_SAMPLES = 4      # scheduled tasks per category for a postponement pattern
ROUTINE_MIN_WEEKS = 3         # distinct weeks a routine must have happened in
ROUTINE_MIN_RATIO = 0.6       # of the weeks since it first appeared
ROUTINE_LOOKBACK_WEEKS = 8
ROUTINE_RECENCY_DAYS = 21     # it must have happened within this many days
ROUTINE_TOLERANCE_MIN = 45    # starts within +/- this of the routine time count as the same habit

_STOP = frozenset({"the", "a", "an", "my", "to", "for", "of", "and", "at", "go", "do", "some"})


@dataclass(frozen=True)
class TaskFact:
    """One task occurrence on one local day. ``outcome``: completed | missed | skipped | deferred | open."""
    title: str
    category: str
    day: date
    outcome: str
    start_local: Optional[datetime] = None      # planned/actual local start (naive or aware local wall time)
    planned_minutes: Optional[int] = None
    actual_minutes: Optional[int] = None        # from real start/finish timestamps only, else None


@dataclass(frozen=True)
class RatingFact:
    """A real post-task reflection (provenance == reflection)."""
    start_local: datetime
    focus: Optional[int] = None
    energy: Optional[int] = None


def routine_key(title: str) -> str:
    """'Go to the gym!' / 'gym' -> 'gym': the identity a weekly habit is grouped (and later matched) by."""
    words = [w for w in re.findall(r"[a-z0-9]+", (title or "").lower()) if w not in _STOP]
    return " ".join(words) or (title or "").strip().lower()


def part_of_day(hour: int) -> str:
    h = hour if hour >= 5 else hour + 24
    return next(name for name, lo, hi in PARTS_OF_DAY if lo <= h < hi)


def _learning(needed: int, sample: int, unit: str) -> Dict:
    return {"status": "learning", "sample_size": sample, "needed": max(1, needed), "unit": unit}


def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _minutes_of(dt: datetime) -> int:
    return dt.hour * 60 + dt.minute


def _clock(minutes: int) -> str:
    h, m = divmod(int(minutes) % (24 * 60), 60)
    suffix = "AM" if h < 12 else "PM"
    return f"{(h % 12) or 12}:{m:02d} {suffix}"


# ── completion this week vs last ─────────────────────────────────────────────

def completion_trend(facts: Sequence[TaskFact], today: date) -> Dict:
    """Share of planned work actually done, this week (to today) vs last week. Open future work is excluded."""
    this_w, last_w = _week_start(today), _week_start(today) - timedelta(days=7)

    def rate(lo: date, hi: date) -> Tuple[int, int]:
        rows = [f for f in facts if lo <= f.day <= hi and f.day <= today and f.outcome != "open"]
        return sum(1 for f in rows if f.outcome == "completed"), len(rows)

    done_now, n_now = rate(this_w, today)
    done_prev, n_prev = rate(last_w, this_w - timedelta(days=1))
    if n_now < MIN_WEEK_TASKS:
        return _learning(MIN_WEEK_TASKS - n_now, n_now, "planned tasks this week")
    out = {"status": "ready", "sample_size": n_now, "this_week": round(done_now / n_now, 3),
           "completed": done_now, "planned": n_now, "confidence": round(min(1.0, n_now / 15), 2)}
    if n_prev >= MIN_WEEK_TASKS:
        out["last_week"] = round(done_prev / n_prev, 3)
        out["change_pts"] = round((out["this_week"] - out["last_week"]) * 100)
    return out


def weekday_completion(facts: Sequence[TaskFact], today: date, weeks: int = 4) -> Dict:
    lo = today - timedelta(weeks=weeks)
    by_day: Dict[int, List[TaskFact]] = defaultdict(list)
    for f in facts:
        if lo <= f.day <= today and f.outcome != "open":
            by_day[f.day.weekday()].append(f)
    days = []
    for wd in range(7):
        rows = by_day.get(wd, [])
        days.append({"weekday": WEEKDAYS[wd][:3], "planned": len(rows),
                     "rate": round(sum(1 for f in rows if f.outcome == "completed") / len(rows), 3) if len(rows) >= 2 else None})
    total = sum(d["planned"] for d in days)
    if total < MIN_WEEK_TASKS * 2:
        return _learning(MIN_WEEK_TASKS * 2 - total, total, "planned tasks")
    return {"status": "ready", "sample_size": total, "days": days, "confidence": round(min(1.0, total / 40), 2)}


# ── planned vs actual ────────────────────────────────────────────────────────

def duration_by_category(facts: Sequence[TaskFact]) -> Dict:
    """Median actual/planned per category, from real timestamps only (ratios outside 0.2x..5x are noise)."""
    ratios: Dict[str, List[float]] = defaultdict(list)
    for f in facts:
        if f.outcome == "completed" and f.actual_minutes and f.planned_minutes:
            r = f.actual_minutes / f.planned_minutes
            if 0.2 <= r <= 5.0:
                ratios[(f.category or "General").strip() or "General"].append(r)
    total = sum(len(v) for v in ratios.values())
    rows = [{"category": c, "ratio": round(statistics.median(v), 2), "sample_size": len(v)}
            for c, v in ratios.items() if len(v) >= MIN_CATEGORY_DURATIONS]
    if not rows:
        best = max((len(v) for v in ratios.values()), default=0)
        return _learning(MIN_CATEGORY_DURATIONS - best, total, "timed completions in one category")
    rows.sort(key=lambda r: -r["sample_size"])
    return {"status": "ready", "sample_size": total, "categories": rows,
            "confidence": round(min(1.0, total / 20), 2)}


# ── best focus windows ───────────────────────────────────────────────────────

def focus_windows(ratings: Sequence[RatingFact]) -> Dict:
    rated = [r for r in ratings if r.focus is not None]
    if len(rated) < MIN_FOCUS_RATINGS:
        return _learning(MIN_FOCUS_RATINGS - len(rated), len(rated), "reflections")
    by_part: Dict[str, List[int]] = defaultdict(list)
    for r in rated:
        by_part[part_of_day(r.start_local.hour)].append(int(r.focus))
    windows = [{"part": p, "avg_focus": round(statistics.mean(v), 2), "sample_size": len(v)}
               for p, v in by_part.items() if len(v) >= MIN_FOCUS_PER_WINDOW]
    if not windows:
        return _learning(MIN_FOCUS_PER_WINDOW - max(len(v) for v in by_part.values()), len(rated),
                         "reflections in one part of the day")
    windows.sort(key=lambda w: (-w["avg_focus"], -w["sample_size"]))
    best = windows[0]
    # a "best" window must actually stand out from the others, else nothing is claimed
    stands_out = len(windows) == 1 or best["avg_focus"] - windows[1]["avg_focus"] >= 0.3
    return {"status": "ready", "sample_size": len(rated), "windows": windows,
            "best": best["part"] if stands_out else None,
            "confidence": round(min(1.0, len(rated) / 25), 2)}


# ── postponement ─────────────────────────────────────────────────────────────

def postponement(facts: Sequence[TaskFact]) -> Dict:
    by_cat: Dict[str, List[TaskFact]] = defaultdict(list)
    for f in facts:
        if f.outcome != "open":
            by_cat[(f.category or "General").strip() or "General"].append(f)
    total = sum(len(v) for v in by_cat.values())
    rows = []
    for cat, v in by_cat.items():
        if len(v) < MIN_POSTPONE_SAMPLES:
            continue
        moved = sum(1 for f in v if f.outcome in ("skipped", "deferred", "missed"))
        rows.append({"category": cat, "rate": round(moved / len(v), 3), "sample_size": len(v),
                     "deferred": sum(1 for f in v if f.outcome == "deferred"),
                     "skipped": sum(1 for f in v if f.outcome == "skipped"),
                     "missed": sum(1 for f in v if f.outcome == "missed")})
    if not rows:
        best = max((len(v) for v in by_cat.values()), default=0)
        return _learning(MIN_POSTPONE_SAMPLES - best, total, "tasks in one category")
    rows.sort(key=lambda r: (-r["rate"], -r["sample_size"]))
    return {"status": "ready", "sample_size": total, "categories": rows,
            "confidence": round(min(1.0, total / 30), 2)}


# ── weekly routines ──────────────────────────────────────────────────────────

def weekly_routines(facts: Sequence[TaskFact], today: date) -> List[Dict]:
    """Consistent weekly habits ("Gym · Tuesday · 7:00 PM · 4 of the last 5 weeks").

    A routine needs: completions in >= ROUTINE_MIN_WEEKS distinct weeks on the same weekday at about the same time
    (within ROUTINE_TOLERANCE_MIN of their median start), on >= ROUTINE_MIN_RATIO of the weeks since it first
    appeared (within the lookback), and the latest one within ROUTINE_RECENCY_DAYS.
    """
    lo = today - timedelta(weeks=ROUTINE_LOOKBACK_WEEKS)
    groups: Dict[Tuple[str, int], List[TaskFact]] = defaultdict(list)
    for f in facts:
        if f.outcome == "completed" and f.start_local is not None and lo <= f.day <= today:
            groups[(routine_key(f.title), f.day.weekday())].append(f)

    out: List[Dict] = []
    for (key, wd), rows in groups.items():
        median_min = statistics.median(_minutes_of(f.start_local) for f in rows)
        near = [f for f in rows if abs(_minutes_of(f.start_local) - median_min) <= ROUTINE_TOLERANCE_MIN]
        weeks = {_week_start(f.day) for f in near}
        if len(weeks) < ROUTINE_MIN_WEEKS:
            continue
        last = max(f.day for f in near)
        if (today - last).days > ROUTINE_RECENCY_DAYS:
            continue
        first_week = min(weeks)
        span = (_week_start(today) - first_week).days // 7 + 1
        # the current week only counts once its weekday has passed
        if wd > today.weekday() and _week_start(today) not in weeks:
            span -= 1
        span = max(span, len(weeks))
        ratio = len(weeks) / span
        if ratio < ROUTINE_MIN_RATIO:
            continue
        start = int(round(statistics.median(_minutes_of(f.start_local) for f in near) / 15.0) * 15)
        title = max(near, key=lambda f: f.day).title
        out.append({
            "key": key, "title": title, "weekday": WEEKDAYS[wd], "weekday_index": wd,
            "start_minutes": start, "start_label": _clock(start),
            "weeks_seen": len(weeks), "weeks_span": span, "last_seen": last.isoformat(),
            "confidence": round(min(1.0, len(weeks) / 6) * ratio, 2),
            "label": f"{title} · {WEEKDAYS[wd]} · {_clock(start)} · {len(weeks)} of the last {span} weeks",
        })
    out.sort(key=lambda r: (-r["confidence"], r["weekday_index"], r["start_minutes"]))
    return out


def routine_for(routines: Iterable[Dict], title: str, weekday: int) -> Optional[Dict]:
    """The learned routine an untimed new task matches on that weekday, if any (exact routine identity)."""
    key = routine_key(title)
    return next((r for r in routines if r["key"] == key and r["weekday_index"] == weekday), None)


# ── one summary for the Insights tab ─────────────────────────────────────────

def summarize(facts: Sequence[TaskFact], ratings: Sequence[RatingFact], today: date) -> Dict:
    routines = weekly_routines(facts, today)
    return {
        "completion": completion_trend(facts, today),
        "weekdays": weekday_completion(facts, today),
        "durations": duration_by_category(facts),
        "focus": focus_windows(ratings),
        "postponement": postponement(facts),
        "routines": ({"status": "ready", "sample_size": len(routines), "items": routines} if routines
                     else _learning(ROUTINE_MIN_WEEKS, 0, "weeks of a repeated task")),
    }
