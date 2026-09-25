from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from ..models.readiness_observation import ObservationSource

class ReadinessProfileSchema(BaseModel):
    id: str
    user_id: str
    version: int
    preferred_peak_start: str
    preferred_peak_end: str
    preferred_dip_start: str
    preferred_dip_end: str
    typical_sleep_minutes: int
    weekday_wake_time: str
    weekend_wake_time: str
    wake_variability: float
    sleep_inertia_minutes: int
    preferred_session_minutes: int
    energy_predictability: str
    optimization_goal: str
    personalization_enabled: bool
    confidence_level: float
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class ReadinessOnboardingRequest(BaseModel):
    """Payload submitted at completion of the 12-question adaptive onboarding flow."""
    preferred_peak_start: str = Field(default="09:30", description="HH:MM start of strongest focus window")
    preferred_peak_end: str = Field(default="11:45", description="HH:MM end of strongest focus window")
    weekday_wake_time: str = Field(default="07:00", description="HH:MM wake time when having obligations")
    weekend_wake_time: str = Field(default="08:30", description="HH:MM wake time on free days")
    bedtime: str = Field(default="23:00", description="HH:MM usual fall asleep time")
    sleep_inertia_minutes: int = Field(default=30, ge=0, le=180, description="Time until properly awake")
    draining_work_types: List[str] = Field(default_factory=list, description="Work categories that cost the most focus")
    fatigue_symptom: Optional[str] = Field(default="distracted", description="Behavior when tired")
    session_disruptor: Optional[str] = Field(default="phone", description="Primary focus disruptor")
    preferred_session_minutes: int = Field(default=45, ge=15, le=180, description="Comfortable focus duration before break")
    primary_goal: str = Field(default="start_difficult_work", description="What Flowstate should help with most")
    energy_predictability: str = Field(default="mostly_predictable", description="Predictability of day-to-day energy")
    schedule_disruptors: List[str] = Field(default_factory=list, description="Regular schedule changers")
    adaptive_followup_answers: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Answers to triggered follow-up questions")
    timezone: Optional[str] = Field(default="Asia/Kolkata", description="User local IANA timezone")

class StartingRhythmSummary(BaseModel):
    focus_window_range: str
    readiness_score: int
    recommendation_band: str
    confidence: float
    explanation: str

class ReadinessOnboardingResponse(ReadinessProfileSchema):
    starting_rhythm: Optional[StartingRhythmSummary] = None
    profile_version: int = 1

class ObservationCreate(BaseModel):
    task_id: Optional[str] = None
    wake_time: Optional[str] = None
    sleep_minutes: Optional[int] = Field(default=None, ge=60, le=960)
    sleep_quality: Optional[int] = Field(default=None, ge=1, le=5)
    time_since_waking: Optional[int] = Field(default=None, ge=0, le=1440)
    energy_rating: Optional[int] = Field(default=None, ge=1, le=5)
    focus_rating: Optional[int] = Field(default=None, ge=1, le=5)
    difficulty_rating: Optional[int] = Field(default=None, ge=1, le=5)
    distraction_rating: Optional[int] = Field(default=None, ge=1, le=5)
    environment_type: Optional[str] = Field(default=None, max_length=50)
    task_type: Optional[str] = Field(default=None, max_length=50)
    task_difficulty: Optional[str] = Field(default=None, max_length=50)
    planned_minutes: Optional[int] = Field(default=None, ge=1, le=480)
    actual_minutes: Optional[int] = Field(default=None, ge=1, le=480)
    outcome: Optional[str] = Field(default=None, max_length=50)
    source: ObservationSource = Field(default=ObservationSource.self_report)

class ObservationResponse(BaseModel):
    id: str
    user_id: str
    task_id: Optional[str] = None
    observed_at: datetime
    energy_rating: Optional[int] = None
    focus_rating: Optional[int] = None
    difficulty_rating: Optional[int] = None
    distraction_rating: Optional[int] = None
    task_type: Optional[str] = None
    planned_minutes: Optional[int] = None
    actual_minutes: Optional[int] = None
    outcome: Optional[str] = None
    source: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class ReadinessPredictionResponse(BaseModel):
    id: str
    user_id: str
    task_id: Optional[str] = None
    slot_start: Optional[datetime] = None
    slot_end: Optional[datetime] = None
    readiness_score: int
    task_fit_score: int
    confidence: float
    recommendation_band: str
    model_version: str
    top_factors: List[str]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class TodayReadinessResponse(BaseModel):
    readiness_score: int
    task_fit_score: int
    confidence: float
    recommendation_band: str
    stage: str # "Stage A (Rules)", "Stage B (Empirical)", "Stage C (Personal Model)"
    observation_count: int
    top_factors: List[str]
    focus_window_range: str
    explanation: str
    model_version: str
    hourly_rhythm: List[Dict[str, Any]]
