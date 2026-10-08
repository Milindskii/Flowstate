"""
Personal routines: recurrence TEMPLATES with a bounded planning horizon.

A routine is never expanded into unbounded task rows. ``ensure_horizon`` materializes occurrences only for the next
ROUTINE_HORIZON_DAYS local days and remembers how far it went (``materialized_through``), so a task the user deleted is
not resurrected and history is never touched. Where an occurrence goes is the user's stated time ("fixed") or a soft
preference; Build My Day / Replan (the deterministic planner) remain the only authority for flexible placement.
"""
import re
import uuid
from datetime import date, datetime, time, timedelta, timezone
from typing import Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from ..models.routine import Routine
from ..models.task import Task, TaskDifficulty, TaskPriority, TaskSource, TaskStatus, TaskType
from ..schemas.routine import RoutineCreate, RoutineProposal, RoutineUpdate

ROUTINE_HORIZON_DAYS = 7
ROW_KINDS = ("fixed", "preferred")          # kinds that become task rows
CONSTRAINT_KINDS = ("earliest", "avoid")    # kinds that only constrain Build My Day placement
_DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
_ABBR = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
_ACTIVITY_SYNONYMS = {"workout": "gym", "work out": "gym", "exercise": "gym", "training": "gym"}


# ── pure helpers ──────────────────────────────────────────────────────────────

def parse_weekdays(values) -> List[int]:
    out: List[int] = []
    for v in values or []:
        if isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 6:
            idx = v
        else:
            idx = _ABBR.get(str(v).strip().lower()[:3])
            if idx is None:
                continue
        if idx not in out:
            out.append(idx)
    return sorted(out)


def normalize_title(title: str) -> str:
    t = re.sub(r"[^a-z0-9 ]+", " ", (title or "").lower())
    t = re.sub(r"\b(session|class|time|the|my|a)\b", " ", t)
    t = " ".join(t.split())
    for k, v in _ACTIVITY_SYNONYMS.items():
        t = re.sub(rf"\b{k}\b", v, t)
    return t


def titles_match(a: str, b: str) -> bool:
    na, nb = normalize_title(a), normalize_title(b)
    return bool(na) and na == nb


def clock_label(hhmm: Optional[str]) -> str:
    if not hhmm:
        return ""
    h, m = int(hhmm[:2]), int(hhmm[3:5])
    return f"{h % 12 or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"


def summarize(kind: str, recurrence: str, weekdays: Optional[Sequence[int]], start: Optional[str],
              end: Optional[str]) -> str:
    if recurrence == "daily" or not weekdays:
        when = "Every day"
    elif sorted(weekdays) == [0, 1, 2, 3, 4]:
        when = "Weekdays"
    elif len(weekdays) == 1:
        when = f"Every {_DAY_NAMES[weekdays[0]]}"
    else:
        when = "Every " + ", ".join(_DAY_NAMES[d][:3] for d in sorted(weekdays))
    if kind == "avoid":
        return f"{when} · not between {clock_label(start)} and {clock_label(end)}"
    if kind == "earliest":
        return f"{when} · not before {clock_label(start)}"
    if kind == "preferred":
        return f"{when} · usually around {clock_label(start)}"
    return f"{when} · {clock_label(start)}" if start else when


def applies_on(r: Routine, day: date) -> bool:
    if day < r.effective_from or day.isoformat() in (r.skipped_dates or []):
        return False
    if r.recurrence == "weekly":
        return day.weekday() in (r.weekdays or [])
    return True


def horizon_dates(today: date, days: int = ROUTINE_HORIZON_DAYS) -> List[date]:
    return [today + timedelta(days=i) for i in range(days)]


def _local(day: date, hhmm: str, tz: ZoneInfo) -> datetime:
    return datetime.combine(day, time(int(hhmm[:2]), int(hhmm[3:5])), tzinfo=tz)


def preview_dates(kind: str, recurrence: str, weekdays: Optional[Sequence[int]], start: Optional[str],
                  today: date, now_local: datetime, tz: ZoneInfo) -> List[date]:
    """The dates a confirm would plan (bounded). A row-kind occurrence whose time already passed is not planned."""
    if kind not in ROW_KINDS:
        return []
    out = []
    for d in horizon_dates(today):
        if recurrence == "weekly" and d.weekday() not in (weekdays or []):
            continue
        if start and _local(d, start, tz) < now_local:
            continue
        out.append(d)
    return out


def make_proposal(*, title: str, kind: str, recurrence: str, weekdays, start: Optional[str], end: Optional[str],
                  task_type: str, category: str, minutes: int, candidate_id: Optional[str], today: date,
                  now_local: datetime, tz: ZoneInfo) -> RoutineProposal:
    wd = parse_weekdays(weekdays) if recurrence == "weekly" else None
    return RoutineProposal(
        proposal_id="rp_" + uuid.uuid4().hex[:12], candidate_id=candidate_id, title=title[:255], task_type=task_type,
        category=category, estimated_minutes=minutes, kind=kind, recurrence=recurrence, weekdays=wd,
        start_hhmm=start, end_hhmm=end, summary=summarize(kind, recurrence, wd, start, end),
        plan_dates=preview_dates(kind, recurrence, wd, start, today, now_local, tz),
    )


# ── persistence ───────────────────────────────────────────────────────────────

def active_routines(db: Session, user_id: str) -> List[Routine]:
    return (db.query(Routine).filter(Routine.user_id == user_id, Routine.deleted_at.is_(None))
            .order_by(Routine.created_at).all())


def _enum(cls, value, default):
    try:
        return cls(value)
    except ValueError:
        return default


def _new_occurrence(r: Routine, day: date, tz: ZoneInfo) -> Task:
    start = _local(day, r.start_hhmm, tz)
    end = start + timedelta(minutes=r.estimated_minutes)
    ttype = _enum(TaskType, r.task_type, TaskType.personal)
    return Task(
        user_id=r.user_id, title=r.title, category=r.category, task_type=ttype,
        difficulty=TaskDifficulty.physical if ttype == TaskType.physical else TaskDifficulty.medium,
        priority=TaskPriority.medium, estimated_minutes=r.estimated_minutes,
        scheduled_start=start, scheduled_end=end, source=TaskSource.manual,
        time_locked=(r.kind == "fixed"), planned_date=day, routine_id=r.id, routine_date=day,
        preferred_start=start if r.kind == "preferred" else None,
        duration_source="explicit", priority_source="inferred", focus_source="inferred",
    )


def materialize(db: Session, r: Routine, tz: ZoneInfo, now_local: datetime) -> List[date]:
    """Generate occurrences for the rolling horizon beyond ``materialized_through``. Idempotent."""
    if r.deleted_at is not None or r.kind not in ROW_KINDS or not r.start_hhmm:
        return []
    now = now_local.astimezone(tz)
    today = now.date()
    last = today + timedelta(days=ROUTINE_HORIZON_DAYS - 1)
    first = max(today, r.effective_from)
    if r.materialized_through is not None:
        first = max(first, r.materialized_through + timedelta(days=1))
    existing = {d for (d,) in db.query(Task.routine_date).filter(Task.routine_id == r.id).all()}
    made: List[date] = []
    d = first
    while d <= last:
        if applies_on(r, d) and d not in existing and _local(d, r.start_hhmm, tz) >= now:
            db.add(_new_occurrence(r, d, tz))
            made.append(d)
        d += timedelta(days=1)
    r.materialized_through = last
    db.flush()
    return made


def ensure_horizon(db: Session, user_id: str, tz: ZoneInfo, now_local: datetime) -> int:
    n = 0
    for r in active_routines(db, user_id):
        n += len(materialize(db, r, tz, now_local))
    return n


def create_routine(db: Session, user_id: str, body: RoutineCreate, tz: ZoneInfo, now_local: datetime
                   ) -> Tuple[Routine, List[date], bool]:
    """Returns (routine, planned_dates, replayed). A repeated idempotency key returns the same routine."""
    if body.idempotency_key:
        prior = db.query(Routine).filter(Routine.user_id == user_id,
                                         Routine.idempotency_key == body.idempotency_key).first()
        if prior is not None:
            return prior, [], True
    today = now_local.astimezone(tz).date()
    weekdays = parse_weekdays(body.weekdays) if body.recurrence == "weekly" else None
    if body.recurrence == "weekly" and not weekdays:
        raise ValueError("A weekly routine needs at least one weekday.")
    same = next((x for x in active_routines(db, user_id) if x.kind == body.kind and titles_match(x.title, body.title)), None)
    if same is not None:   # "Gym every day at 5 PM" when a Gym routine exists is an edit, never a second routine
        upd = RoutineUpdate(recurrence=body.recurrence, weekdays=weekdays, start_hhmm=body.start_hhmm,
                            end_hhmm=body.end_hhmm, estimated_minutes=body.estimated_minutes)
        return same, update_routine(db, same, upd, tz, now_local), False
    if body.kind in ("fixed", "preferred", "earliest") and not body.start_hhmm:
        raise ValueError("This routine needs a time.")
    if body.kind == "avoid" and not (body.start_hhmm and body.end_hhmm):
        raise ValueError("An unavailable window needs a start and an end.")
    r = Routine(
        user_id=user_id, title=body.title.strip(), task_type=body.task_type, category=body.category,
        estimated_minutes=body.estimated_minutes, kind=body.kind, recurrence=body.recurrence, weekdays=weekdays,
        start_hhmm=body.start_hhmm, end_hhmm=body.end_hhmm, effective_from=today, skipped_dates=[],
        idempotency_key=body.idempotency_key,
    )
    db.add(r)
    db.flush()
    return r, materialize(db, r, tz, now_local), False


def _future_open_occurrences(db: Session, r: Routine, tz: ZoneInfo, now_local: datetime) -> List[Task]:
    """Occurrences that have not started and are not in the past: the only rows an edit/delete may touch."""
    today = now_local.astimezone(tz).date()
    rows = db.query(Task).filter(Task.routine_id == r.id, Task.routine_date >= today,
                                 Task.status.in_([TaskStatus.todo, TaskStatus.postponed]),
                                 Task.started_at.is_(None)).all()
    now_utc = now_local.astimezone(timezone.utc)
    out = []
    for t in rows:
        st = t.scheduled_start
        if st is not None and st.tzinfo is None:
            st = st.replace(tzinfo=timezone.utc)
        if st is None or st > now_utc:
            out.append(t)
    return out


def update_routine(db: Session, r: Routine, body: RoutineUpdate, tz: ZoneInfo, now_local: datetime) -> List[date]:
    """Edit the template; future occurrences are re-generated, history (past/completed/skipped rows) is untouched."""
    data = body.model_dump(exclude_unset=True, exclude={"timezone", "current_local_time"})
    for k, v in data.items():
        if k == "weekdays":
            v = parse_weekdays(v)
        setattr(r, k, v)
    if r.recurrence == "daily":
        r.weekdays = None
    if r.recurrence == "weekly" and not r.weekdays:
        raise ValueError("A weekly routine needs at least one weekday.")
    for t in _future_open_occurrences(db, r, tz, now_local):
        db.delete(t)
    db.flush()
    r.materialized_through = None
    return materialize(db, r, tz, now_local)


def delete_routine(db: Session, r: Routine, tz: ZoneInfo, now_local: datetime) -> int:
    """Stop future occurrences; keep every past/completed occurrence."""
    removed = 0
    for t in _future_open_occurrences(db, r, tz, now_local):
        db.delete(t)
        removed += 1
    r.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return removed


def skip_day(db: Session, r: Routine, day: date) -> None:
    """One-day override: today's explicit request wins; the template (and every other day) stays as it was."""
    skipped = list(r.skipped_dates or [])
    if day.isoformat() not in skipped:
        skipped.append(day.isoformat())
        r.skipped_dates = skipped
    for t in db.query(Task).filter(Task.routine_id == r.id, Task.routine_date == day,
                                   Task.status.in_([TaskStatus.todo, TaskStatus.postponed]),
                                   Task.started_at.is_(None)).all():
        db.delete(t)
    db.flush()


# ── planner inputs ────────────────────────────────────────────────────────────

def _activity_matches(r: Routine, title: str, task_type: str) -> bool:
    na, nb = normalize_title(r.title), normalize_title(title)
    if na and nb and (na == nb or na in nb or nb in na):
        return True
    return na == "gym" and task_type == "physical"


def constraint_windows(routines: Sequence[Routine], title: str, task_type: str, day: date, tz: ZoneInfo
                       ) -> Dict[str, object]:
    """Routine constraints for an untimed dump task on ``day``: {"avoid": [(start,end)], "earliest": datetime|None}."""
    avoid: List[Tuple[datetime, datetime]] = []
    earliest: Optional[datetime] = None
    for r in routines:
        if r.kind not in CONSTRAINT_KINDS or not applies_on(r, day) or not _activity_matches(r, title, task_type):
            continue
        if r.kind == "avoid" and r.start_hhmm and r.end_hhmm:
            avoid.append((_local(day, r.start_hhmm, tz), _local(day, r.end_hhmm, tz)))
        elif r.kind == "earliest" and r.start_hhmm:
            e = _local(day, r.start_hhmm, tz)
            earliest = e if earliest is None or e > earliest else earliest
    return {"avoid": avoid, "earliest": earliest}


def matching_routine(routines: Sequence[Routine], title: str) -> Optional[Routine]:
    for r in routines:
        if r.kind in ROW_KINDS and titles_match(r.title, title):
            return r
    return None
