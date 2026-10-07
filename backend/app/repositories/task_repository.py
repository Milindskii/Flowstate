from typing import Optional, List, Tuple
from datetime import date, datetime
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
        day: date,
        start_of_day: datetime,
        end_of_day: datetime,
    ) -> List[Task]:
        """Tasks relevant to the user's local today (see ``list_open_for_day``). Future-planned tasks never bleed in."""
        # Single source of truth shared with the day view and Replan.
        return TaskRepository.list_open_for_day(db, user_id, day, start_of_day, end_of_day, True)

    @staticmethod
    def list_for_planning(db: Session, user_id: str, since: datetime) -> List[Task]:
        """Persisted tasks that occupy or affect the schedule from ``since`` onwards (build/replan input).

        Scoped to ``user_id``. Includes open tasks with a slot, every in-progress task, and tasks
        completed since ``since`` (their time is busy).
        """
        return db.query(Task).filter(
            Task.user_id == user_id,
            or_(
                and_(Task.status.in_([TaskStatus.todo, TaskStatus.postponed]),
                     Task.scheduled_start.isnot(None), Task.scheduled_start >= since),
                Task.status == TaskStatus.in_progress,
                and_(Task.status == TaskStatus.completed, Task.completed_at >= since),
            ),
        ).all()

    @staticmethod
    def _owned_by_day(day: date, day_start: datetime, day_end: datetime):
        """Task belongs to local ``day``: its planned_date; legacy rows without one fall back to their slot.

        Never created_at / completed_at (date invariant: completing a task never moves it to today).
        """
        return or_(
            Task.planned_date == day,
            and_(Task.planned_date.is_(None), Task.scheduled_start.between(day_start, day_end)),
        )

    @staticmethod
    def list_open_for_day(db: Session, user_id: str, day: date, day_start: datetime, day_end: datetime,
                          is_today: bool) -> List[Task]:
        """THE day-relevance query: day view, Replan and (via the day view) Today all use it.

        Open (todo/in_progress) tasks owned by the local ``day`` ([day_start, day_end] are its UTC bounds).
        Scoped to ``user_id``. Today additionally shows (without changing their planned_date):
          * in-progress work;
          * work due today or overdue by its deadline, unless planned/slotted for a later day;
          * legacy undated rows (no planned_date, no slot).
        A missed task without a deadline stays on its own day; only an explicit reschedule moves it.
        """
        open_states = [TaskStatus.todo, TaskStatus.in_progress]
        owned = TaskRepository._owned_by_day(day, day_start, day_end)
        if is_today:
            cond = or_(
                owned,
                Task.status == TaskStatus.in_progress,
                and_(Task.deadline_at <= day_end,
                     or_(Task.planned_date.is_(None), Task.planned_date <= day),
                     or_(Task.scheduled_start.is_(None), Task.scheduled_start <= day_end)),
                and_(Task.planned_date.is_(None), Task.scheduled_start.is_(None)),
            )
        else:
            cond = owned
        return (
            db.query(Task)
            .filter(Task.user_id == user_id, Task.status.in_(open_states), cond)
            .order_by(Task.priority.desc(), Task.created_at.asc())
            .all()
        )

    @staticmethod
    def list_completed_for_day(db: Session, user_id: str, day: date, day_start: datetime, day_end: datetime) -> List[Task]:
        """Completed tasks owned by ``day``. A task planned Oct 1 and completed Oct 3 stays on Oct 1."""
        return db.query(Task).filter(
            Task.user_id == user_id,
            Task.status == TaskStatus.completed,
            TaskRepository._owned_by_day(day, day_start, day_end),
        ).all()

    @staticmethod
    def create(db: Session, task: Task) -> Task:
        db.add(task)
        db.commit()
        db.refresh(task)
        return task

    @staticmethod
    def add_no_commit(db: Session, task: Task) -> Task:
        """Stage a task inside the caller's transaction (caller commits once)."""
        db.add(task)
        db.flush()
        return task

    @staticmethod
    def find_open_duplicate(db: Session, user_id: str, title: str, start, minutes: int):
        """An open task of this user with identical title/start/duration (double-submit guard)."""
        q = db.query(Task).filter(
            Task.user_id == user_id,
            Task.status.in_([TaskStatus.todo, TaskStatus.in_progress, TaskStatus.postponed]),
            Task.estimated_minutes == minutes,
        )
        for t in q.filter(Task.scheduled_start == start).all():
            if t.title.strip().lower() == title.strip().lower():
                return t
        return None

    @staticmethod
    def update(db: Session, task: Task, update_data: dict) -> Task:
        # Explicit nulls are honoured (e.g. clearing scheduled_start). Non-nullable
        # fields are rejected with None at the schema layer (TaskUpdate), so a None
        # reaching here is always an intentional clear.
        for key, value in update_data.items():
            if hasattr(task, key):
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
