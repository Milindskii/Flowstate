from typing import Optional, List
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from ..models.task import TaskStatus, TaskType, TaskDifficulty, TaskPriority, TaskSource

class TaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    category: str = "General"
    task_type: TaskType = TaskType.deep_work
    difficulty: TaskDifficulty = TaskDifficulty.medium
    priority: TaskPriority = TaskPriority.medium
    estimated_minutes: int = Field(default=45, ge=5, le=480)
    deadline_at: Optional[datetime] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    source: TaskSource = TaskSource.manual

class TaskUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    description: Optional[str] = None
    category: Optional[str] = None
    task_type: Optional[TaskType] = None
    difficulty: Optional[TaskDifficulty] = None
    priority: Optional[TaskPriority] = None
    estimated_minutes: Optional[int] = Field(default=None, ge=5, le=480)
    deadline_at: Optional[datetime] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    status: Optional[TaskStatus] = None

class TaskComplete(BaseModel):
    completed_at: Optional[datetime] = None
    actual_minutes: Optional[int] = Field(default=None, ge=1, le=1440)

class TaskResponse(BaseModel):
    id: str
    user_id: str
    title: str
    description: Optional[str] = None
    category: str
    task_type: TaskType
    difficulty: TaskDifficulty
    priority: TaskPriority
    estimated_minutes: int
    deadline_at: Optional[datetime] = None
    scheduled_start: Optional[datetime] = None
    scheduled_end: Optional[datetime] = None
    status: TaskStatus
    source: TaskSource
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class TaskListResponse(BaseModel):
    items: List[TaskResponse]
    total: int
    limit: int
    offset: int
