from typing import Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query, status, HTTPException
from sqlalchemy.orm import Session
from ...db.session import get_db
from ...core.security import get_current_user, get_current_user_allow_deactivated, security_scheme, decode_access_token
from fastapi.security import HTTPAuthorizationCredentials
from ...models.user import User
from ...models.task import Task
from ...models.flow_progression import FlowProfile, FlowCompanion, FlowFocusSession
from ...models.privacy_grievance import PrivacyGrievance
from ...schemas.user import (
    UserResponse,
    UserPreferencesSchema,
    UserPreferencesUpdate,
    ConsentUpdateRequest,
    EmailPreferencesUpdateRequest,
    DeleteAccountResponse,
    UserExportDataResponse,
    AccountDeactivateResponse,
    AccountReactivateResponse,
    GrievanceCreateRequest,
    GrievanceResponse,
)
from ...services.user_service import UserService

router = APIRouter(prefix="/auth", tags=["Authentication & Profile"])
user_service = UserService()

@router.get("/me", response_model=UserResponse)
def get_current_user_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns the authenticated user profile and circadian rhythm preferences.
    User identity is authenticated via Supabase JWT.
    """
    is_completed = bool(current_user.onboarding_completed or (current_user.readiness_profile is not None))
    if is_completed and not current_user.onboarding_completed:
        current_user.onboarding_completed = True
        db.commit()
        db.refresh(current_user)
    return current_user

@router.patch("/preferences", response_model=UserPreferencesSchema)
def update_user_preferences(
    preferences_update: UserPreferencesUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Updates circadian rhythm preferences and user timezone (e.g. Asia/Kolkata).
    """
    updated = user_service.update_preferences(db, current_user.id, preferences_update)
    return updated

@router.post("/consent", response_model=UserResponse)
def update_user_consent(
    consent: ConsentUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Records explicit user consent for Terms of Service, Privacy Policy,
    and Age Verification (16+ / COPPA compliance).
    """
    current_user.terms_accepted = consent.terms_accepted
    current_user.privacy_accepted = consent.privacy_accepted
    current_user.age_confirmed = consent.age_confirmed
    if consent.marketing_emails_enabled is not None:
        current_user.marketing_emails_enabled = consent.marketing_emails_enabled
    current_user.consent_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(current_user)
    return current_user

@router.patch("/email-preferences", response_model=UserResponse)
def update_email_preferences(
    pref: EmailPreferencesUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Updates marketing / digest email preferences for the authenticated user.
    """
    current_user.marketing_emails_enabled = pref.marketing_emails_enabled
    db.commit()
    db.refresh(current_user)
    return current_user

@router.get("/unsubscribe")
@router.post("/unsubscribe")
def unsubscribe_email(
    email: Optional[str] = Query(None, description="User email to unsubscribe"),
    db: Session = Depends(get_db),
):
    """
    One-click unsubscribe endpoint complying with RFC 8058 and CAN-SPAM.
    Disables marketing emails without requiring login.
    """
    if not email:
        return {"status": "ok", "message": "Unsubscribe requested. Please provide a valid email."}
    user = db.query(User).filter(User.email == email.strip().lower()).first()
    if user:
        user.marketing_emails_enabled = False
        db.commit()
    return {
        "status": "ok",
        "message": f"Successfully unsubscribed {email} from Flowstate marketing & digest emails.",
    }

@router.post("/export-data", response_model=UserExportDataResponse)
def export_user_data(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    GDPR Article 20 Right to Data Portability:
    Generates a structured, machine-readable JSON bundle of all personal data,
    tasks, rhythm preferences, and focus history.
    """
    tasks = db.query(Task).filter(Task.user_id == current_user.id).all()
    tasks_data = [
        {
            "id": t.id,
            "title": t.title,
            "category": t.category,
            "estimated_minutes": t.estimated_minutes,
            "is_completed": str(getattr(t, "status", "")).lower().endswith("completed"),
            "is_priority": str(getattr(t, "priority", "")).lower().endswith(("high", "urgent")),
            "created_at": t.created_at.isoformat() if t.created_at else None,
        }
        for t in tasks
    ]

    pref_data = None
    if current_user.preferences:
        p = current_user.preferences
        pref_data = {
            "timezone": p.timezone,
            "wake_time": p.wake_time,
            "sleep_hours": p.sleep_hours,
            "focus_peak": p.focus_peak,
            "energy_dip_time": p.energy_dip_time,
            "primary_goal": p.primary_goal,
            "accent_color": p.accent_color,
            "density_mode": p.density_mode,
        }

    flow_profile = db.query(FlowProfile).filter(FlowProfile.user_id == current_user.id).first()
    companion = db.query(FlowCompanion).filter(FlowCompanion.user_id == current_user.id, FlowCompanion.is_active == True).first()
    sessions_count = db.query(FlowFocusSession).filter(FlowFocusSession.user_id == current_user.id, FlowFocusSession.status == "completed").count()

    return UserExportDataResponse(
        user_id=current_user.id,
        email=current_user.email,
        name=current_user.name,
        exported_at=datetime.now(timezone.utc),
        preferences=pref_data,
        tasks_count=len(tasks),
        tasks=tasks_data,
        flow_profile={
            "flow_balance": flow_profile.flow_balance if flow_profile else 0,
            "lifetime_flow": flow_profile.lifetime_flow if flow_profile else 0,
            "current_streak": flow_profile.current_streak if flow_profile else 0,
            "shields_available": flow_profile.shields_available if flow_profile else 0,
        } if flow_profile else None,
        companion={
            "species": companion.species if companion else "fox",
            "name": companion.name if companion else "Noya",
            "level": companion.level if companion else 1,
            "stage": companion.stage if companion else "Baby",
        } if companion else None,
        completed_sessions_count=sessions_count,
    )

@router.delete("/me", response_model=DeleteAccountResponse)
def delete_current_user_account(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    GDPR Article 17 Right to Erasure ("Right to be Forgotten") & CCPA deletion:
    Permanently deletes the user account and cascades deletion across all
    tasks, task performances, readiness observations, preferences, and companion progression.
    """
    user_id = current_user.id
    email = current_user.email

    db.delete(current_user)
    db.commit()

    return DeleteAccountResponse(
        success=True,
        message=f"Account for {email} and all associated personal data have been permanently deleted.",
        deleted_user_id=user_id,
    )

@router.post("/deactivate", response_model=AccountDeactivateResponse)
def deactivate_current_user_account(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Deactivates the user account without permanently erasing data.
    The account becomes inaccessible and non-essential processing is suspended.
    The user can reactivate at any time.
    """
    current_user.is_active = False
    db.commit()
    return AccountDeactivateResponse(
        success=True,
        status="deactivated",
        message="Your account has been deactivated. Your tasks and progression remain safely preserved, and non-essential processing is suspended. You can reactivate anytime by logging back in.",
        user_id=current_user.id,
    )

@router.post("/reactivate", response_model=AccountReactivateResponse)
def reactivate_user_account(
    current_user: User = Depends(get_current_user_allow_deactivated),
    db: Session = Depends(get_db),
):
    """
    Reactivates a deactivated user account.
    """
    current_user.is_active = True
    db.commit()
    db.refresh(current_user)
    return AccountReactivateResponse(
        success=True,
        status="active",
        message="Welcome back! Your account has been reactivated.",
        user_id=current_user.id,
    )

@router.post("/grievance", response_model=GrievanceResponse)
def submit_privacy_grievance(
    grievance_in: GrievanceCreateRequest,
    db: Session = Depends(get_db),
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme),
):
    """
    Submits a privacy inquiry, data access/correction request, or grievance.
    No fabricated SLA promises: strictly confirms receipt and states response will be provided
    as required by applicable law.
    """
    user_id = None
    email = grievance_in.email
    if credentials and credentials.credentials:
        payload = decode_access_token(credentials.credentials)
        if payload:
            user_id = payload.get("sub")
            if not email:
                email = payload.get("email")

    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Contact email is required to submit a privacy grievance",
        )

    grievance = PrivacyGrievance(
        user_id=user_id,
        email=str(email).strip().lower(),
        request_type=grievance_in.request_type,
        message=grievance_in.message.strip(),
        status="received",
    )
    db.add(grievance)
    db.commit()
    db.refresh(grievance)

    return GrievanceResponse(
        ticket_id=grievance.id,
        status="received",
        message="Your privacy inquiry or grievance has been received. We will review your request and respond as required by applicable law.",
        request_type=grievance.request_type,
        email=grievance.email,
        contact_email="Milindkrishnan24@gmail.com",
        created_at=grievance.created_at,
    )

