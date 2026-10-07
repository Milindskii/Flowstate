from typing import Optional, List, Dict, Any, Literal
from uuid import uuid4
from datetime import date, datetime
from pydantic import BaseModel, ConfigDict, Field, model_validator
from ..models.task import TaskStatus, TaskType, TaskDifficulty, TaskPriority, TaskSource

Source = Literal["explicit", "inferred"]


class TaskQualityFields(BaseModel):
    """Build My Day contract fields persisted on tasks (spec 2026-10-03 §2, §9)."""
    focus_level: Optional[Literal["low", "medium", "high"]] = None
    deadline_kind: Optional[Literal["hard", "soft"]] = None
    priority_source: Optional[Source] = None
    duration_source: Optional[Source] = None
    focus_source: Optional[Source] = None
    depends_on: Optional[List[str]] = None
    preferred_start: Optional[datetime] = None
    preferred_window_start: Optional[datetime] = None
    preferred_window_end: Optional[datetime] = None


class TaskCreate(TaskQualityFields):
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
    time_locked: bool = False
    is_commitment: bool = False
    planned_date: Optional[date] = None

class FieldProvenance(BaseModel):
    source: str = "default"  # "explicit", "inferred", "default"
    confidence: float = 1.0


class TemporalConstraints(BaseModel):
    """User-stated timing information kept separate from the selected schedule."""
    fixed_start: Optional[datetime] = None
    earliest_start: Optional[datetime] = None
    latest_end: Optional[datetime] = None
    preferred_start: Optional[datetime] = None
    preferred_window_start: Optional[datetime] = None
    preferred_window_end: Optional[datetime] = None
    target_date: Optional[date] = None
    relative_before: Optional[str] = None
    relative_after: Optional[str] = None
    flexibility: str = "flexible"  # fixed | constrained | preferred | flexible
    confidence: float = 1.0
    provenance: Dict[str, FieldProvenance] = Field(default_factory=dict)


class FixedEventContext(BaseModel):
    title: str
    start_time: Optional[str] = None  # "HH:MM" e.g. "10:00"
    end_time: Optional[str] = None    # "HH:MM" e.g. "10:45"
    duration_minutes: Optional[int] = None
    target_date: Optional[date] = None


class TravelContext(BaseModel):
    from_location: Optional[str] = None
    to_location: Optional[str] = None
    duration_minutes: int = 30
    departure_time: Optional[str] = None  # "HH:MM" e.g. "08:30"
    target_date: Optional[date] = None


class ProtectedPeriodContext(BaseModel):
    name: str  # "lunch", "break", etc.
    preferred_start: Optional[str] = None  # "HH:MM" e.g. "13:00"
    duration_minutes: int = 45
    is_movable: bool = True
    target_date: Optional[date] = None


class AvailabilityContext(BaseModel):
    label: str  # e.g. "office_hours", "workday"
    start_time: Optional[str] = None  # "09:30"
    end_time: Optional[str] = None    # "17:30"
    target_date: Optional[date] = None


class TaskDependencyContext(BaseModel):
    predecessor: str  # task title or keyword
    successor: str    # task title or keyword


class PlanningContext(BaseModel):
    """Day-level planning context extracted from natural language brain dump."""
    fixed_events: List[FixedEventContext] = Field(default_factory=list)
    travel_segments: List[TravelContext] = Field(default_factory=list)
    protected_periods: List[ProtectedPeriodContext] = Field(default_factory=list)
    availability_windows: List[AvailabilityContext] = Field(default_factory=list)
    task_dependencies: List[TaskDependencyContext] = Field(default_factory=list)
    priority_order: List[str] = Field(default_factory=list)
    deferred_tasks: List[str] = Field(default_factory=list)
    energy_preference: Optional[str] = None  # e.g. "morning_heavy", "evening_heavy"
    buffer_preference: Optional[str] = None  # e.g. "spacious", "do_not_fill_every_minute"


class TaskCandidateResponse(TaskCreate):
    candidate_id: str = Field(default_factory=lambda: "c_" + uuid4().hex[:12])
    depends_on: List[str] = Field(default_factory=list)  # candidate_ids that must finish first
    confidence: float = 1.0
    missing_fields: List[str] = Field(default_factory=list)
    ambiguities: List[str] = Field(default_factory=list)
    field_provenance: dict[str, FieldProvenance] = Field(default_factory=dict)
    temporal: Optional[TemporalConstraints] = None
    target_date: Optional[date] = None
    fixed_start: Optional[str] = None
    deadline: Optional[str] = None
    recommended_slot_start: Optional[datetime] = None
    recommended_slot_end: Optional[datetime] = None
    recommended_slot_display: Optional[str] = None
    scheduling_explanation: Optional[str] = None
    scheduling_reasons: Optional[dict[str, Any]] = None
    recommended_slot_date: Optional[str] = None          # user-local YYYY-MM-DD of the recommended slot
    unscheduled_reason: Optional[str] = None             # set when the planner could not place it
    learned_hint: Optional[str] = None                   # "Usually Tuesday 7:00 PM": a learned routine was suggested
    validation_issues: List[dict[str, Any]] = Field(default_factory=list)  # [{code, field, message}]
    suggested_slot_start: Optional[datetime] = None      # roll-over proposal, never auto-applied
    suggested_slot_end: Optional[datetime] = None
    suggested_slot_display: Optional[str] = None

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
    time_locked: Optional[bool] = None
    planned_date: Optional[date] = None
    focus_level: Optional[Literal["low", "medium", "high"]] = None
    deadline_kind: Optional[Literal["hard", "soft"]] = None
    priority_source: Optional[Source] = None
    duration_source: Optional[Source] = None
    focus_source: Optional[Source] = None
    depends_on: Optional[List[str]] = None
    preferred_start: Optional[datetime] = None
    preferred_window_start: Optional[datetime] = None
    preferred_window_end: Optional[datetime] = None

    # Fields that may be explicitly set to null (clear). Everything else is non-nullable.
    _NULLABLE = {"description", "deadline_at", "scheduled_start", "scheduled_end", "planned_date",
                 "focus_level", "deadline_kind", "priority_source", "duration_source", "focus_source",
                 "depends_on", "preferred_start", "preferred_window_start", "preferred_window_end"}

    @model_validator(mode="after")
    def _reject_null_for_required_fields(self):
        for name in self.model_fields_set:
            if name not in self._NULLABLE and getattr(self, name) is None:
                raise ValueError(f"'{name}' cannot be null")
        return self

class TaskComplete(BaseModel):
    completed_at: Optional[datetime] = None
    actual_minutes: Optional[int] = Field(default=None, ge=1, le=1440)

class TaskParseRequest(BaseModel):
    text: Optional[str] = Field(default=None, max_length=1500, description="Natural language task description")
    raw_text: Optional[str] = Field(default=None, max_length=1500)
    timezone: Optional[str] = Field(default=None, max_length=64, description="IANA zone; falls back to the stored preference")
    use_ai: Optional[bool] = Field(default=False, description="Whether to prioritize cloud AI extraction")

    def get_clean_text(self) -> str:
        content = (self.text or self.raw_text or "").strip()
        if len(content) < 2:
            raise ValueError("Task description text must be at least 2 characters")
        if len(content) > 1500:
            raise ValueError("Task description text exceeds maximum limit of 1500 characters")
        return content

class TaskResponse(TaskQualityFields):
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
    time_locked: bool = False
    is_commitment: bool = False
    planned_date: Optional[date] = None
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

class BatchTaskItem(TaskQualityFields):
    # depends_on holds candidate_ids / client_refs of sibling items in the same batch.
    candidate_id: Optional[str] = Field(default=None, max_length=100)
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
    source: TaskSource = TaskSource.ai_parsed
    time_locked: bool = False
    is_commitment: bool = False
    planned_date: Optional[date] = None
    client_ref: Optional[str] = Field(default=None, max_length=100)  # echoed back so the client can swap temp ids

class BatchCreateAndScheduleRequest(BaseModel):
    tasks: List[BatchTaskItem] = Field(default_factory=list, max_length=100)
    idempotency_key: Optional[str] = Field(default=None, max_length=100)
    plan_id: Optional[str] = Field(default=None, max_length=100)   # preferred; falls back to idempotency_key
    timezone: Optional[str] = Field(default=None, max_length=64)   # IANA name
    current_local_time: Optional[datetime] = None                  # aware client clock

class BatchCreateAndScheduleResponse(BaseModel):
    created_count: int
    tasks: List[TaskResponse]                    # aligned 1:1 with the request items
    client_refs: List[Optional[str]] = Field(default_factory=list)  # aligned with `tasks`
    message: str = "Tasks created and scheduled successfully"
    adjustments: List[Dict[str, Any]] = Field(default_factory=list)   # server re-placed a stale slot
    unscheduled: List[Dict[str, Any]] = Field(default_factory=list)   # persisted without a slot (never dropped)
    deduplicated: List[Optional[str]] = Field(default_factory=list)   # client_refs that already existed
    conflicts: List[Dict[str, Any]] = Field(default_factory=list)
    timezone_used: Optional[str] = None
    idempotent_replay: bool = False

