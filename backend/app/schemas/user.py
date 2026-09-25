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
    accent_color: str = "cyan"
    density_mode: str = "comfortable"

    model_config = ConfigDict(from_attributes=True)

class UserPreferencesUpdate(BaseModel):
    timezone: Optional[str] = None
    wake_time: Optional[str] = None
    sleep_hours: Optional[float] = None
    focus_peak: Optional[str] = None
    energy_dip_time: Optional[str] = None
    primary_goal: Optional[str] = None
    accent_color: Optional[str] = None
    density_mode: Optional[str] = None

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    avatar_url: Optional[str] = None
    is_active: bool
    created_at: datetime
    onboarding_completed: bool = False
    terms_accepted: bool = False
    privacy_accepted: bool = False
    age_confirmed: bool = False
    marketing_emails_enabled: bool = False
    consent_at: Optional[datetime] = None
    preferences: Optional[UserPreferencesSchema] = None

    model_config = ConfigDict(from_attributes=True)

class ConsentUpdateRequest(BaseModel):
    terms_accepted: bool = True
    privacy_accepted: bool = True
    age_confirmed: bool = True
    marketing_emails_enabled: Optional[bool] = False

class EmailPreferencesUpdateRequest(BaseModel):
    marketing_emails_enabled: bool

class DeleteAccountResponse(BaseModel):
    success: bool
    message: str
    deleted_user_id: str

class UserExportDataResponse(BaseModel):
    user_id: str
    email: str
    name: str
    exported_at: datetime
    preferences: Optional[dict] = None
    tasks_count: int = 0
    tasks: list = []
    flow_profile: Optional[dict] = None
    companion: Optional[dict] = None
    completed_sessions_count: int = 0

class AccountDeactivateResponse(BaseModel):
    success: bool
    status: str
    message: str
    user_id: str

class AccountReactivateResponse(BaseModel):
    success: bool
    status: str
    message: str
    user_id: str

class GrievanceCreateRequest(BaseModel):
    request_type: str = "general_grievance"
    message: str
    email: Optional[EmailStr] = None

class GrievanceResponse(BaseModel):
    ticket_id: str
    status: str
    message: str
    request_type: str
    email: str
    contact_email: str
    created_at: datetime

