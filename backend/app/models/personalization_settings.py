from datetime import datetime, timezone
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class PersonalizationSettings(Base):
    """
    Personalization Settings: Clear user privacy controls.
    Avoids exposing technical model hyperparameters like learning_rate to users.
    """
    __tablename__ = "personalization_settings"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)

    personalization_enabled = Column(Boolean, default=True, nullable=False)
    context_capture_enabled = Column(Boolean, default=True, nullable=False)
    use_task_history = Column(Boolean, default=True, nullable=False)
    use_focus_feedback = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", back_populates="personalization_settings")
