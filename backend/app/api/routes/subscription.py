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
    Server-side Google Play subscription verification contract.
    Validates token and unlocks Pro entitlement. Rejects unverified or simulated requests.
    """
    return AIEconomyService.verify_google_play_purchase(
        db=db,
        user_id=current_user.id,
        purchase_token=request.purchase_token,
        product_id=request.product_id,
        order_id=request.order_id,
    )

@router.post("/streak-recover")
def recover_streak_purchase(
    request: StreakRecoveryRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    ₹50 Streak Recovery Google Play Purchase Verification Contract.
    Strictly server-verified. Never grants streak restoration without a valid token.
    """
    return AIEconomyService.verify_streak_recovery(
        db=db,
        user_id=current_user.id,
        purchase_token=request.purchase_token,
        cost_inr=request.cost_inr,
    )
