import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    Date,
    String,
    Integer,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Text,
    UniqueConstraint,
    text,
)
from ..db.session import Base
from ..db.types import UTCDateTime

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


class AIPlanningAttempt(Base):
    """One row per real Gemini call (or client-reported failure) of a Build My Day request.

    request_id is the stable planning request id (the client idempotency key); every retry gets a new
    attempt_id. Diagnostics only: charging is decided by AIPlanningRequestCache/AIUsageRecord.
    """
    __tablename__ = "ai_planning_attempts"

    attempt_id = Column(String, primary_key=True, default=lambda: uuid.uuid4().hex)
    request_id = Column(String, nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(String, nullable=False)  # succeeded | failed
    failure_code = Column(String, nullable=True)
    failure_reason = Column(Text, nullable=True)
    latency_ms = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)


class AIRequest(Base):
    """One AI planning request: the reservation, the idempotency record, and (later) the job-queue row.

    status: reserved (in flight; usage already charged) -> succeeded | failed | expired (usage refunded).
    The partial unique index admits at most one in-flight request per user across all API instances;
    UNIQUE(user_id, idempotency_key) makes a client key private to its user.
    """
    __tablename__ = "ai_requests"

    id = Column(String, primary_key=True, default=lambda: uuid.uuid4().hex)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    idempotency_key = Column(String, nullable=False)
    kind = Column(String, nullable=False, default="plan")
    status = Column(String, nullable=False, default="reserved")
    charge_source = Column(String, nullable=False, default="none")  # none | pro | free | shield
    request_sha256 = Column(String(64), nullable=False)
    deadline_at = Column(UTCDateTime(), nullable=False)
    finished_at = Column(UTCDateTime(), nullable=True)
    error_code = Column(String, nullable=True)  # a short code, never exception text
    latency_ms = Column(Integer, nullable=True)
    response_json = Column(Text, nullable=True)  # replay cache; purged after 24h
    created_at = Column(UTCDateTime(), default=utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "idempotency_key", name="uq_ai_requests_user_key"),
        Index(
            "uq_ai_requests_one_inflight", "user_id", unique=True,
            postgresql_where=text("status = 'reserved'"), sqlite_where=text("status = 'reserved'"),
        ),
    )


class AIUsagePeriod(Base):
    """Atomic fair-use counters: (user, kind, period_start) with kind in day | month | parse_day."""
    __tablename__ = "ai_usage_periods"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    period_kind = Column(String, primary_key=True)
    period_start = Column(Date, primary_key=True)
    used = Column(Integer, nullable=False, default=0)


class RateLimitWindow(Base):
    """Cross-instance fixed-window counters (bucket_key like 'ai:<user_id>'); purged daily."""
    __tablename__ = "rate_limit_windows"

    bucket_key = Column(String, primary_key=True)
    window_start = Column(Integer, primary_key=True)  # epoch seconds, floored to the window
    count = Column(Integer, nullable=False, default=0)
