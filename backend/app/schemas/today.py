from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
from .task import TaskResponse

class TodayUserContext(BaseModel):
    id: str
    email: str
    name: str
    timezone: str = "Asia/Kolkata"

class ReadinessDetail(BaseModel):
    score: Optional[int] = None
    max_score: int = 100
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    model_version: str = "v1.0.0-deterministic"
    status_message: str = "Learning your rhythm"
    focus_window_range: str = "9:30 AM – 11:30 AM"
    explanation: str = "We're still learning when you work best."
    is_calibrated: bool = False
    factors: List[str] = Field(default_factory=list)
    hourly_rhythm: List[Dict[str, Any]] = Field(default_factory=list)

class CurrentRecommendation(BaseModel):
    task: Optional[TaskResponse] = None
    reasons: List[str] = Field(default_factory=list)

class AIBrief(BaseModel):
    title: str = "FLOWSTATE"
    message: str
    action_label: str = "Use this plan"

class WorkloadSummary(BaseModel):
    planned_minutes: int = 0
    formatted_workload: str = "0m planned"
    message: str = "Let's build your day."
    is_overloaded: bool = False
    available_minutes: int = 480

class ScheduleItemResponse(BaseModel):
    id: str
    time: str
    period: str
    title: str
    type: str
    tag_text: str
    is_active: bool = False
    duration_minutes: int = 60

class CalendarContext(BaseModel):
    events_count: int = 0
    next_event: Optional[str] = None

class TodayResponse(BaseModel):
    user: TodayUserContext
    date: str
    lifecycle_state: str  # "new_user" | "learning" | "calibrated"
    readiness: ReadinessDetail
    current_recommendation: Optional[CurrentRecommendation] = None
    ai_brief: AIBrief
    workload_summary: WorkloadSummary
    active_task: Optional[TaskResponse] = None
    upcoming_timeline: List[ScheduleItemResponse] = Field(default_factory=list)
    calendar_context: CalendarContext
