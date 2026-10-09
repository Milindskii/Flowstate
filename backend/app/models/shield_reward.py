"""Records behind Shields earned outside the free refill: rewarded ads and paid packs.

Both are written only by services/shield_rewards.py. Each row is the replay guard for one external event:
  * an ad session pays at most once, and only after Google's signed server-side verification names it;
  * a Google Play purchase token pays at most once (unique), whatever the app sends and however often.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, ForeignKey, Integer, String, UniqueConstraint

from ..db.session import Base
from ..db.types import UTCDateTime


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ShieldAdSession(Base):
    """One rewarded ad the app is about to show. Its id is the SSV `custom_data`, so a verified callback can be tied to
    exactly one account and one showing. status: pending -> verified (counted) | over_limit (verified, paid nothing)."""
    __tablename__ = "shield_ad_sessions"

    id = Column(String, primary_key=True, default=lambda: uuid.uuid4().hex)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    status = Column(String, nullable=False, default="pending")
    transaction_id = Column(String, nullable=True)       # AdMob's id for the reward; unique: a replayed callback pays nothing
    shields_granted = Column(Integer, nullable=False, default=0)
    created_at = Column(UTCDateTime(), nullable=False, default=_utcnow)
    verified_at = Column(UTCDateTime(), nullable=True)

    __table_args__ = (UniqueConstraint("transaction_id", name="uq_shield_ad_sessions_transaction"),)


class ShieldPurchase(Base):
    """One verified store purchase of a Shield pack. status: granted (Shields credited, store consume pending) ->
    consumed (Google acknowledged the consumption, the item can be bought again)."""
    __tablename__ = "shield_purchases"

    id = Column(String, primary_key=True, default=lambda: uuid.uuid4().hex)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    store = Column(String, nullable=False, default="google_play")
    product_id = Column(String, nullable=False)
    purchase_token = Column(String, nullable=False)
    order_id = Column(String, nullable=True)
    units = Column(Integer, nullable=False)
    status = Column(String, nullable=False, default="granted")
    created_at = Column(UTCDateTime(), nullable=False, default=_utcnow)
    consumed_at = Column(UTCDateTime(), nullable=True)

    __table_args__ = (UniqueConstraint("purchase_token", name="uq_shield_purchases_token"),)
