"""
Flowstate Personalization Engine V1
====================================
Deterministic behavioral personalization layer.

Philosophy
----------
    SELF-REPORTED PROFILE      →   PRIOR
    OBSERVED USER BEHAVIOR     →   EVIDENCE
    RECENCY + RELEVANCE        →   BEHAVIORAL SIGNAL
    CONSERVATIVE ADAPTATION    →   PROFILE UPDATE

Design principles
-----------------
- Sparse evidence must NEVER be treated as strong evidence.
- Recent evidence weighs more than ancient evidence (smooth decay).
- Task-type × time-bucket interaction is first-class.
- Sparse combinations shrink toward broader evidence (hierarchical Bayes).
- Self-reported profile is preserved unless evidence is genuinely strong.
- No hard rules. Personalization is weighted guidance, not law.
- Deterministic, bounded, fast. No external dependencies, no ML, no LLM.

Consistency with readiness_engine.py
------------------------------------
- Same session-success philosophy (completion strong, focus supporting).
- Same four time buckets (morning / midday / afternoon / evening).
- Same recency half-life (120 days).
- Same Beta-Binomial shrinkage concept.

Return-contract compatibility
-----------------------------
Legacy keys preserved exactly:
    total_observations, window_success_rates, task_type_success,
    avg_duration_ratio, divergence_detected
Additional additive keys are documented at the top of `derive_features`.
"""

from typing import List, Dict, Any, Optional, Tuple
from collections import defaultdict
from datetime import datetime, timezone
import math

from ..models.readiness_profile import ReadinessProfile
from ..models.readiness_observation import ReadinessObservation, ObservationSource


# ── Constants (aligned with readiness_engine.py) ─────────────────────────────
RECENCY_HALF_LIFE_DAYS = 120.0   # Smooth decay; weight halves every 120 days
SHRINKAGE_STRENGTH = 3.0         # Beta-Binomial pseudo-prior strength per level

# Session-success score decomposition — MUST match readiness_engine.py exactly
SUCCESS_COMPLETED_BASE = 0.85
SUCCESS_FOCUS_BONUS_PER_PT = 0.03     # +0.03 per focus point above 3
SUCCESS_COMPLETED_LOW_FOCUS = 0.05    # penalty per focus point below 3
SUCCESS_INCOMPLETE_BASE = 0.30        # non-completed, no/low focus
SUCCESS_INCOMPLETE_FOCUS_ADD = 0.10   # non-completed but focus >= 3

# Duration sanity bounds — reject extreme outliers, not merely large values
DURATION_RATIO_MIN = 0.25
DURATION_RATIO_MAX = 4.0
DURATION_MIN_OBS_PER_TYPE = 2         # task-type duration needs >= 2 samples

# Divergence detection thresholds — deliberate, conservative
DIVERGENCE_MIN_OBS = 8                # need at least this many observations
DIVERGENCE_MIN_PER_WINDOW = 3         # at least one window with >= this many
DIVERGENCE_STRENGTH_THRESHOLD = 0.15  # top window rate − mean others

# Completion-outcome normalization — matched against lowercased, prefix-stripped
COMPLETED_OUTCOMES = frozenset({"completed", "done", "finished"})


class PersonalizationEngine:
    """
    Personalization Engine: transforms raw observations into derived behavioral
    features and optionally updates recomputable profile parameters.
    """

    # ═════════════════════════════════════════════════════════════════════════
    # Helpers
    # ═════════════════════════════════════════════════════════════════════════

    @staticmethod
    def _normalize_outcome(value: Any) -> str:
        """
        Return a lowercase, prefix-stripped outcome string.
        Handles None, plain strings, and enum-style values like
        'ObservationSource.COMPLETED' or 'Outcome.COMPLETED'.
        """
        if value is None:
            return ""
        text = str(value).lower().strip()
        if "." in text:
            text = text.rsplit(".", 1)[-1]
        return text

    @staticmethod
    def _time_bucket(hour: float) -> str:
        """Preserve the four-bucket semantics used elsewhere in Flowstate."""
        if 5.0 <= hour < 12.0:
            return "morning"
        elif 12.0 <= hour < 15.0:
            return "midday"
        elif 15.0 <= hour < 19.0:
            return "afternoon"
        return "evening"

    @staticmethod
    def _hour_bin(hour: float) -> str:
        """Zero-padded 24-hour bin, e.g. '09', '14', '21'."""
        return f"{int(hour) % 24:02d}"

    @staticmethod
    def _safe_observation_hour(obs: ReadinessObservation) -> Optional[float]:
        """Return hour-of-day as fractional hours, or None if unavailable."""
        try:
            ts = getattr(obs, "observed_at", None)
            if ts is None or not hasattr(ts, "hour"):
                return None
            minute = getattr(ts, "minute", 0) or 0
            return ts.hour + minute / 60.0
        except Exception:
            return None

    @staticmethod
    def _safe_age_days(obs: ReadinessObservation, now: datetime) -> float:
        """
        Age of an observation in days, defensively handling tz-aware vs naive.
        Missing or malformed timestamps fall back to a neutral-old default so
        the observation still contributes a small amount rather than crashing.
        """
        try:
            ts = getattr(obs, "observed_at", None)
            if ts is None or not hasattr(ts, "year"):
                return RECENCY_HALF_LIFE_DAYS * 4.0

            if ts.tzinfo is not None and now.tzinfo is None:
                ts_cmp = ts.replace(tzinfo=None)
                now_cmp = now
            elif ts.tzinfo is None and now.tzinfo is not None:
                ts_cmp = ts
                now_cmp = now.replace(tzinfo=None)
            else:
                ts_cmp, now_cmp = ts, now

            age = (now_cmp - ts_cmp).total_seconds() / 86400.0
            if age < 0:
                return 0.0
            # Cap the age so an ancient observation cannot become *anti*-evidence.
            return min(age, RECENCY_HALF_LIFE_DAYS * 8.0)
        except Exception:
            return RECENCY_HALF_LIFE_DAYS * 4.0

    @staticmethod
    def _recency_weight(age_days: float) -> float:
        """Smooth exponential decay, half-life RECENCY_HALF_LIFE_DAYS."""
        return 0.5 ** (age_days / RECENCY_HALF_LIFE_DAYS)

    @staticmethod
    def _session_success_score(obs: ReadinessObservation) -> float:
        """
        Continuous [0, 1] success score. Identical to the readiness engine's
        semantics so that both engines describe the same behavioral reality.

        Completion is the strong signal; focus rating is a supporting quality
        signal. Non-completed sessions never receive full credit, and
        completed sessions with low focus are mildly discounted.
        """
        outcome = PersonalizationEngine._normalize_outcome(
            getattr(obs, "outcome", None)
        )
        focus_raw = getattr(obs, "focus_rating", None)
        try:
            focus = int(focus_raw) if focus_raw is not None else None
        except (TypeError, ValueError):
            focus = None

        completed = outcome in COMPLETED_OUTCOMES
        if completed:
            base = SUCCESS_COMPLETED_BASE
            if focus is not None and focus >= 3:
                base = min(1.0, base + SUCCESS_FOCUS_BONUS_PER_PT * (focus - 3))
            elif focus is not None and focus < 3:
                base = max(0.55, base - SUCCESS_COMPLETED_LOW_FOCUS * (3 - focus))
            return base

        if focus is not None and focus >= 3:
            return SUCCESS_INCOMPLETE_BASE + SUCCESS_INCOMPLETE_FOCUS_ADD
        return SUCCESS_INCOMPLETE_BASE * 0.5

    @staticmethod
    def _safe_duration_pair(obs: ReadinessObservation) -> Optional[Tuple[float, float]]:
        """
        Return (planned_minutes, actual_minutes) if both are valid positive
        numbers and their ratio is within the sanity bounds. Extreme outliers
        are rejected so a single 60→300 session cannot destroy the estimate.
        """
        try:
            planned = getattr(obs, "planned_minutes", None)
            actual = getattr(obs, "actual_minutes", None)
            if planned is None or actual is None:
                return None
            planned = float(planned)
            actual = float(actual)
            if planned <= 0 or actual <= 0:
                return None
            ratio = actual / planned
            if ratio < DURATION_RATIO_MIN or ratio > DURATION_RATIO_MAX:
                return None
            return planned, actual
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _shrunk_rate(
        k: float,
        n: float,
        prior: float,
        strength: float = SHRINKAGE_STRENGTH,
    ) -> float:
        """Beta-Binomial posterior mean with pseudo-prior `prior` weighted by `strength`."""
        if n <= 0:
            return prior
        return (k + strength * prior) / (n + strength)

    @staticmethod
    def _detect_divergence(
        window_rates: Dict[str, float],
        window_evidence: Dict[str, int],
        total_observations: int,
    ) -> Tuple[Optional[str], bool, float]:
        """
        Detect whether the observed behavior has a clear time-of-day peak.

        Returns:
            (learned_peak_window, divergence_detected, divergence_strength)

        This is a signal about the user's OBSERVED rhythm, not yet a comparison
        against the self-reported profile (which requires a profile argument and
        is performed in `recompute_profile`). Conservative by design: it fires
        only when there is enough evidence AND the top window clearly dominates
        the mean of the other windows.
        """
        if total_observations < DIVERGENCE_MIN_OBS:
            return None, False, 0.0

        candidates = {
            win: rate
            for win, rate in window_rates.items()
            if window_evidence.get(win, 0) >= DIVERGENCE_MIN_PER_WINDOW
        }
        if not candidates:
            return None, False, 0.0

        top_window = max(candidates, key=lambda w: candidates[w])
        top_rate = candidates[top_window]

        other_rates = [r for w, r in candidates.items() if w != top_window]
        if other_rates:
            mean_other = sum(other_rates) / len(other_rates)
        else:
            # Only one qualifying window; can't meaningfully compare.
            mean_other = 0.5

        strength = round(max(0.0, top_rate - mean_other), 2)
        detected = strength >= DIVERGENCE_STRENGTH_THRESHOLD
        return top_window, detected, strength

    # ═════════════════════════════════════════════════════════════════════════
    # Empty-evidence baseline
    # ═════════════════════════════════════════════════════════════════════════

    @staticmethod
    def _empty_features() -> Dict[str, Any]:
        """
        Sensible defaults when no observations exist. All legacy keys plus all
        additive keys are present so callers never need a branch on shape.
        """
        return {
            "total_observations": 0,
            "window_success_rates": {},
            "task_type_success": {},
            "avg_duration_ratio": 1.0,
            "divergence_detected": False,

            # Additive
            "window_evidence": {},
            "task_type_evidence": {},
            "task_time_success": {},
            "task_time_evidence": {},
            "hourly_success": {},
            "hourly_evidence": {},
            "overall_success_rate": 0.0,
            "overall_evidence": 0,
            "duration_evidence_count": 0,
            "task_type_duration_ratio": {},
            "learned_peak_window": None,
            "divergence_strength": 0.0,
        }

    # ═════════════════════════════════════════════════════════════════════════
    # Public API
    # ═════════════════════════════════════════════════════════════════════════

    def derive_features(
        self,
        observations: List[ReadinessObservation],
    ) -> Dict[str, Any]:
        """
        Derive behavioral features from a raw observation stream.

        Single pass, deterministic, no external calls. Never crashes on
        malformed observations — bad fields are skipped locally.

        Legacy keys (preserved exactly):
            total_observations, window_success_rates, task_type_success,
            avg_duration_ratio, divergence_detected

        Additive keys (may be absent on old callers — safe to add):
            window_evidence, task_type_evidence,
            task_time_success, task_time_evidence,
            hourly_success, hourly_evidence,
            overall_success_rate, overall_evidence,
            duration_evidence_count, task_type_duration_ratio,
            learned_peak_window, divergence_strength
        """
        # Only real post-task reflections are evidence: legacy rows carried made-up ratings and the onboarding
        # baseline is a self-description, not a session.
        observations = [o for o in (observations or []) if getattr(o, "provenance", None) in (None, "reflection")]
        if not observations:
            return self._empty_features()

        now = datetime.now(timezone.utc)

        # Accumulators: every level tracks (weighted success, weighted total, raw count)
        overall = {"k": 0.0, "n": 0.0, "count": 0}
        window_stats = defaultdict(lambda: {"k": 0.0, "n": 0.0, "count": 0})
        hour_stats = defaultdict(lambda: {"k": 0.0, "n": 0.0, "count": 0})
        type_stats = defaultdict(lambda: {"k": 0.0, "n": 0.0, "count": 0})
        task_time_stats = defaultdict(lambda: {"k": 0.0, "n": 0.0, "count": 0})

        # Duration accumulators (recency-weighted, outlier-rejected)
        duration_overall = {"ratio": 0.0, "weight": 0.0, "count": 0}
        duration_by_type = defaultdict(lambda: {"ratio": 0.0, "weight": 0.0, "count": 0})

        for obs in observations:
            hour = self._safe_observation_hour(obs)
            age_days = self._safe_age_days(obs, now)
            w_rec = self._recency_weight(age_days)
            success = self._session_success_score(obs)

            # ── Global baseline ─────────────────────────────────────────
            overall["k"] += success * w_rec
            overall["n"] += w_rec
            overall["count"] += 1

            # ── Time bucket + hourly bin ────────────────────────────────
            bucket: Optional[str] = None
            if hour is not None:
                bucket = self._time_bucket(hour)
                window_stats[bucket]["k"] += success * w_rec
                window_stats[bucket]["n"] += w_rec
                window_stats[bucket]["count"] += 1

                hb = self._hour_bin(hour)
                hour_stats[hb]["k"] += success * w_rec
                hour_stats[hb]["n"] += w_rec
                hour_stats[hb]["count"] += 1

            # ── Task type + task × time ─────────────────────────────────
            task_type_raw = getattr(obs, "task_type", None)
            task_key: Optional[str] = None
            if task_type_raw:
                task_key = str(task_type_raw).lower().strip() or None

            if task_key:
                type_stats[task_key]["k"] += success * w_rec
                type_stats[task_key]["n"] += w_rec
                type_stats[task_key]["count"] += 1

                if bucket is not None:
                    combo_key = f"{task_key}|{bucket}"
                    task_time_stats[combo_key]["k"] += success * w_rec
                    task_time_stats[combo_key]["n"] += w_rec
                    task_time_stats[combo_key]["count"] += 1

            # ── Duration ────────────────────────────────────────────────
            pair = self._safe_duration_pair(obs)
            if pair is not None:
                planned, actual = pair
                ratio = actual / planned
                duration_overall["ratio"] += ratio * w_rec
                duration_overall["weight"] += w_rec
                duration_overall["count"] += 1

                if task_key:
                    duration_by_type[task_key]["ratio"] += ratio * w_rec
                    duration_by_type[task_key]["weight"] += w_rec
                    duration_by_type[task_key]["count"] += 1

        # ── Rates (rounded, recency-weighted) ────────────────────────────
        def _rate(stats: Dict[str, Any]) -> float:
            return round(stats["k"] / stats["n"], 2) if stats["n"] > 0 else 0.0

        overall_success_rate = _rate(overall)
        window_rates = {k: _rate(v) for k, v in window_stats.items() if v["n"] > 0}
        type_rates = {k: _rate(v) for k, v in type_stats.items() if v["n"] > 0}
        hourly_rates = {k: _rate(v) for k, v in hour_stats.items() if v["n"] > 0}
        task_time_rates = {k: _rate(v) for k, v in task_time_stats.items() if v["n"] > 0}

        # ── Evidence counts (raw, not weighted) ──────────────────────────
        window_evidence = {k: v["count"] for k, v in window_stats.items()}
        hour_evidence = {k: v["count"] for k, v in hour_stats.items()}
        type_evidence = {k: v["count"] for k, v in type_stats.items()}
        task_time_evidence = {k: v["count"] for k, v in task_time_stats.items()}

        # ── Duration aggregates ──────────────────────────────────────────
        if duration_overall["weight"] > 0:
            avg_ratio = round(
                duration_overall["ratio"] / duration_overall["weight"], 2
            )
        else:
            avg_ratio = 1.0

        task_type_duration_ratio = {
            k: round(v["ratio"] / v["weight"], 2)
            for k, v in duration_by_type.items()
            if v["weight"] > 0 and v["count"] >= DURATION_MIN_OBS_PER_TYPE
        }

        # ── Divergence / learned peak ────────────────────────────────────
        learned_peak_window, divergence_detected, divergence_strength = \
            self._detect_divergence(
                window_rates=window_rates,
                window_evidence=window_evidence,
                total_observations=overall["count"],
            )

        return {
            # Legacy keys — preserved exactly
            "total_observations": overall["count"],
            "window_success_rates": window_rates,
            "task_type_success": type_rates,
            "avg_duration_ratio": avg_ratio,
            "divergence_detected": divergence_detected,

            # Additive keys — safe for existing callers (extra dict entries)
            "window_evidence": window_evidence,
            "task_type_evidence": type_evidence,
            "task_time_success": task_time_rates,
            "task_time_evidence": task_time_evidence,
            "hourly_success": hourly_rates,
            "hourly_evidence": hour_evidence,
            "overall_success_rate": overall_success_rate,
            "overall_evidence": overall["count"],
            "duration_evidence_count": duration_overall["count"],
            "task_type_duration_ratio": task_type_duration_ratio,
            "learned_peak_window": learned_peak_window,
            "divergence_strength": divergence_strength,
        }

    def recompute_profile(
        self,
        profile: ReadinessProfile,
        observations: List[ReadinessObservation],
    ) -> ReadinessProfile:
        """
        Recompute profile-level meta-parameters from observations.

        Conservative by design:
          - Only `confidence_level` and `version` are ever modified on the
            profile. All other fields (peak window, dip window, wake times,
            bedtime, etc.) are treated as self-report and are NOT overwritten
            from behavioral evidence.
          - Learned behavioral signals (task fit, time fit, task × time fit,
            duration multipliers, learned peak window) are returned from
            `derive_features()` for downstream consumers (ReadinessEngine,
            SchedulingEngine), rather than being forced onto the profile.
          - `version` is incremented on each call to preserve backward
            compatibility with existing callers that use it as a recompute
            counter.
        """
        features = self.derive_features(observations)
        n = features["total_observations"]

        # ── Confidence model ─────────────────────────────────────────────
        # Gradual and bounded. Uses overall evidence count as a proxy for how
        # much behavioral evidence is available; consumers that need
        # evidence-specific confidence for a task × time query should read
        # `window_evidence` / `task_type_evidence` / `task_time_evidence` from
        # the features dict and apply their own relevance weighting.
        if n == 0:
            profile.confidence_level = 0.20
        elif n < 10:
            profile.confidence_level = round(0.20 + n * 0.02, 2)
        elif n < 50:
            profile.confidence_level = round(0.40 + n * 0.007, 2)
        else:
            profile.confidence_level = min(0.95, round(0.75 + n * 0.002, 2))

        # ── Version bookkeeping ──────────────────────────────────────────
        # Preserved for backward compatibility. If the profile contract ever
        # distinguishes "recompute calls" from "meaningful updates", this can
        # become conditional on actual parameter changes.
        profile.version += 1

        return profile