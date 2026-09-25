import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, Float, DateTime, ForeignKey, Index
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class ReadinessPrediction(Base):
    """
    Readiness Prediction: Audit log of predictive outputs.
    Records model_version and factors so that prediction accuracy
    and calibration can be evaluated against actual behavioral outcomes.
    """
    __tablename__ = "readiness_predictions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True, index=True)

    slot_start = Column(DateTime(timezone=True), nullable=True)
    slot_end = Column(DateTime(timezone=True), nullable=True)

    readiness_score = Column(Integer, nullable=False) # 0 to 100
    task_fit_score = Column(Integer, nullable=False) # 0 to 100
    confidence = Column(Float, nullable=False) # 0.0 to 1.0
    recommendation_band = Column(String, nullable=False) # strong_fit, reasonable_fit, light_work_preferred, insufficient_confidence
    model_version = Column(String, nullable=False) # e.g. "v2.0.0-progressive"
    top_factors = Column(String, nullable=True) # JSON array of string factors

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    # Relationships
    user = relationship("User", back_populates="readiness_predictions")
    task = relationship("Task")
    evaluations = relationship("ReadinessEvaluation", back_populates="prediction", cascade="all, delete-orphan")

Index("ix_readiness_pred_user_created", ReadinessPrediction.user_id, ReadinessPrediction.created_at)
