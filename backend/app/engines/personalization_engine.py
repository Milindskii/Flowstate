from typing import List, Dict, Any, Optional
from collections import defaultdict
from ..models.readiness_profile import ReadinessProfile
from ..models.readiness_observation import ReadinessObservation, ObservationSource

class PersonalizationEngine:
    """
    Personalization Engine: Transforms raw observations into derived features
    and updates recomputable user profile parameters.
    """

    def derive_features(self, observations: List[ReadinessObservation]) -> Dict[str, Any]:
        """Calculates derived behavioral metrics from raw observation stream."""
        if not observations:
            return {
                "total_observations": 0,
                "window_success_rates": {},
                "task_type_success": {},
                "avg_duration_ratio": 1.0,
                "divergence_detected": False,
            }

        window_counts = defaultdict(lambda: {"total": 0, "success": 0})
        type_counts = defaultdict(lambda: {"total": 0, "success": 0})
        duration_ratios: List[float] = []

        for obs in observations:
            # Time of day window
            hour = obs.observed_at.hour + obs.observed_at.minute / 60.0
            if 5.0 <= hour < 12.0:
                win = "morning"
            elif 12.0 <= hour < 15.0:
                win = "midday"
            elif 15.0 <= hour < 19.0:
                win = "afternoon"
            else:
                win = "evening"

            is_success = (obs.outcome == "completed" or (obs.focus_rating and obs.focus_rating >= 3))

            window_counts[win]["total"] += 1
            if is_success:
                window_counts[win]["success"] += 1

            if obs.task_type:
                t_key = obs.task_type.lower()
                type_counts[t_key]["total"] += 1
                if is_success:
                    type_counts[t_key]["success"] += 1

            if obs.planned_minutes and obs.actual_minutes and obs.planned_minutes > 0:
                duration_ratios.append(obs.actual_minutes / obs.planned_minutes)

        window_rates = {
            win: round(data["success"] / data["total"], 2)
            for win, data in window_counts.items()
            if data["total"] > 0
        }

        type_rates = {
            t: round(data["success"] / data["total"], 2)
            for t, data in type_counts.items()
            if data["total"] > 0
        }

        avg_ratio = round(sum(duration_ratios) / len(duration_ratios), 2) if duration_ratios else 1.0

        return {
            "total_observations": len(observations),
            "window_success_rates": window_rates,
            "task_type_success": type_rates,
            "avg_duration_ratio": avg_ratio,
        }

    def recompute_profile(
        self,
        profile: ReadinessProfile,
        observations: List[ReadinessObservation],
    ) -> ReadinessProfile:
        """
        Recomputes profile statistics and confidence from observations.
        Separates self_report declarations from observed behavioral evidence.
        """
        features = self.derive_features(observations)
        n = features["total_observations"]

        # Confidence grows asymptotically with observation count
        if n == 0:
            profile.confidence_level = 0.20
        elif n < 10:
            profile.confidence_level = round(0.20 + (n * 0.02), 2)
        elif n < 50:
            profile.confidence_level = round(0.40 + (n * 0.007), 2)
        else:
            profile.confidence_level = min(0.95, round(0.75 + (n * 0.002), 2))

        profile.version += 1
        return profile
