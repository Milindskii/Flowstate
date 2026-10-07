"""
Flowstate Master Scheduling Architecture
=========================================
Scheduling Authority & Cognitive Optimizer for Flowstate.

Core Principles:
1. Gemini understands language. Flowstate decides schedule. The user confirms.
2. Hard constraints first: eliminate impossible slots before scoring.
3. Deterministic slot scoring combining urgency, priority, personal fit, task-type fit,
   calendar quality, continuity, context-switch avoidance, anti-overpacking, and anti-procrastination.
4. Current time is required: local datetime, timezone, remaining available time today.
5. Explanation Engine: produces structured reason codes and deterministic, user-facing
   explanations without extra LLM requests.
"""

from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo

# ── TASK TYPE & PRIORITY VALUES ───────────────────────────────────────────────
TASK_VALUE_MAP: Dict[str, float] = {
    "urgent": 1.00,
    "high": 0.80,
    "medium": 0.55,
    "low": 0.30,
    "unspecified": 0.50,
}

TASK_TYPE_WEIGHTS: Dict[str, float] = {
    "deep_work": 1.00,
    "study": 0.90,
    "creative": 0.85,
    "physical": 0.70,
    "meeting": 0.80,
    "admin": 0.50,
    "shallow_work": 0.45,
    "personal": 0.40,
}


# ── PLANNING PROFILE ──────────────────────────────────────────────────────────

class PlanningProfile:
    """
    User Cognitive & Scheduling Planning Profile.
    Integrates baseline questionnaire responses with learned performance history.
    Provides strict access to all core questionnaire anchors:
    wake_time, weekend_wake_time, bedtime, peak_window_start, peak_window_end,
    warmup_minutes, high_energy_task_types, tired_behavior, routine_shift_preference.
    """
    def __init__(
        self,
        preferred_peak_start: float = 9.5,   # 09:30 AM
        preferred_peak_end: float = 11.75,   # 11:45 AM
        preferred_dip_start: float = 14.0,   # 02:00 PM
        preferred_dip_end: float = 15.5,     # 03:30 PM
        weekday_wake_time: float = 7.0,      # 07:00 AM
        weekend_wake_time: float = 8.5,      # 08:30 AM
        bedtime: float = 23.0,               # 11:00 PM
        warmup_minutes: int = 30,            # 30 min cognitive warmup
        high_energy_task_types: Optional[List[str]] = None,
        tired_behavior: str = "distracted",
        routine_shift_preference: str = "quick_recovery",
        preferred_session_minutes: int = 45,
        energy_predictability: str = "mostly_predictable",
        confidence_level: float = 0.20,
        avg_duration_ratio: float = 1.0,
        learned_afternoon_focus: bool = False,
    ):
        self.preferred_peak_start = preferred_peak_start
        self.preferred_peak_end = preferred_peak_end
        self.preferred_dip_start = preferred_dip_start
        self.preferred_dip_end = preferred_dip_end
        self.weekday_wake_time = weekday_wake_time
        self.weekend_wake_time = weekend_wake_time
        self.bedtime = bedtime
        self.warmup_minutes = warmup_minutes
        self.high_energy_task_types = [t.lower() for t in (high_energy_task_types or ["coding", "problem_solving", "deep_work", "study"])]
        self.tired_behavior = tired_behavior
        self.routine_shift_preference = routine_shift_preference
        self.preferred_session_minutes = preferred_session_minutes
        self.energy_predictability = energy_predictability
        self.confidence_level = confidence_level
        self.avg_duration_ratio = avg_duration_ratio
        self.learned_afternoon_focus = learned_afternoon_focus

    # Standardized profile aliases
    @property
    def wake_time(self) -> float:
        return self.weekday_wake_time

    @wake_time.setter
    def wake_time(self, val: float):
        self.weekday_wake_time = val

    @property
    def peak_window_start(self) -> float:
        return self.preferred_peak_start

    @peak_window_start.setter
    def peak_window_start(self, val: float):
        self.preferred_peak_start = val

    @property
    def peak_window_end(self) -> float:
        return self.preferred_peak_end

    @peak_window_end.setter
    def peak_window_end(self, val: float):
        self.preferred_peak_end = val

    @classmethod
    def from_user_context(
        cls,
        readiness_profile: Optional[Any] = None,
        preferences: Optional[Any] = None,
        performance_history: Optional[List[Any]] = None,
    ) -> "PlanningProfile":
        peak_start = 9.5
        peak_end = 11.75
        dip_start = 14.0
        dip_end = 15.5
        wake_time = 7.0
        weekend_wake = 8.5
        bedtime = 23.0
        warmup_mins = 30
        high_energy_types = ["coding", "problem_solving", "deep_work", "study"]
        tired_beh = "distracted"
        routine_shift = "quick_recovery"
        session_mins = 45
        predictability = "mostly_predictable"
        confidence = 0.20

        if readiness_profile:
            try:
                ps = getattr(readiness_profile, "preferred_peak_start", "09:30").split(":")
                peak_start = int(ps[0]) + int(ps[1]) / 60.0
                pe = getattr(readiness_profile, "preferred_peak_end", "11:45").split(":")
                peak_end = int(pe[0]) + int(pe[1]) / 60.0
                ds = getattr(readiness_profile, "preferred_dip_start", "14:00").split(":")
                dip_start = int(ds[0]) + int(ds[1]) / 60.0
                de = getattr(readiness_profile, "preferred_dip_end", "15:30").split(":")
                dip_end = int(de[0]) + int(de[1]) / 60.0
                session_mins = int(getattr(readiness_profile, "preferred_session_minutes", 45))
                predictability = str(getattr(readiness_profile, "energy_predictability", "mostly_predictable"))
                confidence = float(getattr(readiness_profile, "confidence_level", 0.20))
                ww = getattr(readiness_profile, "weekday_wake_time", "07:00").split(":")
                wake_time = int(ww[0]) + int(ww[1]) / 60.0
                wew = getattr(readiness_profile, "weekend_wake_time", "08:30").split(":")
                weekend_wake = int(wew[0]) + int(wew[1]) / 60.0

                bt_val = getattr(readiness_profile, "bedtime", "23:00")
                if bt_val and ":" in str(bt_val):
                    bt_parts = str(bt_val).split(":")
                    bedtime = int(bt_parts[0]) + int(bt_parts[1]) / 60.0
                elif isinstance(bt_val, (int, float)):
                    bedtime = float(bt_val)

                warmup_val = getattr(readiness_profile, "sleep_inertia_minutes", None)
                if warmup_val is not None:
                    warmup_mins = int(warmup_val)

                draining_val = getattr(readiness_profile, "draining_work_types", None)
                if draining_val:
                    if isinstance(draining_val, list):
                        high_energy_types = list(draining_val)
                    elif isinstance(draining_val, str):
                        high_energy_types = [s.strip().lower() for s in draining_val.split(",") if s.strip()]

                tired_beh = str(getattr(readiness_profile, "fatigue_symptom", "distracted") or "distracted")
                routine_shift = str(getattr(readiness_profile, "routine_shift_preference", "quick_recovery") or "quick_recovery")
            except Exception:
                pass

        if preferences:
            try:
                wt = getattr(preferences, "wake_time", None)
                if wt and ":" in str(wt):
                    p = str(wt).split(":")
                    wake_time = int(p[0]) + int(p[1]) / 60.0
            except Exception:
                pass

        # Empirical recency-weighted learning from actual completed tasks & reflection history
        avg_ratio = 1.0
        learned_pm_focus = False
        if performance_history:
            # Sort by recency descending if timestamp available
            sorted_history = sorted(
                performance_history,
                key=lambda x: getattr(x, "created_at", None) or getattr(x, "completed_at", None) or datetime.min,
                reverse=True,
            )
            ratios: List[float] = []
            weights: List[float] = []
            pm_focus_ratings: List[int] = []

            # legacy rows (before 2026-10-07) carried made-up scores and planned-as-actual minutes: not evidence
            real_history = [p for p in sorted_history if getattr(p, "provenance", None) != "legacy"]
            for idx, perf in enumerate(real_history[:30]):
                w = 0.90 ** idx  # Exponential recency weighting
                est = getattr(perf, "estimated_minutes", None)
                act = getattr(perf, "actual_minutes", None)
                if est and act and est > 0:
                    ratios.append((act / est) * w)
                    weights.append(w)
                start_dt = getattr(perf, "actual_start", None) or getattr(perf, "scheduled_start", None)
                if start_dt and hasattr(start_dt, "hour") and 13 <= start_dt.hour <= 17:
                    f_score = getattr(perf, "focus_score", None)
                    if f_score is not None and getattr(perf, "provenance", None) in (None, "reflection"):
                        pm_focus_ratings.append(int(f_score))

            if weights and sum(weights) > 0:
                avg_ratio = sum(ratios) / sum(weights)
            if len(pm_focus_ratings) >= 3 and (sum(pm_focus_ratings) / len(pm_focus_ratings)) >= 3.8:
                learned_pm_focus = True

        return cls(
            preferred_peak_start=peak_start,
            preferred_peak_end=peak_end,
            preferred_dip_start=dip_start,
            preferred_dip_end=dip_end,
            weekday_wake_time=wake_time,
            weekend_wake_time=weekend_wake,
            bedtime=bedtime,
            warmup_minutes=warmup_mins,
            high_energy_task_types=high_energy_types,
            tired_behavior=tired_beh,
            routine_shift_preference=routine_shift,
            preferred_session_minutes=session_mins,
            energy_predictability=predictability,
            confidence_level=confidence,
            avg_duration_ratio=avg_ratio,
            learned_afternoon_focus=learned_pm_focus,
        )


# ── CANDIDATE SLOT & SCORING RESULT ───────────────────────────────────────────

class CandidateSlot:
    def __init__(
        self,
        start_time: datetime,
        end_time: datetime,
        day_offset: int,
        is_peak_window: bool = False,
        is_dip_window: bool = False,
        buffer_minutes_after: int = 15,
    ):
        self.start_time = start_time
        self.end_time = end_time
        self.day_offset = day_offset
        self.is_peak_window = is_peak_window
        self.is_dip_window = is_dip_window
        self.buffer_minutes_after = buffer_minutes_after


class SlotScoreResult:
    def __init__(
        self,
        slot: CandidateSlot,
        score: float,
        primary_reason: str,
        secondary_reasons: List[str],
        explanation: str,
    ):
        self.slot = slot
        self.score = score
        self.primary_reason = primary_reason
        self.secondary_reasons = secondary_reasons
        self.explanation = explanation


# ── MASTER SCHEDULING OPTIMIZER ───────────────────────────────────────────────

class SchedulingEngine:
    """
    Concrete Cognitive Scheduling Optimizer.
    Acts as the single scheduling authority for Flowstate.
    
    Invariants & Rules:
    1. Explicit scheduled time: If task.scheduled_start or fixed_start exists, it is an immutable anchor.
    2. Fixed calendar events / busy intervals: Treated as hard non-schedulable obstacles.
    3. No past scheduling: New schedule slots must begin >= max(now_local, start_of_day).
    4. Urgency ordering: Overdue unfinished tasks first, imminent deadlines second, high priority third.
    5. Anti-procrastination: High value / urgent tasks are scheduled today if viable, not postponed.
    6. Cognitive matching:
       - Deep work & study: matched to circadian peak window (or learned high-focus window).
       - Admin / light work: matched to circadian dip window or interstitial slots.
       - Physical: matched to morning or late-afternoon windows.
    7. Anti-overpacking: Enforces buffer spaces (15m for deep work, 10m for meetings).
    8. Explanation Engine: Produces structured reason codes and concise human explanations.
    """

    def generate_schedule(
        self,
        tasks: List[Any],
        readiness_profile: Optional[Any] = None,
        now_local: Optional[datetime] = None,
        fixed_busy_intervals: Optional[List[Tuple[datetime, datetime]]] = None,
        tz: Optional[ZoneInfo] = None,
        user_preferences: Optional[Any] = None,
        performance_history: Optional[List[Any]] = None,
    ) -> List[Dict[str, Any]]:
        """
        LEGACY compatibility entry point (kept so existing callers/tests keep working).

        No product path calls this any more: Build My Day, Replan, the Calendar and Today all go through
        ``app.engines.planner.plan`` (spec section 4). Note the legacy semantics here: any task with a
        ``scheduled_start`` is treated as an immovable anchor and anchors are not overlap-checked.
        New code must use the planner.
        """
        if not tasks:
            return []

        tz = tz or timezone.utc
        if now_local is None:
            now_local = datetime.now(tz)
        elif now_local.tzinfo is None:
            now_local = now_local.replace(tzinfo=tz)

        profile = PlanningProfile.from_user_context(
            readiness_profile=readiness_profile,
            preferences=user_preferences,
            performance_history=performance_history,
        )

        fixed_busy: List[Tuple[datetime, datetime]] = list(fixed_busy_intervals or [])
        schedule_items: List[Dict[str, Any]] = []

        # 1. Anchored tasks (explicitly fixed times)
        anchored_tasks = []
        flexible_tasks = []

        for t in tasks:
            sched_start = getattr(t, "scheduled_start", None) or getattr(t, "fixed_start", None)
            if isinstance(sched_start, str) and ":" in sched_start:
                try:
                    parts = sched_start.split(":")
                    sched_start = datetime.combine(now_local.date(), time(int(parts[0]), int(parts[1])), tzinfo=tz)
                except Exception:
                    sched_start = None

            if sched_start:
                if getattr(sched_start, "tzinfo", None) is None:
                    sched_start = sched_start.replace(tzinfo=tz)
                anchored_tasks.append((sched_start, t))
            else:
                flexible_tasks.append(t)

        for s_start, t in sorted(anchored_tasks, key=lambda x: x[0]):
            dur = getattr(t, "estimated_minutes", 45) or 45
            s_end = s_start + timedelta(minutes=dur)
            fixed_busy.append((s_start, s_end))

            item_type = self._resolve_task_type_str(t)
            tag_text = self._resolve_tag_text(item_type)
            schedule_items.append({
                "id": f"sched-{getattr(t, 'id', 'item')}",
                "task_id": str(getattr(t, "id", "")),
                "title": getattr(t, "title", "Task"),
                "start_time": s_start,
                "end_time": s_end,
                "duration_minutes": dur,
                "type": item_type,
                "tag_text": tag_text,
                "is_active": getattr(t, "status", None) == "in_progress",
                "is_anchored": True,
                "primary_reason": "explicit_time",
                "secondary_reasons": ["user_specified_time"],
                "explanation": f"Scheduled at your requested time ({s_start.strftime('%I:%M %p').lstrip('0')}).",
            })

        # 2. Sort flexible tasks by urgency, priority, and cognitive demand
        def _sort_key(t: Any):
            deadline = getattr(t, "deadline_at", None)
            is_overdue = False
            is_due_today = False
            if deadline:
                d = deadline if getattr(deadline, "tzinfo", None) is not None else deadline.replace(tzinfo=tz)
                if d < now_local:
                    is_overdue = True
                elif d.date() == now_local.date():
                    is_due_today = True

            pri = str(getattr(t, "priority", "medium") or "medium").lower()
            pri_weight = TASK_VALUE_MAP.get(pri, 0.5)

            t_type = self._resolve_task_type_str(t)
            type_weight = TASK_TYPE_WEIGHTS.get(t_type, 0.5)

            # Rank: 0 = Overdue, 1 = Due Today, 2 = High Priority, 3 = Normal
            if is_overdue:
                urgency_rank = 0
            elif is_due_today:
                urgency_rank = 1
            elif pri in ("urgent", "high"):
                urgency_rank = 2
            else:
                urgency_rank = 3

            return (urgency_rank, -pri_weight, -type_weight)

        sorted_flexible = sorted(flexible_tasks, key=_sort_key)

        # 3. Schedule flexible tasks sequentially into scored feasible slots
        for t in sorted_flexible:
            dur = getattr(t, "estimated_minutes", 45) or 45
            slot_res = self.evaluate_best_slot_for_task(
                task=t,
                existing_busy=fixed_busy,
                profile=profile,
                now_local=now_local,
                tz=tz,
            )

            if slot_res:
                s_start = slot_res.slot.start_time
                s_end = slot_res.slot.end_time
                # Register allocated slot + buffer in busy intervals
                buffer_mins = slot_res.slot.buffer_minutes_after
                fixed_busy.append((s_start, s_end + timedelta(minutes=buffer_mins)))

                item_type = self._resolve_task_type_str(t)
                tag_text = self._resolve_tag_text(item_type)

                schedule_items.append({
                    "id": f"sched-{getattr(t, 'id', 'item')}",
                    "task_id": str(getattr(t, "id", "")),
                    "title": getattr(t, "title", "Task"),
                    "start_time": s_start,
                    "end_time": s_end,
                    "duration_minutes": dur,
                    "type": item_type,
                    "tag_text": tag_text,
                    "is_active": getattr(t, "status", None) == "in_progress",
                    "is_anchored": False,
                    "primary_reason": slot_res.primary_reason,
                    "secondary_reasons": slot_res.secondary_reasons,
                    "explanation": slot_res.explanation,
                })

        schedule_items.sort(key=lambda x: x["start_time"])
        return schedule_items

    def evaluate_best_slot_for_task(
        self,
        task: Any,
        existing_busy: List[Tuple[datetime, datetime]],
        profile: PlanningProfile,
        now_local: datetime,
        tz: ZoneInfo,
    ) -> Optional[SlotScoreResult]:
        """
        Evaluates candidate slots for a task across today and tomorrow,
        eliminates hard constraints, scores each slot, and returns the highest-scoring slot.
        """
        return self.evaluate_best_slot_with_reason(task, existing_busy, profile, now_local, tz)[0]

    @staticmethod
    def buffer_minutes_for(task_type: str) -> int:
        """Soft gap kept after a task (15 min for cognitively heavy work, else 10)."""
        return 15 if task_type in ("deep_work", "study") else 10

    def urgency_sort_key(self, task: Any, now_local: datetime, tz: ZoneInfo):
        """Placement order: overdue -> due today -> high/urgent -> rest; then priority, then type weight."""
        deadline = getattr(task, "deadline_at", None)
        is_overdue = False
        is_due_today = False
        if deadline:
            d = deadline if getattr(deadline, "tzinfo", None) is not None else deadline.replace(tzinfo=tz)
            if d < now_local:
                is_overdue = True
            elif d.astimezone(tz).date() == now_local.date():
                is_due_today = True
        pri = str(getattr(task, "priority", "medium") or "medium").lower()
        pri_weight = TASK_VALUE_MAP.get(pri, 0.5)
        type_weight = TASK_TYPE_WEIGHTS.get(self._resolve_task_type_str(task), 0.5)
        if is_overdue:
            rank = 0
        elif is_due_today:
            rank = 1
        elif pri in ("urgent", "high"):
            rank = 2
        else:
            rank = 3
        return (rank, -pri_weight, -type_weight)

    def evaluate_best_slot_with_reason(
        self,
        task: Any,
        existing_busy: List[Tuple[datetime, datetime]],
        profile: PlanningProfile,
        now_local: datetime,
        tz: ZoneInfo,
    ) -> Tuple[Optional[SlotScoreResult], Optional[str]]:
        """Same as evaluate_best_slot_for_task but also explains a None result.

        Reasons: explicit_time_in_past | explicit_time_conflict | explicit_time_after_deadline |
        no_feasible_slot.
        """
        dur = getattr(task, "estimated_minutes", 45) or 45
        t_type = self._resolve_task_type_str(task)
        deadline = getattr(task, "deadline_at", None)
        if deadline and getattr(deadline, "tzinfo", None) is None:
            deadline = deadline.replace(tzinfo=tz)

        # Candidates keep user language separate from Flowstate's final selected slot.
        # This supports a strict hard-constraints-first pass before cognitive scoring.
        temporal = getattr(task, "temporal", None)
        target_date = getattr(temporal, "target_date", None) if temporal else None
        earliest_start = getattr(temporal, "earliest_start", None) if temporal else None
        user_latest_end = getattr(temporal, "latest_end", None) if temporal else None
        relative_before = getattr(temporal, "relative_before", None) if temporal else None
        relative_after = getattr(temporal, "relative_after", None) if temporal else None
        preferred_start = getattr(temporal, "preferred_start", None) if temporal else None
        preferred_window_start = getattr(temporal, "preferred_window_start", None) if temporal else None
        preferred_window_end = getattr(temporal, "preferred_window_end", None) if temporal else None

        def _aware(value: Optional[datetime]) -> Optional[datetime]:
            if value is None:
                return None
            return value if value.tzinfo else value.replace(tzinfo=tz)

        earliest_start = _aware(earliest_start)
        user_latest_end = _aware(user_latest_end)
        preferred_start = _aware(preferred_start)
        preferred_window_start = _aware(preferred_window_start)
        preferred_window_end = _aware(preferred_window_end)

        # ── MEAL ANCHOR TABLE ──────────────────────────────────────────────────
        # Default meal times (overridable by profile meal times when available).
        # Provenance: source=default — treated as soft context, not hard medical fact.
        MEAL_DEFAULT_TIMES: Dict[str, time] = {
            "breakfast": time(7, 30),
            "lunch":     time(13, 0),
            "dinner":    time(20, 0),
        }

        # Extract time-of-day component from relative constraints so we can re-anchor
        # them per candidate day. This is the root fix for the 'after dinner tomorrow'
        # bug where earliest_start was pinned to TODAY's 20:00.
        relative_after_time: Optional[time] = None
        relative_before_time: Optional[time] = None
        if relative_after and relative_after in MEAL_DEFAULT_TIMES:
            relative_after_time = MEAL_DEFAULT_TIMES[relative_after]
        # A plain `earliest_start` is an ABSOLUTE instant and is never re-anchored onto other days.
        # (It used to be: "not before tomorrow 09:30" then allowed today after 09:30, so a postponed task
        # could land earlier than the time the user pushed it to.) Only meal-relative bounds are per-day.
        if relative_before and relative_before in MEAL_DEFAULT_TIMES:
            relative_before_time = MEAL_DEFAULT_TIMES[relative_before]
        elif user_latest_end and relative_before and relative_before not in ("bedtime",):
            relative_before_time = user_latest_end.time()

        # Extract preferred_window time-of-day components for per-candidate-day re-anchoring.
        # BUG FIX: preferred_window dates are anchored to today at parse time.
        # When a candidate slot is on tomorrow, the window must be projected onto tomorrow's date.
        pref_window_time_start: Optional[time] = preferred_window_start.time() if preferred_window_start else None
        pref_window_time_end: Optional[time] = preferred_window_end.time() if preferred_window_end else None
        pref_start_time: Optional[time] = preferred_start.time() if preferred_start else None

        # Explicit starts are immutable anchors. The planner may explain them but must not move them.
        # EXCEPTION: A fixed_start in the past is invalid; fall through to candidate generation.
        fixed_start = getattr(task, "scheduled_start", None) or getattr(temporal, "fixed_start", None) if temporal else getattr(task, "scheduled_start", None)
        fixed_start = _aware(fixed_start)
        if fixed_start:
            # HARD INVARIANT: No newly scheduled task may be placed in the past.
            if fixed_start < now_local - timedelta(seconds=60):
                # D6: an explicit time in the past is never silently moved.
                return None, "explicit_time_in_past"
            else:
                fixed_end = fixed_start + timedelta(minutes=dur)
                has_collision = any(fixed_start < b_end and fixed_end > b_start for b_start, b_end in existing_busy)
                violates_deadline = bool(deadline and fixed_end > deadline)
                if violates_deadline:
                    return None, "explicit_time_after_deadline"
                if has_collision:
                    return None, "explicit_time_conflict"
                day_diff = max(0, (fixed_start.date() - now_local.date()).days)
                return SlotScoreResult(
                    slot=CandidateSlot(fixed_start, fixed_end, day_diff),
                    score=1.0,
                    primary_reason="explicit_time",
                    secondary_reasons=["user_specified_time"],
                    explanation=f"Scheduled at your requested time ({fixed_start.strftime('%I:%M %p').lstrip('0')}).",
                ), None

        pri_str = str(getattr(task, "priority", "medium") or "medium").lower()

        candidate_slots: List[CandidateSlot] = []

        # ── Dynamic day-range candidate generation ─────────────────────────────
        # CRITICAL FIX: The scheduler previously only generated candidates for
        # today and tomorrow. Any target_date further away (e.g. "Gym Friday"
        # said on a Monday) produced zero feasible slots → fell back to
        # "Tomorrow 4:30 PM", ignoring the user's intent entirely.
        #
        # New behaviour:
        #   - When target_date is set: generate ONLY the target day (maximum
        #     8 days ahead).
        #   - When deadline is set: generate days from today up to the deadline
        #     day (maximum 8 days).
        #   - Otherwise: generate today + tomorrow (legacy, unchanged).
        #
        # day_offset is kept as the integer distance from today so the
        # explanation engine can still say "Today" / "Tomorrow" / weekday name.

        today_date = now_local.date()
        MAX_LOOKAHEAD_DAYS = 8

        # Determine which dates to cover
        if target_date:
            days_to_cover = [(target_date - today_date).days]
            days_to_cover = [d for d in days_to_cover if 0 <= d <= MAX_LOOKAHEAD_DAYS]
        elif deadline:
            dl_date = deadline.date()
            span = min((dl_date - today_date).days, MAX_LOOKAHEAD_DAYS)
            days_to_cover = list(range(max(0, span - 1), span + 1)) if span >= 0 else [0]
        else:
            # No constraint: cover today and tomorrow (existing behaviour)
            days_to_cover = [0, 1]

        if not days_to_cover:
            days_to_cover = [0, 1]  # safe fallback

        for day_offset in days_to_cover:
            cand_date = today_date + timedelta(days=day_offset)
            wake_h = profile.weekend_wake_time if cand_date.weekday() >= 5 else profile.weekday_wake_time
            day_start_dt = datetime.combine(cand_date, time(int(wake_h), int((wake_h % 1) * 60)), tzinfo=tz)
            # Clamp bedtime hour to 23 (24 means midnight end-of-day; Python time() only accepts 0-23)
            bedtime_h = min(int(profile.bedtime), 23)
            bedtime_m = int((profile.bedtime % 1) * 60)
            day_bedtime_dt = datetime.combine(cand_date, time(bedtime_h, bedtime_m), tzinfo=tz)

            if day_offset == 0:
                cursor = max(now_local, day_start_dt)
                # Zero sub-minute noise (rounding up), then round up to the 15-minute grid
                if cursor.second or cursor.microsecond:
                    cursor = cursor.replace(second=0, microsecond=0) + timedelta(minutes=1)
                rem = cursor.minute % 15
                if rem > 0:
                    cursor += timedelta(minutes=(15 - rem))
                # Imminent deadline: allow small bedtime overrun
                day_limit = day_bedtime_dt
                if deadline and deadline > now_local and (deadline - now_local) <= timedelta(hours=14):
                    day_limit = day_bedtime_dt + timedelta(minutes=90)
            else:
                cursor = day_start_dt
                day_limit = day_bedtime_dt

            while cursor + timedelta(minutes=dur) <= day_limit:
                c_start = cursor
                c_end = cursor + timedelta(minutes=dur)
                c_h = c_start.hour + c_start.minute / 60.0
                is_peak = (profile.preferred_peak_start <= c_h <= profile.preferred_peak_end)
                is_dip = (profile.preferred_dip_start <= c_h <= profile.preferred_dip_end)
                buffer = 15 if t_type in ("deep_work", "study") else 10
                candidate_slots.append(CandidateSlot(
                    c_start, c_end,
                    day_offset=day_offset,
                    is_peak_window=is_peak,
                    is_dip_window=is_dip,
                    buffer_minutes_after=buffer,
                ))
                cursor += timedelta(minutes=15)

        # ── HARD CONSTRAINTS FILTER ──
        feasible_slots = []
        for slot in candidate_slots:
            # 1. Collision with fixed busy intervals
            collision = False
            for b_start, b_end in existing_busy:
                if slot.start_time < b_end and slot.end_time > b_start:
                    collision = True
                    break
            if collision:
                continue

            # 2. Hard Deadline constraint: must finish before deadline
            if deadline and slot.end_time > deadline:
                continue

            # 3. User-stated temporal bounds. These are hard; preferences are scored below.
            if target_date and slot.start_time.date() != target_date:
                continue

            # ── Re-anchor relative meal constraints per candidate day ──────────
            # CRITICAL FIX: earliest_start / latest_end from meal references
            # (after dinner, after lunch, after breakfast) are stored with today's
            # date at parse time. When the candidate slot is on tomorrow, we must
            # re-evaluate the bound against TOMORROW's meal time, not today's.
            # E.g. 'after dinner tomorrow' must mean tomorrow 20:00, not today 20:00.
            slot_date = slot.start_time.date()
            effective_earliest = earliest_start
            effective_latest = user_latest_end

            if relative_after_time and (not earliest_start or earliest_start.date() != slot_date):
                # Re-anchor: earliest = same time-of-day on the candidate day
                effective_earliest = datetime.combine(slot_date, relative_after_time, tzinfo=tz)
            if relative_before_time and relative_before not in ("bedtime",) and (not user_latest_end or user_latest_end.date() != slot_date):
                effective_latest = datetime.combine(slot_date, relative_before_time, tzinfo=tz)

            if effective_earliest and slot.start_time < effective_earliest:
                continue
            if effective_latest and slot.end_time > effective_latest:
                continue

            if relative_before == "bedtime":
                _bt_h = min(int(profile.bedtime), 23)
                _bt_m = int((profile.bedtime % 1) * 60)
                bedtime_dt = datetime.combine(slot_date, time(_bt_h, _bt_m), tzinfo=tz)
                if slot.end_time > bedtime_dt:
                    continue

            # 4. No past scheduling
            if slot.start_time < now_local:
                continue

            feasible_slots.append(slot)

        if not feasible_slots:
            # A deadline or an explicit temporal bound may never be bypassed by a fallback.
            if deadline or target_date or earliest_start or user_latest_end or relative_before:
                return None, "no_feasible_slot"
            # No hard user constraint exists: earliest opening after the busy schedule,
            # but never past that day's bedtime (finding 18).
            fallback_start = now_local + timedelta(minutes=5)
            if existing_busy:
                max_busy_end = max(b[1] for b in existing_busy)
                fallback_start = max(fallback_start, max_busy_end + timedelta(minutes=10))
            fallback_start = fallback_start.replace(second=0, microsecond=0)
            fb_end = fallback_start + timedelta(minutes=dur)
            fb_bed = datetime.combine(
                fallback_start.date(), time(min(int(profile.bedtime), 23), int((profile.bedtime % 1) * 60)), tzinfo=tz
            )
            if fb_end > fb_bed or fb_end.date() != fallback_start.date():
                return None, "no_feasible_slot"
            fb_slot = CandidateSlot(
                fallback_start, fb_end, day_offset=max(0, (fallback_start.date() - now_local.date()).days)
            )
            return SlotScoreResult(
                slot=fb_slot,
                score=0.1,
                primary_reason="available_slot",
                secondary_reasons=["best_fit_in_busy_schedule"],
                explanation="Scheduled into the earliest available opening in your schedule.",
            ), None

        # ── SLOT SCORING ──
        best_result: Optional[SlotScoreResult] = None
        highest_score = -9999.0

        task_title = str(getattr(task, "title", "") or "").lower()
        is_cognitive = (
            t_type in ("deep_work", "study") or
            any(k.lower() in task_title for k in profile.high_energy_task_types) or
            any(w in task_title for w in ["coding", "code", "problem solving", "assignment", "thesis", "algorithm", "study", "exam", "paper", "deep work"])
        )
        is_physical = (
            t_type == "physical" or
            any(w in task_title for w in ["gym", "workout", "run", "lift", "exercise", "training"])
        )
        is_light = (
            t_type in ("admin", "shallow_work", "personal") or
            any(w in task_title for w in ["email", "clean", "desk", "room", "laundry", "errand", "groceries", "call", "admin"])
        )

        for slot in feasible_slots:
            score = 0.0
            primary_reason = "available_slot"
            secondary_reasons: List[str] = []

            c_h = slot.start_time.hour + slot.start_time.minute / 60.0
            slot_date = slot.start_time.date()

            # ── Re-anchor preferred_window onto the candidate day ─────────────
            # BUG FIX: preferred_window_start/end are parsed with today's date.
            # When a candidate slot is on tomorrow, we must compare window times
            # against the same time-of-day on the SLOT's date, not today's date.
            # E.g. 'around 6 PM' (22:30 now) must score tomorrow 18:00 high, not low.
            slot_pref_window_start: Optional[datetime] = None
            slot_pref_window_end: Optional[datetime] = None
            slot_pref_start: Optional[datetime] = None
            if pref_window_time_start and pref_window_time_end:
                slot_pref_window_start = datetime.combine(slot_date, pref_window_time_start, tzinfo=tz)
                slot_pref_window_end = datetime.combine(slot_date, pref_window_time_end, tzinfo=tz)
            if pref_start_time:
                slot_pref_start = datetime.combine(slot_date, pref_start_time, tzinfo=tz)

            # Flexible user timing is a soft preference, not an invented fixed appointment.
            # preferred_window_start/end: reward slots inside the window, penalise slots outside.
            # preferred_start ("around X PM"): score by proximity — closer = higher reward.
            if slot_pref_window_start and slot_pref_window_end:
                if slot_pref_window_start <= slot.start_time <= slot_pref_window_end:
                    score += 0.60
                    secondary_reasons.append("matches_preferred_time_window")
                    if primary_reason == "available_slot":
                        primary_reason = "preferred_time_window"
                else:
                    # Outside the explicitly stated window: apply a meaningful penalty.
                    # This is stronger than the old -0.20 so afternoon/evening/after-dinner
                    # preferences actually beat the default morning-focus heuristic.
                    score -= 0.55
            elif slot_pref_start:
                distance_minutes = abs((slot.start_time - slot_pref_start).total_seconds()) / 60.0
                # Inverse-distance reward: 0 min away = +0.60, 45 min away = +0.15, 90+ min = -0.20
                if distance_minutes <= 15:
                    score += 0.60
                    secondary_reasons.append("near_preferred_time")
                    if primary_reason == "available_slot":
                        primary_reason = "preferred_time_window"
                elif distance_minutes <= 45:
                    score += 0.45 - (0.30 * (distance_minutes - 15) / 30.0)
                    secondary_reasons.append("near_preferred_time")
                    if primary_reason == "available_slot":
                        primary_reason = "preferred_time_window"
                elif distance_minutes <= 90:
                    # Outside ±45 min of preference: small bonus that tapers off
                    score += 0.15 - (0.35 * (distance_minutes - 45) / 45.0)
                else:
                    # Significantly far from preference: penalise
                    score -= 0.20

            # 1. Wake & Cognitive Warmup Window Protection
            target_wake_h = profile.weekend_wake_time if slot.start_time.weekday() >= 5 else profile.weekday_wake_time
            warmup_end_h = target_wake_h + (profile.warmup_minutes / 60.0)

            if is_cognitive and c_h < warmup_end_h:
                score -= 0.85
                secondary_reasons.append("during_cognitive_warmup")

            # 2. Deadline Urgency Score
            requires_tonight_for_deadline = False
            if deadline:
                hours_until = (deadline - slot.start_time).total_seconds() / 3600.0
                dl_date = deadline.date()
                tomorrow_date = today_date + timedelta(days=1)
                if hours_until <= 14 and (dl_date <= today_date or (dl_date == tomorrow_date and deadline.hour <= 10)):
                    requires_tonight_for_deadline = True

                if hours_until <= 3:
                    score += 0.55
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_under_3h")
                elif hours_until <= 16:
                    score += 0.45
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_under_16h")
                elif hours_until <= 24:
                    score += 0.30
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_within_24h")
                else:
                    score += 0.05

            # 3. Priority Score (Internal ranking only, separate from user priority)
            if pri_str == "urgent":
                score += 0.35
                secondary_reasons.append("urgent_priority")
            elif pri_str == "high":
                score += 0.25
                secondary_reasons.append("high_priority")
            elif pri_str == "medium":
                score += 0.15
            else:
                score += 0.05

            # 4. Personal Fit & Task-Type Matching
            if is_cognitive:
                if slot.is_peak_window:
                    score += 0.45
                    if primary_reason == "available_slot":
                        primary_reason = "peak_window"
                    secondary_reasons.append("strong_focus_window")
                elif c_h >= warmup_end_h and 8.0 <= c_h <= 13.0:
                    score += 0.20
                    secondary_reasons.append("morning_focus")
                elif profile.learned_afternoon_focus and 14.0 <= c_h <= 17.0:
                    score += 0.25
                    if primary_reason == "available_slot":
                        primary_reason = "learned_focus_window"
                    secondary_reasons.append("learned_afternoon_focus")
                elif c_h >= 20.0:
                    score -= 0.50
                    secondary_reasons.append("avoids_late_fatigue")
            elif is_light:
                if slot.is_dip_window:
                    score += 0.35
                    if primary_reason == "available_slot":
                        primary_reason = "dip_window"
                    secondary_reasons.append("light_work_dip")
                elif 13.0 <= c_h <= 18.0:
                    score += 0.20
                elif c_h >= 20.0:
                    score -= 0.40
                    secondary_reasons.append("avoids_late_fatigue")
            elif is_physical:
                if (7.0 <= c_h <= 9.5) or (16.0 <= c_h <= 19.5):
                    score += 0.40
                    if primary_reason == "available_slot":
                        primary_reason = "physical_window"
                    secondary_reasons.append("optimal_workout_window")
                elif c_h >= 20.0:
                    score -= 0.50
                    secondary_reasons.append("avoids_late_fatigue")

            # 5. Sleep Protection & Deadline Safety Override
            bedtime_h = profile.bedtime
            is_near_bedtime = (slot.day_offset == 0 and c_h >= (bedtime_h - 1.25))

            if is_near_bedtime:
                if requires_tonight_for_deadline:
                    # Deadline safety overrides normal bedtime preference when necessary!
                    score += 0.70
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_safety_overrides_sleep")
                else:
                    # Ordinary / low-priority / non-deadline tasks get heavy sleep protection penalty
                    score -= 1.00
                    if primary_reason == "available_slot":
                        primary_reason = "sleep_protection"
                    secondary_reasons.append("protects_sleep_schedule")

            # General late-night safety rule: do not schedule non-urgent tasks late at night (>=20:00).
            # Applied to BOTH today and tomorrow — without this, tomorrow evening is artificially
            # cheaper than today evening, causing 'after dinner' to always roll to tomorrow.
            # Explicitly-stated evening/after-dinner preferences still win (+0.60 window bonus >> -0.35).
            if c_h >= 20.0 and not requires_tonight_for_deadline:
                score -= 0.35

            # 6. Anti-Procrastination Rule:
            # If high value / urgent work has viable daytime today, penalize pushing to tomorrow afternoon
            if (pri_str in ("urgent", "high") or (deadline and (deadline - now_local).total_seconds() < 86400)):
                if slot.day_offset > 0 and c_h > 12.0 and now_local.hour < 18:
                    score -= 0.35

            # 7. Routine adaptation on shifted schedule / weekends
            if slot.day_offset > 0 and slot.start_time.weekday() >= 5:
                if profile.routine_shift_preference == "lighter_work" and is_cognitive:
                    score -= 0.20
                elif profile.routine_shift_preference == "slower_tempo" and c_h < (target_wake_h + 2.0) and is_cognitive:
                    score -= 0.25

            # Formulate user-facing explanation
            time_display = slot.start_time.strftime("%I:%M %p").lstrip("0")
            if slot.day_offset == 0:
                day_display = "Today"
            elif slot.day_offset == 1:
                day_display = "Tomorrow"
            else:
                # e.g. "Friday" for a slot 4 days from now
                day_display = slot.start_time.strftime("%A")

            if primary_reason == "peak_window":
                expl = f"{day_display} at {time_display} — That's one of your strongest focus windows with a clear uninterrupted block."
            elif primary_reason == "deadline_imminent":
                if "deadline_safety_overrides_sleep" in secondary_reasons:
                    expl = f"{day_display} at {time_display} — Prioritized tonight to protect your upcoming deadline before your bedtime."
                else:
                    expl = f"{day_display} at {time_display} — Prioritized to protect your upcoming deadline."
            elif primary_reason == "sleep_protection" or (slot.day_offset == 1 and not deadline and now_local.hour >= 20):
                expl = f"Tomorrow at {time_display} — Moved to tomorrow to protect your sleep schedule and wind-down window."
            elif primary_reason == "dip_window":
                expl = f"{day_display} at {time_display} — Fits into your afternoon window to maintain momentum without cognitive strain."
            elif primary_reason == "physical_window":
                expl = f"{day_display} at {time_display} — Ideal physical session window with post-workout recovery space."
            elif primary_reason == "preferred_time_window":
                expl = f"{day_display} at {time_display} — Fits the time window you preferred while keeping the schedule feasible."
            elif slot.day_offset == 1 and not deadline:
                expl = f"Tomorrow at {time_display} — Tomorrow contains a strong uninterrupted focus block."
            else:
                expl = f"{day_display} at {time_display} — Best feasible slot matching your availability."

            result = SlotScoreResult(
                slot=slot,
                score=score,
                primary_reason=primary_reason,
                secondary_reasons=secondary_reasons,
                explanation=expl,
            )

            if score > highest_score:
                highest_score = score
                best_result = result

        return best_result, (None if best_result else "no_feasible_slot")

    @staticmethod
    def _resolve_task_type_str(task: Any) -> str:
        t_type = getattr(task, "task_type", None) or getattr(task, "type", None)
        if hasattr(t_type, "value"):
            return str(t_type.value)
        return str(t_type or "deep_work")

    @staticmethod
    def _resolve_tag_text(task_type: str) -> str:
        if task_type in ("deep_work", "study", "creative"):
            return "DEEP WORK"
        elif task_type in ("admin", "shallow_work"):
            return "ADMIN"
        elif task_type == "physical":
            return "PHYSICAL"
        elif task_type == "meeting":
            return "MEETING"
        return "TASK"
