"""
Flowstate — Recommendation Repository
=======================================
All DB access for RecommendationDecision and RecommendationOutcome.
Strict user isolation enforced on every query.
"""

from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import desc

from ..models.recommendation import RecommendationDecision, RecommendationOutcome


class RecommendationRepository:

    # ── Decision ──────────────────────────────────────────────────────────

    def create_decision(
        self, db: Session, decision: RecommendationDecision
    ) -> RecommendationDecision:
        db.add(decision)
        db.commit()
        db.refresh(decision)
        return decision

    def get_decision(
        self, db: Session, decision_id: str, user_id: str
    ) -> Optional[RecommendationDecision]:
        """User-isolated lookup — returns None if decision belongs to a different user."""
        return (
            db.query(RecommendationDecision)
            .filter(
                RecommendationDecision.id == decision_id,
                RecommendationDecision.user_id == user_id,
            )
            .first()
        )

    def list_decisions(
        self,
        db: Session,
        user_id: str,
        limit: int = 100,
    ) -> List[RecommendationDecision]:
        return (
            db.query(RecommendationDecision)
            .filter(RecommendationDecision.user_id == user_id)
            .order_by(desc(RecommendationDecision.created_at))
            .limit(limit)
            .all()
        )

    def get_latest_decision(
        self, db: Session, user_id: str
    ) -> Optional[RecommendationDecision]:
        return (
            db.query(RecommendationDecision)
            .filter(RecommendationDecision.user_id == user_id)
            .order_by(desc(RecommendationDecision.created_at))
            .first()
        )

    # ── Outcome ───────────────────────────────────────────────────────────

    def create_outcome(
        self, db: Session, outcome: RecommendationOutcome
    ) -> RecommendationOutcome:
        db.add(outcome)
        db.commit()
        db.refresh(outcome)
        return outcome

    def get_outcome_by_decision(
        self, db: Session, decision_id: str, user_id: str
    ) -> Optional[RecommendationOutcome]:
        return (
            db.query(RecommendationOutcome)
            .filter(
                RecommendationOutcome.decision_id == decision_id,
                RecommendationOutcome.user_id == user_id,
            )
            .first()
        )

    def update_outcome(
        self, db: Session, outcome: RecommendationOutcome, **kwargs
    ) -> RecommendationOutcome:
        for k, v in kwargs.items():
            if hasattr(outcome, k):
                setattr(outcome, k, v)
        db.commit()
        db.refresh(outcome)
        return outcome

    def list_outcomes(
        self,
        db: Session,
        user_id: str,
        limit: int = 200,
    ) -> List[RecommendationOutcome]:
        return (
            db.query(RecommendationOutcome)
            .filter(RecommendationOutcome.user_id == user_id)
            .order_by(desc(RecommendationOutcome.created_at))
            .limit(limit)
            .all()
        )

    # ── Analytics helpers ──────────────────────────────────────────────────

    def count_accepted(self, db: Session, user_id: str) -> int:
        return (
            db.query(RecommendationOutcome)
            .filter(
                RecommendationOutcome.user_id == user_id,
                RecommendationOutcome.user_action == "accepted",
            )
            .count()
        )

    def count_overridden(self, db: Session, user_id: str) -> int:
        return (
            db.query(RecommendationOutcome)
            .filter(
                RecommendationOutcome.user_id == user_id,
                RecommendationOutcome.user_action == "overridden",
            )
            .count()
        )

    def count_postponed(self, db: Session, user_id: str) -> int:
        return (
            db.query(RecommendationOutcome)
            .filter(
                RecommendationOutcome.user_id == user_id,
                RecommendationOutcome.user_action == "later",
            )
            .count()
        )

    def count_total_decisions(self, db: Session, user_id: str) -> int:
        return (
            db.query(RecommendationDecision)
            .filter(RecommendationDecision.user_id == user_id)
            .count()
        )
