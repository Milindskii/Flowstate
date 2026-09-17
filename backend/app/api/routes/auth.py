from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.user import UserResponse, UserPreferencesSchema, UserPreferencesUpdate
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
