from typing import Optional
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

class FeedbackCreate(BaseModel):
    actual_minutes: Optional[int] = Field(default=None, ge=1, le=1440)
    # each rating is optional: an unrated field is stored as NULL, never a made-up 3
    focus_score: Optional[int] = Field(default=None, ge=1, le=5)
    energy_score: Optional[int] = Field(default=None, ge=1, le=5)
    difficulty_score: Optional[int] = Field(default=None, ge=1, le=5)
    distraction_score: Optional[int] = Field(default=None, ge=1, le=5)
    notes: Optional[str] = None

class FeedbackResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    completed_at: datetime
    estimated_minutes: int
    actual_minutes: int
    focus_score: Optional[int] = None
    energy_score: Optional[int] = None
    difficulty_score: Optional[int] = None
    distraction_score: Optional[int] = None
    notes: Optional[str] = None
    provenance: str = "reflection"
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
