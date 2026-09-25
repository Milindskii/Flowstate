from typing import Optional, List, Tuple
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from ..models.task import Task, TaskStatus, TaskType

class TaskRepository:
    @staticmethod
    def get_by_id(db: Session, task_id: str, user_id: str) -> Optional[Task]:
        """Retrieves a task by ID ensuring it belongs to the authenticated user."""
        return db.query(Task).filter(Task.id == task_id, Task.user_id == user_id).first()

    @staticmethod
    def list_by_user(
        db: Session,
        user_id: str,
        status: Optional[TaskStatus] = None,
        category: Optional[str] = None,
        task_type: Optional[TaskType] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[Task], int]:
        """Paginated list of tasks for the authenticated user with optional filters."""
        query = db.query(Task).filter(Task.user_id == user_id)

        if status:
            query = query.filter(Task.status == status)
        else:
            # By default, do not surface archived tasks in general list
            query = query.filter(Task.status != TaskStatus.archived)

        if category and category.lower() != "all":
            query = query.filter(Task.category.ilike(category))
        if task_type:
            query = query.filter(Task.task_type == task_type)

        total = query.count()
        items = query.order_by(Task.created_at.desc()).offset(offset).limit(limit).all()
        return items, total

    @staticmethod
    def list_today_tasks(
        db: Session,
        user_id: str,
        start_of_day: datetime,
        end_of_day: datetime,
    ) -> List[Task]:
        """
        Retrieves tasks relevant to the user's current day:
        1. Explicitly scheduled for today (scheduled_start within day bounds)
        2. Currently active (status == in_progress)
        3. Due today AND not scheduled for a future day
        4. Overdue unfinished tasks (deadline_at < start_of_day)
        5. Unscheduled active tasks (no deadline and no future scheduled date)
        
        Does NOT bleed future-dated tasks (e.g. Due Friday) into today.
        """
        return db.query(Task).filter(
            Task.user_id == user_id,
            Task.status.in_([TaskStatus.todo, TaskStatus.in_progress]),
            or_(
                # 1. Explicitly scheduled for today
                Task.scheduled_start.between(start_of_day, end_of_day),
                # 2. Currently being worked on right now
                Task.status == TaskStatus.in_progress,
                # 3. Due today AND not scheduled for a future date
                and_(
                    Task.deadline_at.between(start_of_day, end_of_day),
                    or_(
                        Task.scheduled_start.is_(None),
                        Task.scheduled_start <= end_of_day
                    )
                ),
                # 4. Overdue unfinished tasks (deadline in the past and still todo/in_progress)
                and_(
                    Task.deadline_at < start_of_day,
                    or_(
                        Task.scheduled_start.is_(None),
                        Task.scheduled_start <= end_of_day
                    )
                ),
                # 5. Unscheduled active tasks (no deadline and no future scheduled start)
                and_(
                    Task.deadline_at.is_(None),
                    or_(
                        Task.scheduled_start.is_(None),
                        Task.scheduled_start.between(start_of_day, end_of_day)
                    )
                )
            )
        ).order_by(Task.priority.desc(), Task.created_at.asc()).all()

    @staticmethod
    def create(db: Session, task: Task) -> Task:
        db.add(task)
        db.commit()
        db.refresh(task)
        return task

    @staticmethod
    def update(db: Session, task: Task, update_data: dict) -> Task:
        for key, value in update_data.items():
            if value is not None and hasattr(task, key):
                setattr(task, key, value)
        db.commit()
        db.refresh(task)
        return task

    @staticmethod
    def soft_delete(db: Session, task: Task) -> Task:
        """Soft-deletes task by setting status to archived, preserving TaskPerformance records."""
        task.status = TaskStatus.archived
        db.commit()
        db.refresh(task)
        return task

    @staticmethod
    def hard_delete(db: Session, task: Task) -> None:
        """Permanently erases task and associated data from database."""
        db.delete(task)
        db.commit()
