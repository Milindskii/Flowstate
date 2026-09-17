from typing import Optional, List
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...models.task import TaskStatus, TaskType
from ...models.task_performance import TaskPerformance
from ...schemas.task import TaskCreate, TaskUpdate, TaskComplete, TaskResponse, TaskListResponse
from ...schemas.task_performance import FeedbackCreate, FeedbackResponse
from ...services.task_service import TaskService
from ...services.ai_service import AIService
from ...repositories.task_performance_repository import TaskPerformanceRepository

router = APIRouter(prefix="/tasks", tags=["Tasks & Performance"])
task_service = TaskService()
ai_service = AIService()
performance_repo = TaskPerformanceRepository()

class ParseRequest(BaseModel):
    raw_text: str

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
    """Paginated list of tasks for current user with optional filtering."""
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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns tasks relevant to the user's current day according to their configured timezone.
    """
    return task_service.list_today_tasks(db, current_user)

@router.post("/parse", response_model=List[TaskCreate])
def parse_unstructured_tasks(
    request: ParseRequest,
    current_user: User = Depends(get_current_user),
):
    """
    'What's on your plate?' Natural Language Task Parser.
    Parses messy brain dumps into structured task suggestions.
    Crucial Rule: Returns candidates for user confirmation. Does NOT silently insert into DB.
    """
    return ai_service.parse_task_dump(request.raw_text)

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
    return task_service.update_task(db, task_id, current_user.id, task_update)

@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Deletes a task. Returns 404 if not found or unauthorized."""
    task_service.delete_task(db, task_id, current_user.id)

@router.post("/{task_id}/start", response_model=TaskResponse)
def start_task(
    task_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks task as actively started (status: in_progress, started_at: now)."""
    return task_service.start_task(db, task_id, current_user.id)

@router.post("/{task_id}/complete", response_model=TaskResponse)
def complete_task(
    task_id: str,
    complete_in: TaskComplete = TaskComplete(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks task as completed (status: completed, completed_at: now)."""
    return task_service.complete_task(db, task_id, current_user.id, complete_in)

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
    )
    return performance_repo.create(db, performance)
