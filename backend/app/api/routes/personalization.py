from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.personalization import (
    PersonalizationSettingsSchema,
    PersonalizationSettingsUpdate,
    PersonalizationResetResponse,
    PersonalizationExportResponse,
    PersonalizationEvaluationResponse,
)
from ...services.personalization_service import PersonalizationService
from ...services.evaluation_service import EvaluationService

router = APIRouter(prefix="/personalization", tags=["Personalization & Privacy"])
personalization_service = PersonalizationService()
evaluation_service = EvaluationService()

@router.get("/settings", response_model=PersonalizationSettingsSchema)
def get_personalization_settings(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns user personalization and privacy settings."""
    return personalization_service.get_settings(db, current_user.id)

@router.patch("/settings", response_model=PersonalizationSettingsSchema)
def update_personalization_settings(
    settings_update: PersonalizationSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates user personalization preferences and data usage toggles."""
    return personalization_service.update_settings(db, current_user.id, settings_update)

@router.post("/reset", response_model=PersonalizationResetResponse)
def reset_personalization_history(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Clears all recorded observations, predictions, and evaluation records for the authenticated user.
    Restores cold-start baseline confidence without affecting tasks or completed items.
    """
    return personalization_service.reset_user_personalization(db, current_user.id)

@router.get("/export", response_model=PersonalizationExportResponse)
def export_personalization_data(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Exports all stored personalization observations, predictions, and profile state for data portability."""
    return personalization_service.export_user_data(db, current_user.id)

@router.get("/evaluation", response_model=PersonalizationEvaluationResponse)
def get_model_evaluation_metrics(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns live prediction evaluation metrics for the user:
    - Brier calibration score
    - Overall completion and postponement rates
    - Actual vs planned duration ratios
    - Accuracy by time of day window
    """
    return evaluation_service.compute_evaluation_metrics(db, current_user.id)
