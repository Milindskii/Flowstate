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

class FieldProvenance(BaseModel):
    source: str = "default"  # "explicit", "inferred", "default"
    confidence: float = 1.0

class TaskCandidateResponse(TaskCreate):
    confidence: float = 1.0
    missing_fields: List[str] = Field(default_factory=list)
    ambiguities: List[str] = Field(default_factory=list)
    field_provenance: dict[str, FieldProvenance] = Field(default_factory=dict)

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

class TaskParseRequest(BaseModel):
    text: Optional[str] = Field(default=None, max_length=1500, description="Natural language task description")
    raw_text: Optional[str] = Field(default=None, max_length=1500)
    timezone: Optional[str] = Field(default="UTC", max_length=50)
    use_ai: Optional[bool] = Field(default=False, description="Whether to prioritize cloud AI extraction")

    def get_clean_text(self) -> str:
        content = (self.text or self.raw_text or "").strip()
        if len(content) < 2:
            raise ValueError("Task description text must be at least 2 characters")
        if len(content) > 1500:
            raise ValueError("Task description text exceeds maximum limit of 1500 characters")
        return content

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
