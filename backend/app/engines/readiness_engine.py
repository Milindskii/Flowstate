import math
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime, timezone, time

from ..models.readiness_profile import ReadinessProfile
from ..models.readiness_observation import ReadinessObservation, ObservationSource

STAGE_A_MAX_OBSERVATIONS = 9
STAGE_B_MAX_OBSERVATIONS = 49
SHRINKAGE_ALPHA = 5.0 # Empirical Bayes pseudo-prior weight
MODEL_VERSION = "v2.0.0-progressive"

class ReadinessEngineV2:
    """
    Non-medical progressive intelligence readiness engine.
    Computes P(success | person, task, time, context) across:
    - Stage A: Rules + weighted scoring (0-9 observations)
    - Stage B: Empirical statistics with Empirical Bayes shrinkage (10-49 observations)
    - Stage C: Personalized online model (50+ observations)
    """

    def __init__(self, model_version: str = MODEL_VERSION):
        self.model_version = model_version

    def determine_stage(self, observation_count: int) -> Tuple[str, str]:
        if observation_count <= STAGE_A_MAX_OBSERVATIONS:
            return "Stage A", "Stage A (Rules & Weighted Prior)"
        elif observation_count <= STAGE_B_MAX_OBSERVATIONS:
            return "Stage B", "Stage B (Empirical Bayes Shrinkage)"
        else:
            return "Stage C", "Stage C (Personalized Predictive Model)"

    def _parse_time_str(self, time_str: str) -> float:
        """Parses 'HH:MM' into fractional hours (e.g. '09:30' -> 9.5)."""
        try:
            parts = time_str.strip().split(":")
            return int(parts[0]) + int(parts[1]) / 60.0
        except Exception:
            return 9.0

    def _get_time_of_day_bucket(self, hour: float) -> str:
        if 5.0 <= hour < 12.0:
            return "morning"
        elif 12.0 <= hour < 15.0:
            return "midday"
        elif 15.0 <= hour < 19.0:
            return "afternoon"
        else:
            return "evening"

    def compute_prior_fit(
        self,
        profile: Optional[ReadinessProfile],
        task_type: str,
        task_difficulty: str,
        target_time: datetime,
    ) -> Tuple[float, List[str]]:
        """Stage A: Rules-based prior probability calculation."""
        factors: List[str] = []
        hour = target_time.hour + target_time.minute / 60.0

        peak_start = self._parse_time_str(profile.preferred_peak_start if profile else "09:30")
        peak_end = self._parse_time_str(profile.preferred_peak_end if profile else "11:45")
        dip_start = self._parse_time_str(profile.preferred_dip_start if profile else "14:00")
        dip_end = self._parse_time_str(profile.preferred_dip_end if profile else "15:30")

        # Base cognitive readiness score from time-of-day alignment
        if peak_start <= hour <= peak_end:
            base_readiness = 0.88
            factors.append("Preferred cognitive peak focus window")
        elif dip_start <= hour <= dip_end:
            base_readiness = 0.45
            factors.append("Typical afternoon energy dip period")
        elif 9.0 <= hour <= 18.0:
            base_readiness = 0.68
            factors.append("Standard daylight working window")
        else:
            base_readiness = 0.50
            factors.append("Off-peak circadian boundary")

        # Sleep inertia penalty if near reported wake time
        wake_hour = self._parse_time_str(profile.weekday_wake_time if profile else "07:00")
        inertia_hours = (profile.sleep_inertia_minutes if profile else 30) / 60.0
        if 0 <= (hour - wake_hour) < inertia_hours:
            base_readiness *= 0.70
            factors.append(f"Post-wake sleep inertia transition (~{int(inertia_hours * 60)}m)")

        # Task demand weighting
        task_multiplier = 1.0
        diff_lower = (task_difficulty or "medium").lower()
        type_lower = (task_type or "deep_work").lower()

        if type_lower in ("deep_work", "study", "problem_solving", "coding"):
            if peak_start <= hour <= peak_end:
                task_multiplier = 1.15
            elif dip_start <= hour <= dip_end:
                task_multiplier = 0.65
                factors.append("High-load task during energy dip")
        elif type_lower in ("admin", "planning", "light"):
            if dip_start <= hour <= dip_end:
                task_multiplier = 1.10
                factors.append("Light task appropriately positioned for energy dip")

        if diff_lower in ("high", "intense") and base_readiness < 0.60:
            task_multiplier *= 0.80

        prior_p = min(0.95, max(0.20, base_readiness * task_multiplier))
        return prior_p, factors

    def compute_empirical_stats(
        self,
        observations: List[ReadinessObservation],
        task_type: str,
        target_bucket: str,
    ) -> Tuple[int, int]:
        """Calculates successful observations (k) out of total relevant observations (n)."""
        k = 0
        n = 0
        for obs in observations:
            obs_hour = obs.observed_at.hour + obs.observed_at.minute / 60.0
            obs_bucket = self._get_time_of_day_bucket(obs_hour)

            # Match bucket or task type
            is_bucket_match = (obs_bucket == target_bucket)
            is_type_match = (obs.task_type and obs.task_type.lower() == task_type.lower())

            if is_bucket_match or is_type_match:
                weight = 2 if (is_bucket_match and is_type_match) else 1
                n += weight
                # Success criteria: outcome completed and focus rating >= 3
                is_success = (obs.outcome == "completed" or (obs.focus_rating and obs.focus_rating >= 3))
                if is_success:
                    k += weight

        return k, n

    def evaluate_readiness(
        self,
        profile: Optional[ReadinessProfile],
        observations: List[ReadinessObservation],
        task_type: str = "deep_work",
        task_difficulty: str = "medium",
        target_time: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Executes the progressive intelligence readiness evaluation.
        """
        if target_time is None:
            target_time = datetime.now(timezone.utc)

        obs_count = len(observations)
        stage_code, stage_label = self.determine_stage(obs_count)

        # 1. Stage A: Prior probability
        prior_p, factors = self.compute_prior_fit(profile, task_type, task_difficulty, target_time)

        # 2. Stage B / C Progression
        target_hour = target_time.hour + target_time.minute / 60.0
        target_bucket = self._get_time_of_day_bucket(target_hour)

        if stage_code == "Stage A":
            estimated_p = prior_p
            confidence = min(0.35, 0.20 + (obs_count * 0.015))
        elif stage_code == "Stage B":
            k, n = self.compute_empirical_stats(observations, task_type, target_bucket)
            # Conjugate Beta-Binomial Bayesian Updating with Empirical Bayes Shrinkage:
            # Prior: Beta(alpha_0, beta_0) where alpha_0 = M * prior_p, beta_0 = M * (1 - prior_p), M = SHRINKAGE_ALPHA (5.0)
            # Likelihood: Binomial(n, k) of successful sessions k out of relevant sessions n
            # Posterior: Beta(alpha_0 + k, beta_0 + n - k)
            # Posterior Mean: E[p | k, n] = (k + M * prior_p) / (n + M)
            shrunk_p = (k + SHRINKAGE_ALPHA * prior_p) / (n + SHRINKAGE_ALPHA)
            estimated_p = shrunk_p
            confidence = min(0.72, 0.40 + (obs_count / 100.0))
            factors.append(f"Empirical Bayes smoothing ({n} historical sessions considered)")
        else: # Stage C: Personalized online model
            k, n = self.compute_empirical_stats(observations, task_type, target_bucket)
            shrunk_p = (k + (SHRINKAGE_ALPHA * 0.5) * prior_p) / (n + (SHRINKAGE_ALPHA * 0.5))

            # Additional personalized behavioral weights
            recent_focus_avg = sum((o.focus_rating or 3) for o in observations[:15]) / max(1, len(observations[:15]))
            focus_modifier = (recent_focus_avg - 3.0) * 0.05
            estimated_p = min(0.96, max(0.25, shrunk_p + focus_modifier))
            confidence = min(0.92, 0.75 + min(0.15, (obs_count - 50) * 0.002))
            factors.append(f"Personal predictive model (focus avg: {round(recent_focus_avg, 1)}/5.0)")

        # 3. Determine Recommendation Band
        readiness_score = int(round(estimated_p * 100))
        task_fit_score = int(round(min(100, max(20, readiness_score * 1.02))))

        if confidence < 0.25 and obs_count < 3:
            recommendation_band = "insufficient_confidence"
        elif readiness_score >= 75:
            recommendation_band = "strong_fit"
        elif readiness_score >= 55:
            recommendation_band = "reasonable_fit"
        else:
            recommendation_band = "light_work_preferred"

        # 4. Hourly Circadian Curve — computed from actual profile + observations
        # Rather than a hardcoded generic curve, we derive level values from:
        #   - The user's configured peak / dip windows (always available)
        #   - Empirical success rates per hour bucket (when observations exist)
        hourly_rhythm = self._compute_hourly_rhythm(profile, observations)

        peak_start = profile.preferred_peak_start if profile else "09:30"
        peak_end   = profile.preferred_peak_end   if profile else "11:45"
        focus_window_range = f"{peak_start} – {peak_end}"

        if stage_code == "Stage A":
            explanation = (
                "Your focus window is estimated from your self-reported schedule. "
                "Add more sessions to make this personal."
            )
        elif stage_code == "Stage B":
            explanation = (
                f"Based on {obs_count} recorded sessions, blended with your schedule preferences."
            )
        else:
            explanation = (
                f"Your personalized model is built from {obs_count} focus sessions and behavioral patterns."
            )

        return {
            "readiness_score": readiness_score,
            "task_fit_score": task_fit_score,
            "confidence": round(confidence, 2),
            "recommendation_band": recommendation_band,
            "stage": stage_label,
            "observation_count": obs_count,
            "top_factors": factors,
            "focus_window_range": focus_window_range,
            "explanation": explanation,
            "model_version": self.model_version,
            "hourly_rhythm": hourly_rhythm,
        }

    def _compute_hourly_rhythm(
        self,
        profile,
        observations: List[ReadinessObservation],
    ) -> List[dict]:
        """
        Derives a readiness curve for display (8 sample points, 6a–8p).
        Uses:
        1. User's profile-defined peak and dip hours for shape
        2. Empirical success rates per bucket when observations >= 5
        """
        SAMPLE_HOURS = [6, 8, 10, 12, 14, 16, 18, 20]
        LABELS       = ["6a", "8a", "10a", "12p", "2p", "4p", "6p", "8p"]

        peak_start = self._parse_time_str(profile.preferred_peak_start if profile else "09:30")
        peak_end   = self._parse_time_str(profile.preferred_peak_end   if profile else "11:45")
        dip_start  = self._parse_time_str(profile.preferred_dip_start  if profile else "14:00")
        dip_end    = self._parse_time_str(profile.preferred_dip_end    if profile else "15:30")

        # Build empirical bucket rates if we have enough data
        bucket_rates: dict = {}
        if len(observations) >= 5:
            from collections import defaultdict
            bucket_counts = defaultdict(lambda: {"n": 0, "k": 0})
            for obs in observations:
                h = obs.observed_at.hour + obs.observed_at.minute / 60.0
                b = self._get_time_of_day_bucket(h)
                bucket_counts[b]["n"] += 1
                if obs.outcome == "completed" or (obs.focus_rating and obs.focus_rating >= 3):
                    bucket_counts[b]["k"] += 1
            for bucket, data in bucket_counts.items():
                if data["n"] >= 2:
                    bucket_rates[bucket] = round(data["k"] / data["n"], 2)

        def _profile_level(h: float) -> float:
            """Compute a 0–1 readiness level for hour h from profile shape."""
            if peak_start <= h <= peak_end:
                return 0.88
            elif dip_start <= h <= dip_end:
                return 0.40
            elif 9.0 <= h <= 18.0:
                return 0.65
            elif 5.0 <= h < 9.0:
                return 0.45 + (h - 5.0) * 0.05  # ramp up
            else:
                return 0.38

        curve = []
        for h, label in zip(SAMPLE_HOURS, LABELS):
            base = _profile_level(float(h))

            # Blend in empirical rate if available for this bucket
            bucket = self._get_time_of_day_bucket(float(h))
            if bucket in bucket_rates:
                empirical = bucket_rates[bucket]
                # 40% empirical, 60% profile shape
                level = round(0.60 * base + 0.40 * empirical, 2)
            else:
                level = round(base, 2)

            curve.append({"label": label, "level": level})

        return curve
