import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    String,
    Integer,
    Boolean,
    DateTime,
    ForeignKey,
    Text,
)
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class AIUsageRecord(Base):
    """
    Persistent server-authoritative record of AI planning usage per user.
    Enforces the Free AI Economy:
      - 1 Free included AI planning use.
      - Subsequent uses require 1 Flow Shield from FlowProfile.
      - Pro subscription provides generous/unlimited usage allowance.
    """
    __tablename__ = "ai_usage_records"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)

    free_uses_total = Column(Integer, default=1, nullable=False)
    free_uses_consumed = Column(Integer, default=0, nullable=False)
    shield_uses_consumed = Column(Integer, default=0, nullable=False)
    total_ai_uses = Column(Integer, default=0, nullable=False)

    last_ai_use_at = Column(DateTime(timezone=True), nullable=True)

    # Entitlement state
    is_pro = Column(Boolean, default=False, nullable=False)
    subscription_tier = Column(String, default="free", nullable=False) # free, pro_monthly, pro_yearly
    subscription_status = Column(String, default="inactive", nullable=False) # inactive, active, cancelled, expired
    subscription_expires_at = Column(DateTime(timezone=True), nullable=True)
    google_play_order_id = Column(String, nullable=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

class AIPlanningRequestCache(Base):
    """
    Idempotency cache for AI planning requests.
    Prevents duplicate double-charging of free credits or shields if a user
    double-taps 'Build' or retries an identical request.
    """
    __tablename__ = "ai_planning_requests"

    idempotency_key = Column(String, primary_key=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(String, default="pending", nullable=False) # pending, completed, failed
    response_json = Column(Text, nullable=True)
    shield_used = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
