from typing import Optional, List, Tuple
from datetime import datetime, time, timezone
from zoneinfo import ZoneInfo
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from ..models.task import Task, TaskStatus, TaskType
from ..models.user import User
from ..schemas.task import TaskCreate, TaskUpdate, TaskComplete
from ..repositories.task_repository import TaskRepository

class TaskService:
    def __init__(self, task_repo: TaskRepository = TaskRepository()):
        self.task_repo = task_repo

    @staticmethod
    def get_user_day_bounds(user_timezone_str: str) -> Tuple[datetime, datetime]:
        """
        Calculates the start and end of 'today' according to the user's configured timezone,
        returned as UTC datetime objects for accurate database querying.
        """
        try:
            tz = ZoneInfo(user_timezone_str)
        except Exception:
            tz = timezone.utc

        now_in_user_tz = datetime.now(tz)
        start_of_day_local = datetime.combine(now_in_user_tz.date(), time.min, tzinfo=tz)
        end_of_day_local = datetime.combine(now_in_user_tz.date(), time.max, tzinfo=tz)

        start_of_day_utc = start_of_day_local.astimezone(timezone.utc)
        end_of_day_utc = end_of_day_local.astimezone(timezone.utc)
        return start_of_day_utc, end_of_day_utc

    def get_task_or_404(self, db: Session, task_id: str, user_id: str) -> Task:
        """
        Retrieves task by ID. Returns HTTP 404 if the task doesn't exist OR belongs
        to another user to prevent entity enumeration.
        """
        task = self.task_repo.get_by_id(db, task_id, user_id)
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Task with id '{task_id}' not found",
            )
        return task

    def create_task(self, db: Session, user: User, task_in: TaskCreate) -> Task:
        task_data = task_in.model_dump()
        task = Task(user_id=user.id, **task_data)
        return self.task_repo.create(db, task)

    def list_tasks(
        self,
        db: Session,
        user_id: str,
        status_filter: Optional[TaskStatus] = None,
        category: Optional[str] = None,
        task_type: Optional[TaskType] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[Task], int]:
        # Enforce maximum pagination limit
        safe_limit = min(max(1, limit), 100)
        safe_offset = max(0, offset)
        return self.task_repo.list_by_user(
            db=db,
            user_id=user_id,
            status=status_filter,
            category=category,
            task_type=task_type,
            limit=safe_limit,
            offset=safe_offset,
        )

    def list_today_tasks(self, db: Session, user: User) -> List[Task]:
        user_tz = user.preferences.timezone if user.preferences else "UTC"
        start_of_day, end_of_day = self.get_user_day_bounds(user_tz)
        return self.task_repo.list_today_tasks(db, user.id, start_of_day, end_of_day)

    def update_task(self, db: Session, task_id: str, user_id: str, task_update: TaskUpdate) -> Task:
        task = self.get_task_or_404(db, task_id, user_id)
        update_data = task_update.model_dump(exclude_unset=True)
        return self.task_repo.update(db, task, update_data)

    def start_task(self, db: Session, task_id: str, user_id: str) -> Task:
        """
        Enforces legal state transitions for starting work.
        - todo / postponed -> in_progress (allowed)
        - in_progress -> in_progress (idempotent)
        - completed / cancelled / archived -> 400 Bad Request
        """
        task = self.get_task_or_404(db, task_id, user_id)

        if task.status == TaskStatus.in_progress:
            return task

        if task.status == TaskStatus.completed:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot start a task that has already been completed",
            )
        if task.status == TaskStatus.cancelled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot start a cancelled task",
            )
        if task.status == TaskStatus.archived:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot start an archived task",
            )

        update_data = {
            "status": TaskStatus.in_progress,
            "started_at": datetime.now(timezone.utc),
        }
        return self.task_repo.update(db, task, update_data)

    def complete_task(self, db: Session, task_id: str, user_id: str, complete_in: TaskComplete) -> Task:
        """
        Enforces legal state transitions for task completion.
        - in_progress / todo / postponed -> completed (allowed)
        - completed -> completed (idempotent)
        - cancelled / archived -> 400 Bad Request
        """
        task = self.get_task_or_404(db, task_id, user_id)

        if task.status == TaskStatus.completed:
            return task

        if task.status == TaskStatus.cancelled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot complete a cancelled task",
            )
        if task.status == TaskStatus.archived:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot complete an archived task",
            )

        completion_time = complete_in.completed_at or datetime.now(timezone.utc)
        update_data = {
            "status": TaskStatus.completed,
            "completed_at": completion_time,
        }
        return self.task_repo.update(db, task, update_data)

    def delete_task(self, db: Session, task_id: str, user_id: str, permanent: bool = False) -> Task:
        """
        By default, performs a soft-delete (archives task) to safeguard TaskPerformance history.
        Permanent deletion only occurs if permanent=True is explicitly passed.
        """
        task = self.get_task_or_404(db, task_id, user_id)
        if permanent:
            self.task_repo.hard_delete(db, task)
            return task
        return self.task_repo.soft_delete(db, task)
