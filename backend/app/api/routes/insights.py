"""
Flowstate — Evidence-Driven Insights API
==========================================
Returns real behavioral data, not fabricated stats.

Philosophy:
  Every insight must answer "So what?"
  Until there is sufficient data, be honest: "still learning."
  Never show a chart or number that didn't come from real sessions.
"""

from typing import Optional, Dict, List, Any
from collections import defaultdict
from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...models.readiness_observation import ReadinessObservation
from ...repositories.readiness_repository import ReadinessRepository
from ...repositories.recommendation_repository import RecommendationRepository

router = APIRouter(prefix="/insights", tags=["Insights"])
readiness_repo = ReadinessRepository()
rec_repo = RecommendationRepository()

MIN_SESSIONS_FOR_PATTERNS = 3
MIN_SESSIONS_FOR_TIME_PATTERNS = 5


class TimeWindowStats(BaseModel):
    sessions: int = 0
    completion_rate: float = 0.0
    avg_focus: float = 0.0


class InsightsSummaryResponse(BaseModel):
    # ── Core counts ──────────────────────────────────────────────────────
    total_sessions: int = 0
    total_focus_minutes: int = 0

    # ── Session quality ───────────────────────────────────────────────────
    completion_rate: float = 0.0
    avg_focus_rating: float = 0.0
    duration_accuracy: float = 1.0   # actual / planned ratio (1.0 = perfect)

    # ── Recommendation behaviour ──────────────────────────────────────────
    acceptance_rate: float = 0.0
    override_rate: float = 0.0
    total_recommendations: int = 0

    # ── Patterns (only populated with enough history) ─────────────────────
    time_of_day_performance: Dict[str, TimeWindowStats] = {}
    best_window: Optional[str] = None            # "morning" | "afternoon" | etc.
    underestimation_pct: Optional[float] = None  # e.g. 25.0 means 25% longer than estimated

    # ── Readiness model state ─────────────────────────────────────────────
    personalization_stage: str = "Stage A"
    confidence: float = 0.0
    hourly_rhythm: List[Dict[str, Any]] = []

    # ── Narrative ─────────────────────────────────────────────────────────
    has_sufficient_history: bool = False
    status_message: str = "Complete a few sessions to see your patterns."
    pattern_headline: Optional[str] = None   # "You focus best between 9–11 AM"
    pattern_detail: Optional[str] = None     # "Your deep-work sessions tend to overrun by ~25%"
    actionable_note: Optional[str] = None    # "Flowstate will use this when planning tomorrow."


@router.get("/summary", response_model=InsightsSummaryResponse)
def get_insights_summary(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns evidence-driven insights for the Insights tab.

    All numbers are derived from actual user sessions.
    Returns honest low-data state when insufficient history exists.
    Never fabricates metrics.
    """
    observations: List[ReadinessObservation] = readiness_repo.list_observations(
        db, current_user.id, limit=500
    )
    obs_count = len(observations)
    has_sufficient = obs_count >= MIN_SESSIONS_FOR_PATTERNS

    # ── Cold start ─────────────────────────────────────────────────────────
    if not has_sufficient:
        sessions_needed = MIN_SESSIONS_FOR_PATTERNS - obs_count
        return InsightsSummaryResponse(
            total_sessions=obs_count,
            has_sufficient_history=False,
            status_message=f"Complete {sessions_needed} more session{'s' if sessions_needed != 1 else ''} to see your patterns.",
        )

    # ── Core statistics ────────────────────────────────────────────────────
    completed = [o for o in observations if o.outcome == "completed" or (o.focus_rating and o.focus_rating >= 3)]
    completion_rate = round(len(completed) / obs_count, 2) if obs_count > 0 else 0.0

    focus_ratings = [o.focus_rating for o in observations if o.focus_rating is not None]
    avg_focus = round(sum(focus_ratings) / len(focus_ratings), 1) if focus_ratings else 0.0

    total_actual_minutes = sum(o.actual_minutes or 0 for o in observations)

    # Duration accuracy (actual / planned)
    duration_ratios = []
    for o in observations:
        if o.planned_minutes and o.actual_minutes and o.planned_minutes > 0:
            duration_ratios.append(o.actual_minutes / o.planned_minutes)
    avg_ratio = round(sum(duration_ratios) / len(duration_ratios), 2) if duration_ratios else 1.0

    # ── Recommendation acceptance rate ────────────────────────────────────
    total_decisions = rec_repo.count_total_decisions(db, current_user.id)
    total_accepted = rec_repo.count_accepted(db, current_user.id)
    total_overridden = rec_repo.count_overridden(db, current_user.id)

    acceptance_rate = round(total_accepted / total_decisions, 2) if total_decisions > 0 else 0.0
    override_rate = round(total_overridden / total_decisions, 2) if total_decisions > 0 else 0.0

    # ── Time-of-day performance ────────────────────────────────────────────
    window_stats: Dict[str, Dict] = {}
    if obs_count >= MIN_SESSIONS_FOR_TIME_PATTERNS:
        buckets = defaultdict(lambda: {"sessions": 0, "completed": 0, "focus_sum": 0, "focus_n": 0})
        for o in observations:
            h = o.observed_at.hour
            if 5 <= h < 12:
                b = "morning"
            elif 12 <= h < 15:
                b = "midday"
            elif 15 <= h < 19:
                b = "afternoon"
            else:
                b = "evening"
            buckets[b]["sessions"] += 1
            if o.outcome == "completed" or (o.focus_rating and o.focus_rating >= 3):
                buckets[b]["completed"] += 1
            if o.focus_rating:
                buckets[b]["focus_sum"] += o.focus_rating
                buckets[b]["focus_n"] += 1

        for b, data in buckets.items():
            n = data["sessions"]
            window_stats[b] = TimeWindowStats(
                sessions=n,
                completion_rate=round(data["completed"] / n, 2) if n > 0 else 0.0,
                avg_focus=round(data["focus_sum"] / data["focus_n"], 1) if data["focus_n"] > 0 else 0.0,
            )

    # ── Best window ────────────────────────────────────────────────────────
    best_window = None
    if window_stats:
        best_window = max(
            window_stats,
            key=lambda b: window_stats[b].completion_rate,
        )

    # ── Readiness model state ─────────────────────────────────────────────
    from ...engines.readiness_engine import ReadinessEngineV2
    readiness_profile = readiness_repo.get_profile(db, current_user.id)
    now_utc = datetime.now(timezone.utc)

    rengine = ReadinessEngineV2()
    r_result = rengine.evaluate_readiness(
        profile=readiness_profile,
        observations=observations,
        task_type="deep_work",
        task_difficulty="medium",
        target_time=now_utc,
    )
    stage = r_result.get("stage", "Stage A")
    confidence = r_result.get("confidence", 0.0)
    hourly_rhythm = r_result.get("hourly_rhythm", [])

    # ── Narrative generation ───────────────────────────────────────────────
    pattern_headline = None
    pattern_detail = None
    actionable_note = None

    if best_window and obs_count >= MIN_SESSIONS_FOR_TIME_PATTERNS:
        window_display = {
            "morning": "9 AM – 12 PM",
            "midday": "12 PM – 3 PM",
            "afternoon": "3 PM – 7 PM",
            "evening": "after 7 PM",
        }
        bw_stats = window_stats.get(best_window)
        if bw_stats:
            pattern_headline = f"You tend to perform best in the {best_window} ({window_display.get(best_window, best_window)})"

    # Duration accuracy insight
    underestimation_pct = None
    if avg_ratio > 1.10:
        underestimation_pct = round((avg_ratio - 1.0) * 100, 0)
        pattern_detail = f"You tend to underestimate task duration by ~{int(underestimation_pct)}%"
    elif avg_ratio < 0.90:
        pattern_detail = "You tend to overestimate how long tasks take — your estimates may have buffer built in."

    if pattern_headline or pattern_detail:
        actionable_note = "Flowstate will use this when planning your next session."

    # ── Status message ─────────────────────────────────────────────────────
    if completion_rate >= 0.75:
        status_msg = "You're getting things done. Keep it up."
    elif completion_rate >= 0.50:
        status_msg = "Decent consistency — room to push a bit more."
    else:
        status_msg = "Some sessions are incomplete. Starting smaller can help."

    return InsightsSummaryResponse(
        total_sessions=obs_count,
        total_focus_minutes=total_actual_minutes,
        completion_rate=completion_rate,
        avg_focus_rating=avg_focus,
        duration_accuracy=avg_ratio,
        acceptance_rate=acceptance_rate,
        override_rate=override_rate,
        total_recommendations=total_decisions,
        time_of_day_performance=window_stats,
        best_window=best_window,
        underestimation_pct=underestimation_pct,
        personalization_stage=stage,
        confidence=confidence,
        hourly_rhythm=hourly_rhythm,
        has_sufficient_history=True,
        status_message=status_msg,
        pattern_headline=pattern_headline,
        pattern_detail=pattern_detail,
        actionable_note=actionable_note,
    )
