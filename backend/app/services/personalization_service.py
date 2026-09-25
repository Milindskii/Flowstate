from typing import Optional, Dict, Any
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from ..repositories.readiness_repository import ReadinessRepository
from ..schemas.personalization import (
    PersonalizationSettingsSchema,
    PersonalizationSettingsUpdate,
    PersonalizationResetResponse,
    PersonalizationExportResponse,
)
from ..schemas.readiness import ReadinessProfileSchema, ObservationResponse, ReadinessPredictionResponse

class PersonalizationService:
    def __init__(self):
        self.repo = ReadinessRepository()

    def get_settings(self, db: Session, user_id: str) -> PersonalizationSettingsSchema:
        settings = self.repo.get_settings(db, user_id)
        return PersonalizationSettingsSchema.model_validate(settings)

    def update_settings(
        self,
        db: Session,
        user_id: str,
        update_in: PersonalizationSettingsUpdate,
    ) -> PersonalizationSettingsSchema:
        updates = update_in.model_dump(exclude_unset=True)
        updated = self.repo.update_settings(db, user_id, **updates)
        return PersonalizationSettingsSchema.model_validate(updated)

    def reset_user_personalization(self, db: Session, user_id: str) -> PersonalizationResetResponse:
        counts = self.repo.reset_personalization_data(db, user_id)
        return PersonalizationResetResponse(
            status="success",
            message="Personalization history and models have been reset. Cold-start baseline restored.",
            deleted_observations=counts["deleted_observations"],
            deleted_predictions=counts["deleted_predictions"],
            deleted_evaluations=counts["deleted_evaluations"],
        )

    def export_user_data(self, db: Session, user_id: str) -> PersonalizationExportResponse:
        profile = self.repo.get_profile(db, user_id)
        settings = self.repo.get_settings(db, user_id)
        observations = self.repo.list_observations(db, user_id, limit=500)
        predictions = self.repo.list_predictions(db, user_id, limit=500)
        evaluations = self.repo.list_evaluations(db, user_id, limit=500)

        return PersonalizationExportResponse(
            user_id=user_id,
            exported_at=datetime.now(timezone.utc),
            profile=ReadinessProfileSchema.model_validate(profile) if profile else None,
            settings=PersonalizationSettingsSchema.model_validate(settings),
            observations_count=len(observations),
            observations=[ObservationResponse.model_validate(o) for o in observations],
            predictions_count=len(predictions),
            predictions=[
                ReadinessPredictionResponse(
                    id=p.id,
                    user_id=p.user_id,
                    task_id=p.task_id,
                    slot_start=p.slot_start,
                    slot_end=p.slot_end,
                    readiness_score=p.readiness_score,
                    task_fit_score=p.task_fit_score,
                    confidence=p.confidence,
                    recommendation_band=p.recommendation_band,
                    model_version=p.model_version,
                    top_factors=[],
                    created_at=p.created_at,
                )
                for p in predictions
            ],
            evaluations_count=len(evaluations),
        )
