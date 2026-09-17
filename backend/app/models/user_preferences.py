from sqlalchemy import Column, String, Float, ForeignKey
from sqlalchemy.orm import relationship
from ..db.session import Base

class UserPreferences(Base):
    __tablename__ = "user_preferences"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    timezone = Column(String, default="Asia/Kolkata", nullable=False)
    wake_time = Column(String, default="06:45", nullable=False)
    sleep_hours = Column(Float, default=7.5, nullable=False)
    focus_peak = Column(String, default="morning", nullable=False) # morning, afternoon, evening, varies
    energy_dip_time = Column(String, default="14:30", nullable=False)
    primary_goal = Column(String, default="College", nullable=False)

    user = relationship("User", back_populates="preferences")
