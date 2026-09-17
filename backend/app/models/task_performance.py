import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class TaskPerformance(Base):
    __tablename__ = "task_performance"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    task_id = Column(String, ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    scheduled_start = Column(DateTime(timezone=True), nullable=True)
    actual_start = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=False, default=utcnow)

    estimated_minutes = Column(Integer, nullable=False, default=45)
    actual_minutes = Column(Integer, nullable=False, default=45)

    # Subjective post-session reflection ratings (1 to 5)
    focus_score = Column(Integer, nullable=False, default=3) # 1 (distracted) to 5 (flow)
    energy_score = Column(Integer, nullable=False, default=3) # 1 (drained) to 5 (energized)
    difficulty_score = Column(Integer, nullable=False, default=3) # 1 (breeze) to 5 (intense)
    distraction_score = Column(Integer, nullable=True) # 1 (none) to 5 (severe)

    notes = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    # Relationships
    task = relationship("Task", back_populates="performance_records")
    user = relationship("User", back_populates="performances")
