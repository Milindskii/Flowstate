import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Boolean, DateTime
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class User(Base):
    __tablename__ = "users"

    # User ID matches Supabase Auth user UUID
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False, default="Friend")
    avatar_url = Column(String, nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    is_admin = Column(Boolean, default=False, nullable=False)
    onboarding_completed = Column(Boolean, default=False, nullable=False)
    # Legal & Compliance
    terms_accepted = Column(Boolean, default=False, nullable=False)
    privacy_accepted = Column(Boolean, default=False, nullable=False)
    age_confirmed = Column(Boolean, default=False, nullable=False)
    marketing_emails_enabled = Column(Boolean, default=False, nullable=False)
    consent_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    # Relationships
    preferences = relationship("UserPreferences", back_populates="user", uselist=False, cascade="all, delete-orphan")
    tasks = relationship("Task", back_populates="user", cascade="all, delete-orphan")
    performances = relationship("TaskPerformance", back_populates="user", cascade="all, delete-orphan")
    readiness_profile = relationship("ReadinessProfile", back_populates="user", uselist=False, cascade="all, delete-orphan")
    personalization_settings = relationship("PersonalizationSettings", back_populates="user", uselist=False, cascade="all, delete-orphan")
    readiness_observations = relationship("ReadinessObservation", back_populates="user", cascade="all, delete-orphan")
    readiness_predictions = relationship("ReadinessPrediction", back_populates="user", cascade="all, delete-orphan")
