from typing import Optional
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

class FeedbackCreate(BaseModel):
    actual_minutes: Optional[int] = Field(default=None, ge=1, le=1440)
    focus_score: int = Field(default=3, ge=1, le=5)
    energy_score: int = Field(default=3, ge=1, le=5)
    difficulty_score: int = Field(default=3, ge=1, le=5)
    distraction_score: Optional[int] = Field(default=None, ge=1, le=5)
    notes: Optional[str] = None

class FeedbackResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    completed_at: datetime
    estimated_minutes: int
    actual_minutes: int
    focus_score: int
    energy_score: int
    difficulty_score: int
    distraction_score: Optional[int] = None
    notes: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
