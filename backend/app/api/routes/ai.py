from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...core.logging import logger
from ...models.user import User
from ...schemas.ai import (
    AIPlanRequest,
    AIPlanResponse,
    AIUsageStatus,
)
from ...services.ai_economy_service import AIEconomyService
from ...services.ai_service import AIService

router = APIRouter(prefix="/ai", tags=["AI Planning Economy"])

@router.get("/status", response_model=AIUsageStatus)
def get_ai_planning_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns the user's current AI planning usage status:
    - is_pro
    - free_uses_remaining
    - shields_available
    - can_plan_free
    - requires_shield
    """
    return AIEconomyService.get_usage_status(db, current_user.id)

@router.post("/plan", response_model=AIPlanResponse)
def generate_ai_plan(
    request: AIPlanRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Gemini Brain-Dump Task Planner:
    - Enforces Free AI Economy (1 free plan, subsequent require 1 Flow Shield, Pro gets full allowance).
    - Checks server-side sliding window rate limit (max 5/hr).
    - Checks client idempotency key to prevent double charging.
    - Atomically charges usage ONLY after successful Gemini extraction.
    - Returns structured task candidates for deterministic scheduling.
    """
    # 1. Technical rate limit check
    AIEconomyService.check_technical_rate_limit(current_user.id)

    # 2. Check Idempotency Cache
    cached_payload = AIEconomyService.check_idempotency(db, current_user.id, request.idempotency_key)
    if cached_payload:
        status_info = AIEconomyService.get_usage_status(db, current_user.id)
        cached_payload["usage"] = status_info.model_dump()
        return cached_payload

    # 3. Authorize usage & determine charge type
    charge_type, profile = AIEconomyService.authorize_request(
        db=db,
        user_id=current_user.id,
        consume_shield=request.consume_shield,
    )

    # 4. Record technical rate limit timestamp
    AIEconomyService.record_technical_request(current_user.id)

    # 5. Execute Gemini Task Extraction with safe rollback
    user_tz = request.timezone or (current_user.preferences.timezone if current_user.preferences else "UTC")
    try:
        candidates, ambiguities, needs_confirmation = AIService.extract_structured_plan_with_gemini(
            raw_text=request.raw_text,
            user_timezone_str=user_tz,
        )
    except Exception as e:
        # Atomic guarantee: Never consume user's free credit or shield on failure
        logger.error(f"Gemini extraction failed for user {current_user.id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI task structuring failed: {str(e)}. Your free plans and shields were not charged.",
        )

    # 6. Finalize usage & commit deduction atomically
    response_data = {
        "tasks": [c.model_dump() for c in candidates],
        "ambiguities": ambiguities,
        "needs_confirmation": needs_confirmation,
        "shield_consumed": (charge_type == "shield"),
        "free_consumed": (charge_type == "free"),
    }

    AIEconomyService.finalize_usage(
        db=db,
        user_id=current_user.id,
        charge_type=charge_type,
        profile=profile,
        idempotency_key=request.idempotency_key,
        response_payload=response_data,
    )

    # 7. Return response with fresh usage status
    usage_status = AIEconomyService.get_usage_status(db, current_user.id)
    return AIPlanResponse(
        tasks=candidates,
        ambiguities=ambiguities,
        needs_confirmation=needs_confirmation,
        usage=usage_status,
        shield_consumed=(charge_type == "shield"),
        free_consumed=(charge_type == "free"),
    )
