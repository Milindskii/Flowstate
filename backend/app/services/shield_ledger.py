"""The one place Shield balances change outside an AI charge's own conditional UPDATE.

Server-authoritative by construction:
  * the free-refill clock is `flow_profiles.shield_refill_at`, a server instant; the device clock is never read;
  * every change is ONE conditional UPDATE (compare-and-set), so concurrent requests, retries and double taps can
    never grant or spend the same unit twice;
  * the balance never exceeds MAX_FREE_SHIELDS through a grant (a refund returns exactly what a charge took).

Callers: ai_gateway (debits), ai_economy_service / flow_service (reads: `sync_refill`), flow_service (quest grants).
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from sqlalchemy import case, func, literal, null, select, update
from sqlalchemy.orm import Session

from ..core.economy_config import MAX_FREE_SHIELDS, SHIELD_REFILL_DAYS
from ..db.types import UTCDateTime
from ..models.flow_progression import FlowProfile

REFILL_INTERVAL = timedelta(days=SHIELD_REFILL_DAYS)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None:
        return None
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


def _ts(value: datetime):
    return literal(value, type_=UTCDateTime())


@dataclass(frozen=True)
class ShieldStatus:
    balance: int
    maximum: int
    next_refill_at: Optional[datetime]  # None: at the maximum, no cooldown is running
    server_now: datetime
    granted: bool = False               # this read just granted the free refill

    @property
    def seconds_until_refill(self) -> Optional[int]:
        if self.next_refill_at is None:
            return None
        return max(0, int((self.next_refill_at - self.server_now).total_seconds()))


def debit_values(cost: int, now: Optional[datetime] = None) -> Dict[str, Any]:
    """`.values(...)` for a conditional Shield debit: balance - cost, and the refill clock starts if none is running
    (or if the balance was full, so spending from a full wallet never inherits an old, expired clock)."""
    now = now or _utcnow()
    next_at = _ts(now + REFILL_INTERVAL)
    return {
        "shields_available": FlowProfile.shields_available - cost,
        "shield_refill_at": case(
            (FlowProfile.shields_available >= MAX_FREE_SHIELDS, next_at),
            else_=func.coalesce(FlowProfile.shield_refill_at, next_at),
        ),
    }


def sync_refill(db: Session, user_id: str, now: Optional[datetime] = None,
                profile: Optional[FlowProfile] = None) -> ShieldStatus:
    """Bring the account's free-refill state up to date at SERVER time and report it.

    * balance at the maximum -> any stale clock is cleared;
    * below it and no clock -> the clock starts now (next free Shield in SHIELD_REFILL_DAYS);
    * the clock has run out -> ONE Shield is granted and the clock restarts, atomically (compare-and-set on the
      exact `shield_refill_at` that was read: a concurrent claim matches no row and grants nothing).

    Safe to call on every read; it writes only when something actually changed. A caller that already holds the
    account's profile row passes it in, so a plain read costs no extra query.
    """
    now = now or _utcnow()
    if profile is None:
        profile = db.execute(select(FlowProfile).where(FlowProfile.user_id == user_id)).scalar_one_or_none()
    if profile is None:
        return ShieldStatus(balance=0, maximum=MAX_FREE_SHIELDS, next_refill_at=None, server_now=now)

    balance = profile.shields_available
    due = _aware(profile.shield_refill_at)
    granted = False
    changed = False

    if balance >= MAX_FREE_SHIELDS:
        if due is not None:
            res = db.execute(update(FlowProfile)
                             .where(FlowProfile.user_id == user_id, FlowProfile.shields_available >= MAX_FREE_SHIELDS)
                             .values(shield_refill_at=None))
            changed = res.rowcount == 1
    elif due is None:
        res = db.execute(update(FlowProfile)
                         .where(FlowProfile.user_id == user_id, FlowProfile.shield_refill_at.is_(None),
                                FlowProfile.shields_available < MAX_FREE_SHIELDS)
                         .values(shield_refill_at=now + REFILL_INTERVAL))
        changed = res.rowcount == 1
    elif due <= now:
        next_at = _ts(now + REFILL_INTERVAL)
        res = db.execute(
            update(FlowProfile)
            .where(FlowProfile.user_id == user_id, FlowProfile.shield_refill_at == _ts(due),
                   FlowProfile.shields_available < MAX_FREE_SHIELDS)
            .values(
                shields_available=FlowProfile.shields_available + 1,
                shield_refill_at=case((FlowProfile.shields_available + 1 >= MAX_FREE_SHIELDS, null()), else_=next_at),
            ))
        granted = changed = res.rowcount == 1

    if changed:
        db.commit()
        db.refresh(profile)
    return ShieldStatus(
        balance=profile.shields_available, maximum=MAX_FREE_SHIELDS,
        next_refill_at=_aware(profile.shield_refill_at), server_now=now, granted=granted,
    )


def grant_capped(db: Session, user_id: str, units: int) -> int:
    """Credit up to `units` Shields without passing MAX_FREE_SHIELDS, in one UPDATE. Returns the units credited.
    The caller owns the transaction (a quest claim commits the grant together with its ledger row)."""
    if units <= 0:
        return 0
    before = db.execute(select(FlowProfile.shields_available).where(FlowProfile.user_id == user_id)).scalar_one()
    db.execute(
        update(FlowProfile).where(FlowProfile.user_id == user_id).values(
            shields_available=case(
                (FlowProfile.shields_available >= MAX_FREE_SHIELDS, FlowProfile.shields_available),  # never lowered
                (FlowProfile.shields_available + units > MAX_FREE_SHIELDS, MAX_FREE_SHIELDS),
                else_=FlowProfile.shields_available + units),
        ))
    after = db.execute(select(FlowProfile.shields_available).where(FlowProfile.user_id == user_id)).scalar_one()
    return max(0, after - before)
