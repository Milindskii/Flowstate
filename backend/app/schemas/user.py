from typing import Optional
from datetime import datetime
from pydantic import BaseModel, ConfigDict, EmailStr

class UserPreferencesSchema(BaseModel):
    timezone: str = "Asia/Kolkata"
    wake_time: str = "06:45"
    sleep_hours: float = 7.5
    focus_peak: str = "morning"
    energy_dip_time: str = "14:30"
    primary_goal: str = "College"

    model_config = ConfigDict(from_attributes=True)

class UserPreferencesUpdate(BaseModel):
    timezone: Optional[str] = None
    wake_time: Optional[str] = None
    sleep_hours: Optional[float] = None
    focus_peak: Optional[str] = None
    energy_dip_time: Optional[str] = None
    primary_goal: Optional[str] = None

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    avatar_url: Optional[str] = None
    is_active: bool
    created_at: datetime
    preferences: Optional[UserPreferencesSchema] = None

    model_config = ConfigDict(from_attributes=True)
