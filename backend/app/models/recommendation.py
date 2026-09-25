"""
Flowstate — Recommendation Audit Tables
========================================
Stores every recommendation decision and its outcome so we can:
1. Audit why a task was recommended
2. Measure acceptance, override, postponement rates
3. Close the learning loop: recommendation → action → outcome → engine improvement
4. Run engine experiments (generic_v1 vs personalized_v1)
"""

import uuid
import json
from datetime import datetime, timezone
from sqlalchemy import Column, String, Float, Integer, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from ..db.session import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class RecommendationDecision(Base):
    """
    Immutable audit record of one recommendation made by Flowstate.

    Written every time GET /today is called and a recommendation is generated.
    Stores ALL candidate scores so we can evaluate ranking quality, not just the winner.
    """
    __tablename__ = "recommendation_decisions"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False, index=True)

    # ── Context snapshot at the moment of recommendation ──────────────────
    # Stored as JSON-encoded strings for portability (SQLite-compatible)
    readiness_score = Column(Float, nullable=True)        # 0–100 from ReadinessEngineV2
    readiness_confidence = Column(Float, nullable=True)   # 0.0–1.0
    readiness_stage = Column(String, nullable=True)       # "Stage A" / "Stage B" / "Stage C"
    total_pending_tasks = Column(Integer, default=0)
    total_pending_minutes = Column(Integer, default=0)
    available_minutes = Column(Integer, default=390)

    # ── Candidate scores (ALL tasks that were ranked) ─────────────────────
    # JSON array: [{"task_id": "...", "score": 0.82, "reasons": [...], "breakdown": {...}}]
    candidate_scores_json = Column(Text, default="[]")

    # ── Winner ────────────────────────────────────────────────────────────
    recommended_task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True, index=True)
    recommendation_score = Column(Float, nullable=True)
    recommendation_reasons_json = Column(Text, default="[]")  # JSON array of reason strings

    # ── Engine provenance ─────────────────────────────────────────────────
    engine_version = Column(String, default="generic_v1")   # "generic_v1" | "personalized_v1"
    strategy = Column(String, default="exploitation")        # "exploitation" | "exploration"
    observation_count = Column(Integer, default=0)

    # ── Relationships ──────────────────────────────────────────────────────
    user = relationship("User")
    outcomes = relationship("RecommendationOutcome", back_populates="decision", cascade="all, delete-orphan")

    # ── Convenience property helpers ───────────────────────────────────────
    @property
    def candidate_scores(self):
        try:
            return json.loads(self.candidate_scores_json or "[]")
        except Exception:
            return []

    @candidate_scores.setter
    def candidate_scores(self, value):
        self.candidate_scores_json = json.dumps(value)

    @property
    def recommendation_reasons(self):
        try:
            return json.loads(self.recommendation_reasons_json or "[]")
        except Exception:
            return []

    @recommendation_reasons.setter
    def recommendation_reasons(self, value):
        self.recommendation_reasons_json = json.dumps(value)


class RecommendationOutcome(Base):
    """
    Tracks what the user actually did after a recommendation.

    Written when:
    - User starts a focus session (user_action = "accepted")
    - User taps "Later" (user_action = "later")
    - User picks a different task (user_action = "overridden")
    - User dismisses without action (user_action = "dismissed")
    - Focus session completes (fills completed_at, actual_minutes, focus_rating)
    """
    __tablename__ = "recommendation_outcomes"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    decision_id = Column(
        String,
        ForeignKey("recommendation_decisions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # ── Task actually worked on ────────────────────────────────────────────
    task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True)

    # ── User decision ─────────────────────────────────────────────────────
    user_action = Column(
        String,
        nullable=False,
        default="accepted",
        # accepted | overridden | later | dismissed
    )

    # Free-text reason from the override enum, written by the user
    override_reason = Column(String, nullable=True)
    # The task_id chosen if user overrode recommendation
    override_to_task_id = Column(String, ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True)

    # ── Session timing ────────────────────────────────────────────────────
    started_at    = Column(DateTime(timezone=True), nullable=True)   # when user actually started
    completed_at  = Column(DateTime(timezone=True), nullable=True)
    postponed_at  = Column(DateTime(timezone=True), nullable=True)
    abandoned_at  = Column(DateTime(timezone=True), nullable=True)

    # ── Session quality ────────────────────────────────────────────────────
    actual_minutes    = Column(Integer, nullable=True)
    focus_rating      = Column(Integer, nullable=True)   # 1–5
    energy_rating     = Column(Integer, nullable=True)   # 1–5
    difficulty_rating = Column(Integer, nullable=True)   # 1–5

    # Derived outcome string: "completed" | "abandoned" | "postponed" | "not_started"
    outcome = Column(String, nullable=True)

    # ── Postpone replanning ────────────────────────────────────────────────
    # Suggested next window sent back to user after "Later"
    suggested_replan_date = Column(String, nullable=True)    # "YYYY-MM-DD"
    suggested_replan_time = Column(String, nullable=True)    # "HH:MM"

    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    # ── Relationships ──────────────────────────────────────────────────────
    decision = relationship("RecommendationDecision", back_populates="outcomes")
    user = relationship("User")
