from typing import Optional, List, Dict, Any
from collections import defaultdict
from sqlalchemy.orm import Session

from ..models.readiness_prediction import ReadinessPrediction
from ..models.readiness_observation import ReadinessObservation
from ..models.readiness_evaluation import ReadinessEvaluation
from ..repositories.readiness_repository import ReadinessRepository
from ..schemas.personalization import PersonalizationEvaluationResponse, EvaluationMetric

class EvaluationService:
    def __init__(self):
        self.repo = ReadinessRepository()

    def record_evaluation(
        self,
        db: Session,
        user_id: str,
        observation: ReadinessObservation,
        prediction: Optional[ReadinessPrediction] = None,
    ) -> Optional[ReadinessEvaluation]:
        """Links an observation to its preceding prediction and calculates calibration score."""
        if not prediction:
            prediction = self.repo.get_latest_prediction(db, user_id, task_id=observation.task_id)

        if not prediction:
            return None

        is_success = (observation.outcome == "completed" or (observation.focus_rating and observation.focus_rating >= 3))
        planned = observation.planned_minutes or 45
        actual = observation.actual_minutes or planned
        duration_ratio = round(actual / planned, 2) if planned > 0 else 1.0

        predicted_prob = prediction.readiness_score / 100.0
        actual_val = 1.0 if is_success else 0.0
        brier_score = round((predicted_prob - actual_val) ** 2, 4)

        evaluation = ReadinessEvaluation(
            user_id=user_id,
            prediction_id=prediction.id,
            observation_id=observation.id,
            predicted_band=prediction.recommendation_band,
            actual_outcome=observation.outcome or ("completed" if is_success else "incomplete"),
            planned_minutes=planned,
            actual_minutes=actual,
            duration_ratio=duration_ratio,
            brier_score=brier_score,
            is_successful=is_success,
        )
        return self.repo.create_evaluation(db, evaluation)

    def compute_evaluation_metrics(self, db: Session, user_id: str) -> PersonalizationEvaluationResponse:
        evals = self.repo.list_evaluations(db, user_id, limit=300)
        total = len(evals)
        if total == 0:
            return PersonalizationEvaluationResponse(
                total_evaluations=0,
                brier_calibration_score=0.0,
                overall_completion_rate=0.0,
                overall_postponement_rate=0.0,
                avg_duration_ratio=1.0,
                accuracy_by_time_window={"morning": 0.0, "afternoon": 0.0, "evening": 0.0},
                metrics_by_task_type=[],
                model_version="v2.0.0-progressive",
            )

        avg_brier = sum(e.brier_score for e in evals) / total
        completed_count = sum(1 for e in evals if e.is_successful)
        postponed_count = sum(1 for e in evals if e.actual_outcome == "postponed")
        avg_ratio = sum(e.duration_ratio for e in evals) / total

        # Group by hour window
        window_stats = defaultdict(lambda: {"total": 0, "correct": 0})
        for e in evals:
            hr = e.created_at.hour
            win = "morning" if 5 <= hr < 12 else ("afternoon" if 12 <= hr < 18 else "evening")
            window_stats[win]["total"] += 1
            if e.is_successful and e.predicted_band in ("strong_fit", "reasonable_fit"):
                window_stats[win]["correct"] += 1
            elif not e.is_successful and e.predicted_band == "light_work_preferred":
                window_stats[win]["correct"] += 1

        accuracy_by_window = {
            win: round(data["correct"] / data["total"], 2) if data["total"] > 0 else 0.0
            for win, data in window_stats.items()
        }

        return PersonalizationEvaluationResponse(
            total_evaluations=total,
            brier_calibration_score=round(avg_brier, 4),
            overall_completion_rate=round(completed_count / total, 2),
            overall_postponement_rate=round(postponed_count / total, 2),
            avg_duration_ratio=round(avg_ratio, 2),
            accuracy_by_time_window=accuracy_by_window,
            metrics_by_task_type=[
                EvaluationMetric(
                    category="deep_work",
                    total_samples=completed_count,
                    completion_rate=round(completed_count / total, 2),
                    avg_duration_ratio=round(avg_ratio, 2),
                )
            ],
            model_version="v2.0.0-progressive",
        )
