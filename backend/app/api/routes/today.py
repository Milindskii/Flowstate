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
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status as http_status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.config import settings
from ...core.logging import logger
from ...models.user import User
from ...models.task import Task, TaskStatus, TaskPriority, TaskType
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

class OverrideResponse(BaseModel):
    recorded: bool
    next_window: Optional[dict] = None   # {"label": "Tomorrow · 9:30 AM", "suggested_date": ..., "suggested_time": ...}
    message: str


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


# ── Primary endpoint ──────────────────────────────────────────────────────────

@router.get("", response_model=TodayResponse)
def get_today_experience(
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
    from zoneinfo import ZoneInfo

    now_utc = datetime.now(timezone.utc)

    today_tasks: List[Task] = task_service.list_today_tasks(db, current_user)
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
    user_tz_str = current_user.preferences.timezone if current_user.preferences else "UTC"
    try:
        user_tz = ZoneInfo(user_tz_str)
    except Exception:
        user_tz = timezone.utc

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
        if t.status not in (TaskStatus.completed, TaskStatus.cancelled, TaskStatus.archived):
            pending_tasks.append(t)

    total_pending_minutes = sum(t.estimated_minutes for t in pending_tasks)
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

    if pending_tasks:
        # Select engine based on observation count
        if obs_count >= 10:
            engine_obj = PersonalizedRecommendationEngine(observations=observations)
        else:
            engine_obj = GenericRecommendationEngine()

        scored_candidates, strategy = engine_obj.rank(
            pending_tasks=pending_tasks,
            now_utc=now_utc,
            readiness_score=readiness_score_float,
            active_task_type=active_task_type,
            pending_minutes=total_pending_minutes,
            available_minutes=available_minutes,
        )

        if scored_candidates:
            top = scored_candidates[0]
            recommended_task = top.task
            reasons = top.reasons[:3]

            # ── Log RecommendationDecision ─────────────────────────────
            try:
                decision = RecommendationDecision(
                    user_id=current_user.id,
                    readiness_score=result["readiness_score"] if lifecycle_state != "new_user" else None,
                    readiness_confidence=result["confidence"] if lifecycle_state != "new_user" else None,
                    readiness_stage=result["stage"] if lifecycle_state != "new_user" else "new_user",
                    total_pending_tasks=len(pending_tasks),
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
                logger.warning(f"Non-critical: failed to log RecommendationDecision: {e}")

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
        count = len(pending_tasks)

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

    if total_pending_minutes == 0:
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
    )

    # ── 7. Schedule (cognitive scheduling engine) ──────────────────────────
    from ...engines.scheduling_engine import SchedulingEngine
    scheduling_engine = SchedulingEngine()

    scheduled_blocks = scheduling_engine.generate_schedule(
        tasks=today_tasks,
        readiness_profile=readiness_profile,
        now_local=now_local,
        tz=user_tz,
    )

    timeline_items: List[ScheduleItemResponse] = []
    for block in scheduled_blocks:
        start_dt = block["start_time"]
        time_str = start_dt.strftime("%I:%M").lstrip("0")
        period_str = start_dt.strftime("%p")
        timeline_items.append(
            ScheduleItemResponse(
                id=block["id"],
                time=time_str,
                period=period_str,
                title=block["title"],
                type=block["type"],
                tag_text=block["tag_text"],
                is_active=block["is_active"],
                duration_minutes=block["duration_minutes"],
            )
        )

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
        calendar_context=CalendarContext(events_count=0, next_event=None),
        decision_id=decision_id,
    )


# ── Override / Later endpoint ─────────────────────────────────────────────────

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
    from zoneinfo import ZoneInfo
    from datetime import timezone as tz_module

    now_utc = datetime.now(timezone.utc)
    user_tz_str = current_user.preferences.timezone if current_user.preferences else "UTC"
    try:
        user_tz = ZoneInfo(user_tz_str)
    except Exception:
        user_tz = tz_module.utc

    # Validate decision belongs to current user
    decision = rec_repo.get_decision(db, req.decision_id, current_user.id)
    if not decision:
        # Don't 404 — silently succeed so override never blocks the user
        return OverrideResponse(recorded=False, message="Logged.")

    reason = req.reason or "unspecified"
    is_later = reason in ("later", "wrong_timing", "too_tired")
    is_override = req.chosen_task_id is not None and req.chosen_task_id != decision.recommended_task_id

    user_action = "later" if is_later and not is_override else ("overridden" if is_override else "later")

    next_window = None

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

        # ── Suggest next window for "Later" ───────────────────────────────
        if is_later and decision.recommended_task_id:
            from ...models.task import Task as TaskModel
            task_obj = db.query(TaskModel).filter(
                TaskModel.id == decision.recommended_task_id,
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

    except Exception as e:
        logger.warning(f"Non-critical: failed to log override outcome: {e}")

    if is_later and next_window:
        return OverrideResponse(
            recorded=True,
            next_window=next_window,
            message=f"Okay. I'll move it. Next good window: {next_window.get('label', 'Tomorrow')}",
        )

    return OverrideResponse(
        recorded=True,
        next_window=None,
        message="Got it." if is_override else "Noted.",
    )
