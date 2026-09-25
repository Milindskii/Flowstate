import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class ReadinessProfile(Base):
    """
    Readiness Profile: recomputable user cognitive profile.
    Separates derived parameters from raw observations so the profile
    can be recomputed as personalization models evolve.
    """
    __tablename__ = "readiness_profiles"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    version = Column(Integer, default=1, nullable=False)

    preferred_peak_start = Column(String, default="09:30", nullable=False)
    preferred_peak_end = Column(String, default="11:45", nullable=False)
    preferred_dip_start = Column(String, default="14:00", nullable=False)
    preferred_dip_end = Column(String, default="15:30", nullable=False)

    typical_sleep_minutes = Column(Integer, default=480, nullable=False)
    weekday_wake_time = Column(String, default="07:00", nullable=False)
    weekend_wake_time = Column(String, default="08:30", nullable=False)
    wake_variability = Column(Float, default=1.5, nullable=False) # hours diff
    sleep_inertia_minutes = Column(Integer, default=30, nullable=False)
    preferred_session_minutes = Column(Integer, default=45, nullable=False)

    energy_predictability = Column(String, default="mostly_predictable", nullable=False)
    optimization_goal = Column(String, default="start_difficult_work", nullable=False)

    personalization_enabled = Column(Boolean, default=True, nullable=False)
    confidence_level = Column(Float, default=0.20, nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", back_populates="readiness_profile")
