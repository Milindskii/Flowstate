from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.config import settings
from ...models.user import User
from ...models.task import Task, TaskStatus, TaskPriority, TaskType
from ...models.task_performance import TaskPerformance
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

router = APIRouter(prefix="/today", tags=["Today Experience"])
task_service = TaskService()

@router.get("", response_model=TodayResponse)
def get_today_experience(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Aggregated Today endpoint: Single source of truth for the Today page.
    Combines:
    - User context & local date
    - Lifecycle state (new_user, learning, calibrated)
    - Non-medical Readiness score & confidence
    - Deterministic RIGHT NOW recommendation + reasons
    - Deterministic AI Brief
    - Workload calculation
    - Active in-progress task
    - Upcoming timeline blocks
    - Calendar context
    """
    today_tasks: List[Task] = task_service.list_today_tasks(db, current_user)
    total_sessions: int = (
        db.query(TaskPerformance)
        .filter(TaskPerformance.user_id == current_user.id)
        .count()
    )

    # 1. Determine Lifecycle State
    if len(today_tasks) == 0 and total_sessions == 0:
        lifecycle_state = "new_user"
    elif total_sessions < settings.CALIBRATION_MIN_SESSIONS:
        lifecycle_state = "learning"
    else:
        lifecycle_state = "calibrated"

    # 2. Compute Readiness Details
    if lifecycle_state in ("new_user", "learning"):
        readiness = ReadinessDetail(
            score=None,
            max_score=100,
            confidence=0.0,
            model_version=settings.READINESS_MODEL_VERSION,
            status_message="Learning your rhythm",
            focus_window_range="9:30 AM – 11:30 AM",
            explanation="We're still learning when you work best.",
            is_calibrated=False,
            factors=["Awaiting more session data to calibrate"],
            hourly_rhythm=[],
        )
    else:
        # Calibrated user
        calibrated_score = 78
        confidence = min(0.95, round(0.70 + (total_sessions / 100.0), 2))
        readiness = ReadinessDetail(
            score=calibrated_score,
            max_score=100,
            confidence=confidence,
            model_version=settings.READINESS_MODEL_VERSION,
            status_message="Strong focus window coming up",
            focus_window_range="9:30 AM – 11:30 AM",
            explanation="Your readiness is based on recent sleep, your usual rhythm, today's check-in, and what we've learned from your previous work sessions.",
            is_calibrated=True,
            factors=[
                "Consistent wake-up schedule",
                "Optimal sleep duration for focus",
                "Circadian morning peak alignment",
            ],
            hourly_rhythm=[
                {"label": "6a", "level": 0.28},
                {"label": "8a", "level": 0.52},
                {"label": "10a", "level": 0.88},
                {"label": "12p", "level": 0.72},
                {"label": "2p", "level": 0.42},
                {"label": "4p", "level": 0.65},
                {"label": "6p", "level": 0.55},
            ],
        )

    # 3. Active Task & Candidate Recommendation
    active_task: Optional[Task] = None
    pending_tasks: List[Task] = []
    for t in today_tasks:
        if t.status == TaskStatus.in_progress and active_task is None:
            active_task = t
        if t.status not in (TaskStatus.completed, TaskStatus.cancelled, TaskStatus.archived):
            pending_tasks.append(t)

    # Deterministic task recommendation
    recommended_task: Optional[Task] = None
    reasons: List[str] = []

    if pending_tasks:
        # Sort pending tasks by priority and deadline
        def sort_key(t: Task):
            is_pri = 0 if (t.priority in (TaskPriority.high, TaskPriority.urgent)) else 1
            has_dead = 0 if t.deadline_at is not None else 1
            dead_time = t.deadline_at.timestamp() if t.deadline_at else float("inf")
            return (is_pri, has_dead, dead_time)

        sorted_candidates = sorted(pending_tasks, key=sort_key)
        recommended_task = sorted_candidates[0]

        # 3 concise reasons
        if recommended_task.priority in (TaskPriority.high, TaskPriority.urgent):
            reasons.append("High priority")
        else:
            reasons.append("Aligned with today's goals")

        if recommended_task.task_type == TaskType.deep_work:
            reasons.append("Strong focus window")
        else:
            reasons.append("Fits cognitive energy slot")

        if recommended_task.deadline_at:
            reasons.append("Approaching deadline")
        else:
            reasons.append("Scheduled for today")

    current_rec = None
    if recommended_task:
        current_rec = CurrentRecommendation(
            task=TaskResponse.model_validate(recommended_task),
            reasons=reasons,
        )

    # 4. Deterministic AI Brief
    if lifecycle_state == "new_user":
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message="Good morning. You haven't planned any tasks yet. Add what you need to get done to build your day.",
            action_label="Add a task",
        )
    elif recommended_task:
        count = len(pending_tasks)
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message=f"You have {count} important tasks today. Your strongest focus window starts in 15 minutes. I'd tackle your {recommended_task.title} first.",
            action_label="Use this plan",
        )
    else:
        ai_brief = AIBrief(
            title="FLOWSTATE",
            message="All scheduled tasks for today are completed. Enjoy your recovery window.",
            action_label="Review day",
        )

    # 5. Workload Summary
    planned_minutes = sum(t.estimated_minutes for t in pending_tasks)
    hours = planned_minutes // 60
    mins = planned_minutes % 60
    if hours > 0 and mins > 0:
        formatted_workload = f"{hours}h {mins}m planned"
    elif hours > 0:
        formatted_workload = f"{hours}h planned"
    else:
        formatted_workload = f"{mins}m planned"

    available_minutes = 390  # 6h 30m typical focus window
    is_overloaded = planned_minutes > available_minutes

    if planned_minutes == 0:
        workload_msg = "Let's build your day."
    elif is_overloaded:
        workload_msg = f"You're trying to fit {formatted_workload} of work into {available_minutes // 60}h {available_minutes % 60}m."
    else:
        workload_msg = "Your day looks manageable."

    workload_summary = WorkloadSummary(
        planned_minutes=planned_minutes,
        formatted_workload=formatted_workload,
        message=workload_msg,
        is_overloaded=is_overloaded,
        available_minutes=available_minutes,
    )

    # 6. Timeline Construction
    timeline_items: List[ScheduleItemResponse] = []
    # Build schedule items from pending tasks & rhythmic breaks
    timeline_slots = [
        ("9:30", "AM", "High Focus", "DEEP WORK"),
        ("11:30", "AM", "Study", "MEDIUM"),
        ("1:00", "PM", "Rest", "REST"),
        ("2:30", "PM", "Admin", "LIGHT"),
        ("5:30", "PM", "Physical", "PHYSICAL"),
    ]

    for idx, (time_str, period_str, type_str, tag_str) in enumerate(timeline_slots):
        if idx < len(today_tasks):
            t = today_tasks[idx]
            timeline_items.append(
                ScheduleItemResponse(
                    id=f"sched-{t.id}",
                    time=time_str,
                    period=period_str,
                    title=t.title,
                    type=type_str,
                    tag_text=tag_str,
                    is_active=(t.status == TaskStatus.in_progress),
                    duration_minutes=t.estimated_minutes,
                )
            )
        elif type_str == "Rest":
            timeline_items.append(
                ScheduleItemResponse(
                    id=f"sched-break-{idx}",
                    time=time_str,
                    period=period_str,
                    title="Lunch & Recovery Walk",
                    type="Rest",
                    tag_text="REST",
                    is_active=False,
                    duration_minutes=45,
                )
            )

    # 7. User Context
    user_context = TodayUserContext(
        id=current_user.id,
        email=current_user.email,
        name=current_user.name or "Friend",
        timezone=current_user.preferences.timezone if current_user.preferences else "Asia/Kolkata",
    )

    return TodayResponse(
        user=user_context,
        date=datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        lifecycle_state=lifecycle_state,
        readiness=readiness,
        current_recommendation=current_rec,
        ai_brief=ai_brief,
        workload_summary=workload_summary,
        active_task=TaskResponse.model_validate(active_task) if active_task else None,
        upcoming_timeline=timeline_items,
        calendar_context=CalendarContext(events_count=0, next_event=None),
    )
