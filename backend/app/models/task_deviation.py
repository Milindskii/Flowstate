import uuid

from sqlalchemy import Column, Date, ForeignKey, Index, String

from ..db.session import Base
from ..db.types import UTCDateTime
from .task import utcnow


class TaskDeviation(Base):
    """What happened to a task on a given day, kept apart from where the task goes next.

    A skip/defer moves the task's planned_date forward; this row keeps the fact that it was
    skipped on ``deviation_date`` at ``original_start``, so that day's path can still show it.
    Display-only history: it is never busy time and never planner input.
    """

    __tablename__ = "task_deviations"
    __table_args__ = (Index("ix_task_deviations_user_date", "user_id", "deviation_date"),)

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True)
    deviation_date = Column(Date, nullable=False)
    kind = Column(String(20), nullable=False)  # "skipped" | "deferred" | "missed" | "auto_skipped"
    original_start = Column(UTCDateTime, nullable=True)
    original_end = Column(UTCDateTime, nullable=True)
    moved_to_date = Column(Date, nullable=True)
    plan_id = Column(String(100), nullable=True)
    created_at = Column(UTCDateTime, nullable=False, default=utcnow)
