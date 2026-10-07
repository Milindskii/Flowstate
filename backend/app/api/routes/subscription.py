from typing import List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.ai import (
    ProPlanInfo,
    ProSubscriptionStatusResponse,
    VerifySubscriptionRequest,
    StreakRecoveryRequest,
)
from ...services.ai_economy_service import AIEconomyService

router = APIRouter(prefix="/subscription", tags=["Pro Subscription & Purchases"])
_RETIRED_DETAIL = "This endpoint has been retired. Pro status is managed by your Flowstate account."

@router.get("/plans", response_model=List[ProPlanInfo])
def get_pro_plans():
    """
    Returns centralized Pro subscription catalog.
    Prices are intentionally TBD / pricing coming soon in V1 until production Google Play billing is enabled.
    """
    return AIEconomyService.get_pro_plans()

@router.get("/status", response_model=ProSubscriptionStatusResponse)
def get_subscription_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns authoritative server-verified subscription status for current user.
    Never trusts client flags.
    """
    return AIEconomyService.get_subscription_status(db, current_user.id)

@router.post("/verify")
def verify_google_play_subscription(
    request: VerifySubscriptionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retired. Pro is never unlocked by a token the client hands us: it is activated server-side from a verified
    payment-provider webhook and read back through the entitlement endpoints.
    """
    raise HTTPException(status_code=status.HTTP_410_GONE, detail=_RETIRED_DETAIL)

@router.post("/streak-recover")
def recover_streak_purchase(
    request: StreakRecoveryRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retired: a client-reported purchase is never trusted. Streak recovery will return with server-side billing."""
    raise HTTPException(status_code=status.HTTP_410_GONE, detail=_RETIRED_DETAIL)
