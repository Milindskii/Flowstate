import uuid
from datetime import datetime, timezone
import enum
from sqlalchemy import JSON, Boolean, Column, Date, ForeignKey, Index, Integer, String, Text, Enum as SQLEnum, false
from sqlalchemy.orm import relationship
from ..db.session import Base
from ..db.types import UTCDateTime

def utcnow():
    return datetime.now(timezone.utc)

class TaskStatus(str, enum.Enum):
    todo = "todo"
    in_progress = "in_progress"
    completed = "completed"
    cancelled = "cancelled"
    postponed = "postponed"
    archived = "archived"

class TaskType(str, enum.Enum):
    deep_work = "deep_work"
    shallow_work = "shallow_work"
    study = "study"
    creative = "creative"
    admin = "admin"
    physical = "physical"
    meeting = "meeting"
    personal = "personal"

class TaskDifficulty(str, enum.Enum):
    high = "high"
    medium = "medium"
    light = "light"
    physical = "physical"

class TaskPriority(str, enum.Enum):
    low = "low"
    medium = "medium"
    high = "high"
    urgent = "urgent"

class TaskSource(str, enum.Enum):
    manual = "manual"
    ai_parsed = "ai_parsed"
    calendar = "calendar"
    imported = "imported"

class Task(Base):
    __tablename__ = "tasks"
    __table_args__ = (Index("ix_tasks_user_scheduled_start", "user_id", "scheduled_start"),)

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    title = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    category = Column(String(50), nullable=False, default="General")

    task_type = Column(SQLEnum(TaskType), nullable=False, default=TaskType.deep_work)
    difficulty = Column(SQLEnum(TaskDifficulty), nullable=False, default=TaskDifficulty.medium)
    priority = Column(SQLEnum(TaskPriority), nullable=False, default=TaskPriority.medium)

    estimated_minutes = Column(Integer, nullable=False, default=45)

    # Real temporal definitions
    deadline_at = Column(UTCDateTime, nullable=True)
    scheduled_start = Column(UTCDateTime, nullable=True)
    scheduled_end = Column(UTCDateTime, nullable=True)

    # True ONLY when the user (or an external calendar/import source) fixed this start time.
    # Scheduler-chosen times are never locked. See spec section 3.
    time_locked = Column(Boolean, nullable=False, default=False, server_default=false())
    # A fixed block the user is away for ("Going out 6:30-8:30"): always time_locked, but not work: never remaining
    # minutes, current, missed, completable or movable by Replan. Migration 011.
    is_commitment = Column(Boolean, nullable=False, default=False, server_default=false())
    # "Intended for this local date, time not chosen" (replaces the midnight-deadline hack).
    planned_date = Column(Date, nullable=True)

    # Build My Day contract (migration 009). *_source: "explicit" (user-stated) | "inferred".
    focus_level = Column(String(16), nullable=True)        # low | medium | high
    deadline_kind = Column(String(16), nullable=True)      # hard (never exceeded) | soft (preferred target)
    priority_source = Column(String(16), nullable=True)
    duration_source = Column(String(16), nullable=True)
    focus_source = Column(String(16), nullable=True)
    depends_on = Column(JSON, nullable=True)               # task ids that must finish first
    # Written only when the user explicitly stated a preferred time/window; never inferred.
    preferred_start = Column(UTCDateTime, nullable=True)
    preferred_window_start = Column(UTCDateTime, nullable=True)
    preferred_window_end = Column(UTCDateTime, nullable=True)

    status = Column(SQLEnum(TaskStatus), nullable=False, default=TaskStatus.todo, index=True)
    source = Column(SQLEnum(TaskSource), nullable=False, default=TaskSource.manual)

    started_at = Column(UTCDateTime, nullable=True)
    completed_at = Column(UTCDateTime, nullable=True)

    created_at = Column(UTCDateTime, default=utcnow, nullable=False)
    updated_at = Column(UTCDateTime, default=utcnow, onupdate=utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="tasks")
    performance_records = relationship("TaskPerformance", back_populates="task", cascade="all, delete-orphan")
