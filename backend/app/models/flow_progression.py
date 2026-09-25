import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    String,
    Integer,
    Boolean,
    DateTime,
    ForeignKey,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from ..db.session import Base

def utcnow():
    return datetime.now(timezone.utc)

class FlowCompanion(Base):
    __tablename__ = "flow_companions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    species = Column(String, default="fox", nullable=False) # fox, otter, owl, capybara
    name = Column(String, default="Noya", nullable=False)
    level = Column(Integer, default=1, nullable=False)
    stage = Column(String, default="Baby", nullable=False) # Baby, Young, Explorer, Adult, Evolved
    companion_xp = Column(Integer, default=0, nullable=False)
    xp_to_next_level = Column(Integer, default=60, nullable=False)
    is_evolution_ready = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    cosmetic_state = Column(Text, default="{}", nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    last_progress_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="companions")

class FlowProfile(Base):
    __tablename__ = "flow_profiles"

    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    flow_balance = Column(Integer, default=0, nullable=False)
    lifetime_flow = Column(Integer, default=0, nullable=False)
    current_streak = Column(Integer, default=0, nullable=False)
    longest_streak = Column(Integer, default=0, nullable=False)
    streak_start_date = Column(String, nullable=True) # YYYY-MM-DD
    last_qualifying_date = Column(String, nullable=True) # YYYY-MM-DD
    shield_progress_days = Column(Integer, default=0, nullable=False) # 0 to 6
    shields_available = Column(Integer, default=0, nullable=False) # 0 to 3
    shields_used_count = Column(Integer, default=0, nullable=False)
    last_shield_used_date = Column(String, nullable=True) # YYYY-MM-DD

    weekly_flow_points = Column(Integer, default=0, nullable=False)
    current_week_identifier = Column(String, nullable=True) # e.g. 2026-W38
    league_tier = Column(String, default="Bronze", nullable=False) # Bronze, Silver, Gold, Platinum, Diamond
    is_pro = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", backref="flow_profile", uselist=False)

class FlowFocusSession(Base):
    __tablename__ = "flow_focus_sessions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    task_id = Column(String, nullable=True, index=True)

    server_start_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    server_completed_at = Column(DateTime(timezone=True), nullable=True)
    duration_minutes = Column(Integer, nullable=True)
    status = Column(String, default="started", nullable=False) # started, completed, abandoned

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="flow_sessions")

class FlowChallenge(Base):
    __tablename__ = "flow_challenges"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    week_identifier = Column(String, nullable=False, index=True)

    title = Column(String, default="Complete 5 priority tasks", nullable=False)
    target_count = Column(Integer, default=5, nullable=False)
    current_count = Column(Integer, default=0, nullable=False)
    reward_flow = Column(Integer, default=100, nullable=False)
    is_completed = Column(Boolean, default=False, nullable=False)
    is_claimed = Column(Boolean, default=False, nullable=False)
    challenge_type = Column(String, default="priority_tasks", nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="flow_challenges")

class FlowEconomicEvent(Base):
    """
    Authoritative audit ledger and semantic idempotency log.
    Ensures that (user_id, event_type, reference_id) can never be rewarded twice.
    """
    __tablename__ = "flow_economic_events"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    idempotency_key = Column(String, nullable=False, index=True)

    event_type = Column(String, nullable=False, index=True) # focus_session, priority_task, feedback, daily_plan, challenge_claim, evolution
    reference_id = Column(String, nullable=False, index=True) # session_id, task_id, YYYY-MM-DD, challenge_id

    flow_awarded = Column(Integer, default=0, nullable=False)
    xp_awarded = Column(Integer, default=0, nullable=False)
    metadata_json = Column(Text, default="{}", nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="flow_events")

    __table_args__ = (
        UniqueConstraint("user_id", "event_type", "reference_id", name="uq_user_event_reference"),
    )


class FlowDailyQuest(Base):
    """
    Lightweight, progress-driven daily quest.
    Progress accumulates automatically with real events; user explicitly claims when completed.
    """
    __tablename__ = "flow_daily_quests"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    quest_date = Column(String, nullable=False, index=True)  # YYYY-MM-DD
    quest_key = Column(String, nullable=False)  # complete_1_session, finish_2_tasks, give_feedback

    title = Column(String, nullable=False)
    description = Column(String, default="", nullable=False)
    target_count = Column(Integer, default=1, nullable=False)
    current_count = Column(Integer, default=0, nullable=False)
    reward_flow = Column(Integer, default=15, nullable=False)
    is_completed = Column(Boolean, default=False, nullable=False)
    is_claimed = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="daily_quests")

    __table_args__ = (
        UniqueConstraint("user_id", "quest_date", "quest_key", name="uq_user_daily_quest"),
    )


class FlowAchievement(Base):
    """
    Meaningful milestone achievements earned through verified productive work.
    """
    __tablename__ = "flow_achievements"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    achievement_key = Column(String, nullable=False)

    title = Column(String, nullable=False)
    description = Column(String, nullable=False)
    icon = Column(String, default="star", nullable=False)
    reward_flow = Column(Integer, default=25, nullable=False)
    is_unlocked = Column(Boolean, default=False, nullable=False)
    unlocked_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="flow_achievements")

    __table_args__ = (
        UniqueConstraint("user_id", "achievement_key", name="uq_user_achievement"),
    )


class FlowInventoryItem(Base):
    """
    Tracks items purchased from the Flow Shop (companions, cosmetics, shields).
    Each row is an owned item — unlocks gate the companion selector UI.
    """
    __tablename__ = "flow_inventory_items"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    item_type = Column(String, nullable=False)  # companion, cosmetic, shield_bonus
    item_key = Column(String, nullable=False)   # e.g. 'otter', 'theme_dark_wave'
    flow_spent = Column(Integer, default=0, nullable=False)
    purchased_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    user = relationship("User", backref="flow_inventory")

    __table_args__ = (
        UniqueConstraint("user_id", "item_type", "item_key", name="uq_user_inventory_item"),
    )


class FlowWeeklyProgress(Base):
    """
    Authoritative weekly-grind tracker. One row per (user, week_identifier).
    Drives adaptive target calculation, league scoring, and weekly quest completion.
    Updated atomically by the reward pipeline after every qualifying event.
    """
    __tablename__ = "flow_weekly_progress"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    week_identifier = Column(String, nullable=False, index=True)  # e.g. 2026-W38

    # Grind counters (reset each week)
    sessions_completed = Column(Integer, default=0, nullable=False)
    focus_minutes_logged = Column(Integer, default=0, nullable=False)
    priority_tasks_completed = Column(Integer, default=0, nullable=False)
    feedback_given = Column(Integer, default=0, nullable=False)
    flow_points_earned = Column(Integer, default=0, nullable=False)

    # Adaptive weekly target (server-set, updated each week based on prior 4 weeks)
    adaptive_session_target = Column(Integer, default=3, nullable=False)
    adaptive_minutes_target = Column(Integer, default=60, nullable=False)

    # Weekly completion flag (set when sessions_completed >= adaptive_session_target)
    weekly_goal_hit = Column(Boolean, default=False, nullable=False)
    goal_hit_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship("User", backref="weekly_progress")

    __table_args__ = (
        UniqueConstraint("user_id", "week_identifier", name="uq_user_weekly_progress"),
    )
