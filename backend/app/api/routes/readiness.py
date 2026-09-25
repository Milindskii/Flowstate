from typing import Optional, List
from fastapi import APIRouter, Depends, status, HTTPException
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.readiness import (
    ReadinessProfileSchema,
    ReadinessOnboardingRequest,
    ReadinessOnboardingResponse,
    TodayReadinessResponse,
    ObservationCreate,
    ObservationResponse,
)
from ...services.readiness_service import ReadinessService
from ...services.observation_service import ObservationService

router = APIRouter(prefix="/readiness", tags=["Readiness Engine V2"])
readiness_service = ReadinessService()
observation_service = ObservationService()

@router.get("/profile", response_model=ReadinessProfileSchema)
def get_readiness_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves current user readiness profile, creating baseline if not yet established."""
    profile = readiness_service.get_or_create_default_profile(db, current_user.id)
    return profile

@router.get("/today", response_model=TodayReadinessResponse)
def get_today_readiness(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns non-medical progressive readiness estimate for the current local context:
    - readiness_score (0-100)
    - task_fit_score (0-100)
    - confidence (0.0-1.0)
    - recommendation_band ('strong_fit', 'reasonable_fit', 'light_work_preferred')
    - stage ('Stage A', 'Stage B', 'Stage C')
    - top_factors
    - hourly_rhythm
    """
    return readiness_service.get_today_readiness(db, current_user.id)

@router.post("/onboarding", response_model=ReadinessOnboardingResponse, status_code=status.HTTP_201_CREATED)
def submit_onboarding_questionnaire(
    onboarding: ReadinessOnboardingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submits answers from the 12-question adaptive onboarding flow to establish baseline profile."""
    return readiness_service.submit_onboarding_answers(db, current_user.id, onboarding)

@router.post("/observations", response_model=ObservationResponse, status_code=status.HTTP_201_CREATED)
def record_observation(
    observation_in: ObservationCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records a new behavioral observation or manual check-in tagged with source provenance."""
    obs = observation_service.record_observation(db, current_user.id, observation_in)
    return obs
