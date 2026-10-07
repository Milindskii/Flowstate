from sqlalchemy import Column, ForeignKey, String, Text

from ..db.session import Base
from ..db.types import UTCDateTime
from .task import utcnow


class PlanApplication(Base):
    """Write-once record per (user, plan_id): makes confirm/apply idempotent (spec §7, §8.2)."""

    __tablename__ = "plan_applications"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    plan_id = Column(String(100), primary_key=True)
    kind = Column(String(20), nullable=False)  # "build" | "replan"
    response_json = Column(Text, nullable=False)
    created_at = Column(UTCDateTime, nullable=False, default=utcnow)
