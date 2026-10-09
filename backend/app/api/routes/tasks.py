from typing import Optional, List
from datetime import datetime, timezone
import time
from collections import defaultdict
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.logging import logger
from ...core.timezone import resolve_user_timezone
from ...models.user import User
from ...models.task import Task, TaskStatus, TaskType
from ...models.task_performance import TaskPerformance
from ...schemas.task import (
    TaskCreate,
    TaskCandidateResponse,
    TaskUpdate,
    TaskComplete,
    TaskParseRequest,
    TaskResponse,
    TaskListResponse,
    BatchCreateAndScheduleRequest,
    BatchCreateAndScheduleResponse,
)
from ...schemas.task_performance import FeedbackCreate, FeedbackResponse
from ...services.task_service import TaskService
from ...services.ai_service import AIService
from ...services.observation_service import ObservationService
from ...services.evaluation_service import EvaluationService
from ...schemas.readiness import ObservationCreate
from ...models.readiness_observation import ObservationSource
from ...repositories.task_performance_repository import TaskPerformanceRepository

router = APIRouter(prefix="/tasks", tags=["Tasks & Performance"])
task_service = TaskService()
ai_service = AIService()
performance_repo = TaskPerformanceRepository()
observation_service = ObservationService()
evaluation_service = EvaluationService()

# In-memory sliding window rate limiter: user_id -> list of request timestamps
_PARSE_RATE_LIMITS = defaultdict(list)
MAX_PARSE_PER_MINUTE = 10

def check_parse_rate_limit(user_id: str):
    """Protects LLM endpoint from abusive or runaway request volumes"""
    now = time.time()
    recent_requests = [t for t in _PARSE_RATE_LIMITS[user_id] if now - t < 60]
    _PARSE_RATE_LIMITS[user_id] = recent_requests
    if len(recent_requests) >= MAX_PARSE_PER_MINUTE:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit exceeded: maximum {MAX_PARSE_PER_MINUTE} parsing requests allowed per minute.",
        )
    _PARSE_RATE_LIMITS[user_id].append(now)

# Daily AI-parse budget (Postgres-backed via ai_usage_periods, shared by every instance). Over budget the parser
# silently degrades to the local deterministic path, so the cloud call is never a free paywall bypass.
FREE_PARSE_AI_PER_DAY = 10
PRO_PARSE_AI_PER_DAY = 100


@router.post("", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
def create_task(
    task_in: TaskCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Creates a new task tied to the authenticated user."""
    return task_service.create_task(db, current_user, task_in)

@router.get("", response_model=TaskListResponse)
def list_tasks(
    status_filter: Optional[TaskStatus] = Query(None, alias="status"),
    category: Optional[str] = Query(None),
    task_type: Optional[TaskType] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Paginated list of tasks for current user with optional filtering (archived excluded by default)."""
    items, total = task_service.list_tasks(
        db=db,
        user_id=current_user.id,
        status_filter=status_filter,
        category=category,
        task_type=task_type,
        limit=limit,
        offset=offset,
    )
    return TaskListResponse(items=items, total=total, limit=limit, offset=offset)

@router.get("/today", response_model=List[TaskResponse])
def get_today_tasks(
    timezone: Optional[str] = Query(None, description="IANA zone of the device; falls back to the stored preference"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns tasks relevant strictly to the user's current day according to their configured timezone:
    - Scheduled for today
    - Currently in progress
    - Due today and not scheduled for a future day
    """
    return task_service.list_today_tasks(db, current_user, timezone)

@router.post("/parse", response_model=List[TaskCandidateResponse])
def parse_unstructured_tasks(
    request: TaskParseRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    'What's on your plate?' Natural Language Task Parser.
    Protected with rate limiting, input size limits, and safe audit logging.
    Crucial Rule: Returns candidates for user confirmation. Does NOT silently insert into DB.
    """
    check_parse_rate_limit(current_user.id)

    try:
        clean_text = request.get_clean_text()
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e))

    _, user_tz = resolve_user_timezone(current_user, request.timezone)
    from ...services import ai_gateway
    from ...services.ai_economy_service import AIEconomyService, effective_is_pro

    user_id = current_user.id
    is_pro = effective_is_pro(AIEconomyService.get_or_create_usage(db, user_id))
    granted = False

    def ai_gate() -> bool:
        # One unit of budget per request, however many cloud attempts the parser makes.
        nonlocal granted
        if not granted:
            granted = ai_gateway.consume_parse_budget(
                db, user_id, PRO_PARSE_AI_PER_DAY if is_pro else FREE_PARSE_AI_PER_DAY)
        return granted

    start_time = time.perf_counter()
    try:
        candidates = ai_service.parse_task_dump(
            clean_text,
            user_timezone_str=user_tz,
            force_ai=bool(request.use_ai),
            ai_gate=ai_gate,
        )
        latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
        # Safe audit logging: user_id, duration, candidate count — NEVER log private text content
        logger.info(
            f"Audit: /tasks/parse user={current_user.id} latency={latency_ms}ms candidates={len(candidates)} status=success"
        )
        return candidates
    except Exception as e:
        latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
        logger.error(
            f"Audit: /tasks/parse user={current_user.id} latency={latency_ms}ms error={type(e).__name__} status=failure"
        )
        raise

@router.post("/batch-create-and-schedule", response_model=BatchCreateAndScheduleResponse, status_code=status.HTTP_201_CREATED)
def batch_create_and_schedule_tasks(
    request: BatchCreateAndScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Build My Day confirm. Atomic (single transaction), idempotent per `plan_id`
    (falls back to `idempotency_key`), server-validated, and slot-revalidated by the
    shared planner. See docs/superpowers/specs/build-my-day-replan.md section 7.

    422 `{detail: {code: "validation_failed", errors: [{index, client_ref, field, code, message}]}}`
    means nothing was persisted; the client keeps the preview open and shows `message`.
    """
    from ...services import plan_confirm_service
    from ...services.ai_economy_service import AIEconomyService

    with AIEconomyService.get_user_request_lock(current_user.id):
        return plan_confirm_service.batch_create(db, current_user, request)

@router.get("/{task_id}", response_model=TaskResponse)
def get_task(
    task_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves a single task. Returns 404 if not found or unauthorized."""
    return task_service.get_task_or_404(db, task_id, current_user.id)

@router.patch("/{task_id}", response_model=TaskResponse)
def update_task_partial(
    task_id: str,
    task_update: TaskUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Partially updates task fields. Returns 404 if not found or unauthorized."""
    return _update_and_restore(db, task_id, current_user, task_update)

@router.put("/{task_id}", response_model=TaskResponse)
def update_task_put(
    task_id: str,
    task_update: TaskUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates task fields (supports HTTP PUT). Returns 404 if not found or unauthorized."""
    return _update_and_restore(db, task_id, current_user, task_update)


def _update_and_restore(db: Session, task_id: str, user: User, task_update: TaskUpdate):
    """An un-completion (completed -> open) re-opens an auto-skipped neighbour it no longer closes in."""
    from .today import restore_auto_skipped

    before = db.query(Task.status).filter(Task.id == task_id, Task.user_id == user.id).scalar()
    task = task_service.update_task(db, task_id, user, task_update)
    if before == TaskStatus.completed and task.status != TaskStatus.completed:
        restore_auto_skipped(db, user, task)
        db.refresh(task)
    return task

@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: str,
    permanent: bool = Query(False, description="Whether to permanently delete or soft-delete (archive)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Deletes a task.
    Defaults to soft-delete (archive) to protect TaskPerformance history.
    Returns 404 if not found or unauthorized.
    """
    task_service.delete_task(db, task_id, current_user.id, permanent=permanent)

@router.post("/{task_id}/start", response_model=TaskResponse)
def start_task(
    task_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Marks task as actively started (status: in_progress, started_at: now).
    Enforces legal state transitions (fails if already completed/cancelled/archived).
    """
    return task_service.start_task(db, task_id, current_user.id)

@router.post("/{task_id}/complete", response_model=TaskResponse)
def complete_task(
    task_id: str,
    complete_in: TaskComplete = TaskComplete(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Marks task as completed (status: completed, completed_at: now).
    Enforces legal state transitions (fails if cancelled/archived).

    Open stops it closes in are auto-skipped: A done, B and C open, finishing D records B and C as auto-skipped at
    their own slots (they are not moved). Open stops that are not between two done stops stay open.
    """
    from .today import skip_bypassed_tasks

    task = task_service.complete_task(db, task_id, current_user.id, complete_in)
    skip_bypassed_tasks(db, current_user, task)
    db.refresh(task)
    return task

@router.post("/{task_id}/feedback", response_model=FeedbackResponse, status_code=status.HTTP_201_CREATED)
def record_task_feedback(
    task_id: str,
    feedback_in: FeedbackCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Records post-session reflection and focus metrics into TaskPerformance.
    Feeds the learning loop for personalization. Returns 404 if unauthorized.
    """
    task = task_service.get_task_or_404(db, task_id, current_user.id)

    actual_duration = feedback_in.actual_minutes or task.estimated_minutes
    rated = any(v is not None for v in (feedback_in.focus_score, feedback_in.energy_score,
                                         feedback_in.difficulty_score, feedback_in.distraction_score))
    provenance = "reflection" if rated else "timestamps"

    performance = TaskPerformance(
        task_id=task.id,
        user_id=current_user.id,
        scheduled_start=task.scheduled_start,
        actual_start=task.started_at,
        completed_at=task.completed_at or datetime.now(timezone.utc),
        estimated_minutes=task.estimated_minutes,
        actual_minutes=actual_duration,
        focus_score=feedback_in.focus_score,
        energy_score=feedback_in.energy_score,
        difficulty_score=feedback_in.difficulty_score,
        distraction_score=feedback_in.distraction_score,
        notes=feedback_in.notes,
        provenance=provenance,
    )
    created_perf = performance_repo.create(db, performance)

    # Automatically feed verified focus feedback into the readiness observation layer
    try:
        t_type = task.task_type.value if hasattr(task.task_type, "value") else str(task.task_type)
        t_diff = task.difficulty.value if hasattr(task.difficulty, "value") else str(task.difficulty)
        obs_create = ObservationCreate(
            task_id=task.id,
            energy_rating=feedback_in.energy_score,
            focus_rating=feedback_in.focus_score,
            difficulty_rating=feedback_in.difficulty_score,
            distraction_rating=feedback_in.distraction_score,
            planned_minutes=task.estimated_minutes,
            actual_minutes=actual_duration,
            task_type=t_type,
            task_difficulty=t_diff,
            outcome="completed",
            source=ObservationSource.self_report if rated else ObservationSource.observed,
        )
        saved_obs = observation_service.record_observation(db, current_user.id, obs_create, provenance=provenance)
        evaluation_service.record_evaluation(db, current_user.id, saved_obs)

        # Trigger Personalization Profile update to close the learning loop
        from ...engines.personalization_engine import PersonalizationEngine
        from ...repositories.readiness_repository import ReadinessRepository
        read_repo = ReadinessRepository()
        user_prof = read_repo.get_profile(db, current_user.id)
        if user_prof:
            all_obs = read_repo.list_observations(db, current_user.id, limit=200)
            PersonalizationEngine().recompute_profile(user_prof, all_obs)
            db.commit()
    except Exception as e:
        logger.warning(f"Non-critical feedback observation hook error: {type(e).__name__}")

    return created_perf

