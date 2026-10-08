import uuid
from sqlalchemy import JSON, Column, Date, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from ..db.session import Base
from ..db.types import UTCDateTime
from .task import utcnow


class Routine(Base):
    """A recurring routine TEMPLATE ("Gym, every day at 4 PM"). Never an unbounded set of task rows.

    Occurrences are materialized as ordinary tasks only inside a bounded rolling horizon (ROUTINE_HORIZON_DAYS) and are
    topped up from ``materialized_through``. Editing or deleting a routine touches future occurrences only; past rows
    (completed, missed, skipped) are history and are never rewritten.
    """
    __tablename__ = "routines"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    title = Column(String(255), nullable=False)
    task_type = Column(String(32), nullable=False, default="personal")
    category = Column(String(50), nullable=False, default="General")
    estimated_minutes = Column(Integer, nullable=False, default=45)

    # fixed: locked at start_hhmm | preferred: soft, planned at start_hhmm but movable
    # earliest: may not start before start_hhmm (no slot invented) | avoid: never during [start_hhmm, end_hhmm)
    kind = Column(String(16), nullable=False, default="fixed")
    recurrence = Column(String(16), nullable=False, default="daily")   # daily | weekly
    weekdays = Column(JSON, nullable=True)                              # [0..6] Monday=0; null for daily
    start_hhmm = Column(String(5), nullable=True)
    end_hhmm = Column(String(5), nullable=True)

    effective_from = Column(Date, nullable=False)
    materialized_through = Column(Date, nullable=True)     # last local date occurrences were generated for
    skipped_dates = Column(JSON, nullable=True)            # ["YYYY-MM-DD"]: one-day overrides, never re-created
    idempotency_key = Column(String(100), nullable=True)   # a double-confirm creates the routine once
    deleted_at = Column(UTCDateTime, nullable=True)

    created_at = Column(UTCDateTime, default=utcnow, nullable=False)
    updated_at = Column(UTCDateTime, default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User")
