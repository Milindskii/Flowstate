from typing import Optional, List
from sqlalchemy.orm import Session

from ..models.readiness_observation import ReadinessObservation, ObservationSource
from ..schemas.readiness import ObservationCreate
from ..repositories.readiness_repository import ReadinessRepository
from ..engines.personalization_engine import PersonalizationEngine

class ObservationService:
    def __init__(self):
        self.repo = ReadinessRepository()
        self.personalization_engine = PersonalizationEngine()

    def record_observation(
        self,
        db: Session,
        user_id: str,
        data: ObservationCreate,
    ) -> ReadinessObservation:
        obs = ReadinessObservation(
            user_id=user_id,
            task_id=data.task_id,
            wake_time=data.wake_time,
            sleep_minutes=data.sleep_minutes,
            sleep_quality=data.sleep_quality,
            time_since_waking=data.time_since_waking,
            energy_rating=data.energy_rating,
            focus_rating=data.focus_rating,
            difficulty_rating=data.difficulty_rating,
            distraction_rating=data.distraction_rating,
            environment_type=data.environment_type,
            task_type=data.task_type,
            task_difficulty=data.task_difficulty,
            planned_minutes=data.planned_minutes,
            actual_minutes=data.actual_minutes,
            outcome=data.outcome,
            source=data.source.value if hasattr(data.source, "value") else str(data.source),
        )
        saved = self.repo.create_observation(db, obs)

        # Trigger progressive profile recomputation
        profile = self.repo.get_profile(db, user_id)
        if profile and profile.personalization_enabled:
            all_obs = self.repo.list_observations(db, user_id, limit=200)
            self.personalization_engine.recompute_profile(profile, all_obs)
            db.commit()

        return saved

    def list_user_observations(self, db: Session, user_id: str, limit: int = 100) -> List[ReadinessObservation]:
        return self.repo.list_observations(db, user_id, limit=limit)
