import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Text, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class PrivacyGrievance(Base):
    __tablename__ = "privacy_grievances"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    email = Column(String, nullable=False, index=True)
    request_type = Column(String, nullable=False, default="general_grievance")  # access, correction, erasure_inquiry, objection, general_grievance
    message = Column(Text, nullable=False)
    status = Column(String, nullable=False, default="received")  # received, in_review, resolved, closed
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", backref="grievances")
