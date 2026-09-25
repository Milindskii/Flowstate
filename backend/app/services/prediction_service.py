import json
from typing import Optional, Dict, Any
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from ..models.readiness_prediction import ReadinessPrediction
from ..repositories.readiness_repository import ReadinessRepository
from ..engines.readiness_engine import ReadinessEngineV2

class PredictionService:
    def __init__(self):
        self.repo = ReadinessRepository()
        self.engine = ReadinessEngineV2()

    def generate_and_record_prediction(
        self,
        db: Session,
        user_id: str,
        task_id: Optional[str] = None,
        task_type: str = "deep_work",
        task_difficulty: str = "medium",
        slot_start: Optional[datetime] = None,
        slot_end: Optional[datetime] = None,
    ) -> ReadinessPrediction:
        profile = self.repo.get_profile(db, user_id)
        observations = self.repo.list_observations(db, user_id, limit=200)

        eval_result = self.engine.evaluate_readiness(
            profile=profile,
            observations=observations,
            task_type=task_type,
            task_difficulty=task_difficulty,
            target_time=slot_start or datetime.now(timezone.utc),
        )

        prediction = ReadinessPrediction(
            user_id=user_id,
            task_id=task_id,
            slot_start=slot_start,
            slot_end=slot_end,
            readiness_score=eval_result["readiness_score"],
            task_fit_score=eval_result["task_fit_score"],
            confidence=eval_result["confidence"],
            recommendation_band=eval_result["recommendation_band"],
            model_version=eval_result["model_version"],
            top_factors=json.dumps(eval_result["top_factors"]),
        )
        return self.repo.create_prediction(db, prediction)
