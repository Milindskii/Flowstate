"""
Flowstate — Recommendation Engine
==================================
Scores candidate tasks using an explicit decision objective:

  ExpectedUtility(task, context) =
    task_value × readiness_multiplier
    + deadline_urgency
    - context_switch_cost
    - overload_cost

Design principle: completion probability is a multiplier, not the objective.
The engine optimizes for IMPORTANT work getting done, not tasks disappearing from the list.

Stages:
  - GenericRecommendationEngine: fully deterministic scoring (no history needed)
  - PersonalizedRecommendationEngine: adds empirical history weighting (10+ obs)
"""

import random
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timezone

from ..models.task import Task, TaskPriority, TaskType, TaskStatus

# ── Task Value Map ────────────────────────────────────────────────────────────
TASK_VALUE_MAP: Dict[str, float] = {
    "urgent": 1.00,
    "high":   0.80,
    "medium": 0.55,
    "low":    0.30,
}

OVERDUE_BONUS       = 0.30  # task missed its deadline
DEADLINE_TODAY_BONUS = 0.15  # deadline within 24 h

# ── Readiness floor ───────────────────────────────────────────────────────────
# Even at very low readiness, task priority must still matter.
READINESS_FLOOR = 0.50

# ── Penalties ────────────────────────────────────────────────────────────────
CONTEXT_SWITCH_PENALTY  = 0.08   # switching to different task type mid-day
OVERLOAD_PENALTY_PER_H  = 0.05   # per hour of overload (cap: 0.15)
DEADLINE_2H_URGENCY     = 0.25   # must-do-now
DEADLINE_24H_URGENCY    = 0.12   # due today

# ── Exploration parameters ────────────────────────────────────────────────────
EXPLORATION_SCORE_GAP       = 0.08   # candidates within this delta are "close enough"
EXPLORATION_PROBABILITY     = 0.10   # 10% chance when conditions are safe
EXPLORATION_MIN_DEADLINE_HRS = 4.0  # no exploration if deadline is soon

ENGINE_VERSION_GENERIC      = "generic_v1"
ENGINE_VERSION_PERSONALIZED = "personalized_v1"


def _hours_to_deadline(task: Task, now_utc: datetime) -> Optional[float]:
    """Returns hours until deadline (negative = overdue). None if no deadline."""
    if not task.deadline_at:
        return None
    dl = task.deadline_at if task.deadline_at.tzinfo else task.deadline_at.replace(tzinfo=timezone.utc)
    return (dl - now_utc).total_seconds() / 3600.0


def _task_type_str(task: Task) -> str:
    return task.task_type.value if hasattr(task.task_type, "value") else str(task.task_type or "deep_work")


def _priority_str(task: Task) -> str:
    return task.priority.value if hasattr(task.priority, "value") else str(task.priority or "medium")


# ── Score dataclass ───────────────────────────────────────────────────────────

class TaskScore:
    """Result of scoring one task against current context."""

    __slots__ = ("task", "score", "reasons", "breakdown")

    def __init__(
        self,
        task: Task,
        score: float,
        reasons: List[str],
        breakdown: Dict[str, float],
    ):
        self.task = task
        self.score = score
        self.reasons = reasons
        self.breakdown = breakdown

    def to_dict(self) -> Dict[str, Any]:
        return {
            "task_id": str(self.task.id),
            "score": round(self.score, 4),
            "reasons": self.reasons[:3],
            "breakdown": {k: round(v, 4) for k, v in self.breakdown.items()},
        }


# ── Generic Engine ─────────────────────────────────────────────────────────────

class GenericRecommendationEngine:
    """
    Deterministic scoring engine. No personal history required.

    Suitable for new users (Stage A), cold-start situations,
    and as the evaluation baseline in A/B experiments.
    """

    ENGINE_VERSION = ENGINE_VERSION_GENERIC

    # ── Score single task ──

    def score_task(
        self,
        task: Task,
        now_utc: datetime,
        readiness_score: float = 0.65,          # 0.0 – 1.0 from ReadinessEngineV2
        active_task_type: Optional[str] = None, # currently-running task type (for context-switch cost)
        pending_minutes: int = 0,               # total pending work in minutes
        available_minutes: int = 390,           # realistic focus window (6.5 h default)
    ) -> TaskScore:
        reasons: List[str] = []
        breakdown: Dict[str, float] = {}

        t_type = _task_type_str(task)
        priority = _priority_str(task)

        # ── 1. Task value (importance × priority) ─────────────────────────
        base_value = TASK_VALUE_MAP.get(priority.lower(), 0.55)
        hours_left = _hours_to_deadline(task, now_utc)
        is_overdue = hours_left is not None and hours_left < 0

        if is_overdue:
            base_value = min(1.0, base_value + OVERDUE_BONUS)
            reasons.append("Overdue — needs attention now")
        elif hours_left is not None and hours_left < 24:
            base_value = min(1.0, base_value + DEADLINE_TODAY_BONUS)
            reasons.append("Due today")

        if not is_overdue and priority.lower() in ("urgent", "high"):
            reasons.append(f"{priority.capitalize()} priority")

        breakdown["task_value"] = round(base_value, 4)

        # ── 2. Readiness multiplier ───────────────────────────────────────
        # Deep-work tasks are penalized more at low readiness (they need energy).
        # Admin / light tasks are less sensitive.
        if t_type in ("deep_work", "study", "creative", "coding"):
            readiness_mult = max(READINESS_FLOOR, readiness_score)
            if readiness_score >= 0.70:
                reasons.append("Good time for focused work")
            elif readiness_score < 0.45:
                reasons.append("Energy is low — consider lighter work first")
        elif t_type in ("admin", "personal", "shallow_work", "meeting"):
            # Light tasks: floor is effectively 0.60 (always somewhat schedulable)
            readiness_mult = max(READINESS_FLOOR, 0.55 + readiness_score * 0.35)
        else:
            readiness_mult = max(READINESS_FLOOR, readiness_score)

        breakdown["readiness_multiplier"] = round(readiness_mult, 4)

        # Core score
        core_score = base_value * readiness_mult

        # ── 3. Deadline urgency (increases score the closer the deadline) ─
        deadline_urgency = 0.0
        if hours_left is not None:
            if hours_left < 0:
                deadline_urgency = DEADLINE_2H_URGENCY * 1.5   # overdue: biggest boost
            elif hours_left < 2:
                deadline_urgency = DEADLINE_2H_URGENCY
                reasons.append("Deadline in < 2 hours")
            elif hours_left < 24:
                deadline_urgency = DEADLINE_24H_URGENCY
        breakdown["deadline_urgency"] = round(deadline_urgency, 4)

        # ── 4. Context-switch cost ────────────────────────────────────────
        context_switch = 0.0
        if active_task_type and active_task_type.lower() != t_type.lower():
            context_switch = CONTEXT_SWITCH_PENALTY
        breakdown["context_switch"] = round(context_switch, 4)

        # ── 5. Overload cost ──────────────────────────────────────────────
        overload_cost = 0.0
        if pending_minutes > available_minutes:
            overloaded_hours = (pending_minutes - available_minutes) / 60.0
            overload_cost = min(0.15, overloaded_hours * OVERLOAD_PENALTY_PER_H)
        breakdown["overload_cost"] = round(overload_cost, 4)

        # ── Final score ───────────────────────────────────────────────────
        final = core_score + deadline_urgency - context_switch - overload_cost
        final = round(max(0.0, min(1.0, final)), 4)
        breakdown["final_score"] = final

        return TaskScore(task=task, score=final, reasons=reasons, breakdown=breakdown)

    # ── Rank all candidates ─────────────────────────────────────────────────

    def rank(
        self,
        pending_tasks: List[Task],
        now_utc: datetime,
        readiness_score: float = 0.65,
        active_task_type: Optional[str] = None,
        pending_minutes: int = 0,
        available_minutes: int = 390,
        allow_exploration: bool = True,
    ) -> Tuple[List[TaskScore], str]:
        """
        Returns (sorted_scored_list, strategy).
        strategy is 'exploitation' | 'exploration'.

        Exploration is user-invisible and only fires when all safety
        conditions are met (no urgent deadlines, candidates genuinely close).
        """
        if not pending_tasks:
            return [], "exploitation"

        scored = [
            self.score_task(
                task=t,
                now_utc=now_utc,
                readiness_score=readiness_score,
                active_task_type=active_task_type,
                pending_minutes=pending_minutes,
                available_minutes=available_minutes,
            )
            for t in pending_tasks
        ]

        # Sort descending
        scored.sort(key=lambda s: s.score, reverse=True)

        strategy = "exploitation"

        # Safe exploration: swap top-2 only when conditions are all safe
        if allow_exploration and len(scored) >= 2:
            top = scored[0]
            runner_up = scored[1]
            gap = top.score - runner_up.score

            top_hours = _hours_to_deadline(top.task, now_utc)
            runner_hours = _hours_to_deadline(runner_up.task, now_utc)

            no_urgent_top = top_hours is None or top_hours >= EXPLORATION_MIN_DEADLINE_HRS
            no_overdue = (top_hours is None or top_hours >= 0) and (runner_hours is None or runner_hours >= 0)

            if (
                gap <= EXPLORATION_SCORE_GAP
                and no_urgent_top
                and no_overdue
                and random.random() < EXPLORATION_PROBABILITY
            ):
                scored[0], scored[1] = scored[1], scored[0]
                strategy = "exploration"

        return scored, strategy

    # ── Human-readable explanation ─────────────────────────────────────────

    def build_explanation(
        self,
        task_score: TaskScore,
        obs_count: int,
        lifecycle_stage: str,
    ) -> str:
        """
        Returns a short human-readable sentence for the recommendation.
        Never fabricates. Uses only what is actually true.
        """
        reasons = task_score.reasons
        if not reasons:
            return "Best match for your available time right now."

        if obs_count >= 10:
            return " · ".join(reasons[:3])
        else:
            # Cold start: only state what is explicitly known
            return " · ".join(reasons[:2])

    # ── Suggest next good window after "Later" ─────────────────────────────

    def suggest_next_window(
        self,
        task: Task,
        now_utc: datetime,
        readiness_profile: Any = None,
        user_tz: Any = None,
    ) -> Dict[str, Any]:
        """
        Returns the next schedulable window for a postponed task.
        Used to power "I'll move it — next good window: Tomorrow · 9:30 AM"
        """
        from datetime import timedelta, time, date
        from zoneinfo import ZoneInfo

        tz = user_tz or timezone.utc
        now_local = datetime.now(tz)

        # Determine peak start from profile or default
        peak_start_str = "09:30"
        if readiness_profile:
            peak_start_str = getattr(readiness_profile, "preferred_peak_start", "09:30")

        try:
            parts = peak_start_str.split(":")
            peak_h, peak_m = int(parts[0]), int(parts[1])
        except Exception:
            peak_h, peak_m = 9, 30

        t_type = _task_type_str(task)
        is_deep = t_type in ("deep_work", "study", "creative", "coding")

        # Try today first (only if at least 2 h remain before the target window)
        today_peak = datetime.combine(now_local.date(), time(peak_h, peak_m), tzinfo=tz)
        if today_peak > now_local + timedelta(hours=2) and is_deep:
            return {
                "label": f"Today · {today_peak.strftime('%I:%M %p').lstrip('0')}",
                "suggested_date": today_peak.strftime("%Y-%m-%d"),
                "suggested_time": peak_start_str,
            }

        # Otherwise suggest tomorrow's peak window
        tomorrow = now_local.date() + timedelta(days=1)
        tomorrow_peak = datetime.combine(tomorrow, time(peak_h, peak_m), tzinfo=tz)
        return {
            "label": f"Tomorrow · {tomorrow_peak.strftime('%I:%M %p').lstrip('0')}",
            "suggested_date": tomorrow.strftime("%Y-%m-%d"),
            "suggested_time": peak_start_str,
        }


# ── Personalized Engine ────────────────────────────────────────────────────────

class PersonalizedRecommendationEngine(GenericRecommendationEngine):
    """
    Extends GenericRecommendationEngine with empirical behavioral weights.

    Activated when obs_count >= 10 (Stage B / C of ReadinessEngineV2).
    Uses actual historical success rates per time-of-day window and task type
    to adjust the readiness multiplier rather than relying solely on the
    profile-based prior.
    """

    ENGINE_VERSION = ENGINE_VERSION_PERSONALIZED

    SHRINKAGE_ALPHA = 3.0   # Empirical Bayes weight on the generic prior

    def __init__(self, observations: List[Any]):
        self._obs = observations

    def _empirical_success_rate(
        self,
        task_type: str,
        target_hour: float,
    ) -> Optional[float]:
        """
        Computes historical P(success | task_type, time_window) with
        Empirical Bayes shrinkage toward the generic prior (0.65).
        """
        if not self._obs:
            return None

        target_bucket = self._hour_to_bucket(target_hour)

        k = 0
        n = 0
        for obs in self._obs:
            obs_hour = obs.observed_at.hour + obs.observed_at.minute / 60.0
            obs_bucket = self._hour_to_bucket(obs_hour)
            type_match = obs.task_type and obs.task_type.lower() == task_type.lower()
            bucket_match = obs_bucket == target_bucket

            if type_match or bucket_match:
                weight = 2 if (type_match and bucket_match) else 1
                n += weight
                is_success = (
                    obs.outcome == "completed"
                    or (obs.focus_rating and obs.focus_rating >= 3)
                )
                if is_success:
                    k += weight

        if n == 0:
            return None

        # Empirical Bayes shrinkage toward 0.65 prior
        prior = 0.65
        shrunk = (k + self.SHRINKAGE_ALPHA * prior) / (n + self.SHRINKAGE_ALPHA)
        return round(shrunk, 4)

    @staticmethod
    def _hour_to_bucket(hour: float) -> str:
        if 5.0 <= hour < 12.0:
            return "morning"
        elif 12.0 <= hour < 15.0:
            return "midday"
        elif 15.0 <= hour < 19.0:
            return "afternoon"
        return "evening"

    def score_task(
        self,
        task: Task,
        now_utc: datetime,
        readiness_score: float = 0.65,
        active_task_type: Optional[str] = None,
        pending_minutes: int = 0,
        available_minutes: int = 390,
    ) -> TaskScore:
        """Override to blend empirical success rate into readiness_score."""
        t_type = _task_type_str(task)
        hour_utc = now_utc.hour + now_utc.minute / 60.0
        empirical = self._empirical_success_rate(t_type, hour_utc)

        if empirical is not None:
            # Blend generic readiness with empirical history
            blended = 0.5 * readiness_score + 0.5 * empirical
        else:
            blended = readiness_score

        return super().score_task(
            task=task,
            now_utc=now_utc,
            readiness_score=blended,
            active_task_type=active_task_type,
            pending_minutes=pending_minutes,
            available_minutes=available_minutes,
        )
