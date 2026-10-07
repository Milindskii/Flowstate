"""AI gateway: atomic usage reservation, idempotency, refunds, rate limits and provider admission.

Postgres (Supabase) is the single source of truth, so every guarantee holds across API instances:

* **Reserve** (one short transaction): claim the user's single in-flight slot (partial unique index), then charge
  exactly one source with a conditional ``UPDATE ... WHERE <allowance left> RETURNING``-style statement. Two
  concurrent requests can never both spend the last free use, shield or Pro cap unit.
* **Provider call**: no DB transaction is open while the provider is called.
* **Finish** (one short transaction): flip ``reserved`` -> ``succeeded`` (charge stands) or ``failed``/``expired``
  (charge refunded). The status flip is conditional, so a refund can happen at most once.
"""
import hashlib
import json
import time
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable, Dict, Optional

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..core.ai_limits import provider_admission, request_deadline, breaker
from ..core.config import settings
from ..core.logging import logger
from ..models.ai_usage import AIRequest, AIUsagePeriod, AIUsageRecord, RateLimitWindow
from ..models.flow_progression import FlowProfile
from .ai_economy_service import AIEconomyService, effective_is_pro
from .ai_service import GeminiFailure

# Failures that say the provider (not the request) is unhealthy; they feed the circuit breaker.
PROVIDER_HEALTH_CODES = frozenset(
    {"provider_quota", "provider_auth", "model_not_found", "provider_unavailable", "timeout", "network"}
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class GatewayError(Exception):
    """A refusal with a machine-readable code, e.g. 409 request_in_progress or 429 rate_limited."""

    def __init__(self, http_status: int, code: str, message: str, headers: Optional[Dict[str, str]] = None):
        super().__init__(message)
        self.http_status, self.code, self.message, self.headers = http_status, code, message, headers or {}


class QuotaExceeded(HTTPException):
    """The user's Flowstate allowance is used up (distinct from provider quota). `code` is machine-readable."""

    def __init__(self, http_status: int, detail: str, code: str = "quota_exhausted"):
        super().__init__(status_code=http_status, detail=detail)
        self.code = code


@dataclass
class Ticket:
    request_id: str
    user_id: str
    charge_source: str  # pro | free | shield
    idempotency_key: str
    started_at: float


@dataclass
class Replay:
    payload: Dict[str, Any]


def request_fingerprint(raw_text: str, timezone_name: Optional[str], consume_shield: bool) -> str:
    blob = json.dumps([raw_text, timezone_name or "", bool(consume_shield)], separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


# ---- dialect-aware atomic helpers ------------------------------------------------------------------------------

def _dialect_insert(db: Session, model):
    return (pg_insert if db.get_bind().dialect.name == "postgresql" else sqlite_insert)(model)


def hit_window(db: Session, bucket_key: str, window_seconds: int, now: Optional[float] = None) -> int:
    """Atomically count one hit in the current fixed window and commit immediately (a rejected or failed
    request still counts). Returns the new count."""
    now = time.time() if now is None else now
    window_start = int(now // window_seconds * window_seconds)
    stmt = _dialect_insert(db, RateLimitWindow).values(bucket_key=bucket_key, window_start=window_start, count=1)
    stmt = stmt.on_conflict_do_update(
        index_elements=["bucket_key", "window_start"], set_={"count": RateLimitWindow.count + 1}
    ).returning(RateLimitWindow.count)
    count = db.execute(stmt).scalar_one()
    db.commit()
    return int(count)


def _period_start(kind: str, today: date) -> date:
    return today.replace(day=1) if kind == "month" else today


def consume_period(db: Session, user_id: str, kind: str, cap: int, today: Optional[date] = None) -> bool:
    """Atomically spend one unit of a fair-use counter; False when the cap is reached. Does not commit."""
    start = _period_start(kind, today or _utcnow().date())
    db.execute(
        _dialect_insert(db, AIUsagePeriod)
        .values(user_id=user_id, period_kind=kind, period_start=start, used=0)
        .on_conflict_do_nothing()
    )
    res = db.execute(
        update(AIUsagePeriod)
        .where(AIUsagePeriod.user_id == user_id, AIUsagePeriod.period_kind == kind,
               AIUsagePeriod.period_start == start, AIUsagePeriod.used < cap)
        .values(used=AIUsagePeriod.used + 1)
    )
    return res.rowcount == 1


def _refund_period(db: Session, user_id: str, kind: str, today: date) -> None:
    db.execute(
        update(AIUsagePeriod)
        .where(AIUsagePeriod.user_id == user_id, AIUsagePeriod.period_kind == kind,
               AIUsagePeriod.period_start == _period_start(kind, today), AIUsagePeriod.used > 0)
        .values(used=AIUsagePeriod.used - 1)
    )


def consume_parse_budget(db: Session, user_id: str, cap: int) -> bool:
    """Daily budget for AI-assisted /tasks/parse (Postgres-backed, shared by all instances). Commits."""
    ok = consume_period(db, user_id, "parse_day", cap)
    db.commit()
    return ok


# ---- charging --------------------------------------------------------------------------------------------------

def _charge(db: Session, user_id: str, is_pro: bool, consume_shield: bool, today: date) -> str:
    """Spend exactly one allowance unit atomically; raises QuotaExceeded when none is available."""
    if is_pro:
        if not consume_period(db, user_id, "day", settings.AI_PRO_DAILY_CAP, today):
            raise QuotaExceeded(status.HTTP_402_PAYMENT_REQUIRED,
                                "You've reached today's fair-use limit for Flowstate AI planning. It resets tomorrow.",
                                "pro_cap_day")
        if not consume_period(db, user_id, "month", settings.AI_PRO_MONTHLY_CAP, today):
            raise QuotaExceeded(status.HTTP_402_PAYMENT_REQUIRED,
                                "You've reached this month's fair-use limit for Flowstate AI planning.",
                                "pro_cap_month")
        return "pro"

    free = db.execute(
        update(AIUsageRecord)
        .where(AIUsageRecord.user_id == user_id, AIUsageRecord.free_uses_consumed < AIUsageRecord.free_uses_total)
        .values(free_uses_consumed=AIUsageRecord.free_uses_consumed + 1)
    )
    if free.rowcount == 1:
        return "free"

    if not consume_shield:
        raise QuotaExceeded(
            status.HTTP_402_PAYMENT_REQUIRED,
            "You have used your free AI plan. Using an additional AI planning session requires 1 Flow Shield. "
            "Confirm shield consumption to proceed.",
        )
    shield = db.execute(
        update(FlowProfile)
        .where(FlowProfile.user_id == user_id, FlowProfile.shields_available > 0)
        .values(shields_available=FlowProfile.shields_available - 1)
    )
    if shield.rowcount != 1:
        raise QuotaExceeded(
            status.HTTP_403_FORBIDDEN,
            "No Flow Shields available. Earn more shields by maintaining a 7-day focus streak, or upgrade to Flowstate Pro.",
        )
    return "shield"


def _refund(db: Session, user_id: str, charge_source: str, today: date) -> None:
    if charge_source == "free":
        db.execute(update(AIUsageRecord)
                   .where(AIUsageRecord.user_id == user_id, AIUsageRecord.free_uses_consumed > 0)
                   .values(free_uses_consumed=AIUsageRecord.free_uses_consumed - 1))
    elif charge_source == "shield":
        db.execute(update(FlowProfile).where(FlowProfile.user_id == user_id)
                   .values(shields_available=FlowProfile.shields_available + 1))
    elif charge_source == "pro":
        _refund_period(db, user_id, "day", today)
        _refund_period(db, user_id, "month", today)


# ---- lifecycle -------------------------------------------------------------------------------------------------

def _release(db: Session, req_id: str, user_id: str, charge_source: str, new_status: str, code: str,
             latency_ms: Optional[int] = None) -> bool:
    """reserved -> failed/expired and refund, in one transaction. True only for the caller that won the flip."""
    now = _utcnow()
    won = db.execute(
        update(AIRequest).where(AIRequest.id == req_id, AIRequest.status == "reserved")
        .values(status=new_status, error_code=code, finished_at=now, latency_ms=latency_ms)
    ).rowcount == 1
    if won:
        _refund(db, user_id, charge_source, now.date())
    db.commit()
    return won


def expire_stale(db: Session, user_id: Optional[str] = None, limit: int = 50) -> int:
    """Refund reservations whose deadline passed (a crashed worker or a lost connection)."""
    q = select(AIRequest.id, AIRequest.user_id, AIRequest.charge_source).where(
        AIRequest.status == "reserved", AIRequest.deadline_at < _utcnow())
    if user_id:
        q = q.where(AIRequest.user_id == user_id)
    released = 0
    for req_id, uid, source in db.execute(q.limit(limit)).all():
        released += int(_release(db, req_id, uid, source, "expired", "expired"))
    return released


def purge_old_requests(db: Session, older_than_hours: int = 24) -> int:
    """Drop cached replay bodies after 24h (privacy). Idempotency rows themselves are kept for 90 days."""
    cutoff = _utcnow() - timedelta(hours=older_than_hours)
    n = db.execute(update(AIRequest).where(AIRequest.created_at < cutoff, AIRequest.response_json.is_not(None))
                   .values(response_json=None)).rowcount
    db.commit()
    return int(n or 0)


def begin(db: Session, *, user_id: str, idempotency_key: str, fingerprint: str, consume_shield: bool) -> "Ticket | Replay":
    """Idempotency lookup, rate limit, then the atomic reservation. Commits; no transaction stays open."""
    expire_stale(db, user_id)
    usage = AIEconomyService.get_or_create_usage(db, user_id)
    AIEconomyService.get_or_create_profile(db, user_id)
    is_pro = effective_is_pro(usage)

    existing = db.query(AIRequest).filter(
        AIRequest.user_id == user_id, AIRequest.idempotency_key == idempotency_key).first()
    reuse_id: Optional[str] = None
    if existing is not None:
        if existing.status in ("succeeded", "reserved") and existing.request_sha256 != fingerprint:
            raise GatewayError(422, "idempotency_key_reused",
                               "This request key was already used for a different request.")
        if existing.status == "succeeded" and existing.response_json:
            return Replay(json.loads(existing.response_json))
        if existing.status == "reserved":
            raise GatewayError(409, "request_in_progress", "This request is already being processed.",
                               {"Retry-After": "3"})
        reuse_id = existing.id  # a failed/expired attempt: the same key may retry

    limit = settings.AI_RATE_LIMIT_PER_HOUR_PRO if is_pro else settings.AI_RATE_LIMIT_PER_HOUR_FREE
    if hit_window(db, f"ai:{user_id}", 3600) > limit:
        raise GatewayError(
            429, "rate_limited",
            f"Rate limit exceeded: maximum {limit} AI planning requests allowed per hour. Please try again later.",
            {"Retry-After": "600"})

    now = _utcnow()
    deadline = now + timedelta(seconds=settings.AI_REQUEST_DEADLINE_SECONDS + settings.AI_RESERVATION_MARGIN_SECONDS)
    try:
        if reuse_id:
            flipped = db.execute(
                update(AIRequest).where(AIRequest.id == reuse_id, AIRequest.status.in_(("failed", "expired")))
                .values(status="reserved", charge_source="none", request_sha256=fingerprint, deadline_at=deadline,
                        error_code=None, finished_at=None, response_json=None, latency_ms=None, created_at=now)
            ).rowcount
            if flipped != 1:
                raise IntegrityError("claim", {}, Exception("concurrent retry"))
            req_id = reuse_id
        else:
            req = AIRequest(user_id=user_id, idempotency_key=idempotency_key, kind="plan", status="reserved",
                            charge_source="none", request_sha256=fingerprint, deadline_at=deadline, created_at=now)
            db.add(req)
            db.flush()
            req_id = req.id
        source = _charge(db, user_id, is_pro, consume_shield, now.date())
        db.execute(update(AIRequest).where(AIRequest.id == req_id).values(charge_source=source))
        db.commit()
    except IntegrityError:
        db.rollback()
        clash = db.query(AIRequest).filter(
            AIRequest.user_id == user_id, AIRequest.idempotency_key == idempotency_key).first()
        if clash is not None and clash.status == "succeeded" and clash.response_json:
            return Replay(json.loads(clash.response_json))
        raise GatewayError(409, "request_in_progress" if clash is not None and clash.status == "reserved"
                           else "another_request_in_flight",
                           "Another AI planning request is already in progress. Please wait for it to finish.",
                           {"Retry-After": "3"})
    except Exception:
        db.rollback()
        raise
    return Ticket(request_id=req_id, user_id=user_id, charge_source=source, idempotency_key=idempotency_key,
                  started_at=time.perf_counter())


def succeed(db: Session, ticket: Ticket, payload: Dict[str, Any]) -> bool:
    """The charge stands. False if the reservation was already expired and refunded (user keeps the plan)."""
    now = _utcnow()
    latency = round((time.perf_counter() - ticket.started_at) * 1000)
    won = db.execute(
        update(AIRequest).where(AIRequest.id == ticket.request_id, AIRequest.status == "reserved")
        .values(status="succeeded", finished_at=now, latency_ms=latency,
                response_json=json.dumps(payload, default=lambda v: v.isoformat()))
    ).rowcount == 1
    if won:
        values: Dict[str, Any] = {"total_ai_uses": AIUsageRecord.total_ai_uses + 1, "last_ai_use_at": now}
        if ticket.charge_source == "shield":
            values["shield_uses_consumed"] = AIUsageRecord.shield_uses_consumed + 1
            db.execute(update(FlowProfile).where(FlowProfile.user_id == ticket.user_id)
                       .values(shields_used_count=FlowProfile.shields_used_count + 1))
        db.execute(update(AIUsageRecord).where(AIUsageRecord.user_id == ticket.user_id).values(**values))
    else:
        logger.warning("ai_gateway.succeed_after_expiry request=%s", ticket.request_id)
    db.commit()
    return won


def fail(db: Session, ticket: Ticket, code: str) -> bool:
    """The attempt did not produce a plan: refund the reservation (at most once)."""
    latency = round((time.perf_counter() - ticket.started_at) * 1000)
    return _release(db, ticket.request_id, ticket.user_id, ticket.charge_source, "failed", code, latency)


def call_provider(fn: Callable[..., Any], *args, **kwargs) -> Any:
    """Run the provider call under admission control (breaker + concurrency slot) and the request deadline.

    Raises AIBusy when saturated/unhealthy (nothing was called). The circuit breaker learns from the outcome."""
    with provider_admission():
        token = request_deadline.set(time.monotonic() + settings.AI_REQUEST_DEADLINE_SECONDS)
        try:
            result = fn(*args, **kwargs)
        except GeminiFailure as e:
            if e.code in PROVIDER_HEALTH_CODES:
                breaker.record_failure()
            else:
                breaker.record_success()  # the provider answered; the problem was the content/request
            raise
        except Exception:
            breaker.record_neutral()
            raise
        else:
            breaker.record_success()
            return result
        finally:
            request_deadline.reset(token)
