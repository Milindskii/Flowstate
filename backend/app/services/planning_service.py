"""
Planning adapters (spec section 4).

This module is the ONLY bridge between persistence/API shapes and the pure planner in
``app.engines.planner``. It contains translation code only:

  * rows / AI candidates  ->  ``PlanItem``
  * ``PlanResult``        ->  response fields

No placement, ordering, bounds or conflict logic lives here; that is ``planner.plan()``.
Both Build My Day and Replan call the very same ``plan`` function through these helpers.
"""
import re
from dataclasses import replace
from datetime import date, datetime, time, timedelta
from typing import Any, Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from ..engines.planner import (
    K_LOCKED,
    PlanItem,
    PlanResult,
    PlanTemporal,
    plan,
)
from ..core.timezone import owning_date
from ..engines.scheduling_engine import PlanningProfile
from ..models.task import Task
from ..schemas.task import PlanningContext, TaskCandidateResponse, TemporalConstraints


def enum_value(v: Any) -> str:
    return str(getattr(v, "value", v))


def _aware(dt: Optional[datetime], tz: ZoneInfo) -> Optional[datetime]:
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=tz)


# ── rows -> PlanItem ─────────────────────────────────────────────────────────

def task_row_to_plan_item(t: Task, *, tz: ZoneInfo) -> PlanItem:
    start = _aware(t.scheduled_start, tz)
    end = _aware(t.scheduled_end, tz)
    return PlanItem(
        id=str(t.id),
        title=t.title,
        estimated_minutes=t.estimated_minutes or 45,
        status=enum_value(t.status),
        priority=enum_value(t.priority),
        task_type=enum_value(t.task_type),
        start=start,
        end=end,
        time_locked=bool(getattr(t, "time_locked", False)),
        is_commitment=bool(getattr(t, "is_commitment", False)),
        deadline_at=_aware(t.deadline_at, tz),
        planned_date=getattr(t, "planned_date", None),
        started_at=_aware(t.started_at, tz),
        completed_at=_aware(t.completed_at, tz),
        depends_on=tuple(str(d) for d in (getattr(t, "depends_on", None) or [])),
    )


# ── candidates -> PlanItem ───────────────────────────────────────────────────

def candidate_is_explicitly_fixed(c: TaskCandidateResponse) -> bool:
    """Lock source L1 (spec section 3): the user wrote an explicit clock time.

    Both extractors only populate ``scheduled_start`` for an explicit am/pm (or 24h) time
    and mark ``temporal.flexibility == "fixed"``. A bare 'at 6' / 'around 6 PM' becomes a
    *preferred* time and never reaches here. Inferred provenance never locks.
    """
    if c.scheduled_start is None:
        return False
    t = c.temporal
    if t is None or t.flexibility != "fixed":
        return False
    for key in ("fixed_start",):
        prov = t.provenance.get(key)
        if prov is not None and prov.source == "inferred":
            return False
    prov = (c.field_provenance or {}).get("scheduled_time")
    if prov is not None and prov.source == "inferred":
        return False
    return True


def _temporal(c: TaskCandidateResponse, tz: ZoneInfo) -> Optional[PlanTemporal]:
    t: Optional[TemporalConstraints] = c.temporal
    if t is None:
        return None
    return PlanTemporal(
        target_date=t.target_date,
        earliest_start=_aware(t.earliest_start, tz),
        latest_end=_aware(t.latest_end, tz),
        preferred_start=_aware(t.preferred_start, tz),
        preferred_window_start=_aware(t.preferred_window_start, tz),
        preferred_window_end=_aware(t.preferred_window_end, tz),
        relative_before=t.relative_before,
        relative_after=t.relative_after,
        avoid=tuple((_aware(a[0], tz), _aware(a[1], tz)) for a in (t.avoid or []) if len(a) == 2),
    )


def _apply_availability_windows(base: Optional[PlanTemporal], ctx: PlanningContext, tz: ZoneInfo, base_date: date) -> Optional[PlanTemporal]:
    """Office-hours style windows bound any task that has no bound of its own."""
    from datetime import time as _t

    earliest = base.earliest_start if base else None
    latest = base.latest_end if base else None
    for aw in ctx.availability_windows or []:
        if not (aw.start_time and aw.end_time and ":" in aw.start_time and ":" in aw.end_time):
            continue
        try:
            sh, sm = [int(p) for p in aw.start_time.split(":")[:2]]
            eh, em = [int(p) for p in aw.end_time.split(":")[:2]]
            d = aw.target_date or base_date
            if earliest is None:
                earliest = datetime.combine(d, _t(sh, sm), tzinfo=tz)
            if latest is None:
                latest = datetime.combine(d, _t(eh, em), tzinfo=tz)
        except ValueError:
            continue
    if earliest is None and latest is None:
        return base
    from dataclasses import replace

    return replace(base or PlanTemporal(), earliest_start=earliest, latest_end=latest)


def context_busy_intervals(ctx: Optional[PlanningContext], tz: ZoneInfo, base_date: date) -> List[Tuple[datetime, datetime]]:
    """Fixed events, travel and protected periods from the brain dump -> hard busy time."""
    from datetime import time as _t

    out: List[Tuple[datetime, datetime]] = []
    if ctx is None:
        return out

    def hhmm(v: Optional[str]) -> Optional[Tuple[int, int]]:
        if v and ":" in v:
            try:
                h, m = [int(p) for p in v.split(":")[:2]]
                return h, m
            except ValueError:
                return None
        return None

    for fe in ctx.fixed_events or []:
        st = hhmm(fe.start_time)
        if st:
            s = datetime.combine(fe.target_date or base_date, _t(*st), tzinfo=tz)
            en = hhmm(fe.end_time)
            if en:
                e = datetime.combine(fe.target_date or base_date, _t(*en), tzinfo=tz)
            else:
                e = s + timedelta(minutes=fe.duration_minutes or 45)
            if e > s:
                out.append((s, e))
    for tr in ctx.travel_segments or []:
        dp = hhmm(tr.departure_time)
        if dp:
            s = datetime.combine(tr.target_date or base_date, _t(*dp), tzinfo=tz)
            out.append((s, s + timedelta(minutes=tr.duration_minutes or 30)))
    for pp in ctx.protected_periods or []:
        ps = hhmm(pp.preferred_start)
        if ps:
            s = datetime.combine(pp.target_date or base_date, _t(*ps), tzinfo=tz)
            out.append((s, s + timedelta(minutes=pp.duration_minutes or 45)))
    return out


def _clock_in_text(text: str, hh: int, mm: int) -> bool:
    """Did the user actually write this clock time? (L2 provenance: a model-invented time is never persisted.)"""
    t = text.lower()
    h12 = hh % 12 or 12
    if mm:
        return bool(re.search(rf"(?<!\d){h12}[:.]{mm:02d}(?!\d)|(?<!\d){hh:02d}:{mm:02d}(?!\d)", t))
    return bool(re.search(rf"(?<!\d){h12}\s*(?:am|pm)\b|(?<!\d){h12}:00(?!\d)|(?<!\d){hh:02d}:00(?!\d)", t))


def commitments_from_context(
    candidates: List[TaskCandidateResponse],
    ctx: Optional[PlanningContext],
    raw_text: str,
    *,
    tz: ZoneInfo,
    base_date: date,
    now_local: datetime,
) -> List[TaskCandidateResponse]:
    """Turn stated "I'm out 6:30 to 8:30" blocks into locked commitment candidates, so they are saved.

    Only events with a start and an end whose start time the user really wrote are converted; one already listed
    as a task at that time is not duplicated. Converted events leave ``ctx.fixed_events`` (they are busy time as
    locked items now, not twice). Returns the new candidates (already appended to ``candidates``).
    """
    from datetime import time as _t

    from ..schemas.task import FieldProvenance

    if ctx is None or not ctx.fixed_events:
        return []
    added: List[TaskCandidateResponse] = []
    remaining = []
    for fe in ctx.fixed_events:
        st = fe.start_time.split(":") if fe.start_time and ":" in fe.start_time else None
        en = fe.end_time.split(":") if fe.end_time and ":" in fe.end_time else None
        if not st or not en:
            remaining.append(fe)
            continue
        try:
            sh, sm, eh, em = int(st[0]), int(st[1]), int(en[0]), int(en[1])
        except ValueError:
            remaining.append(fe)
            continue
        day = fe.target_date or base_date
        start = datetime.combine(day, _t(sh, sm), tzinfo=tz)
        end = datetime.combine(day, _t(eh, em), tzinfo=tz)
        if end <= start or end <= now_local or not _clock_in_text(raw_text, sh, sm):
            remaining.append(fe)
            continue
        if any(c.scheduled_start is not None and _aware(c.scheduled_start, tz) == start for c in candidates):
            remaining.append(fe)
            continue
        prov = FieldProvenance(source="explicit", confidence=1.0)
        cand = TaskCandidateResponse(
            title=fe.title or "Fixed commitment", category="Personal", task_type="personal",
            estimated_minutes=int((end - start).total_seconds() // 60), priority="medium",
            scheduled_start=start, scheduled_end=end, time_locked=True, is_commitment=True, planned_date=day,
            source="ai_parsed", focus_level="low", duration_source="explicit", priority_source="inferred",
            temporal=TemporalConstraints(target_date=day, fixed_start=start, flexibility="fixed",
                                         provenance={"fixed_start": prov}),
            field_provenance={"title": FieldProvenance(source="gemini", confidence=0.9), "scheduled_time": prov,
                              "duration": prov},
        )
        candidates.append(cand)
        added.append(cand)
    ctx.fixed_events = remaining
    return added


def candidates_to_plan_items(
    candidates: Sequence[TaskCandidateResponse],
    ctx: Optional[PlanningContext],
    *,
    tz: ZoneInfo,
    base_date: date,
) -> Tuple[List[PlanItem], List[str]]:
    """Returns (items, ids) where ids[i] is the plan-item id of candidates[i]."""
    ids = [c.candidate_id for c in candidates]
    deferred = [d.lower() for d in (ctx.deferred_tasks if ctx else []) or []]
    priority_order = [p.lower() for p in (ctx.priority_order if ctx else []) or []]
    dep_pairs = [(d.predecessor.lower(), d.successor.lower()) for d in (ctx.task_dependencies if ctx else []) or []]

    items: List[PlanItem] = []
    for i, c in enumerate(candidates):
        title_l = c.title.lower()
        priority = enum_value(c.priority)
        if any(d in title_l for d in deferred):
            priority = "low"
        locked = candidate_is_explicitly_fixed(c)
        start = _aware(c.scheduled_start, tz) if locked else None
        end = _aware(c.scheduled_end, tz) if (locked and c.scheduled_end) else None
        temporal = _temporal(c, tz)
        if ctx is not None:
            temporal = _apply_availability_windows(temporal, ctx, tz, base_date)

        rank = next((n for n, p in enumerate(priority_order) if p in title_l), None)
        deps: List[str] = [d for d in c.depends_on if d in ids and d != ids[i]]
        for pred, succ in dep_pairs:
            if succ in title_l:
                for j, other in enumerate(candidates):
                    if j != i and pred in other.title.lower() and ids[j] not in deps:
                        deps.append(ids[j])
                        break
        items.append(
            PlanItem(
                id=ids[i],
                title=c.title,
                estimated_minutes=c.estimated_minutes or 45,
                status="todo",
                priority=priority,
                task_type=enum_value(c.task_type),
                start=start,
                end=end,
                time_locked=locked,
                is_commitment=bool(locked and c.is_commitment),
                deadline_at=_aware(c.deadline_at, tz),
                temporal=temporal,
                is_new=True,
                depends_on=tuple(deps),
                rank=rank,
                focus_level=c.focus_level or "medium",
                deadline_kind=c.deadline_kind or "hard",
            )
        )
    return items, ids


# ── PlanResult -> response fields ────────────────────────────────────────────

def _day_label(slot_start: datetime, today: date, tz: ZoneInfo) -> str:
    d = slot_start.astimezone(tz).date()
    off = (d - today).days
    if off == 0:
        return "Today"
    if off == 1:
        return "Tomorrow"
    return slot_start.astimezone(tz).strftime("%A")


def clock_label(slot_start: datetime, tz: ZoneInfo) -> str:
    """Local wall-clock time as shown to users, e.g. '6:00 PM'."""
    return slot_start.astimezone(tz).strftime("%I:%M %p").lstrip("0")


def _set_slot(c: TaskCandidateResponse, start: datetime, end: datetime, *, tz: ZoneInfo, today: date,
              explanation: str, primary: str, secondary: Sequence[str]) -> None:
    c.recommended_slot_start = start
    c.recommended_slot_end = end
    c.recommended_slot_date = start.astimezone(tz).date().isoformat()
    c.recommended_slot_display = f"{_day_label(start, today, tz)} · {clock_label(start, tz)}"
    c.scheduling_explanation = explanation
    c.scheduling_reasons = {"primary_reason": primary, "secondary_reasons": list(secondary)}


def apply_result_to_candidates(
    candidates: Sequence[TaskCandidateResponse],
    ids: Sequence[str],
    result: PlanResult,
    *,
    tz: ZoneInfo,
    now_local: datetime,
) -> List[Dict[str, Any]]:
    """Write the plan result onto candidates; return API-shaped conflict dicts."""
    today = now_local.astimezone(tz).date()
    by_id = {cid: c for cid, c in zip(ids, candidates)}
    for p in result.placements:
        c = by_id[p.item_id]
        _set_slot(c, p.start, p.end, tz=tz, today=today, explanation=p.explanation,
                  primary=p.primary_reason, secondary=p.secondary_reasons)
        if "soft_deadline_exceeded" in p.secondary_reasons:
            c.scheduling_reasons["soft_deadline_exceeded"] = True
            c.scheduling_explanation = (
                f"{p.explanation} There was no free time before your target "
                f"({_day_label(c.deadline_at, today, tz)} · {clock_label(c.deadline_at, tz)}), so it runs past it."
            )
    for im in result.immutable:
        c = by_id.get(im.item_id)
        if c is not None and im.kind == K_LOCKED and im.start and im.end:
            c.time_locked = True
            _set_slot(c, im.start, im.end, tz=tz, today=today,
                      explanation=f"Scheduled at your requested time ({clock_label(im.start, tz)}).",
                      primary="explicit_time", secondary=["user_specified_time"])
    for u in result.unscheduled:
        c = by_id[u.item_id]
        c.unscheduled_reason = u.reason
        if u.reason == "explicit_time_in_past":
            when = clock_label(c.scheduled_start, tz) if c.scheduled_start else "that time"
            msg = f"“{c.title}” is set for {when}, which has already passed. Choose a new time."
        else:
            msg = u.message
        c.validation_issues = list(c.validation_issues) + [{"code": u.reason, "field": "scheduled_start", "message": msg}]
        if u.suggestion is not None:
            c.suggested_slot_start = u.suggestion.start
            c.suggested_slot_end = u.suggestion.end
            c.suggested_slot_display = f"{_day_label(u.suggestion.start, today, tz)} · {clock_label(u.suggestion.start, tz)}"
    # Every candidate carries an explicit owning day, so the confirm request persists it unchanged:
    # the slot's local day, else the date the user stated, else today.
    for c in candidates:
        slot = c.recommended_slot_start or c.scheduled_start
        c.planned_date = owning_date(c.target_date, slot, tz) or today
    return [{"code": cf.code, "message": cf.message, "task_refs": [by_id[i].title for i in cf.item_ids if i in by_id]}
            for cf in result.conflicts]


def schedule_candidates(
    candidates: List[TaskCandidateResponse],
    ctx: Optional[PlanningContext],
    existing_tasks: Sequence[Task],
    *,
    profile: PlanningProfile,
    tz: ZoneInfo,
    tz_name: str,
    now_local: datetime,
    routines: Optional[Sequence[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    """Build My Day: one call into the shared planner. Returns conflict dicts.

    ``routines`` (engines/behavior_patterns.weekly_routines) are suggestions only: a candidate with NO stated time,
    window or bound that matches a learned weekly habit gets a soft preferred window around the usual time. Any
    user-stated timing wins, and the planner still treats the window as a preference, never a constraint.

    Raises PlanInvariantError / ValueError on planner bugs; the caller reports them
    (never swallowed silently).
    """
    base_date = now_local.astimezone(tz).date()
    for c in candidates:
        if c.temporal and c.temporal.target_date:
            base_date = c.temporal.target_date
            break

    cand_items, ids = candidates_to_plan_items(candidates, ctx, tz=tz, base_date=base_date)
    hinted = _apply_learned_routines(cand_items, routines or [], tz=tz, base_date=base_date)
    existing_items = [task_row_to_plan_item(t, tz=tz) for t in existing_tasks]
    extra_busy = context_busy_intervals(ctx, tz, base_date)

    if ctx is not None and ctx.energy_preference == "morning_heavy":
        from copy import copy

        profile = copy(profile)
        profile.preferred_peak_start = 8.5
        profile.preferred_peak_end = 12.5

    extra_buf = 5 if (ctx is not None and ctx.buffer_preference == "spacious") else 0
    result = plan(
        existing_items + cand_items,
        now_local=now_local.astimezone(tz),
        tz=tz,
        profile=profile,
        mode="build",
        extra_busy=extra_busy,
        extra_buffer_minutes=extra_buf,
        tz_name=tz_name,
    )
    conflicts = apply_result_to_candidates(candidates, ids, result, tz=tz, now_local=now_local)
    for c in candidates:
        if c.candidate_id in hinted:
            c.learned_hint = hinted[c.candidate_id]
    return conflicts


def _apply_learned_routines(items: List[PlanItem], routines: Sequence[Dict[str, Any]], *, tz: ZoneInfo,
                            base_date: date) -> Dict[str, str]:
    """Soft preferred window (+/- 30 min) for untimed new items matching a learned weekly routine, in place.
    Returns {item id: hint}. An item with any stated time, bound, window or lock is never touched."""
    from ..engines.behavior_patterns import routine_for

    hinted: Dict[str, str] = {}
    if not routines:
        return hinted
    for n, it in enumerate(items):
        t = it.temporal
        stated = it.time_locked or it.start is not None or (t is not None and any(
            (t.earliest_start, t.latest_end, t.preferred_start, t.preferred_window_start, t.preferred_window_end)))
        if not it.is_new or stated:
            continue
        day = (t.target_date if t is not None and t.target_date else None) or base_date
        r = routine_for(routines, it.title, day.weekday())
        if r is None:
            continue
        centre = datetime.combine(day, time(0, 0), tzinfo=tz) + timedelta(minutes=r["start_minutes"])
        base_t = t or PlanTemporal()
        items[n] = replace(it, temporal=replace(base_t, preferred_window_start=centre - timedelta(minutes=30),
                                                preferred_window_end=centre + timedelta(minutes=30) + timedelta(
                                                    minutes=it.estimated_minutes)))
        hinted[it.id] = f"Usually {r['weekday']} {r['start_label']}"
    return hinted


# ── single-task placement (Today "Later" / "Do this now") ────────────────────

def place_single_task(
    task: Task,
    other_tasks: Sequence[Task],
    *,
    profile: PlanningProfile,
    tz: ZoneInfo,
    tz_name: str,
    now_local: datetime,
    earliest_start: Optional[datetime] = None,
    proposed_start: Optional[datetime] = None,
):
    """Find a slot for ONE task via the shared planner; ``None`` when no valid slot exists.

    Every other task is pinned (never moved), so the result can never overlap them, start in the past,
    or finish after the task's deadline: those are the planner's invariants, not re-implemented here.

    * ``earliest_start``: hard lower bound ("Later": not before the suggested window).
    * ``proposed_start``: a slot the user asked for ("Do this now"); kept if valid, else the nearest
      valid slot is used.
    Only open tasks (todo/postponed) can be moved; anything else returns ``None``.
    """
    from dataclasses import replace

    # The user asked to move this task, so its old planned day is not a constraint; the caller
    # re-derives planned_date from the new slot.
    item = replace(task_row_to_plan_item(task, tz=tz), planned_date=None)
    if item.status not in ("todo", "postponed"):
        return None
    temporal = PlanTemporal(earliest_start=earliest_start) if earliest_start is not None else None
    if proposed_start is not None:
        item = replace(
            item, origin_start=item.start, start=proposed_start,
            end=proposed_start + timedelta(minutes=item.estimated_minutes), time_locked=False, temporal=temporal,
        )
    else:
        item = replace(item, origin_start=item.start, start=None, end=None, time_locked=False,
                       force_replace=True, temporal=temporal)
    pinned = [replace(task_row_to_plan_item(t, tz=tz), pinned=True) for t in other_tasks if str(t.id) != item.id]
    result = plan(pinned + [item], now_local=now_local.astimezone(tz), tz=tz, profile=profile,
                  mode="replan", tz_name=tz_name)
    return next((p for p in result.placements if p.item_id == item.id), None)


def describe_slot(start: datetime, tz: ZoneInfo, now_local: datetime) -> Dict[str, str]:
    """``{label, suggested_date, suggested_time}`` for a placed slot (Today's "next good window" card)."""
    local = start.astimezone(tz)
    today = now_local.astimezone(tz).date()
    return {
        "label": f"{_day_label(start, today, tz)} \u00b7 {clock_label(start, tz)}",
        "suggested_date": local.date().isoformat(),
        "suggested_time": local.strftime("%H:%M"),
    }
