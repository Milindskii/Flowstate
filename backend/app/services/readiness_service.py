from typing import Optional
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from ..models.readiness_profile import ReadinessProfile
from ..models.readiness_observation import ReadinessObservation, ObservationSource
from ..models.user_preferences import UserPreferences
from ..models.user import User
from ..schemas.readiness import (
    ReadinessProfileSchema,
    ReadinessOnboardingRequest,
    ReadinessOnboardingResponse,
    StartingRhythmSummary,
    TodayReadinessResponse,
)
from ..repositories.readiness_repository import ReadinessRepository
from ..engines.readiness_engine import ReadinessEngineV2

class ReadinessService:
    def __init__(self):
        self.repo = ReadinessRepository()
        self.engine = ReadinessEngineV2()

    def get_or_create_default_profile(self, db: Session, user_id: str) -> ReadinessProfile:
        profile = self.repo.get_profile(db, user_id)
        if not profile:
            profile = self.repo.create_or_update_profile(
                db=db,
                user_id=user_id,
                preferred_peak_start="09:30",
                preferred_peak_end="11:45",
                preferred_dip_start="14:00",
                preferred_dip_end="15:30",
                typical_sleep_minutes=480,
                weekday_wake_time="07:00",
                weekend_wake_time="08:30",
                wake_variability=1.5,
                sleep_inertia_minutes=30,
                preferred_session_minutes=45,
                energy_predictability="mostly_predictable",
                optimization_goal="start_difficult_work",
                confidence_level=0.20,
            )
        return profile

    def submit_onboarding_answers(
        self,
        db: Session,
        user_id: str,
        onboarding: ReadinessOnboardingRequest,
    ) -> ReadinessOnboardingResponse:
        # Calculate variability between weekday and weekend wake times
        def _to_hours(t_str: str) -> float:
            try:
                p = t_str.split(":")
                return int(p[0]) + int(p[1]) / 60.0
            except Exception:
                return 7.0

        diff = abs(_to_hours(onboarding.weekend_wake_time) - _to_hours(onboarding.weekday_wake_time))

        profile = self.repo.create_or_update_profile(
            db=db,
            user_id=user_id,
            preferred_peak_start=onboarding.preferred_peak_start,
            preferred_peak_end=onboarding.preferred_peak_end,
            preferred_dip_start="14:00",
            preferred_dip_end="15:30",
            typical_sleep_minutes=480,
            weekday_wake_time=onboarding.weekday_wake_time,
            weekend_wake_time=onboarding.weekend_wake_time,
            wake_variability=round(diff, 2),
            sleep_inertia_minutes=onboarding.sleep_inertia_minutes,
            preferred_session_minutes=onboarding.preferred_session_minutes,
            energy_predictability=onboarding.energy_predictability,
            optimization_goal=onboarding.primary_goal,
            confidence_level=0.25, # Initial onboarding prior calibration
        )

        user = db.query(User).filter(User.id == user_id).first()
        if user:
            user.onboarding_completed = True
            db.add(user)
            db.commit()

        # Update user timezone preference if provided
        if onboarding.timezone:
            user_prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
            if user_prefs:
                user_prefs.timezone = onboarding.timezone
                db.add(user_prefs)
                db.commit()

        # Log initial self_report observation baseline
        baseline_obs = ReadinessObservation(
            user_id=user_id,
            wake_time=onboarding.weekday_wake_time,
            sleep_minutes=480,
            energy_rating=4,
            focus_rating=4,
            source=ObservationSource.self_report.value,
        )
        self.repo.create_observation(db, baseline_obs)

        starting_rhythm = StartingRhythmSummary(
            focus_window_range=f"{onboarding.preferred_peak_start} – {onboarding.preferred_peak_end}",
            readiness_score=75,
            recommendation_band="strong_fit",
            confidence=0.25,
            explanation="Your starting rhythm is calibrated from your onboarding responses. Flowstate will refine it as you work.",
        )

        return ReadinessOnboardingResponse(
            **ReadinessProfileSchema.model_validate(profile).model_dump(),
            starting_rhythm=starting_rhythm,
            profile_version=profile.version,
        )

    def get_profile(self, db: Session, user_id: str) -> Optional[ReadinessProfileSchema]:
        profile = self.repo.get_profile(db, user_id)
        if not profile:
            return None
        return ReadinessProfileSchema.model_validate(profile)

    def get_today_readiness(self, db: Session, user_id: str) -> TodayReadinessResponse:
        profile = self.get_or_create_default_profile(db, user_id)
        observations = self.repo.list_observations(db, user_id, limit=200)

        result = self.engine.evaluate_readiness(
            profile=profile,
            observations=observations,
            target_time=datetime.now(timezone.utc),
        )

        return TodayReadinessResponse(**result)
