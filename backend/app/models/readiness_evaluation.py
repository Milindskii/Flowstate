import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Index
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class ReadinessEvaluation(Base):
    """
    Readiness Evaluation: Quantifies predictive accuracy and calibration.
    Computes Brier calibration score and duration tracking comparing
    predictions against actual focus outcomes.
    """
    __tablename__ = "readiness_evaluations"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    prediction_id = Column(String, ForeignKey("readiness_predictions.id", ondelete="CASCADE"), nullable=False, index=True)
    observation_id = Column(String, ForeignKey("readiness_observations.id", ondelete="CASCADE"), nullable=False, index=True)

    predicted_band = Column(String, nullable=False)
    actual_outcome = Column(String, nullable=False) # completed, abandoned, postponed, overrun

    planned_minutes = Column(Integer, nullable=False, default=45)
    actual_minutes = Column(Integer, nullable=False, default=45)
    duration_ratio = Column(Float, nullable=False, default=1.0) # actual / planned
    brier_score = Column(Float, nullable=False, default=0.0) # (readiness_prob - outcome)^2
    is_successful = Column(Boolean, nullable=False, default=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    # Relationships
    user = relationship("User")
    prediction = relationship("ReadinessPrediction", back_populates="evaluations")
    observation = relationship("ReadinessObservation", back_populates="evaluation")

Index("ix_readiness_eval_user_created", ReadinessEvaluation.user_id, ReadinessEvaluation.created_at)
