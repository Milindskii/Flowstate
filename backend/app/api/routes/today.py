"""
Flowstate — Today Aggregated Endpoint
=======================================
Single source of truth for the Today page.

Returns:
- User context + local date
- Lifecycle state (new_user | learning | calibrated)
- Real readiness score from ReadinessEngineV2 (no hardcoded values)
- Scored recommendation from GenericRecommendationEngine (all candidates logged)
- Time-aware AI brief (no hardcoded "15 minutes")
- Workload calculation
- Active task
- Upcoming timeline from scheduling engine
- decision_id for outcome tracking
"""

from typing import List, Optional
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.config import settings
from ...core.logging import logger
from ...core.timezone import owning_date, resolve_user_timezone
from ...engines.scheduling_engine import PlanningProfile
from ...repositories.task_repository import TaskRepository
from ...services.task_state import slot_has_ended, task_slot_elapsed
from ...services import planning_service
from ...models.user import User
from ...models.task import Task, TaskStatus
from ...models.task_deviation import TaskDeviation
from ...models.task_performance import TaskPerformance
from ...models.recommendation import RecommendationDecision, RecommendationOutcome
from ...schemas.today import (
    TodayResponse,
    TodayUserContext,
    ReadinessDetail,
    CurrentRecommendation,
    AIBrief,
    WorkloadSummary,
    ScheduleItemResponse,
    CalendarContext,
    TomorrowTaskResponse,
)
from ...schemas.task import TaskResponse
from ...services.task_service import TaskService
from ...engines.readiness_engine import ReadinessEngineV2
from ...engines.recommendation_engine import (
    GenericRecommendationEngine,
    PersonalizedRecommendationEngine,
)
from ...repositories.readiness_repository import ReadinessRepository
from ...repositories.recommendation_repository import RecommendationRepository

router = APIRouter(prefix="/today", tags=["Today Experience"])
task_service = TaskService()
readiness_repo = ReadinessRepository()
rec_repo = RecommendationRepository()


# ── Override & replan ─────────────────────────────────────────────────────────

class OverrideRequest(BaseModel):
    decision_id: str
    chosen_task_id: Optional[str] = None
    reason: Optional[str] = None  # wrong_timing | too_tired | something_more_important |
                                  # too_difficult | deadline_changed | dont_feel_like_it | other | later
    timezone: Optional[str] = None  # IANA zone of the device; falls back to the stored preference

class OverrideResponse(BaseModel):
    recorded: bool
    next_window: Optional[dict] = None   # {"label": "Tomorrow · 9:30 AM", "suggested_date": ..., "suggested_time": ...}
    message: str


class SkipTaskRequest(BaseModel):
    timezone: Optional[str] = None  # IANA zone of the device; falls back to the stored preference


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _time_aware_greeting(hour: int) -> str:
    if hour < 12:
        return "Good morning"
    elif hour < 17:
        return "Good afternoon"
    return "Good evening"


def _minutes_until(dt: datetime, now_local: datetime) -> Optional[int]:
    """Returns minutes until a datetime, or None if in the past."""
    delta = (dt - now_local).total_seconds() / 60.0
    return int(delta) if delta > 0 else None


NEXT_UP_GRACE = timedelta(minutes=15)


def _actionable_now(tasks: List[Task], now_utc: datetime) -> List[Task]:
    """Tasks that may lead "do this now": in progress, unslotted, in their slot, or about to start.

    A task whose slot already ended unstarted is MISSED: it stays in the timeline and is recovered through
    Replan/Redo, but never dominates the top. If nothing is actionable, the next upcoming slot is offered.
    """
    live: List[Task] = []
    upcoming: List[Task] = []
    for t in tasks:
        if t.is_commitment:
            continue  # a fixed block, not work: never "do this now" / up next
        start = _make_aware(t.scheduled_start)
        if t.status == TaskStatus.in_progress or start is None:
            live.append(t)
            continue
        end = _make_aware(t.scheduled_end) or start + timedelta(minutes=t.estimated_minutes)
        if slot_has_ended(end, now_utc):
            continue
        (live if start <= now_utc + NEXT_UP_GRACE else upcoming).append(t)
    if live:
        return live
    return sorted(upcoming, key=lambda t: _make_aware(t.scheduled_start))[:1]


def _note_origin(db: Session, user: User, task: Task, now_utc: datetime, user_tz, *, skipped: bool = False) -> None:
    """Before a task leaves its slot on the user's request, keep that slot as history (once).

    Skipped by choice -> "skipped"; slot already passed -> "missed". Added to the caller's transaction.
    """
    from ...services.calendar_service import CalendarService

    start = _make_aware(task.scheduled_start)
    if start is None:
        return
    kind = "skipped" if skipped else ("missed" if CalendarService._slot_missed(task, now_utc) else None)
    if kind is None or CalendarService._deviation_recorded(db, [], str(task.id), kind, task.scheduled_start):
        return
    db.add(TaskDeviation(
        user_id=user.id, task_id=str(task.id), deviation_date=start.astimezone(user_tz).date(), kind=kind,
        original_start=task.scheduled_start, original_end=task.scheduled_end))


# ── Primary endpoint ──────────────────────────────────────────────────────────

@router.get("", response_model=TodayResponse)
def get_today_experience(
    timezone_name: Optional[str] = Query(None, alias="timezone", description="IANA zone of the device; falls back to the stored preference"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Aggregated Today endpoint — single source of truth for the Today page.

    Key invariants:
    - All readiness values come from ReadinessEngineV2 (never hardcoded)
    - All task recommendations come from GenericRecommendationEngine (scored, logged)
    - AI brief is time-aware (based on real current time, not hardcoded phrases)
    - A RecommendationDecision is written for every recommendation made
    - Returns decision_id so Flutter can track accept/override/later
    """
    now_utc = datetime.now(timezone.utc)
    user_tz, user_tz_str = resolve_user_timezone(current_user, timezone_name)

    today_tasks: List[Task] = task_service.list_today_tasks(db, current_user, user_tz_str)
    completed_count: int = sum(1 for t in today_tasks if t.status == TaskStatus.completed)
    has_actionable_tasks: bool = len(today_tasks) > 0
    active_or_pending: List[Task] = [
        t for t in today_tasks
        if t.status not in (TaskStatus.completed, TaskStatus.cancelled, TaskStatus.archived)
    ]
    total_sessions: int = (
        db.query(TaskPerformance)
        .filter(TaskPerformance.user_id == current_user.id)
        .count()
    )

    # ── 1. Lifecycle state ─────────────────────────────────────────────────
    if has_actionable_tasks and len(active_or_pending) == 0:
        lifecycle_state = "completed"
    elif len(today_tasks) == 0 and total_sessions == 0:
        lifecycle_state = "new_user"
    elif total_sessions < settings.CALIBRATION_MIN_SESSIONS:
        lifecycle_state = "learning"
    else:
        lifecycle_state = "calibrated"

    # ── 2. Real Readiness (ReadinessEngineV2) ─────────────────────────────
    now_local = datetime.now(user_tz)

    readiness_profile = readiness_repo.get_profile(db, current_user.id)
    observations = readiness_repo.list_observations(db, current_user.id, limit=200)

    if lifecycle_state == "new_user":
        # No data yet — placeholder, honest about it
        readiness = ReadinessDetail(
            score=None,
            max_score=100,
            confidence=0.0,
            model_version=settings.READINESS_MODEL_VERSION,
            status_message="Learning your rhythm",
            focus_window_range=(
                f"{readiness_profile.preferred_peak_start} – {readiness_profile.preferred_peak_end}"
                if readiness_profile else "9:30 AM – 11:45 AM"
            ),
            explanation="Flowstate is learning your rhythm. Complete a few sessions to get personalised insights.",
            is_calibrated=False,
            factors=["Waiting for your first session"],
            hourly_rhythm=[],
        )
        readiness_score_float = 0.60  # neutral default for engine scoring
    else:
        engine = ReadinessEngineV2()
        result = engine.evaluate_readiness(
            profile=readiness_profile,
            observations=observations,
            task_type="deep_work",      # use deep_work as the baseline for the readiness display
            task_difficulty="medium",
            target_time=now_utc,
        )

        readiness_score_float = result["readiness_score"] / 100.0

        # Determine status message from recommendation band
        band = result.get("recommendation_band", "reasonable_fit")
        if band == "strong_fit":
            status_msg = "Good time for focused work"
        elif band == "light_work_preferred":
            status_msg = "Energy is lower right now — consider lighter tasks"
        elif band == "insufficient_confidence":
            status_msg = "Still learning your rhythm"
        else:
            status_msg = "Reasonable time to work"

        readiness = ReadinessDetail(
            score=result["readiness_score"],
            max_score=100,
            confidence=result["confidence"],
            model_version=result["model_version"],
            status_message=status_msg,
            focus_window_range=result["focus_window_range"],
            explanation=result["explanation"],
            is_calibrated=(lifecycle_state == "calibrated"),
            factors=result["top_factors"][:3],
            hourly_rhythm=result["hourly_rhythm"],
        )

    # ── 3. Pending + Active tasks ──────────────────────────────────────────
    active_task: Optional[Task] = None
    pending_tasks: List[Task] = []
    for t in today_tasks:
        if t.status == TaskStatus.in_progress and active_task is None:
            active_task = t
        if t.status not in (TaskStatus.completed, TaskStatus.cancelled, TaskStatus.archived) and not t.is_commitment:
            pending_tasks.append(t)

    # Remaining (actionable) workload excludes tasks whose slot already ended unstarted: they are MISSED, recovered
    # through Redo/Replan, and their minutes are reported apart (missed_minutes) for history/analytics.
    missed_tasks = [t for t in pending_tasks if task_slot_elapsed(t, now_utc)]
    missed_ids = {id(t) for t in missed_tasks}
    remaining_tasks = [t for t in pending_tasks if id(t) not in missed_ids]
    total_pending_minutes = sum(t.estimated_minutes for t in remaining_tasks)
    missed_minutes = sum(t.estimated_minutes for t in missed_tasks)
    available_minutes = 390  # 6.5 h typical focus window

    # Determine active task type for context-switch cost
    active_task_type = None
    if active_task:
        active_task_type = active_task.task_type.value if hasattr(active_task.task_type, "value") else str(active_task.task_type)

    # ── 4. Recommendation Engine ───────────────────────────────────────────
    obs_count = len(observations)
    decision_id: Optional[str] = None
    recommended_task: Optional[Task] = None
    reasons: List[str] = []

    candidates = _actionable_now(pending_tasks, now_utc)
    if candidates:
        # Check for recent user overrides / later actions today
        recent_later_task_ids = set()
        latest_override_task_id = None
        try:
            from ...models.recommendation import RecommendationOutcome
            recent_outcomes = (
                db.query(RecommendationOutcome)
                .filter(
                    RecommendationOutcome.user_id == current_user.id,
                    RecommendationOutcome.created_at >= now_utc - timedelta(hours=12),
                )
                .order_by(RecommendationOutcome.created_at.desc())
                .all()
            )
            for ro in recent_outcomes:
                if ro.user_action == "later" and ro.task_id:
                    recent_later_task_ids.add(str(ro.task_id))
                elif ro.user_action == "overridden" and ro.override_to_task_id and latest_override_task_id is None:
                    latest_override_task_id = str(ro.override_to_task_id)
        except Exception as e:
            logger.warning(f"Could not check recent outcomes: {type(e).__name__}")

        # Select engine based on observation count
        if obs_count >= 10:
            engine_obj = PersonalizedRecommendationEngine(observations=observations)
        else:
            engine_obj = GenericRecommendationEngine()

        scored_candidates, strategy = engine_obj.rank(
            pending_tasks=candidates,
            now_utc=now_utc,
            readiness_score=readiness_score_float,
            active_task_type=active_task_type,
            pending_minutes=total_pending_minutes,
            available_minutes=available_minutes,
        )

        # Demote tasks marked as "later" if other pending candidates exist
        if recent_later_task_ids:
            has_non_later = any(str(sc.task.id) not in recent_later_task_ids for sc in scored_candidates)
            if has_non_later:
                scored_candidates.sort(key=lambda sc: 1 if str(sc.task.id) in recent_later_task_ids else 0)

        # Prioritize task chosen via user override
        if latest_override_task_id:
            scored_candidates.sort(key=lambda sc: 0 if str(sc.task.id) == latest_override_task_id else 1)

        if scored_candidates:
            top = scored_candidates[0]
            recommended_task = top.task
            reasons = top.reasons[:3]

            # ── Log RecommendationDecision ─────────────────────────────
            # The same recommendation re-read within a few minutes (resume, pull-to-refresh, every task edit)
            # reuses its decision row: a GET should not pay an INSERT + commit each time it is polled.
            recent = (
                db.query(RecommendationDecision.id)
                .filter(RecommendationDecision.user_id == current_user.id,
                        RecommendationDecision.recommended_task_id == str(recommended_task.id),
                        RecommendationDecision.created_at >= datetime.now(timezone.utc) - timedelta(minutes=15))
                .order_by(RecommendationDecision.created_at.desc())
                .first()
            )
            if recent is not None:
                decision_id = recent.id
            else:
                try:
                    decision = RecommendationDecision(
                        user_id=current_user.id,
                        readiness_score=result["readiness_score"] if lifecycle_state != "new_user" else None,
                        readiness_confidence=result["confidence"] if lifecycle_state != "new_user" else None,
                        readiness_stage=result["stage"] if lifecycle_state != "new_user" else "new_user",
                        total_pending_tasks=len(remaining_tasks),
                        total_pending_minutes=total_pending_minutes,
                        available_minutes=available_minutes,
                        recommended_task_id=str(recommended_task.id),
                        recommendation_score=top.score,
                        engine_version=engine_obj.ENGINE_VERSION,
                        strategy=strategy,
                        observation_count=obs_count,
                    )
                    decision.candidate_scores = [s.to_dict() for s in scored_candidates]
                    decision.recommendation_reasons = reasons
                    saved_decision = rec_repo.create_decision(db, decision)
                    decision_id = saved_decision.id
                except Exception as e:
                    logger.warning(f"Non-critical: failed to log RecommendationDecision: {type(e).__name__}")

    # ── 5. Time-aware AI Brief ─────────────────────────────────────────────
    hour_local = now_local.hour
    greeting = _time_aware_greeting(hour_local)

    if lifecycle_state == "new_user":
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message=f"{greeting}. You haven't planned any tasks yet. Add what you need to get done to build your day.",
            action_label="Add a task",
        )
    elif recommended_task:
        count = len(remaining_tasks)

        # Compute time until the recommended task's peak fit window, if meaningful
        if readiness_profile:
            try:
                pk_parts = readiness_profile.preferred_peak_start.split(":")
                pk_h, pk_m = int(pk_parts[0]), int(pk_parts[1])
                from datetime import time as dt_time
                peak_dt_local = datetime.combine(now_local.date(), dt_time(pk_h, pk_m), tzinfo=user_tz)
                mins_until_peak = _minutes_until(peak_dt_local, now_local)
            except Exception:
                mins_until_peak = None
        else:
            mins_until_peak = None

        task_title = recommended_task.title

        if lifecycle_state == "calibrated" and mins_until_peak and 5 <= mins_until_peak <= 90:
            brief_msg = (
                f"{greeting}. {count} task{'s' if count != 1 else ''} to get through. "
                f"Your focus window starts in {mins_until_peak} minutes — "
                f"I'd do \"{task_title}\" first."
            )
        elif lifecycle_state == "calibrated" and (mins_until_peak is None or mins_until_peak < 5):
            # Currently in peak window
            brief_msg = (
                f"{greeting}. You're in your focus window. "
                f"I'd tackle \"{task_title}\" now — {count} task{'s' if count != 1 else ''} remaining."
            )
        else:
            # Learning state or outside peak window
            brief_msg = (
                f"{greeting}. {count} task{'s' if count != 1 else ''} today. "
                f"Start with \"{task_title}\" — it matters most right now."
            )

        ai_brief = AIBrief(
            title="FLOWSTATE",
            message=brief_msg,
            action_label="Use this plan",
        )
    elif pending_tasks:
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message=f"{greeting}. {len(missed_tasks)} task{'s' if len(missed_tasks) != 1 else ''} slipped past their time. Redo or replan when you're ready.",
            action_label="Replan",
        )
    else:
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message=f"{greeting}. All scheduled tasks for today are completed. Enjoy your recovery window.",
            action_label="Review day",
        )

    # ── 6. Workload Summary ────────────────────────────────────────────────
    hours = total_pending_minutes // 60
    mins = total_pending_minutes % 60
    if hours > 0 and mins > 0:
        formatted_workload = f"{hours}h {mins}m planned"
    elif hours > 0:
        formatted_workload = f"{hours}h planned"
    else:
        formatted_workload = f"{mins}m planned"

    is_overloaded = total_pending_minutes > available_minutes

    if total_pending_minutes == 0 and missed_tasks:
        workload_msg = (
            f"Nothing left that can still be done today. {len(missed_tasks)} missed "
            f"task{'s' if len(missed_tasks) != 1 else ''}: redo or replan when you're ready."
        )
    elif total_pending_minutes == 0:
        workload_msg = "Let's build your day."
    elif is_overloaded:
        workload_msg = (
            f"You're trying to fit {formatted_workload} into "
            f"{available_minutes // 60}h {available_minutes % 60}m."
        )
    else:
        workload_msg = "Your day looks manageable."

    workload_summary = WorkloadSummary(
        planned_minutes=total_pending_minutes,
        formatted_workload=formatted_workload,
        message=workload_msg,
        is_overloaded=is_overloaded,
        available_minutes=available_minutes,
        missed_minutes=missed_minutes,
        missed_count=len(missed_tasks),
    )

    # ── 7. Schedule: render what is persisted (same source as the Calendar day view) ──────────
    # Placement is never recomputed here; tasks without a stored slot get a flagged suggestion.
    from ...services.calendar_service import CalendarService

    day_view = CalendarService().get_day_schedule(
        db, current_user, now_local.strftime("%Y-%m-%d"), user_tz_str, now_local=now_local
    )
    timeline_items: List[ScheduleItemResponse] = [
        ScheduleItemResponse(
            id=item.id,
            time=item.time,
            period=item.period,
            title=item.title,
            type=item.type,
            tag_text=item.tag_text,
            is_active=item.is_active,
            duration_minutes=item.duration_minutes,
            state=item.state,
            is_missed=item.is_missed,
            is_commitment=item.is_commitment,
        )
        for item in day_view.timeline
        if not item.is_completed
    ]
    # Open tasks planned for today that have no slot and no capacity left are still today's work: list them
    # (flagged UNSCHEDULED, no fake time) after the timed rows instead of dropping them from Today.
    listed_ids = {i.id for i in timeline_items}
    timeline_items += [
        ScheduleItemResponse(
            id=item.id,
            time=item.time,
            period=item.period,
            title=item.title,
            type=item.type,
            tag_text=item.tag_text,
            is_active=False,
            duration_minutes=item.duration_minutes,
            state=item.state,
            is_missed=False,
            is_commitment=False,
        )
        for item in day_view.unscheduled_tasks
        if not item.is_completed and item.id not in listed_ids
    ]

    # ── 7b. Tomorrow: open tasks owned by tomorrow, as a section of their own ─────────────────
    # Same day-ownership query as the Calendar day view. Today's timeline and path are untouched.
    tomorrow_date = now_local.date() + timedelta(days=1)
    tomorrow_start, tomorrow_end = CalendarService._bounds(tomorrow_date, user_tz)
    today_ids = {str(t.id) for t in today_tasks}
    tomorrow_rows = [
        t for t in TaskRepository.list_open_for_day(
            db, current_user.id, tomorrow_date, tomorrow_start, tomorrow_end, is_today=False)
        if str(t.id) not in today_ids
    ]

    def _local(dt: Optional[datetime]) -> Optional[datetime]:
        if dt is None:
            return None
        return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).astimezone(user_tz)

    tomorrow_rows.sort(key=lambda t: (
        t.scheduled_start is None,
        _local(t.scheduled_start) or datetime.max.replace(tzinfo=timezone.utc),
        (t.title or "").lower()))
    tomorrow_tasks = [
        TomorrowTaskResponse(
            id=str(t.id),
            title=t.title,
            start_time=_local(t.scheduled_start),
            duration_minutes=t.estimated_minutes or 45,
            is_commitment=bool(t.is_commitment),
        )
        for t in tomorrow_rows
    ][:50]

    # ── 8. Current recommendation schema ──────────────────────────────────
    current_rec = None
    if recommended_task:
        current_rec = CurrentRecommendation(
            task=TaskResponse.model_validate(recommended_task),
            reasons=reasons,
        )

    # ── 9. User context ────────────────────────────────────────────────────
    user_context = TodayUserContext(
        id=current_user.id,
        email=current_user.email,
        name=current_user.name or "Friend",
        timezone=user_tz_str,
    )

    return TodayResponse(
        user=user_context,
        date=now_local.strftime("%Y-%m-%d"),
        lifecycle_state=lifecycle_state,
        state=lifecycle_state,
        completed_count=completed_count,
        has_actionable_tasks=has_actionable_tasks,
        readiness=readiness,
        current_recommendation=current_rec,
        ai_brief=ai_brief,
        workload_summary=workload_summary,
        active_task=TaskResponse.model_validate(active_task) if active_task else None,
        upcoming_timeline=timeline_items,
        tomorrow_tasks=tomorrow_tasks,
        calendar_context=CalendarContext(events_count=0, next_event=None),
        decision_id=decision_id,
    )


# ── Override / Later endpoint ─────────────────────────────────────────────────

def _place_override(db, user, task_obj, user_tz, user_tz_str, now_utc, *, earliest_start=None, proposed_start=None):
    """Ask the shared planner for a slot for ``task_obj`` against the user's other tasks (all user-scoped)."""
    from datetime import datetime as dt_cls, time as tm_cls

    now_local = now_utc.astimezone(user_tz)
    since = dt_cls.combine(now_local.date(), tm_cls.min, tzinfo=user_tz).astimezone(timezone.utc)
    others = TaskRepository.list_for_planning(db, user.id, since)
    profile = PlanningProfile.from_user_context(
        readiness_profile=readiness_repo.get_profile(db, user.id), preferences=user.preferences)
    return planning_service.place_single_task(
        task_obj, others, profile=profile, tz=user_tz, tz_name=user_tz_str, now_local=now_local,
        earliest_start=earliest_start, proposed_start=proposed_start)


def _persist_placement(task_obj, placement, user_tz) -> None:
    """Write a planner placement. The new time is scheduler-chosen, so it is never user-locked.

    The user asked for this move ("Later" / override), so it is an explicit reschedule: ownership
    follows the new slot's local day.
    """
    task_obj.scheduled_start = placement.start
    task_obj.scheduled_end = placement.end
    task_obj.time_locked = False
    task_obj.planned_date = owning_date(None, placement.start, user_tz)


@router.post("/override", response_model=OverrideResponse)
def record_override(
    req: OverrideRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Records a user override of the current recommendation.

    Called when user taps "Later", "Give me something else",
    or picks a specific different task.

    For "later" actions, returns the suggested next scheduling window
    so the UI can immediately offer: "I'll move it. Next good window: Tomorrow · 9:30 AM"

    Never blocks the user — if logging fails it still returns success.
    """
    now_utc = datetime.now(timezone.utc)
    user_tz, user_tz_str = resolve_user_timezone(current_user, req.timezone)

    # Validate decision belongs to current user
    decision = rec_repo.get_decision(db, req.decision_id, current_user.id)
    if not decision:
        # Don't 404 — silently succeed so override never blocks the user
        return OverrideResponse(recorded=False, message="Logged.")

    if req.chosen_task_id:
        chosen = db.query(Task).filter(Task.id == req.chosen_task_id, Task.user_id == current_user.id).first()
        if chosen is not None and chosen.is_commitment:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"code": "commitment_not_movable",
                        "message": f"“{chosen.title}” is a fixed commitment; it can't be skipped, moved or started."})

    reason = req.reason or "unspecified"
    is_skip = reason == "skip"  # explicit skip: the chosen task is the one skipped, not a "do this now" pick
    is_later = reason in ("later", "wrong_timing", "too_tired", "skip")
    is_override = (not is_skip) and req.chosen_task_id is not None and req.chosen_task_id != decision.recommended_task_id

    user_action = "later" if is_later and not is_override else ("overridden" if is_override else "later")

    next_window = None
    later_no_slot = False

    try:
        # Check for existing outcome record
        existing = rec_repo.get_outcome_by_decision(db, req.decision_id, current_user.id)
        if existing:
            rec_repo.update_outcome(
                db,
                existing,
                user_action=user_action,
                override_reason=reason,
                override_to_task_id=req.chosen_task_id,
                postponed_at=now_utc if is_later else None,
            )
        else:
            outcome = RecommendationOutcome(
                decision_id=req.decision_id,
                user_id=current_user.id,
                task_id=decision.recommended_task_id,
                user_action=user_action,
                override_reason=reason,
                override_to_task_id=req.chosen_task_id,
                postponed_at=now_utc if is_later else None,
                outcome="postponed" if is_later else "overridden",
            )
            rec_repo.create_outcome(db, outcome)

        # ── Suggest next window and persist postponement for "Later" ───────
        later_target_id = (req.chosen_task_id if is_skip and req.chosen_task_id else decision.recommended_task_id)
        if is_later and later_target_id:
            from ...models.task import Task as TaskModel
            task_obj = db.query(TaskModel).filter(
                TaskModel.id == later_target_id,
                TaskModel.user_id == current_user.id,
            ).first()
            if task_obj:
                readiness_profile = readiness_repo.get_profile(db, current_user.id)
                engine_obj = GenericRecommendationEngine()
                next_window = engine_obj.suggest_next_window(
                    task=task_obj,
                    now_utc=now_utc,
                    readiness_profile=readiness_profile,
                    user_tz=user_tz,
                )
                if next_window and next_window.get("suggested_date"):
                    # The recommendation engine only SUGGESTS a window. The shared planner decides the real
                    # slot (never in the past, never overlapping another task, never after the deadline).
                    from datetime import datetime as dt_cls, time as tm_cls
                    t_parts = next_window.get("suggested_time", "09:30").split(":")
                    suggested = dt_cls.combine(
                        dt_cls.fromisoformat(next_window["suggested_date"]).date(),
                        tm_cls(int(t_parts[0]), int(t_parts[1])), tzinfo=user_tz)
                    placement = _place_override(
                        db, current_user, task_obj, user_tz, user_tz_str, now_utc,
                        earliest_start=max(suggested, now_utc.astimezone(user_tz)))
                    if placement is not None:
                        _note_origin(db, current_user, task_obj, now_utc, user_tz, skipped=is_skip)
                        _persist_placement(task_obj, placement, user_tz)
                        db.commit()
                        next_window = planning_service.describe_slot(placement.start, user_tz, now_utc)
                    else:
                        later_no_slot = True
                        next_window = None  # nothing was changed; do not advertise a window that was not booked

        # ── Prioritize chosen task for "Do this now" override ───────────────
        if is_override and req.chosen_task_id:
            from ...models.task import Task as TaskModel
            chosen_obj = db.query(TaskModel).filter(
                TaskModel.id == req.chosen_task_id,
                TaskModel.user_id == current_user.id,
            ).first()
            if chosen_obj:
                # "Do this now": ask the planner for the current minute. If that clashes with another task or
                # the deadline it falls back to the nearest valid slot, or changes nothing.
                now_local = now_utc.astimezone(user_tz)
                proposed = now_local.replace(second=0, microsecond=0) + timedelta(minutes=1)
                placement = _place_override(
                    db, current_user, chosen_obj, user_tz, user_tz_str, now_utc, proposed_start=proposed)
                if placement is not None:
                    _note_origin(db, current_user, chosen_obj, now_utc, user_tz)  # Redo of a missed task keeps the miss
                    _persist_placement(chosen_obj, placement, user_tz)
                    db.commit()
    except Exception as e:
        db.rollback()
        logger.warning(f"Non-critical: failed to log override outcome: {type(e).__name__}")

    if is_later and next_window:
        return OverrideResponse(
            recorded=True,
            next_window=next_window,
            message=f"Okay. I'll move it. Next good window: {next_window.get('label', 'Tomorrow')}",
        )

    if is_later and later_no_slot:
        return OverrideResponse(
            recorded=True,
            next_window=None,
            message="Noted. I couldn't find a free slot that fits before its deadline, so I left it as it is.",
        )
    return OverrideResponse(
        recorded=True,
        next_window=None,
        message="Got it." if is_override else "Noted.",
    )


def _skip_open_task(db: Session, user: User, task_obj: Task, now_utc: datetime, user_tz, user_tz_str) -> Optional[dict]:
    """The one skip: keep the slot as "skipped" history and move the task to its next good window (caller commits).

    Returns the new window's description, or None when no free slot fits before its deadline (the task keeps its slot).
    """
    placement = None
    engine_window = GenericRecommendationEngine().suggest_next_window(
        task=task_obj, now_utc=now_utc, readiness_profile=readiness_repo.get_profile(db, user.id), user_tz=user_tz)
    if engine_window and engine_window.get("suggested_date"):
        from datetime import time as tm_cls
        t_parts = engine_window.get("suggested_time", "09:30").split(":")
        suggested = datetime.combine(datetime.fromisoformat(engine_window["suggested_date"]).date(),
                                     tm_cls(int(t_parts[0]), int(t_parts[1])), tzinfo=user_tz)
        placement = _place_override(db, user, task_obj, user_tz, user_tz_str, now_utc,
                                    earliest_start=max(suggested, now_utc.astimezone(user_tz)))
    _note_origin(db, user, task_obj, now_utc, user_tz, skipped=True)
    if task_obj.status == TaskStatus.in_progress:
        task_obj.status = TaskStatus.todo
    if placement is None:
        return None
    _persist_placement(task_obj, placement, user_tz)
    return planning_service.describe_slot(placement.start, user_tz, now_utc)


AUTO_SKIPPED = "auto_skipped"


def _day_stops(db: Session, user_id: str, anchor: Task, user_tz) -> List[Task]:
    """The planned stops (non-commitment, slotted, not cancelled) of ``anchor``'s local day, in planned order."""
    start = _make_aware(anchor.scheduled_start)
    if start is None:
        return []
    day = start.astimezone(user_tz).date()
    day_start = datetime.combine(day, datetime.min.time(), tzinfo=user_tz).astimezone(timezone.utc)
    rows = (db.query(Task).filter(
        Task.user_id == user_id, Task.status.notin_([TaskStatus.cancelled, TaskStatus.archived]),
        Task.is_commitment.is_(False), Task.scheduled_start.isnot(None),
        Task.scheduled_start >= day_start - timedelta(days=1), Task.scheduled_start < day_start + timedelta(days=2))
        .order_by(Task.scheduled_start.asc(), Task.created_at.asc()).all())
    return [t for t in rows if _make_aware(t.scheduled_start).astimezone(user_tz).date() == day]


def _closed_in(stops: List[Task], i: int) -> bool:
    """Stop ``i`` lies in a run between two done stops: a completed stop comes somewhere before it and after it, with
    only unfinished stops in between. The first and last stops of a day are never closed in."""
    def done(j: int) -> bool:
        return stops[j].status == TaskStatus.completed

    before = next((j for j in range(i - 1, -1, -1) if done(j)), None)
    after = next((j for j in range(i + 1, len(stops)) if done(j)), None)
    return before is not None and after is not None


def bypassed_open_tasks(db: Session, user_id: str, done: Task, user_tz, now_utc: datetime) -> List[Task]:
    """The open stops ``done`` closes in: every open stop in a run between two done stops, on either side of it.

    A → B → C with A and C done leaves B behind; A done, B and C open, D done leaves B AND C behind. Planned order on
    ``done``'s day. The first and last stops of a day are never closed in. Only planned work counts: commitments and
    unslotted tasks are not stops here. A task being worked on keeps its state (it is not skipped), and a slot that
    already ended is MISSED (derived from the clock) and stays missed; either still belongs to the run.
    """
    if done.is_commitment:
        return []
    stops = _day_stops(db, user_id, done, user_tz)
    at = next((i for i, t in enumerate(stops) if t.id == done.id), None)
    if at is None:
        return []

    def is_open(t: Task) -> bool:
        return t.status in (TaskStatus.todo, TaskStatus.postponed) and not task_slot_elapsed(t, now_utc)

    run = []
    for step in (-1, 1):  # the run on each side of ``done``, up to the next done stop
        i = at + step
        while 0 <= i < len(stops) and stops[i].status != TaskStatus.completed:
            run.append(i)
            i += step
    return [stops[i] for i in sorted(run) if is_open(stops[i]) and _closed_in(stops, i)]


def _note_auto_skip(db: Session, user: User, task: Task, user_tz) -> None:
    """Record B as auto-skipped at its slot. B is NOT moved: its stop stays where it was planned (caller commits)."""
    from ...services.calendar_service import CalendarService

    start = _make_aware(task.scheduled_start)
    if start is None or CalendarService._deviation_recorded(db, [], str(task.id), AUTO_SKIPPED, task.scheduled_start):
        return
    db.add(TaskDeviation(
        user_id=user.id, task_id=str(task.id), deviation_date=start.astimezone(user_tz).date(), kind=AUTO_SKIPPED,
        original_start=task.scheduled_start, original_end=task.scheduled_end))


def skip_bypassed_tasks(db: Session, user: User, done: Task, timezone_name: Optional[str] = None) -> List[str]:
    """Completing a stop that closes in open stops (A done, B [and C ...] open, D done) auto-skips each of them.

    Auto-skip is its own state, apart from an explicit Skip (which moves the task), Missed (the clock) and Completed:
    B keeps its slot and stays doable there. Never fails the completion: on any error nothing is recorded.
    """
    try:
        now_utc = datetime.now(timezone.utc)
        user_tz, _ = resolve_user_timezone(user, timezone_name)
        skipped = []
        for t in bypassed_open_tasks(db, user.id, done, user_tz, now_utc):
            _note_auto_skip(db, user, t, user_tz)
            skipped.append(str(t.id))
        if skipped:
            db.commit()
        return skipped
    except Exception as e:
        db.rollback()
        logger.warning(f"Auto-skip after completion failed: {type(e).__name__}")
        return []


def restore_auto_skipped(db: Session, user: User, reopened: Task, timezone_name: Optional[str] = None) -> List[str]:
    """Un-completing a stop can undo an auto-skip: every auto-skipped stop of that day that is no longer between two
    done stops is Open again (its auto-skip record is removed). Explicit skips, missed and completed tasks are never touched.

    Never fails the un-completion: on any error nothing is changed.
    """
    try:
        user_tz, _ = resolve_user_timezone(user, timezone_name)
        stops = _day_stops(db, user.id, reopened, user_tz)
        at = next((i for i, t in enumerate(stops) if t.id == reopened.id), None)
        if at is None:
            return []

        restored = []
        for i, t in enumerate(stops):
            if t.status not in (TaskStatus.todo, TaskStatus.postponed) or _closed_in(stops, i):
                continue  # still closed in (or not open): its state stays
            n = db.query(TaskDeviation).filter(
                TaskDeviation.user_id == user.id, TaskDeviation.task_id == str(t.id),
                TaskDeviation.kind == AUTO_SKIPPED,
                TaskDeviation.original_start == t.scheduled_start).delete(synchronize_session=False)
            if n:
                restored.append(str(t.id))
        if restored:
            db.commit()
        return restored
    except Exception as e:
        db.rollback()
        logger.warning(f"Auto-skip restore after un-completion failed: {type(e).__name__}")
        return []


@router.post("/skip/{task_id}", response_model=OverrideResponse)
def skip_task(
    task_id: str,
    req: Optional[SkipTaskRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Skip ONE task from anywhere (Task page, Calendar, Today), with or without a Today recommendation.

    Same semantics as the override "skip": the task's current slot is kept as "skipped" history (the Calendar keeps
    its stop there) and the shared planner moves the task to its next good window. With no free window before its
    deadline the skip is still recorded and the task keeps its slot. Fixed commitments cannot be skipped.
    """
    now_utc = datetime.now(timezone.utc)
    user_tz, user_tz_str = resolve_user_timezone(current_user, req.timezone if req else None)
    task_obj = db.query(Task).filter(Task.id == task_id, Task.user_id == current_user.id).first()
    if task_obj is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail={"code": "not_found", "message": "Task not found."})
    if task_obj.is_commitment:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
            "code": "commitment_not_movable",
            "message": f"“{task_obj.title}” is a fixed commitment; it can't be skipped, moved or started."})
    if task_obj.status not in (TaskStatus.todo, TaskStatus.in_progress):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
            "code": "not_open", "message": "Only an open task can be skipped."})

    next_window = _skip_open_task(db, current_user, task_obj, now_utc, user_tz, user_tz_str)
    db.commit()
    if next_window is None:
        return OverrideResponse(recorded=True, next_window=None,
                                message="Skipped. I couldn't find a free slot before its deadline, so it stays where it was.")
    return OverrideResponse(recorded=True, next_window=next_window,
                            message=f"Skipped. Next good window: {next_window.get('label', 'later')}")



class DoNowResponse(BaseModel):
    moved: bool
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    message: str


@router.post("/do-now/{task_id}", response_model=DoNowResponse)
def do_task_now(
    task_id: str,
    req: Optional[SkipTaskRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """"Do this now" from anywhere (Calendar stop, Task page), with or without a Today recommendation.

    The shared deterministic planner is asked for the current minute. When that clashes with a fixed block or another
    task it falls back to the nearest valid slot; with no valid slot nothing changes and ``moved`` is false, so the app
    never shows a move that did not happen. A missed slot is kept as "missed" history (the Calendar stop stays where
    it was). Repeating the call while the task already starts now changes nothing (idempotent). Never charges Shields.
    """
    now_utc = datetime.now(timezone.utc)
    user_tz, user_tz_str = resolve_user_timezone(current_user, req.timezone if req else None)
    task_obj = db.query(Task).filter(Task.id == task_id, Task.user_id == current_user.id).first()
    if task_obj is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail={"code": "not_found", "message": "Task not found."})
    if task_obj.is_commitment:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
            "code": "commitment_not_movable",
            "message": f"“{task_obj.title}” is a fixed commitment; it can't be skipped, moved or started."})
    if task_obj.status not in (TaskStatus.todo, TaskStatus.in_progress, TaskStatus.postponed):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
            "code": "not_open", "message": "Only an open task can be started."})

    start = _make_aware(task_obj.scheduled_start)
    if start is not None and abs((start - now_utc).total_seconds()) <= 5 * 60:
        end = _make_aware(task_obj.scheduled_end) or start + timedelta(minutes=task_obj.estimated_minutes)
        return DoNowResponse(moved=True, start_time=start, end_time=end, message="It's already up now.")

    now_local = now_utc.astimezone(user_tz)
    proposed = now_local.replace(second=0, microsecond=0) + timedelta(minutes=1)
    placement = _place_override(db, current_user, task_obj, user_tz, user_tz_str, now_utc, proposed_start=proposed)
    if placement is None:
        return DoNowResponse(moved=False, message="There's no free time for it right now, so nothing was changed.")
    _note_origin(db, current_user, task_obj, now_utc, user_tz)  # a Redo of a missed task keeps the miss on record
    _persist_placement(task_obj, placement, user_tz)
    if task_obj.status == TaskStatus.postponed:
        task_obj.status = TaskStatus.todo
    db.commit()
    starts_now = abs((placement.start - now_utc).total_seconds()) <= 5 * 60
    label = planning_service.describe_slot(placement.start, user_tz, now_utc).get("label", "soon")
    return DoNowResponse(moved=True, start_time=placement.start, end_time=placement.end,
                         message="Moved to now." if starts_now else f"The nearest free time is {label}.")
