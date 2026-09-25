from typing import Optional, List
from datetime import datetime, timezone
from sqlalchemy.orm import Session
from sqlalchemy import desc

from ..models.readiness_profile import ReadinessProfile
from ..models.readiness_observation import ReadinessObservation
from ..models.readiness_prediction import ReadinessPrediction
from ..models.readiness_evaluation import ReadinessEvaluation
from ..models.personalization_settings import PersonalizationSettings

class ReadinessRepository:
    """Repository handling all readiness and personalization database access with strict user isolation."""

    # --- Profile ---
    def get_profile(self, db: Session, user_id: str) -> Optional[ReadinessProfile]:
        return db.query(ReadinessProfile).filter(ReadinessProfile.user_id == user_id).first()

    def create_or_update_profile(self, db: Session, user_id: str, **kwargs) -> ReadinessProfile:
        profile = self.get_profile(db, user_id)
        if not profile:
            profile = ReadinessProfile(user_id=user_id, **kwargs)
            db.add(profile)
        else:
            for k, v in kwargs.items():
                if hasattr(profile, k) and v is not None:
                    setattr(profile, k, v)
        db.commit()
        db.refresh(profile)
        return profile

    # --- Settings ---
    def get_settings(self, db: Session, user_id: str) -> PersonalizationSettings:
        settings = db.query(PersonalizationSettings).filter(PersonalizationSettings.user_id == user_id).first()
        if not settings:
            settings = PersonalizationSettings(user_id=user_id)
            db.add(settings)
            db.commit()
            db.refresh(settings)
        return settings

    def update_settings(self, db: Session, user_id: str, **kwargs) -> PersonalizationSettings:
        settings = self.get_settings(db, user_id)
        for k, v in kwargs.items():
            if hasattr(settings, k) and v is not None:
                setattr(settings, k, v)
        db.commit()
        db.refresh(settings)
        return settings

    # --- Observations ---
    def create_observation(self, db: Session, observation: ReadinessObservation) -> ReadinessObservation:
        db.add(observation)
        db.commit()
        db.refresh(observation)
        return observation

    def list_observations(self, db: Session, user_id: str, limit: int = 100) -> List[ReadinessObservation]:
        return (
            db.query(ReadinessObservation)
            .filter(ReadinessObservation.user_id == user_id)
            .order_by(desc(ReadinessObservation.observed_at))
            .limit(limit)
            .all()
        )

    def count_observations(self, db: Session, user_id: str) -> int:
        return db.query(ReadinessObservation).filter(ReadinessObservation.user_id == user_id).count()

    # --- Predictions ---
    def create_prediction(self, db: Session, prediction: ReadinessPrediction) -> ReadinessPrediction:
        db.add(prediction)
        db.commit()
        db.refresh(prediction)
        return prediction

    def get_latest_prediction(self, db: Session, user_id: str, task_id: Optional[str] = None) -> Optional[ReadinessPrediction]:
        q = db.query(ReadinessPrediction).filter(ReadinessPrediction.user_id == user_id)
        if task_id:
            q = q.filter(ReadinessPrediction.task_id == task_id)
        return q.order_by(desc(ReadinessPrediction.created_at)).first()

    def list_predictions(self, db: Session, user_id: str, limit: int = 100) -> List[ReadinessPrediction]:
        return (
            db.query(ReadinessPrediction)
            .filter(ReadinessPrediction.user_id == user_id)
            .order_by(desc(ReadinessPrediction.created_at))
            .limit(limit)
            .all()
        )

    # --- Evaluations ---
    def create_evaluation(self, db: Session, evaluation: ReadinessEvaluation) -> ReadinessEvaluation:
        db.add(evaluation)
        db.commit()
        db.refresh(evaluation)
        return evaluation

    def list_evaluations(self, db: Session, user_id: str, limit: int = 200) -> List[ReadinessEvaluation]:
        return (
            db.query(ReadinessEvaluation)
            .filter(ReadinessEvaluation.user_id == user_id)
            .order_by(desc(ReadinessEvaluation.created_at))
            .limit(limit)
            .all()
        )

    # --- Reset & Export ---
    def reset_personalization_data(self, db: Session, user_id: str) -> dict:
        del_obs = db.query(ReadinessObservation).filter(ReadinessObservation.user_id == user_id).delete(synchronize_session=False)
        del_preds = db.query(ReadinessPrediction).filter(ReadinessPrediction.user_id == user_id).delete(synchronize_session=False)
        del_evals = db.query(ReadinessEvaluation).filter(ReadinessEvaluation.user_id == user_id).delete(synchronize_session=False)

        profile = self.get_profile(db, user_id)
        if profile:
            profile.confidence_level = 0.20
            profile.version += 1
            db.add(profile)

        db.commit()
        return {
            "deleted_observations": del_obs,
            "deleted_predictions": del_preds,
            "deleted_evaluations": del_evals,
        }
