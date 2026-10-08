from typing import Optional, List, Dict, Any, Literal
from datetime import datetime
from pydantic import AliasChoices, BaseModel, Field
from .task import TaskCandidateResponse, PlanningContext
from .routine import RoutineProposal

class AIPlanRequest(BaseModel):
    raw_text: str = Field(..., min_length=2, max_length=20000,  # memory ceiling only; the real limit is economy_config.input_limit_for
        description="Raw natural-language task brain dump")
    # IANA zone name (e.g. "Asia/Kolkata"). `user_timezone` is accepted for older clients.
    # No default: an absent value resolves to the stored user preference (never silently UTC).
    timezone: Optional[str] = Field(default=None, max_length=64, validation_alias=AliasChoices("timezone", "user_timezone"))
    current_local_time: Optional[datetime] = Field(default=None, description="Client clock (aware); makes planning deterministic")
    consume_shield: bool = Field(default=False, description="User explicitly confirms consuming 1 Flow Shield if free uses are exhausted")
    idempotency_key: Optional[str] = Field(default=None, max_length=100, description="Client idempotency key to prevent duplicate charges")

class PlanningAttemptReport(BaseModel):
    """Client-side Build My Day failure that never reached the server's Gemini call."""
    request_id: str = Field(..., min_length=1, max_length=100)
    failure_code: Literal["privacy_declined", "gemini_error", "input_too_long", "client_error"]
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
    shield_cost: int = 2          # Shields one AI plan costs once the free use is gone (server-owned)
    shield_cost_replan: int = 1   # Shields one AI replan costs (server-owned)
    max_input_words: int = 200    # Build My Day dump limit (server-owned; the app counter shows it)
    can_afford_shield_plan: bool = False
    shield_max: int = 3
    next_shield_refill_at: Optional[datetime] = None   # server instant of the next free Shield; None at the maximum
    server_now: Optional[datetime] = None              # the server clock when this was read (countdown base)
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
    routine_proposals: List[RoutineProposal] = Field(default_factory=list)   # routines to CONFIRM; none is saved yet

class ProPlanInfo(BaseModel):
    plan_id: str
    title: str
    billing_period: str # "monthly" or "yearly"
    price_display: str # e.g. "₹89 / month"
    monthly_price_inr: Optional[int] = None
    daily_price_display: Optional[str] = None      # "₹2.97/day": the headline figure
    billing_disclosure: Optional[str] = None       # "₹89 billed monthly": always shown with the daily figure
    purchasable: bool = False                      # true only once store billing is live (never inferred by the app)
    is_best_value: bool = False
    status: str = "pricing_set"
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
