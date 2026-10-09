"""
Loads a user's real history as plain facts for ``engines/behavior_patterns`` (the pure statistics).

Evidence rules:
  * outcomes come from task rows + task_deviations (skip/defer history), never from client-made scores;
  * actual minutes come only from real start/finish timestamps;
  * ratings come only from ``task_performance`` rows with provenance ``reflection``;
  * fixed commitments are busy time, not work, so they are never evidence.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from typing import Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy import or_
from sqlalchemy.orm import Session

from ..engines import behavior_patterns as bp
from ..engines.behavior_patterns import RatingFact, TaskFact
from ..models.task import Task, TaskStatus
from ..models.task_deviation import TaskDeviation
from ..models.task_performance import TaskPerformance

LOOKBACK_DAYS = bp.ROUTINE_LOOKBACK_WEEKS * 7 + 7


def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _local(dt: Optional[datetime], tz: ZoneInfo) -> Optional[datetime]:
    a = _aware(dt)
    return a.astimezone(tz).replace(tzinfo=None) if a else None


def _status(t: Task) -> str:
    return t.status.value if hasattr(t.status, "value") else str(t.status)


def load_facts(db: Session, user_id: str, tz: ZoneInfo, now: datetime) -> Tuple[List[TaskFact], List[RatingFact]]:
    now_l = now.astimezone(tz)
    today = now_l.date()
    lo_day = today - timedelta(days=LOOKBACK_DAYS)
    lo_utc = datetime.combine(lo_day, time.min, tzinfo=tz).astimezone(timezone.utc)

    rows: List[Task] = (
        db.query(Task)
        .filter(Task.user_id == user_id,
                Task.is_commitment.is_(False),
                Task.status.notin_([TaskStatus.cancelled, TaskStatus.archived]),
                or_(Task.planned_date >= lo_day, Task.scheduled_start >= lo_utc, Task.completed_at >= lo_utc))
        .all()
    )
    devs: List[TaskDeviation] = (
        db.query(TaskDeviation)
        .filter(TaskDeviation.user_id == user_id, TaskDeviation.deviation_date >= lo_day)
        .all()
    )
    by_id: Dict[str, Task] = {str(t.id): t for t in rows}
    # An auto-skipped task keeps its slot, so finishing it there afterwards is told by its own (completed) row.
    devs = [d for d in devs if not (d.kind == "auto_skipped" and d.task_id and str(d.task_id) in by_id
                                    and _status(by_id[str(d.task_id)]) == "completed")]
    deviated_days = {(str(d.task_id), d.deviation_date) for d in devs if d.task_id}

    facts: List[TaskFact] = []
    for t in rows:
        start_l = _local(t.scheduled_start, tz)
        done_l = _local(t.completed_at, tz)
        day = t.planned_date or (start_l.date() if start_l else None) or (done_l.date() if done_l else None)
        if day is None or day > today:
            continue
        if (str(t.id), day) in deviated_days:
            continue  # that day is told by its deviation row; this row has since moved
        status = _status(t)
        if status == "completed":
            outcome = "completed"
        else:
            end = _aware(t.scheduled_end) or (
                _aware(t.scheduled_start) + timedelta(minutes=t.estimated_minutes or 45) if t.scheduled_start else None)
            past = day < today or (end is not None and end <= now)
            outcome = "missed" if past and status in ("todo", "postponed") else "open"
        actual = None
        if t.started_at and t.completed_at:
            mins = (_aware(t.completed_at) - _aware(t.started_at)).total_seconds() / 60.0
            actual = int(round(mins)) if mins >= 1 else None
        started_l = _local(t.started_at, tz)
        facts.append(TaskFact(
            title=t.title, category=t.category or "General", day=day, outcome=outcome,
            start_local=(started_l if outcome == "completed" and started_l else start_l) or (
                done_l - timedelta(minutes=actual or t.estimated_minutes or 0) if done_l else None),
            planned_minutes=t.estimated_minutes, actual_minutes=actual))

    for d in devs:
        t = by_id.get(str(d.task_id)) if d.task_id else None
        if t is None or d.deviation_date > today:
            continue
        facts.append(TaskFact(
            title=t.title, category=t.category or "General", day=d.deviation_date,
            outcome=d.kind if d.kind in ("deferred", "missed", "auto_skipped") else "skipped",
            start_local=_local(d.original_start, tz), planned_minutes=t.estimated_minutes))

    perf = (
        db.query(TaskPerformance)
        .filter(TaskPerformance.user_id == user_id, TaskPerformance.provenance == "reflection",
                TaskPerformance.completed_at >= lo_utc)
        .all()
    )
    ratings = []
    for p in perf:
        at = _local(p.actual_start or p.scheduled_start or p.completed_at, tz)
        if at is not None and (p.focus_score is not None or p.energy_score is not None):
            ratings.append(RatingFact(start_local=at, focus=p.focus_score, energy=p.energy_score))
    return facts, ratings


def summary(db: Session, user_id: str, tz: ZoneInfo, now: datetime) -> Dict:
    facts, ratings = load_facts(db, user_id, tz, now)
    return bp.summarize(facts, ratings, now.astimezone(tz).date())


def routines(db: Session, user_id: str, tz: ZoneInfo, now: datetime) -> List[Dict]:
    facts, _ = load_facts(db, user_id, tz, now)
    return bp.weekly_routines(facts, now.astimezone(tz).date())
