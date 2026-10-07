"""
Build My Day confirm: atomic, idempotent, server-validated batch creation (spec section 7).

Persistence and validation orchestration only. Slot validity/re-placement is decided by the
shared pure planner (``planning_service`` -> ``engines.planner.plan``); nothing here decides
where a task goes.
"""
from datetime import datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..core.timezone import owning_date, resolve_user_timezone
from ..engines.planner import K_LOCKED, PAST_TOLERANCE, PlanItem, PlanTemporal, plan
from ..engines.scheduling_engine import PlanningProfile
from ..models.task import Task
from ..models.user import User
from ..repositories.readiness_repository import ReadinessRepository
from ..repositories.task_repository import TaskRepository
from ..schemas.task import BatchCreateAndScheduleRequest, BatchCreateAndScheduleResponse, TaskResponse
from . import plan_applications, planning_service
from .planning_service import clock_label



def _validation_error(errors: List[Dict[str, Any]]) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail={"code": "validation_failed", "errors": errors},
    )


def _stored_replay(db: Session, user_id: str, plan_id: str) -> Optional[BatchCreateAndScheduleResponse]:
    data = plan_applications.load_stored(db, user_id, plan_id)
    return BatchCreateAndScheduleResponse(**data) if data is not None else None


def _validate_items(request: BatchCreateAndScheduleRequest, now: datetime, tz: ZoneInfo) -> List[Dict[str, Any]]:
    errors: List[Dict[str, Any]] = []
    for i, it in enumerate(request.tasks):
        base = {"index": i, "client_ref": it.client_ref, "title": it.title}
        for field in ("scheduled_start", "scheduled_end", "deadline_at"):
            v = getattr(it, field)
            if v is not None and v.tzinfo is None:
                errors.append({**base, "field": field, "code": "missing_timezone",
                               "message": f"“{it.title}” has a time without a timezone. Please choose the time again."})
        if errors and errors[-1]["index"] == i:
            continue
        start, end = it.scheduled_start, it.scheduled_end
        if it.time_locked and start is None:
            errors.append({**base, "field": "scheduled_start", "code": "locked_without_start",
                           "message": f"“{it.title}” is marked as fixed but has no time. Choose a time."})
            continue
        if start is not None and end is not None and end <= start:
            errors.append({**base, "field": "scheduled_end", "code": "invalid_range",
                           "message": f"“{it.title}” ends before it starts. Check the time."})
            continue
        eff_end = end or (start + timedelta(minutes=it.estimated_minutes) if start else None)
        # Only a hard deadline is a limit; a soft one is a target the planner may pass when necessary.
        # A commitment is a time window, not work due by a deadline: a stray deadline (the editor's "today") must
        # never reject a window that runs past midnight.
        if (not it.is_commitment and it.deadline_at is not None and it.deadline_kind != "soft"
                and eff_end is not None and it.deadline_at < eff_end):
            errors.append({**base, "field": "deadline_at", "code": "deadline_before_end",
                           "message": f"“{it.title}” would finish after its deadline. Choose an earlier time."})
            continue
        if it.time_locked and start is not None and start < now - PAST_TOLERANCE:
            errors.append({
                **base, "field": "scheduled_start", "code": "explicit_time_in_past",
                "requested_start": start.isoformat(),
                "message": f"“{it.title}” is set for {clock_label(start, tz)}, which has already passed. Choose a new time.",
            })
    return errors


def batch_create(db: Session, user: User, request: BatchCreateAndScheduleRequest) -> BatchCreateAndScheduleResponse:
    plan_id = request.plan_id or request.idempotency_key
    if plan_id:
        replay = _stored_replay(db, user.id, plan_id)
        if replay is not None:
            return replay

    if not request.tasks:
        return BatchCreateAndScheduleResponse(created_count=0, tasks=[], message="No tasks provided")

    tz, tz_name = resolve_user_timezone(user, request.timezone)
    if request.current_local_time is not None:
        now = request.current_local_time
        now = now.replace(tzinfo=tz) if now.tzinfo is None else now.astimezone(tz)
    else:
        now = datetime.now(tz)

    errors = _validate_items(request, now, tz)
    if errors:
        raise _validation_error(errors)

    # Plan input: this user's existing tasks are PINNED (never moved); batch items are validated
    # against them by the shared planner (valid proposed slots are kept, stale ones re-placed).
    today_start = datetime.combine(now.date(), time.min, tzinfo=tz).astimezone(timezone.utc)
    existing_rows = TaskRepository.list_for_planning(db, user.id, today_start)
    from dataclasses import replace as dc_replace

    existing_items = [dc_replace(planning_service.task_row_to_plan_item(t, tz=tz), pinned=True) for t in existing_rows]

    # Double-submit guard (clients without a plan_id): an item identical to an existing open task
    # (title + start + duration) is not re-created and is excluded from planning.
    dups: Dict[int, Task] = {}
    for i, it in enumerate(request.tasks):
        if it.scheduled_start is not None:
            found = TaskRepository.find_open_duplicate(db, user.id, it.title, it.scheduled_start, it.estimated_minutes)
            if found is not None:
                dups[i] = found

    # Sibling references (candidate_id / client_ref) -> this batch's plan-item ids.
    item_of_ref: Dict[str, str] = {}
    for i, it in enumerate(request.tasks):
        for ref in (it.candidate_id, it.client_ref):
            if ref:
                item_of_ref.setdefault(ref, f"item-{i}")

    batch_items: List[PlanItem] = []
    for i, it in enumerate(request.tasks):
        if i in dups:
            continue
        start = it.scheduled_start
        end = it.scheduled_end or (start + timedelta(minutes=it.estimated_minutes) if start else None)
        pref = (it.preferred_start, it.preferred_window_start, it.preferred_window_end)
        batch_items.append(PlanItem(
            id=f"item-{i}", title=it.title, estimated_minutes=it.estimated_minutes, status="todo",
            priority=it.priority.value, task_type=it.task_type.value,
            start=start, end=end, time_locked=bool(it.time_locked and start),
            is_commitment=bool(it.is_commitment and it.time_locked and start),
            deadline_at=it.deadline_at, planned_date=it.planned_date,
            temporal=PlanTemporal(preferred_start=pref[0], preferred_window_start=pref[1],
                                  preferred_window_end=pref[2]) if any(pref) else None,
            depends_on=tuple(item_of_ref[d] for d in (it.depends_on or [])
                             if d in item_of_ref and item_of_ref[d] != f"item-{i}"),
            focus_level=it.focus_level or "medium",
            deadline_kind=it.deadline_kind or "hard",
        ))

    profile = PlanningProfile.from_user_context(
        readiness_profile=ReadinessRepository().get_by_user_id(db, user.id),
        preferences=user.preferences,
    )
    result = plan(existing_items + batch_items, now_local=now, tz=tz, profile=profile, mode="replan",
                  scope_date=None, tz_name=tz_name)
    placed = {p.item_id: p for p in result.placements}
    unsched = {u.item_id: u for u in result.unscheduled}
    locked_ids = {i.item_id for i in result.immutable if i.kind == K_LOCKED}

    created: List[Task] = []
    adjustments: List[Dict[str, Any]] = []
    unscheduled_out: List[Dict[str, Any]] = []
    deduplicated: List[Optional[str]] = []
    try:
        for i, it in enumerate(request.tasks):
            if i in dups:
                created.append(dups[i])
                deduplicated.append(it.client_ref)
                continue
            item_id = f"item-{i}"
            start = end = None
            planned_date = it.planned_date
            if item_id in locked_ids:
                start = it.scheduled_start
                end = it.scheduled_end or start + timedelta(minutes=it.estimated_minutes)
            elif item_id in placed:
                p = placed[item_id]
                start, end = p.start, p.end
                if it.scheduled_start is not None and p.start != it.scheduled_start:
                    adjustments.append({
                        "client_ref": it.client_ref, "title": it.title,
                        "from": it.scheduled_start.isoformat(), "to": p.start.isoformat(),
                        "reason": "slot_no_longer_available",
                    })
            else:  # unscheduled by the planner: persisted without a slot, reported, never dropped
                u = unsched.get(item_id)
                if planned_date is None:
                    anchor = it.scheduled_start or now
                    planned_date = anchor.astimezone(tz).date()
                unscheduled_out.append({
                    "client_ref": it.client_ref, "title": it.title,
                    "reason": u.reason if u else "no_capacity", "message": u.message if u else "",
                })

            # Ownership: the persisted slot's local day, else the stated/anchored planned date.
            planned_date = owning_date(planned_date, start, tz) or now.astimezone(tz).date()
            task = Task(
                user_id=user.id, title=it.title, description=it.description, category=it.category,
                task_type=it.task_type, difficulty=it.difficulty, priority=it.priority,
                estimated_minutes=it.estimated_minutes, deadline_at=it.deadline_at,
                scheduled_start=start, scheduled_end=end, source=it.source,
                time_locked=bool(item_id in locked_ids), is_commitment=bool(it.is_commitment and item_id in locked_ids),
                planned_date=planned_date,
                focus_level=it.focus_level, deadline_kind=it.deadline_kind or ("hard" if it.deadline_at else None),
                priority_source=it.priority_source, duration_source=it.duration_source,
                focus_source=it.focus_source, preferred_start=it.preferred_start,
                preferred_window_start=it.preferred_window_start, preferred_window_end=it.preferred_window_end,
            )
            TaskRepository.add_no_commit(db, task)
            created.append(task)

        db.flush()
        # Dependencies: sibling references -> the persisted task ids of this batch.
        task_of_item = {f"item-{i}": t for i, t in enumerate(created)}
        for i, it in enumerate(request.tasks):
            if i in dups or not it.depends_on:
                continue
            ids = [task_of_item[item_of_ref[d]].id for d in it.depends_on
                   if d in item_of_ref and item_of_ref[d] != f"item-{i}"]
            created[i].depends_on = ids or None
        db.flush()
        response = BatchCreateAndScheduleResponse(
            created_count=len(created) - len(deduplicated),
            tasks=[TaskResponse.model_validate(t) for t in created],
            client_refs=[it.client_ref for it in request.tasks],
            message=f"Successfully created and scheduled {len(created) - len(deduplicated)} task"
                    f"{'s' if len(created) - len(deduplicated) != 1 else ''}.",
            adjustments=adjustments, unscheduled=unscheduled_out, deduplicated=deduplicated,
            conflicts=[{"code": c.code, "message": c.message,
                        "task_refs": [request.tasks[int(x.split('-')[1])].title for x in c.item_ids if x.startswith("item-")]}
                       for c in result.conflicts],
            timezone_used=tz_name,
        )
        if plan_id:
            plan_applications.stage(db, user.id, plan_id, "build", response.model_dump(mode="json"))
        db.commit()
        return response
    except IntegrityError:
        db.rollback()
        if plan_id:  # concurrent duplicate: the other request won; return its stored result
            replay = _stored_replay(db, user.id, plan_id)
            if replay is not None:
                return replay
        raise
    except Exception:
        db.rollback()
        raise
