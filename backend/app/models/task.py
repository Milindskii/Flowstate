import uuid
from datetime import datetime, timezone
import enum
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Enum as SQLEnum, Text
from sqlalchemy.orm import relationship
from ..db.session import Base

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
    deadline_at = Column(DateTime(timezone=True), nullable=True)
    scheduled_start = Column(DateTime(timezone=True), nullable=True)
    scheduled_end = Column(DateTime(timezone=True), nullable=True)

    status = Column(SQLEnum(TaskStatus), nullable=False, default=TaskStatus.todo, index=True)
    source = Column(SQLEnum(TaskSource), nullable=False, default=TaskSource.manual)

    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="tasks")
    performance_records = relationship("TaskPerformance", back_populates="task", cascade="all, delete-orphan")
