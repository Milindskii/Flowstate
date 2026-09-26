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
import re

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
        self.preferred_session_minutes = preferred_session_minutes
        self.energy_predictability = energy_predictability
        self.confidence_level = confidence_level
        self.avg_duration_ratio = avg_duration_ratio
        self.learned_afternoon_focus = learned_afternoon_focus

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

        # Learn from empirical task performance records if available
        avg_ratio = 1.0
        learned_pm_focus = False
        if performance_history:
            ratios: List[float] = []
            pm_focus_ratings: List[int] = []
            for perf in performance_history:
                est = getattr(perf, "estimated_minutes", None)
                act = getattr(perf, "actual_minutes", None)
                if est and act and est > 0:
                    ratios.append(act / est)
                start_dt = getattr(perf, "actual_start", None) or getattr(perf, "scheduled_start", None)
                if start_dt and hasattr(start_dt, "hour") and 13 <= start_dt.hour <= 17:
                    f_score = getattr(perf, "focus_score", None)
                    if f_score is not None:
                        pm_focus_ratings.append(int(f_score))
            if ratios:
                avg_ratio = sum(ratios) / len(ratios)
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
        Builds an optimized timeline for tasks strictly adhering to cognitive windows,
        hard constraints, and current local time.
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
        dur = getattr(task, "estimated_minutes", 45) or 45
        t_type = self._resolve_task_type_str(task)
        deadline = getattr(task, "deadline_at", None)
        if deadline and getattr(deadline, "tzinfo", None) is None:
            deadline = deadline.replace(tzinfo=tz)

        pri_str = str(getattr(task, "priority", "medium") or "medium").lower()

        candidate_slots: List[CandidateSlot] = []

        # ── Day 0 (Today) ──
        today_date = now_local.date()
        wake_h = profile.weekend_wake_time if today_date.weekday() >= 5 else profile.weekday_wake_time
        today_day_start = datetime.combine(today_date, time(int(wake_h), int((wake_h % 1) * 60)), tzinfo=tz)
        today_bedtime = datetime.combine(today_date, time(int(profile.bedtime), int((profile.bedtime % 1) * 60)), tzinfo=tz)
        cursor_today = max(now_local, today_day_start)
        # Round up to 15m
        rem = cursor_today.minute % 15
        if rem > 0:
            cursor_today += timedelta(minutes=(15 - rem))
            cursor_today = cursor_today.replace(second=0, microsecond=0)

        while cursor_today + timedelta(minutes=dur) <= today_bedtime:
            c_start = cursor_today
            c_end = cursor_today + timedelta(minutes=dur)
            c_h = c_start.hour + c_start.minute / 60.0
            is_peak = (profile.preferred_peak_start <= c_h <= profile.preferred_peak_end)
            is_dip = (profile.preferred_dip_start <= c_h <= profile.preferred_dip_end)
            buffer = 15 if t_type in ("deep_work", "study") else 10
            candidate_slots.append(CandidateSlot(c_start, c_end, day_offset=0, is_peak_window=is_peak, is_dip_window=is_dip, buffer_minutes_after=buffer))
            cursor_today += timedelta(minutes=15)

        # ── Day 1 (Tomorrow) ──
        tomorrow_date = today_date + timedelta(days=1)
        tmw_wake_h = profile.weekend_wake_time if tomorrow_date.weekday() >= 5 else profile.weekday_wake_time
        tmw_start = datetime.combine(tomorrow_date, time(int(tmw_wake_h), int((tmw_wake_h % 1) * 60)), tzinfo=tz)
        tmw_bedtime = datetime.combine(tomorrow_date, time(int(profile.bedtime), int((profile.bedtime % 1) * 60)), tzinfo=tz)
        cursor_tmw = tmw_start

        while cursor_tmw + timedelta(minutes=dur) <= tmw_bedtime:
            c_start = cursor_tmw
            c_end = cursor_tmw + timedelta(minutes=dur)
            c_h = c_start.hour + c_start.minute / 60.0
            is_peak = (profile.preferred_peak_start <= c_h <= profile.preferred_peak_end)
            is_dip = (profile.preferred_dip_start <= c_h <= profile.preferred_dip_end)
            buffer = 15 if t_type in ("deep_work", "study") else 10
            candidate_slots.append(CandidateSlot(c_start, c_end, day_offset=1, is_peak_window=is_peak, is_dip_window=is_dip, buffer_minutes_after=buffer))
            cursor_tmw += timedelta(minutes=15)

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

            # 3. No past scheduling
            if slot.start_time < now_local:
                continue

            feasible_slots.append(slot)

        if not feasible_slots:
            # Fallback: if all filtered, append to end of existing busy or now_local + 5
            fallback_start = now_local + timedelta(minutes=5)
            if existing_busy:
                max_busy_end = max(b[1] for b in existing_busy)
                fallback_start = max(fallback_start, max_busy_end + timedelta(minutes=10))
            fb_slot = CandidateSlot(fallback_start, fallback_start + timedelta(minutes=dur), day_offset=0)
            return SlotScoreResult(
                slot=fb_slot,
                score=0.1,
                primary_reason="available_slot",
                secondary_reasons=["best_fit_in_busy_schedule"],
                explanation="Scheduled into the earliest available opening in your schedule.",
            )

        # ── SLOT SCORING ──
        best_result: Optional[SlotScoreResult] = None
        highest_score = -9999.0

        for slot in feasible_slots:
            score = 0.0
            primary_reason = "available_slot"
            secondary_reasons: List[str] = []

            c_h = slot.start_time.hour + slot.start_time.minute / 60.0

            # 1. Deadline Urgency Score
            if deadline:
                hours_until = (deadline - slot.start_time).total_seconds() / 3600.0
                if hours_until <= 3:
                    score += 0.50
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_under_3h")
                elif hours_until <= 16:
                    score += 0.40
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_under_16h")
                elif hours_until <= 24:
                    score += 0.30
                    primary_reason = "deadline_imminent"
                    secondary_reasons.append("deadline_within_24h")
                else:
                    score += 0.05

            # 2. Priority Score
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

            # 3. Personal Fit & Task-Type Match
            if t_type in ("deep_work", "study"):
                if slot.is_peak_window:
                    score += 0.35
                    if primary_reason == "available_slot":
                        primary_reason = "peak_window"
                    secondary_reasons.append("strong_focus_window")
                elif 9.0 <= c_h <= 13.0:
                    score += 0.20
                    secondary_reasons.append("morning_focus")
                elif profile.learned_afternoon_focus and 14.0 <= c_h <= 17.0:
                    score += 0.25
                    if primary_reason == "available_slot":
                        primary_reason = "learned_focus_window"
                    secondary_reasons.append("learned_afternoon_focus")
                elif c_h >= 20.0 and pri_str not in ("urgent", "high"):
                    # Late evening fatigue penalty for deep work
                    score -= 0.30
                    secondary_reasons.append("avoids_late_fatigue")
            elif t_type in ("admin", "shallow_work", "personal"):
                if slot.is_dip_window:
                    score += 0.30
                    if primary_reason == "available_slot":
                        primary_reason = "dip_window"
                    secondary_reasons.append("light_work_dip")
                elif c_h >= 13.0:
                    score += 0.20
            elif t_type == "physical":
                if (7.0 <= c_h <= 9.0) or (16.0 <= c_h <= 19.5):
                    score += 0.30
                    if primary_reason == "available_slot":
                        primary_reason = "physical_window"
                    secondary_reasons.append("optimal_workout_window")

            # 4. Anti-Procrastination Rule:
            # If high value / urgent work has viable time today, penalize pushing to tomorrow afternoon
            if (pri_str in ("urgent", "high") or (deadline and (deadline - now_local).total_seconds() < 86400)):
                if slot.day_offset > 0 and c_h > 12.0:
                    score -= 0.35

            # 5. Timing relative to current time:
            # If today and past peak (e.g. now is 18:22) and task has no deadline:
            # A slot tomorrow morning in peak window will naturally score higher due to +0.35 peak bonus
            # and today late slot getting -0.30 late fatigue penalty!

            # Formulate user-facing explanation
            time_display = slot.start_time.strftime("%I:%M %p").lstrip("0")
            day_display = "Today" if slot.day_offset == 0 else "Tomorrow"

            if primary_reason == "peak_window":
                expl = f"{day_display} at {time_display} — That's one of your strongest focus windows with a clear uninterrupted block."
            elif primary_reason == "deadline_imminent":
                expl = f"{day_display} at {time_display} — Prioritized to protect your upcoming deadline."
            elif primary_reason == "dip_window":
                expl = f"{day_display} at {time_display} — Fits into your afternoon window to maintain momentum without cognitive strain."
            elif primary_reason == "physical_window":
                expl = f"{day_display} at {time_display} — Ideal physical session window with post-workout recovery space."
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

        return best_result

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
