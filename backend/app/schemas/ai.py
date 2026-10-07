from typing import Optional, List, Dict, Any, Literal
from datetime import datetime
from pydantic import AliasChoices, BaseModel, Field
from .task import TaskCandidateResponse, PlanningContext

class AIPlanRequest(BaseModel):
    raw_text: str = Field(..., min_length=2, max_length=1500, description="Raw natural-language task brain dump")
    # IANA zone name (e.g. "Asia/Kolkata"). `user_timezone` is accepted for older clients.
    # No default: an absent value resolves to the stored user preference (never silently UTC).
    timezone: Optional[str] = Field(default=None, max_length=64, validation_alias=AliasChoices("timezone", "user_timezone"))
    current_local_time: Optional[datetime] = Field(default=None, description="Client clock (aware); makes planning deterministic")
    consume_shield: bool = Field(default=False, description="User explicitly confirms consuming 1 Flow Shield if free uses are exhausted")
    idempotency_key: Optional[str] = Field(default=None, max_length=100, description="Client idempotency key to prevent duplicate charges")

class PlanningAttemptReport(BaseModel):
    """Client-side Build My Day failure that never reached the server's Gemini call."""
    request_id: str = Field(..., min_length=1, max_length=100)
    failure_code: Literal["privacy_declined", "gemini_error"]
    failure_reason: Optional[str] = Field(default=None, max_length=2000)


class AIUsageStatus(BaseModel):
    is_pro: bool = False
    free_uses_remaining: int = 1
    free_uses_total: int = 1
    free_uses_consumed: int = 0
    free_use_available: bool = True
    can_use_ai: bool = True
    shields_available: int = 2
    can_plan_free: bool = True
    requires_shield: bool = False
    replan_shield_cost: int = 1   # Shields one AI-understood Replan costs (rules-only Replan is free)
    shield_cost: int = 2          # Shields one AI plan costs once the free use is gone (server-owned)
    can_afford_shield_plan: bool = False
    subscription_tier: str = "free"
    subscription_status: str = "inactive"
    subscription_expires_at: Optional[datetime] = None

class AIPlanResponse(BaseModel):
    tasks: List[TaskCandidateResponse]
    planning_context: Optional[PlanningContext] = None
    ambiguities: List[str] = Field(default_factory=list)
    needs_confirmation: bool = False
    usage: AIUsageStatus
    shield_consumed: bool = False
    free_consumed: bool = False
    timezone_used: Optional[str] = None
    scheduling_error: Optional[str] = None
    failure_code: Optional[str] = None   # "scheduling_failed" when the plan could not be scheduled (never charged)
    conflicts: List[Dict[str, Any]] = Field(default_factory=list)

class ProPlanInfo(BaseModel):
    plan_id: str
    title: str
    billing_period: str # "monthly" or "yearly"
    price_display: str # e.g. "₹— / month"
    is_best_value: bool = False
    status: str = "pricing_coming_soon"
    features: List[str] = Field(default_factory=list)

class ProSubscriptionStatusResponse(BaseModel):
    is_pro: bool = False
    tier: str = "free"
    status: str = "inactive"
    renewal_date: Optional[str] = None
    play_store_managed: bool = True
    plans: List[ProPlanInfo] = Field(default_factory=list)

class VerifySubscriptionRequest(BaseModel):
    purchase_token: str = Field(..., min_length=1)
    product_id: str = Field(..., min_length=1)
    order_id: Optional[str] = None

class StreakRecoveryRequest(BaseModel):
    purchase_token: str = Field(..., min_length=1)
