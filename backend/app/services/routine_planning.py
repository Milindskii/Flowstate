"""
Build My Day <-> routines glue. Gemini only INTERPRETS the dump (recurrence words, times, windows); this module turns
that into routine proposals (confirmed by the user before anything is saved) and into planner inputs. Where a flexible
task finally goes is decided by the deterministic planner alone.
"""
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from ..models.routine import Routine
from ..schemas.routine import RoutineProposal
from ..schemas.task import FixedEventContext, PlanningContext, TaskCandidateResponse, TemporalConstraints
from . import routine_service as rs
from .planning_service import _aware, candidate_is_explicitly_fixed


def _hhmm(dt: datetime, tz: ZoneInfo) -> str:
    return dt.astimezone(tz).strftime("%H:%M")


def _candidate_time(c: TaskCandidateResponse, tz: ZoneInfo) -> Tuple[Optional[str], Optional[str]]:
    """(kind, hh:mm) the user actually stated for a recurring candidate, or (None, None): a time is never invented."""
    if candidate_is_explicitly_fixed(c) and c.scheduled_start is not None:
        return "fixed", _hhmm(_aware(c.scheduled_start, tz), tz)
    t: Optional[TemporalConstraints] = c.temporal
    pref = c.preferred_start or (t.preferred_start if t else None)
    if pref is not None:
        return "preferred", _hhmm(_aware(pref, tz), tz)
    if t is not None and t.earliest_start is not None:
        prov = t.provenance.get("earliest_start")
        if prov is None or prov.source == "explicit":
            return "earliest", _hhmm(_aware(t.earliest_start, tz), tz)
    return None, None


def _same_routine(r: Routine, p: RoutineProposal) -> bool:
    return (rs.titles_match(r.title, p.title) and r.kind == p.kind and r.start_hhmm == p.start_hhmm
            and r.end_hhmm == p.end_hhmm and r.recurrence == p.recurrence
            and sorted(r.weekdays or []) == sorted(p.weekdays or []))


def extract_proposals(
    candidates: List[TaskCandidateResponse],
    ctx: Optional[PlanningContext],
    existing: Sequence[Routine],
    *,
    today: date,
    now_local: datetime,
    tz: ZoneInfo,
) -> Tuple[List[TaskCandidateResponse], List[RoutineProposal]]:
    """Split the dump into (one-time candidates, routine proposals). A recurring candidate leaves the task list: the
    routine replaces it, so the same activity is never created twice. A routine already saved produces no proposal."""
    kept: List[TaskCandidateResponse] = []
    proposals: List[RoutineProposal] = []
    for c in candidates:
        if c.recurrence is None:
            kept.append(c)
            continue
        kind, start = _candidate_time(c, tz)
        if kind is None:   # "I go to the gym every day": no stated time -> stays an ordinary task, nothing invented
            kept.append(c)
            continue
        prop = rs.make_proposal(
            title=c.title, kind=kind, recurrence=c.recurrence, weekdays=c.recurrence_weekdays, start=start, end=None,
            task_type=c.task_type.value if hasattr(c.task_type, "value") else str(c.task_type), category=c.category,
            minutes=c.estimated_minutes or 45, candidate_id=c.candidate_id, today=today, now_local=now_local, tz=tz)
        if c.recurrence == "weekly" and not prop.weekdays:
            kept.append(c)   # "every week" without a day: ask nothing, invent nothing
            continue
        if not any(_same_routine(r, prop) for r in existing):
            proposals.append(prop)
    for aw in (ctx.avoid_windows if ctx else []) or []:
        if not aw.recurring:
            continue
        prop = rs.make_proposal(
            title=aw.activity, kind="avoid", recurrence="daily", weekdays=None, start=aw.start_time, end=aw.end_time,
            task_type="personal", category="General", minutes=45, candidate_id=None, today=today,
            now_local=now_local, tz=tz)
        if not any(_same_routine(r, prop) for r in existing):
            proposals.append(prop)
    return kept, proposals


def planning_context_with_routine_busy(
    ctx: Optional[PlanningContext], proposals: Sequence[RoutineProposal], tz: ZoneInfo
) -> PlanningContext:
    """A COPY of the dump context in which each proposed routine's occurrences are busy time, so other work is arranged
    around them even before the user confirms (the shown plan matches what confirming produces)."""
    plan_ctx = ctx.model_copy(deep=True) if ctx is not None else PlanningContext()
    for p in proposals:
        if p.kind not in rs.ROW_KINDS or not p.start_hhmm:
            continue
        for d in p.plan_dates:
            start = datetime.combine(d, datetime.strptime(p.start_hhmm, "%H:%M").time())
            end = start + timedelta(minutes=p.estimated_minutes)
            plan_ctx.fixed_events.append(FixedEventContext(
                title=p.title, start_time=start.strftime("%H:%M"), end_time=end.strftime("%H:%M"),
                duration_minutes=p.estimated_minutes, target_date=d))
    return plan_ctx


def _transient(title: str, kind: str, start: Optional[str], end: Optional[str], today: date) -> Routine:
    return Routine(title=title, kind=kind, recurrence="daily", start_hhmm=start, end_hhmm=end, effective_from=today,
                   skipped_dates=[], estimated_minutes=45, task_type="personal", category="General")


def apply_constraints(
    candidates: Sequence[TaskCandidateResponse],
    ctx: Optional[PlanningContext],
    routines: Sequence[Routine],
    *,
    today: date,
    tz: ZoneInfo,
) -> None:
    """Routine earliest/avoid constraints (saved ones, plus an avoid window stated in this dump) onto untimed tasks.

    The user's own explicit bound on a task always wins; an explicit fixed time is never touched."""
    pool: List[Routine] = [r for r in routines if r.kind in rs.CONSTRAINT_KINDS]
    for aw in (ctx.avoid_windows if ctx else []) or []:
        pool.append(_transient(aw.activity, "avoid", aw.start_time, aw.end_time, today))
    if not pool:
        return
    for c in candidates:
        if candidate_is_explicitly_fixed(c):
            continue
        ttype = c.task_type.value if hasattr(c.task_type, "value") else str(c.task_type)
        t = c.temporal or TemporalConstraints()
        base_day = t.target_date or today
        avoid: List[List[datetime]] = list(t.avoid or [])
        for d in rs.horizon_dates(base_day):
            w = rs.constraint_windows(pool, c.title, ttype, d, tz)
            avoid.extend([[a, b] for a, b in w["avoid"]])
            if d == base_day and w["earliest"] is not None and t.earliest_start is None:
                t.earliest_start = w["earliest"]
                t.provenance["earliest_start"] = _provenance("routine")
        if avoid != list(t.avoid or []):
            t.avoid = avoid
        if avoid or t.earliest_start is not None:
            c.temporal = t


def _provenance(source: str):
    from ..schemas.task import FieldProvenance
    return FieldProvenance(source=source, confidence=1.0)


def mark_overrides(
    candidates: Sequence[TaskCandidateResponse], routines: Sequence[Routine], *, tz: ZoneInfo, today: date
) -> Dict[Tuple[str, date], bool]:
    """An explicit one-time request ("Today I have gym at 6 PM") overrides that day's routine occurrence only.

    Returns {(routine_id, day): True} so the caller can keep the replaced occurrence out of this plan."""
    overridden: Dict[Tuple[str, date], bool] = {}
    for c in candidates:
        if c.recurrence is not None or not candidate_is_explicitly_fixed(c) or c.scheduled_start is None:
            continue
        r = rs.matching_routine(routines, c.title)
        if r is None:
            continue
        day = _aware(c.scheduled_start, tz).astimezone(tz).date()
        if rs.applies_on(r, day):
            c.routine_override_id, c.routine_override_date = r.id, day
            overridden[(r.id, day)] = True
    return overridden
