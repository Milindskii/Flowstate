from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field
from .task import TaskCandidateResponse

class AIPlanRequest(BaseModel):
    raw_text: str = Field(..., min_length=2, max_length=1500, description="Raw natural-language task brain dump")
    timezone: Optional[str] = Field(default="UTC", max_length=50)
    consume_shield: bool = Field(default=False, description="User explicitly confirms consuming 1 Flow Shield if free uses are exhausted")
    idempotency_key: Optional[str] = Field(default=None, max_length=100, description="Client idempotency key to prevent duplicate charges")

class AIUsageStatus(BaseModel):
    is_pro: bool = False
    free_uses_remaining: int = 1
    free_uses_total: int = 1
    shields_available: int = 2
    can_plan_free: bool = True
    requires_shield: bool = False
    subscription_tier: str = "free"
    subscription_status: str = "inactive"
    subscription_expires_at: Optional[datetime] = None

class AIPlanResponse(BaseModel):
    tasks: List[TaskCandidateResponse]
    ambiguities: List[str] = Field(default_factory=list)
    needs_confirmation: bool = False
    usage: AIUsageStatus
    shield_consumed: bool = False
    free_consumed: bool = False

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
    cost_inr: int = Field(default=50)
