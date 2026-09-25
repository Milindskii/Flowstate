import uuid
from enum import Enum
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Index
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class ObservationSource(str, Enum):
    self_report = "self_report"
    observed = "observed"
    inferred = "inferred"
    imported = "imported"

class ReadinessObservation(Base):
    """
    Readiness Observation: Raw immutable behavioral or self-report telemetry.
    Distinguishes self_report from direct behavioral evidence.
    """
    __tablename__ = "readiness_observations"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True, index=True)

    observed_at = Column(DateTime(timezone=True), default=utcnow, nullable=False, index=True)
    wake_time = Column(String, nullable=True)
    sleep_minutes = Column(Integer, nullable=True)
    sleep_quality = Column(Integer, nullable=True) # 1 to 5
    time_since_waking = Column(Integer, nullable=True) # minutes

    energy_rating = Column(Integer, nullable=True) # 1 to 5
    focus_rating = Column(Integer, nullable=True) # 1 to 5
    difficulty_rating = Column(Integer, nullable=True) # 1 to 5
    distraction_rating = Column(Integer, nullable=True) # 1 to 5

    environment_type = Column(String, nullable=True) # home, office, cafe, etc.
    task_type = Column(String, nullable=True) # deep_work, creative, admin, etc.
    task_difficulty = Column(String, nullable=True) # low, medium, high, intense
    planned_minutes = Column(Integer, nullable=True)
    actual_minutes = Column(Integer, nullable=True)
    outcome = Column(String, nullable=True) # completed, abandoned, postponed, overrun

    # Provenance tracking: self_report vs observed vs inferred vs imported
    source = Column(String, default=ObservationSource.observed.value, nullable=False, index=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="readiness_observations")
    task = relationship("Task")
    evaluation = relationship("ReadinessEvaluation", back_populates="observation", uselist=False)

Index("ix_readiness_obs_user_observed", ReadinessObservation.user_id, ReadinessObservation.observed_at)
Index("ix_readiness_obs_user_source", ReadinessObservation.user_id, ReadinessObservation.source)
