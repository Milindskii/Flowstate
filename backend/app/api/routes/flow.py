from typing import List, Optional
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.flow import (
    FlowOverviewResponse,
    FlowCompanionResponse,
    SelectCompanionRequest,
    StartSessionRequest,
    StartSessionResponse,
    CompleteSessionRequest,
    CompleteSessionResponse,
    AbandonSessionResponse,
    EvolveResponse,
    ClaimChallengeResponse,
    ClaimQuestResponse,
    ShopItemResponse,
    PurchaseCompanionResponse,
    UseShieldResponse,
)
from ...services.flow_service import FlowService

router = APIRouter(prefix="/flow", tags=["Flow & Companion Progression"])
flow_service = FlowService()

@router.get("", response_model=FlowOverviewResponse)
def get_flow_overview(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Authoritative overview for the Flow screen:
    - Active Companion (Noya) with Level, XP, and Stage
    - Timezone-aware Streak and Shield count
    - Flow Points balance
    - Active Weekly Challenge
    - Personal Progress and League Cohort status
    """
    return flow_service.get_overview(db, current_user)

@router.post("/session/start", response_model=StartSessionResponse, status_code=status.HTTP_201_CREATED)
def start_focus_session(
    request: StartSessionRequest = StartSessionRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Server-owned session initiation.
    Records server_start_at and prevents overlapping sessions.
    """
    return flow_service.start_focus_session(db, current_user, request.task_id)

@router.post("/session/{session_id}/complete", response_model=CompleteSessionResponse)
def complete_focus_session(
    session_id: str,
    request: CompleteSessionRequest = CompleteSessionRequest(),
    test_mode: bool = Query(False, description="Enables short duration for automated tests"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Server-validated session completion.
    Computes elapsed duration from server clock, validates bounds, awards Companion XP & Flow,
    updates streak and shields, and enforces semantic idempotency.
    """
    return flow_service.complete_focus_session(
        db=db,
        user=current_user,
        session_id=session_id,
        task_completed=request.task_completed,
        feeling_score=request.feeling_score,
        idempotency_key=request.idempotency_key,
        test_mode=test_mode,
    )

@router.post("/session/{session_id}/abandon", response_model=AbandonSessionResponse)
def abandon_focus_session(
    session_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Recoverable session abandonment.
    Companion enters tired state; zero rewards; no companion death.
    """
    return flow_service.abandon_focus_session(db, current_user, session_id)

@router.post("/evolve", response_model=EvolveResponse)
def evolve_companion(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Triggers companion evolution when is_evolution_ready is true.
    Promotes stage (Baby -> Young -> Explorer -> Adult -> Evolved).
    """
    return flow_service.evolve_companion(db, current_user)

@router.post("/companion/select", response_model=FlowCompanionResponse)
def select_companion(
    request: SelectCompanionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Select active animal companion (Fox Noya, Otter Ludo, Owl Aria, Capybara Boba).
    Updates user's companion species and name in database.
    """
    return flow_service.select_companion(db, current_user, request.species, request.name)

@router.post("/challenge/{challenge_id}/claim", response_model=ClaimChallengeResponse)
def claim_challenge(
    challenge_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Claims reward for a completed weekly challenge.
    Protected against duplicate claims.
    """
    return flow_service.claim_challenge(db, current_user, challenge_id)

@router.post("/daily-quests/{quest_id}/claim", response_model=ClaimQuestResponse)
def claim_daily_quest(
    quest_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Claims reward for a completed daily quest.
    Protected against duplicate claims.
    """
    return flow_service.claim_daily_quest(db, current_user, quest_id)

@router.get("/shop", response_model=List[ShopItemResponse])
def get_shop_catalog(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns companion shop catalog with real ownership status
    sourced from the user's FlowInventoryItem records.
    Fox (Noya) is always owned. Others require Flow Points purchase.
    """
    return flow_service.get_shop_catalog(db=db, user_id=current_user.id)

@router.post("/shop/{species}/purchase", response_model=PurchaseCompanionResponse, status_code=status.HTTP_201_CREATED)
def purchase_companion(
    species: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Purchase a companion from the Flow Shop using Flow Points.
    - Validates species exists in catalog
    - Enforces sufficient balance (402 if short)
    - Guards against double-purchase (409 if already owned)
    - Writes FlowInventoryItem + FlowEconomicEvent atomically
    """
    return flow_service.purchase_companion(db, current_user, species)

@router.post("/shields/use", response_model=UseShieldResponse)
def use_streak_shield(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    User-confirmed shield activation.
    Consumes 1 shield to protect/restore streak after an unavoidable missed focus day.
    """
    return flow_service.use_streak_shield(db, current_user)

