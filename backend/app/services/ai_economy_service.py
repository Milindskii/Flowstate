import uuid
import time
import json
import threading
from typing import Optional, Dict, Tuple, Any, List
from datetime import datetime, timezone, timedelta
from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..core.config import settings
from ..models.ai_usage import AIUsageRecord, AIPlanningAttempt
from ..models.flow_progression import FlowProfile
from ..models.user import User
from ..schemas.ai import (
    AIUsageStatus,
    ProPlanInfo,
    ProSubscriptionStatusResponse,
)

# Per-process lock used only to serialize same-user confirm/apply flows (batch create, calendar apply).
# AI planning itself is serialized across instances by the database (services/ai_gateway.py).
_AI_REQUEST_LOCKS: Dict[str, threading.Lock] = {}
_AI_REQUEST_LOCKS_GUARD = threading.Lock()


def effective_is_pro(usage: AIUsageRecord, now: Optional[datetime] = None) -> bool:
    """Server-side Pro check: the flag AND an unexpired subscription (plus a short grace period).

    ``subscription_expires_at`` being NULL means a non-expiring grant (e.g. set by support)."""
    if not usage.is_pro:
        return False
    expires = usage.subscription_expires_at
    if expires is None:
        return True
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    return (now or datetime.now(timezone.utc)) <= expires + timedelta(days=settings.PRO_GRACE_DAYS)


class AIEconomyService:
    """
    Authoritative server-side management of:
    1. AI Economy (1 Free plan, subsequent plans cost 1 Flow Shield, Pro gets unlimited allowance)
    2. Atomic usage consumption & safe rollback on failures
    3. Status/usage reads (reservation, rate limits and idempotency live in ai_gateway)
    4. Idempotency guarantees to prevent double-charging (see ai_gateway)
    5. Pro subscription entitlement verification (never trusting client flags)
    """

    @classmethod
    def get_user_request_lock(cls, user_id: str) -> threading.Lock:
        """Return a per-user lock so double taps cannot race the usage finalization."""
        with _AI_REQUEST_LOCKS_GUARD:
            return _AI_REQUEST_LOCKS.setdefault(user_id, threading.Lock())

    @classmethod
    def get_or_create_usage(cls, db: Session, user_id: str) -> AIUsageRecord:
        record = db.query(AIUsageRecord).filter(AIUsageRecord.user_id == user_id).first()
        if not record:
            record = AIUsageRecord(
                user_id=user_id,
                free_uses_total=1,
                free_uses_consumed=0,
                shield_uses_consumed=0,
                total_ai_uses=0,
                is_pro=False,
                subscription_tier="free",
                subscription_status="inactive",
            )
            db.add(record)
            try:
                db.commit()
            except IntegrityError:  # a concurrent first request created it
                db.rollback()
                record = db.query(AIUsageRecord).filter(AIUsageRecord.user_id == user_id).one()
            else:
                db.refresh(record)
        return record

    @classmethod
    def get_or_create_profile(cls, db: Session, user_id: str) -> FlowProfile:
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == user_id).first()
        if not profile:
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                user = User(id=user_id, email=f"{user_id}@flowstate.local", name="Friend")
                db.add(user)
                db.flush()
            from .flow_service import FlowService
            flow_service = FlowService()
            try:
                profile, _, _ = flow_service.get_or_create_flow_profile(db, user)
                db.commit()
            except IntegrityError:  # a concurrent first request created it
                db.rollback()
                profile = db.query(FlowProfile).filter(FlowProfile.user_id == user_id).one()
        return profile

    @classmethod
    def get_usage_status(cls, db: Session, user_id: str) -> AIUsageStatus:
        usage = cls.get_or_create_usage(db, user_id)
        profile = cls.get_or_create_profile(db, user_id)
        shields = profile.shields_available if profile else 2

        is_pro = effective_is_pro(usage)
        free_remaining = max(0, usage.free_uses_total - usage.free_uses_consumed)
        can_plan_free = is_pro or free_remaining > 0
        requires_shield = (not is_pro) and (free_remaining == 0)

        return AIUsageStatus(
            is_pro=is_pro,
            free_uses_remaining=free_remaining,
            free_uses_total=usage.free_uses_total,
            free_uses_consumed=usage.free_uses_consumed,
            free_use_available=can_plan_free,
            can_use_ai=(can_plan_free or shields > 0 or is_pro),
            shields_available=shields,
            can_plan_free=can_plan_free,
            requires_shield=requires_shield,
            subscription_tier=usage.subscription_tier,
            subscription_status=usage.subscription_status,
            subscription_expires_at=usage.subscription_expires_at,
        )

    @classmethod
    def record_attempt(
        cls,
        db: Session,
        *,
        user_id: str,
        request_id: str,
        status: str,
        failure_code: Optional[str] = None,
        failure_reason: Optional[str] = None,
        latency_ms: Optional[int] = None,
    ) -> str:
        """Diagnostics row for one Build My Day attempt (one real Gemini call, or a client-reported
        failure). Never touches credits. Returns the new attempt_id."""
        attempt = AIPlanningAttempt(
            attempt_id=uuid.uuid4().hex, request_id=request_id, user_id=user_id, status=status,
            failure_code=failure_code, failure_reason=(failure_reason or None) and str(failure_reason)[:2000],
            latency_ms=latency_ms,
        )
        db.add(attempt)
        db.commit()
        return attempt.attempt_id

    @classmethod
    def get_pro_plans(cls) -> List[ProPlanInfo]:
        """Returns centralized pricing config model. Prices are intentionally TBD in V1."""
        return [
            ProPlanInfo(
                plan_id="flowstate_pro_monthly",
                title="Monthly",
                billing_period="monthly",
                price_display="₹— / month",
                is_best_value=False,
                status="pricing_coming_soon",
                features=[
                    "Unlimited AI Brain Dumps",
                    "Advanced circadian personalization",
                    "Flexible focus window scheduling",
                    "Priority feature updates",
                ],
            ),
            ProPlanInfo(
                plan_id="flowstate_pro_yearly",
                title="Yearly",
                billing_period="yearly",
                price_display="₹— / year",
                is_best_value=True,
                status="pricing_coming_soon",
                features=[
                    "All Monthly features",
                    "Best value commitment",
                    "Continuous progression shield boosts",
                ],
            ),
        ]

    @classmethod
    def get_subscription_status(cls, db: Session, user_id: str) -> ProSubscriptionStatusResponse:
        usage = cls.get_or_create_usage(db, user_id)
        renewal = (
            usage.subscription_expires_at.strftime("%Y-%m-%d")
            if usage.subscription_expires_at
            else None
        )
        return ProSubscriptionStatusResponse(
            is_pro=effective_is_pro(usage),
            tier=usage.subscription_tier,
            status=usage.subscription_status,
            renewal_date=renewal,
            play_store_managed=True,
            plans=cls.get_pro_plans(),
        )

    @classmethod
    def verify_google_play_purchase(
        cls,
        db: Session,
        user_id: str,
        purchase_token: str,
        product_id: str,
        order_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Server-authoritative Google Play verification contract.
        In production, verifies purchase token against Google Play Developer API.
        Never unlocks Pro based merely on client claims.
        """
        # Strict validation: tokens must be verified server-side
        if not purchase_token or len(purchase_token.strip()) < 10:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid purchase token. Google Play purchase could not be verified.",
            )

        # In production test mode (or when real verification key configured):
        # We enforce server ownership of entitlement
        usage = cls.get_or_create_usage(db, user_id)
        if product_id not in ["flowstate_pro_monthly", "flowstate_pro_yearly"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unknown product ID '{product_id}'. Must be a recognized Flowstate Pro SKU.",
            )

        # Note: Simulation / fake purchases without valid server token are rejected
        if "test_mock_invalid" in purchase_token:
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail="Payment verification failed with Google Play.",
            )

        # This repository does not yet contain a Google Play Developer API
        # verifier. Never turn an opaque client token into an entitlement.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Play purchase verification is not configured. No entitlement was granted.",
        )

    @classmethod
    def verify_streak_recovery(
        cls,
        db: Session,
        user_id: str,
        purchase_token: str,
        cost_inr: int = 50,
    ) -> Dict[str, Any]:
        """
        Server-authoritative streak recovery contract for ₹50.
        Requires verified Google Play Billing purchase.
        """
        if not purchase_token or len(purchase_token.strip()) < 10:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid purchase token. Google Play streak recovery purchase could not be verified.",
            )

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Play streak recovery verification is not configured. No recovery was granted.",
        )
