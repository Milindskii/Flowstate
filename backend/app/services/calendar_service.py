"""
Flowstate Calendar & Replan Service
===================================
Orchestration only. Placement decisions are made by the shared pure planner
(``app.engines.planner.plan``); this module:

1. loads a user's tasks (always scoped to ``user.id``) with ONE day-relevance query,
2. renders persisted schedules as stored (no recomputation on read, spec C13),
3. parses a natural-language Replan request into operations and applies them to planner INPUT,
4. maps the planner's result to a PlanDiff (with a server-authored apply request),
5. applies a confirmed diff atomically, idempotently, and re-validated server-side.
"""
import re
import uuid
from dataclasses import replace
from datetime import date, datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..core.config import settings
from ..core.logging import logger
from ..core.timezone import owning_date, resolve_user_timezone
from ..engines.planner import (
    K_COMPLETED,
    completed_interval,
    K_IN_PROGRESS,
    K_LOCKED,
    K_OUT_OF_SCOPE,
    PlanItem,
    PlanResult,
    PlanTemporal,
    plan,
    validate_placements,
)
from ..engines.scheduling_engine import PlanningProfile, SchedulingEngine
from ..models.task import Task, TaskDifficulty, TaskPriority, TaskSource, TaskStatus, TaskType
from ..models.recommendation import RecommendationDecision, RecommendationOutcome
from ..models.task_deviation import TaskDeviation
from ..models.user import User
from ..repositories.readiness_repository import ReadinessRepository
from ..repositories.task_repository import TaskRepository
from ..schemas.calendar import (
    DayCompleteStatus,
    ApplyReplanRequest,
    ApplyReplanResponse,
    DayScheduleItem,
    DayScheduleResponse,
    PlanDiff,
    ReplanClarification,
    ReplanIssue,
    ReplanOperation,
    ReplanRequest,
    ReplanResponse,
    TaskDiffItem,
    TaskScheduleUpdate,
)
from ..schemas.task import TaskCreate, TaskResponse
from ..schemas.today import WorkloadSummary
from . import plan_applications, planning_service, replan_understanding
from .task_state import day_boundary, derive_task_state, slot_has_ended, task_slot_elapsed
from .planning_service import clock_label

REDO_GENERIC_QUERIES = frozenset({"", "task", "the task", "it", "that", "missed", "missed task", "missed one", "the missed one"})
_MATCH_STOPWORDS = frozenset({"the", "my", "a", "an", "of", "on", "to", "and"})
# words that name no particular task: they help a match but never make one on their own
_MATCH_GENERIC = frozenset({"work", "task", "tasks", "thing", "things", "stuff", "session", "one"})


def _stem(word: str) -> str:
    return word[:-1] if len(word) > 3 and word.endswith("s") else word


def _words(text: str) -> List[str]:
    return [_stem(w) for w in re.findall(r"[a-z0-9]+", (text or "").lower())]


def _range_label(start: Optional[datetime], end: Optional[datetime], tz: ZoneInfo) -> Optional[str]:
    """"6:30 PM \u2013 8:30 PM": a diff row always shows the whole interval, not only where it starts."""
    if start is None:
        return None
    if end is None or end <= start:
        return clock_label(start, tz)
    return f"{clock_label(start, tz)} \u2013 {clock_label(end, tz)}"
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

# Limits a Replan request must respect. They mirror TaskCreate's own constraints (a test asserts the
# two never drift apart) so an out-of-range request is refused up front instead of failing later.
MIN_TASK_MINUTES = 5
MAX_TASK_MINUTES = 480
MAX_TITLE_LENGTH = 255
MAX_MESSAGE_LENGTH = 500
MIN_DELAY_MINUTES = 1
MAX_DELAY_MINUTES = 720

# Why a task changed in an applied replan (learning signal + skip history). Anything else is "collateral".
REPLAN_INTENTS = frozenset({"skipped", "deferred", "rescheduled", "delayed", "preference_shift"})


_CLAUSE_VERBS = (r"move|skip|defer|postpone|push|reschedule|keep|make|prioriti[sz]e|leave|don'?t|do not|cancel|redo|re-do|"
                 r"i'?m running|i am running|running|i missed|add|schedule|treat|shift|protect|block")
_CLAUSE_VERB_START = re.compile(rf"^(?:{_CLAUSE_VERBS})\b", re.IGNORECASE)
_CANT_SPLIT = re.compile(
    r"(?:,|;|\band)\s+(?=(?:i\s+|i'?m\s+)?(?:can'?t|cannot|won'?t|not able|unable|no time|"
    r"(?:don'?t|do not) have (?:the |enough |any )?time)\b)", re.IGNORECASE)


def _invalid_request(field: str, code: str, message: str) -> HTTPException:
    """Deterministic, user-safe 422 for a Replan request that cannot be understood or honoured.

    Requests are never silently clamped into a different task: the user is told what to change.
    """
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail={"code": "invalid_replan_request", "errors": [{"field": field, "code": code, "message": message}]},
    )


class CalendarService:
    def __init__(self):
        self.readiness_repo = ReadinessRepository()

    # ── helpers ──────────────────────────────────────────────────────────────

    def resolve(self, user: User, tz_override: Optional[str]) -> Tuple[ZoneInfo, str]:
        return resolve_user_timezone(user, tz_override)

    def get_user_tz(self, user: User, tz_override: Optional[str] = None) -> ZoneInfo:
        return self.resolve(user, tz_override)[0]

    def _now(self, tz: ZoneInfo, supplied: Optional[datetime]) -> datetime:
        if supplied is None:
            return datetime.now(tz)
        return supplied.replace(tzinfo=tz) if supplied.tzinfo is None else supplied.astimezone(tz)

    @staticmethod
    def _bounds(d: date, tz: ZoneInfo) -> Tuple[datetime, datetime]:
        s = datetime.combine(d, time.min, tzinfo=tz).astimezone(timezone.utc)
        e = datetime.combine(d, time.max, tzinfo=tz).astimezone(timezone.utc)
        return s, e

    def _profile(self, db: Session, user: User) -> PlanningProfile:
        return PlanningProfile.from_user_context(
            readiness_profile=self.readiness_repo.get_profile(db, user.id),
            preferences=user.preferences,
        )

    def _render(
        self, it: PlanItem, start: datetime, end: datetime, tz: ZoneInfo, *,
        locked: bool, completed: bool = False, active: bool = False, suggested: bool = False,
        missed: bool = False, commitment: bool = False, state: Optional[str] = None, reason: Optional[str] = None,
        explanation: Optional[str] = None, updated_at: Optional[datetime] = None,
    ) -> DayScheduleItem:
        s = start.astimezone(tz)
        e = end.astimezone(tz)
        if completed:
            tag = "COMPLETED"
        elif locked:
            tag = "FIXED"
        else:
            tag = SchedulingEngine._resolve_tag_text(it.task_type)
        return DayScheduleItem(
            id=f"comp-{it.id}" if completed else f"sched-{it.id}",
            task_id=it.id,
            title=it.title,
            start_time=s,
            end_time=e,
            time=s.strftime("%I:%M").lstrip("0"),
            period=s.strftime("%p"),
            duration_minutes=it.estimated_minutes,
            type=it.task_type,
            tag_text=tag,
            is_fixed=locked or completed,
            time_locked=locked,
            is_commitment=commitment,
            is_completed=completed,
            is_active=active,
            is_suggested=suggested,
            is_missed=missed,
            state=state or ("commitment" if commitment else "completed" if completed else "active" if active else "missed" if missed else "scheduled"),
            primary_reason=reason,
            explanation=explanation,
            expected_updated_at=updated_at,
            anchor_start=s,
        )

    # ── 1. GET DAY SCHEDULE (renders what is persisted) ──────────────────────

    def get_day_schedule(
        self,
        db: Session,
        user: User,
        target_date_str: str,
        timezone_str: Optional[str] = None,
        now_local: Optional[datetime] = None,
    ) -> DayScheduleResponse:
        tz, tz_name = self.resolve(user, timezone_str)
        now_local = self._now(tz, now_local)

        try:
            target_date = datetime.strptime(target_date_str, "%Y-%m-%d").date()
        except Exception:
            target_date = now_local.date()
            target_date_str = target_date.strftime("%Y-%m-%d")

        is_today = target_date == now_local.date()
        is_past = target_date < now_local.date()
        day_start_utc, day_end_utc = self._bounds(target_date, tz)
        start_of_day_local = datetime.combine(target_date, time.min, tzinfo=tz)

        open_rows = TaskRepository.list_open_for_day(db, user.id, target_date, day_start_utc, day_end_utc, is_today)
        done_rows = TaskRepository.list_completed_for_day(db, user.id, target_date, day_start_utc, day_end_utc)
        profile = self._profile(db, user)

        timeline_items: List[DayScheduleItem] = []
        completed_items: List[DayScheduleItem] = []
        unslotted: List[Task] = []
        row_by_id = {str(t.id): t for t in open_rows}

        for ct in done_rows:
            it = planning_service.task_row_to_plan_item(ct, tz=tz)
            slot_s = ct.started_at or ct.scheduled_start or start_of_day_local
            raw_start, raw_end = completed_interval(
                ct.started_at, ct.completed_at, ct.scheduled_start or start_of_day_local,
                ct.scheduled_end if ct.scheduled_start else None, ct.estimated_minutes)
            if raw_end is None:
                raw_start, raw_end = slot_s, slot_s + timedelta(minutes=ct.estimated_minutes)
            done_item = self._render(
                it, raw_start, raw_end, tz, locked=True, completed=True,
                reason="completed_session", explanation="Completed task session.", updated_at=ct.updated_at)
            # its stop stays where it was planned on this day, not where the session happened to run
            if it.start is not None and it.start.astimezone(tz).date() == target_date:
                done_item.anchor_start = it.start.astimezone(tz)
            completed_items.append(done_item)

        for t in open_rows:
            it = planning_service.task_row_to_plan_item(t, tz=tz)
            active = t.status == TaskStatus.in_progress
            if t.scheduled_start is not None:
                start = t.scheduled_start
                end = t.scheduled_end or (start + timedelta(minutes=t.estimated_minutes))
                state = derive_task_state(
                    completed=False, cancelled=False, active=active, start=start, end=end, now=now_local,
                    day_boundary=day_boundary(start.astimezone(tz).date(), tz, profile.bedtime),
                    commitment=bool(t.is_commitment))
                missed = state == "missed"
                locked = bool(t.time_locked)
                timeline_items.append(self._render(
                    it, start, end, tz, locked=locked, active=active, missed=missed, state=state,
                    commitment=bool(t.is_commitment),
                    reason="explicit_time" if locked else "scheduled",
                    explanation=(f"Fixed at {clock_label(start, tz)}." if locked else f"Scheduled at {clock_label(start, tz)}."),
                    updated_at=t.updated_at))
            elif active:
                start = t.started_at or now_local
                timeline_items.append(self._render(
                    it, start, start + timedelta(minutes=t.estimated_minutes), tz, locked=False, active=True,
                    reason="in_progress", explanation="In progress.", updated_at=t.updated_at))
            else:
                unslotted.append(t)

        # Tasks without a stored slot get a SUGGESTED placement (never persisted, flagged is_suggested).
        unscheduled_items: List[DayScheduleItem] = []
        if unslotted and not is_past:
            plan_items = [
                replace(planning_service.task_row_to_plan_item(t, tz=tz), pinned=True)
                for t in open_rows if t.scheduled_start is not None
            ]
            plan_items += [planning_service.task_row_to_plan_item(t, tz=tz) for t in done_rows]
            plan_items += [replace(planning_service.task_row_to_plan_item(t, tz=tz), is_new=True) for t in unslotted]
            ref = max(now_local, start_of_day_local) if is_today else start_of_day_local
            by_id = {i.id: i for i in plan_items}
            try:
                result = plan(plan_items, now_local=ref, tz=tz, profile=profile, mode="build", tz_name=tz_name)
            except Exception as exc:  # rendering the day must never fail because suggestions failed
                logger.exception(f"Day view suggestion planning failed for user {user.id}: {type(exc).__name__}")
                result = PlanResult(placements=(), immutable=(), unscheduled=(), conflicts=(), timezone_used=tz_name, mode="build")
            for p in result.placements:
                if p.start.astimezone(tz).date() != target_date:
                    continue
                it = by_id[p.item_id]
                timeline_items.append(self._render(
                    it, p.start, p.end, tz, locked=False, suggested=True,
                    reason=p.primary_reason, explanation=p.explanation,
                    updated_at=row_by_id[p.item_id].updated_at))
            placed_ids = {p.item_id for p in result.placements if p.start.astimezone(tz).date() == target_date}
            for t in unslotted:
                if str(t.id) not in placed_ids:
                    it = by_id[str(t.id)]
                    item = self._render(it, start_of_day_local, start_of_day_local + timedelta(minutes=t.estimated_minutes), tz,
                                        locked=False, reason="insufficient_capacity",
                                        explanation="Could not be scheduled within available focus blocks.",
                                        updated_at=t.updated_at)
                    item.tag_text, item.time, item.period, item.is_conflict = "UNSCHEDULED", "--:--", "", True
                    unscheduled_items.append(item)
        elif unslotted:
            for t in unslotted:
                it = planning_service.task_row_to_plan_item(t, tz=tz)
                item = self._render(it, start_of_day_local, start_of_day_local + timedelta(minutes=t.estimated_minutes), tz,
                                    locked=False, reason="no_slot", explanation="No time was set.", updated_at=t.updated_at)
                item.tag_text, item.time, item.period, item.is_conflict = "UNSCHEDULED", "--:--", "", True
                unscheduled_items.append(item)

        deviation_items = self._deviation_items(db, user, target_date, tz, {i.task_id for i in timeline_items + completed_items + unscheduled_items})

        timeline_items.sort(key=lambda x: x.start_time)
        all_timeline = sorted(timeline_items + completed_items, key=lambda x: x.start_time)
        fixed_commitments = [i for i in timeline_items if i.time_locked]
        remaining_tasks = [i for i in timeline_items if not i.time_locked]

        total_planned = sum(t.duration_minutes for t in timeline_items if not t.is_commitment)
        wake_h = profile.weekend_wake_time if target_date.weekday() >= 5 else profile.weekday_wake_time
        bed_h = profile.bedtime
        total_day_avail_mins = int((bed_h - wake_h) * 60)
        if is_today:
            now_h = now_local.hour + now_local.minute / 60.0
            rem_capacity = int(max(0.0, bed_h - max(now_h, wake_h)) * 60)
        elif is_past:
            rem_capacity = 0
        else:
            rem_capacity = total_day_avail_mins

        hours_p, mins_p = total_planned // 60, total_planned % 60
        f_workload = f"{hours_p}h {mins_p}m planned" if hours_p > 0 else f"{mins_p}m planned"
        is_overloaded = total_planned > max(rem_capacity, 60)
        workload = WorkloadSummary(
            planned_minutes=total_planned,
            formatted_workload=f_workload,
            message="Your day looks manageable." if not is_overloaded else f"Planned workload ({f_workload}) exceeds available capacity.",
            is_overloaded=is_overloaded,
            available_minutes=rem_capacity,
        )

        focus_window = f"{profile.preferred_peak_start}:00 – {profile.preferred_peak_end}:00"
        try:
            sd = datetime.combine(target_date, time(int(profile.preferred_peak_start), int((profile.preferred_peak_start % 1) * 60)))
            ed = datetime.combine(target_date, time(int(profile.preferred_peak_end), int((profile.preferred_peak_end % 1) * 60)))
            focus_window = f"{sd.strftime('%I:%M %p').lstrip('0')} – {ed.strftime('%I:%M %p').lstrip('0')}"
        except Exception:
            pass

        return DayScheduleResponse(
            date=target_date_str, is_today=is_today, is_past=is_past,
            timeline=all_timeline, fixed_commitments=fixed_commitments, completed_tasks=completed_items,
            remaining_tasks=remaining_tasks, unscheduled_tasks=unscheduled_items, deviations=deviation_items, conflicts=[],
            workload=workload, focus_window=focus_window, readiness_score=None,
            total_planned_minutes=total_planned, remaining_capacity_minutes=rem_capacity,
            timezone_used=tz_name,
            day_complete=self.day_complete_status(db, user, target_date, tz, now_local,
                                                  open_rows=open_rows, done_rows=done_rows),
        )

    def day_complete_status(self, db: Session, user: User, day: date, tz: ZoneInfo,
                            now_local: datetime, *, open_rows: Optional[List[Task]] = None,
                            done_rows: Optional[List[Task]] = None) -> DayCompleteStatus:
        """Every task the day owns is done (commitments are not work) and at least one was completed."""
        from ..core.economy_config import DAY_COMPLETE_XP
        from ..models.flow_progression import FlowEconomicEvent

        d_start, d_end = self._bounds(day, tz)
        if open_rows is None:  # the day view passes the rows it already loaded (same query)
            open_rows = TaskRepository.list_open_for_day(db, user.id, day, d_start, d_end, day == now_local.date())
        if done_rows is None:
            done_rows = TaskRepository.list_completed_for_day(db, user.id, day, d_start, d_end)
        claimed = db.query(FlowEconomicEvent.id).filter(
            FlowEconomicEvent.user_id == user.id, FlowEconomicEvent.event_type == "day_complete",
            FlowEconomicEvent.reference_id == day.isoformat()).first() is not None
        eligible = (day <= now_local.date() and any(not t.is_commitment for t in done_rows)
                    and not any(not t.is_commitment for t in open_rows))
        return DayCompleteStatus(eligible=eligible or claimed, claimed=claimed, xp=DAY_COMPLETE_XP)

    def _deviation_items(self, db: Session, user: User, day: date, tz: ZoneInfo, on_day: set) -> List[DayScheduleItem]:
        """Tasks skipped/deferred/missed at an original slot of ``day`` (latest record per task, per missed slot).

        Display-only history. It is returned even when the task is still on this day (a skip that landed later today,
        a Redo): the Calendar day path merges it with the live item into ONE stop at the original slot, so a skipped or
        bypassed stop never leaves its place. Cancelled/deleted tasks and records with no slot to show are left out.

        A ghost for a task that has no live item on ``day`` takes the live item's id (``sched-<task id>``), so the stop
        keeps its identity when the task moves off the day.
        """
        rows = (db.query(TaskDeviation, Task).join(Task, Task.id == TaskDeviation.task_id)
                .filter(TaskDeviation.user_id == user.id, TaskDeviation.deviation_date == day,
                        TaskDeviation.original_start.isnot(None),
                        Task.status.notin_([TaskStatus.cancelled, TaskStatus.archived]))
                .order_by(TaskDeviation.created_at.asc()).all())
        latest: Dict[str, Tuple[TaskDeviation, Task]] = {}
        for dev, t in rows:
            if dev.kind == "missed":
                # each missed occurrence is its own slot, whatever the task's current slot is
                latest[f"{t.id}:{dev.original_start}"] = (dev, t)
            else:
                latest[str(t.id)] = (dev, t)
        items: List[DayScheduleItem] = []
        named: set = set()
        for dev, t in sorted(latest.values(), key=lambda p: p[0].original_start):
            it = planning_service.task_row_to_plan_item(t, tz=tz)
            end = dev.original_end or dev.original_start + timedelta(minutes=t.estimated_minutes)
            missed = dev.kind == "missed"
            item = self._render(it, dev.original_start, end, tz, locked=False, missed=missed, state=dev.kind, reason=dev.kind,
                                explanation=("Missed at its original time" if missed else f"{dev.kind.capitalize()} today") + (
                                    f"; planned for {dev.moved_to_date.isoformat()}." if dev.moved_to_date else "."))
            keeps_identity = str(t.id) not in on_day and str(t.id) not in named
            named.add(str(t.id))
            item.id = f"sched-{t.id}" if keeps_identity else f"dev-{dev.id}"
            item.tag_text, item.deviation, item.is_skipped = dev.kind.upper(), dev.kind, not missed
            items.append(item)
        return sorted(items, key=lambda x: x.start_time)

    # ── 2. REPLAN DELTA PARSING ──────────────────────────────────────────────

    def parse_replan_instruction(self, user_message: str) -> List[ReplanOperation]:
        """Parses natural language into structured ReplanOperations (deterministic rules).

        A message may carry several instructions ("move X later, keep Y as the priority, and leave 6:30 to
        8:30 untouched"): it is split into clauses and every understood clause contributes its operations.
        Sentences that only give context ("I underestimated how long ...") are ignored; an instruction-shaped
        clause that cannot be acted on is reported back (`unparsed`) instead of failing the whole request.
        """
        msg = user_message.strip()
        if not msg:
            raise _invalid_request("user_message", "empty_message", "Tell me what you'd like to change about your day.")
        if len(msg) > MAX_MESSAGE_LENGTH:
            raise _invalid_request(
                "user_message", "message_too_long",
                f"Please keep your request under {MAX_MESSAGE_LENGTH} characters.")
        clauses = self._split_replan_clauses(msg)
        operations: List[ReplanOperation] = []
        for clause in clauses:
            got = self._parse_replan_clause(clause, solo=len(clauses) == 1)
            if got:
                operations.extend(got)
            elif len(clauses) > 1 and _CLAUSE_VERB_START.match(clause):
                operations.append(ReplanOperation(op="unparsed", title=clause))
        # "I'm running late" with no amount is context for the other instructions, not a blanket shift
        if any(o.op not in ("unparsed", "delay_remaining_schedule") for o in operations):
            operations = [o for o in operations if o.intent != "bare"]
        if not any(o.op != "unparsed" for o in operations):
            raise _invalid_request(
                "user_message", "unrecognized_instruction",
                "I didn't understand that change. Try “skip gym”, “move essay to friday”, "
                "“running 20 min late” or “add a 30 min call at 5pm”.")
        return operations

    @staticmethod
    def _split_replan_clauses(msg: str) -> List[str]:
        parts: List[str] = []
        splitter = rf",?\s+(?:and\s+)?(?=(?:{_CLAUSE_VERBS})\b)"
        for sentence in re.split(r'(?<=[.!?])\s+|;\s*', msg.strip()):
            for piece in re.split(splitter, sentence.strip(), flags=re.IGNORECASE):
                # "... and I can't go out" / ", no time for cleaning": a new clause even without a leading verb
                for sub in _CANT_SPLIT.split((piece or "").strip()):
                    sub = (sub or "").strip()
                    if sub:
                        parts.append(sub)
        out: List[str] = []
        for part in parts:
            lower = part.lower().rstrip('.!?,; ')
            lower = re.sub(r'^(?:please|pls|can you|could you)\s+', '', lower)
            lower = re.sub(r'[\s,]+(?:please|pls|thanks|thank you)$', '', lower)
            lower = re.sub(r'(?:[\s,]+and)?(?:\s+i)?$', '', lower)  # "gym at 8 and i" | "don't have time ..."
            if lower:
                out.append(lower)
        return out

    def _parse_replan_clause(self, lower: str, *, solo: bool) -> Optional[List[ReplanOperation]]:
        """One clause -> operations, or None when it is not an instruction this parser understands."""
        operations: List[ReplanOperation] = []

        m_late = re.search(r'running\s+(\d+)\s*(?:m|min|mins|minutes?)?\s*late', lower)
        if m_late:
            delay = int(m_late.group(1))
            if not MIN_DELAY_MINUTES <= delay <= MAX_DELAY_MINUTES:
                raise _invalid_request(
                    "delay", "invalid_delay",
                    f"I can shift your day by {MIN_DELAY_MINUTES} minute to {MAX_DELAY_MINUTES // 60} hours. "
                    f"{delay} minutes is outside that range.")
            operations.append(ReplanOperation(op="delay_remaining_schedule", delay_minutes=delay))
            return operations
        elif "running late" in lower:
            # no amount given: a default shift only when nothing else was asked (see parse_replan_instruction)
            operations.append(ReplanOperation(op="delay_remaining_schedule", delay_minutes=30, intent="bare"))
            return operations

        # "leave going out untouched": protect a task/commitment by name
        m_keep = re.match(
            r"^(?:leave|keep|don'?t (?:touch|move))\s+(?:the\s+|my\s+)?(.+?)\s+(?:untouched|alone|as is|where it is|fixed)$", lower)
        if m_keep and not re.search(r"\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s*(?:to|-|–|until|till)\s*\d", lower):
            operations.append(ReplanOperation(op="protect_task", task_query=m_keep.group(1).strip()))
            return operations
        # "don't touch going out" (no "untouched"/"alone" suffix)
        m_touch = re.match(r"^(?:don'?t|do not)\s+(?:touch|change|move)\s+(?:the\s+|my\s+)?([a-z][\w' ]*?)$", lower)
        if m_touch and not re.search(r"\d", lower):
            operations.append(ReplanOperation(op="protect_task", task_query=m_touch.group(1).strip()))
            return operations

        # "leave the 6:30 to 8:30 outing untouched": a block the planner must keep clear.
        m_block = re.search(
            r"\b(?:leave|keep|protect|block(?: off)?|don'?t (?:touch|schedule|move)(?: anything)?)\b.*?"
            r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:to|-|\u2013|until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", lower)
        if m_block:
            def _clock(h: str, mi: Optional[str], ap: Optional[str]) -> Tuple[int, int]:
                hh, mm = int(h), int(mi or 0)
                if not (0 <= hh <= 23 and 0 <= mm <= 59):
                    raise _invalid_request("time", "invalid_time", "I couldn't read that time range. Try \u201c6:30 to 8:30 PM\u201d.")
                if ap:
                    hh = hh % 12 + (12 if ap == "pm" else 0)
                elif hh <= 7:
                    hh += 12
                return hh, mm
            sh, sm = _clock(m_block.group(1), m_block.group(2), m_block.group(3) or m_block.group(6))
            eh, em = _clock(m_block.group(4), m_block.group(5), m_block.group(6) or m_block.group(3))
            if (eh, em) <= (sh, sm) and eh < 12:
                eh += 12
            if (eh, em) > (sh, sm):
                operations.append(ReplanOperation(
                    op="protect_block", block_start=f"{sh:02d}:{sm:02d}", block_end=f"{eh:02d}:{em:02d}"))
                return operations

        m_prio = (re.match(r"^(?:keep|make|treat)\s+(?:the\s+|my\s+)?(.+?)\s+(?:as\s+)?(?:the\s+|my\s+)?(?:top\s+|first\s+)?priority$", lower)
                  or re.match(r"^prioriti[sz]e\s+(?:the\s+|my\s+)?(.+)$", lower)
                  or re.match(r"^(?:keep|put)\s+(?:the\s+|my\s+)?(.+?)\s+first$", lower))
        if m_prio:
            operations.append(ReplanOperation(op="prioritize", task_query=m_prio.group(1).strip()))
            return operations

        m_later = re.match(
            r"^(?:move|push|shift)\s+(?:the\s+|my\s+)?(.+?)\s+later(?:\s+(?:today|this\s+(?:afternoon|evening)))?$", lower)
        if m_later:
            operations.append(ReplanOperation(op="move_later", task_query=m_later.group(1).strip(), intent="delayed"))
            return operations

        # "I missed gym" / "redo gym" / "redo the missed task": put a task whose time passed back into the day.
        m_redo = re.match(r"^(?:i\s+)?(missed|redo|re-do)\s+(?:the\s+|my\s+)?(.+?)(?:\s+(?:now|again))?$", lower)
        if m_redo:
            operations.append(ReplanOperation(
                op="redo_task", task_query=m_redo.group(2).strip(),
                intent="rescheduled" if m_redo.group(1) == "missed" else "delayed"))
            return operations

        # skip / defer / postpone / push / reschedule / move X [to <day>]: never a cancellation; the task
        # moves to that day (default tomorrow) and today keeps a skipped/deferred history node.
        days = r'tomorrow|later this week|' + '|'.join(WEEKDAYS)
        m_dated = re.search(
            r'\b(skip|defer|postpone|push|reschedule|move)\s+(?:the\s+|my\s+)?([a-z0-9\s]+?)\s+(?:to|until|till|for)\s+'
            rf'(?:next\s+)?({days})$', lower)
        m_bare = re.search(r'\b(skip|defer|postpone|push back)\s+(?:the\s+|my\s+)?([a-z0-9\s]+?)(?:\s+(?:for\s+)?today)?$', lower)
        m_defer = m_dated or m_bare
        if m_defer:
            verb = m_defer.group(1)
            target = m_dated.group(3) if m_dated else "tomorrow"
            operations.append(ReplanOperation(
                op="move_task_date", task_query=m_defer.group(2).strip(),
                target_date="tomorrow" if target == "later this week" else target,
                intent={"skip": "skipped", "move": "rescheduled", "reschedule": "rescheduled"}.get(verb, "deferred")))
            return operations

        m_cancel = re.search(r'cancel\s+(?:the\s+)?([a-zA-Z0-9\s]+?)(?:\s+today)?$', lower)
        if m_cancel:
            operations.append(ReplanOperation(op="cancel_task", task_query=m_cancel.group(1).strip()))
            return operations

        m_move_pref = re.search(r'move\s+([a-zA-Z0-9\s]+?)\s+to\s+(morning|afternoon|evening|night|tonight)', lower)
        if m_move_pref:
            operations.append(ReplanOperation(op="shift_task_preference", task_query=m_move_pref.group(1).strip(),
                                              preferred_window="evening" if m_move_pref.group(2).strip() == "tonight" else m_move_pref.group(2).strip(),
                                              constraint_value="tonight" if m_move_pref.group(2).strip() == "tonight" else None))
            return operations

        m_push_meal = re.search(r'(?:push|move|schedule)\s+(?:the\s+)?([a-zA-Z0-9\s]+?)\s+after\s+(dinner|lunch|breakfast)', lower)
        if m_push_meal:
            operations.append(ReplanOperation(op="add_constraint", task_query=m_push_meal.group(1).strip(),
                                              constraint_type="relative_after", constraint_value=m_push_meal.group(2).strip()))
            return operations

        # Anything left must say it adds work; otherwise refuse instead of inventing a task from the text.
        lead = r"^(?:i have|i've got|i need to|need to|i just got|i must|add|schedule|new task|urgent)\b"
        if re.search(r"\b(?:longer|more time|extra time|running over|run over|runs over)\b", lower) \
                and not re.search(lead, lower):
            return None  # "essay will take 30 minutes longer" is about an existing task, not new work
        add_signal = re.search(lead, lower) or (solo and re.search(
            r"\burgent\b|\d+\s*(?:h|hr|hours?|m|mins|minutes?)\b|\b(?:at|around|before|by)\s+\d", lower))
        if not add_signal:
            return None

        dur_mins = 60
        m_dur = re.search(r'(\d+)\s*(?:h|hr|hours?|m|mins|minutes?)', lower)
        if m_dur:
            dur_val = int(m_dur.group(1))
            dur_mins = dur_val * 60 if "h" in m_dur.group(0) else dur_val
            if not MIN_TASK_MINUTES <= dur_mins <= MAX_TASK_MINUTES:
                raise _invalid_request(
                    "duration", "invalid_duration",
                    f"I can plan tasks between {MIN_TASK_MINUTES} minutes and {MAX_TASK_MINUTES // 60} hours. "
                    f"{m_dur.group(0).strip()} is outside that range.")

        m_time = re.search(r'\b(at|around|before|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', lower)
        target_time_str = None
        constraint_type = "preferred_start"
        if m_time:
            kind = m_time.group(1)
            th = int(m_time.group(2))
            tm = int(m_time.group(3) or 0)
            ampm = m_time.group(4)
            hour_ok = (1 <= th <= 12) if ampm else (0 <= th <= 23)
            if not hour_ok or not 0 <= tm <= 59:
                raise _invalid_request(
                    "time", "invalid_time",
                    f"I couldn't read \u201c{m_time.group(0).strip()}\u201d as a time. Try something like \u201cat 6 PM\u201d.")
            if ampm:
                if ampm.lower() == "pm" and th < 12:
                    th += 12
                elif ampm.lower() == "am" and th == 12:
                    th = 0
            elif th <= 7:
                th += 12
            target_time_str = f"{th:02d}:{tm:02d}"
            # Lock source L4: only "at" is a fixed time. "around" = preference, "before/by" = latest end.
            constraint_type = {"at": "fixed_start", "around": "preferred_start"}.get(kind, "latest_end")

        clean_title = re.sub(r'^(?:i have|i need to do|i just got|urgent|please add|add)\s+', '', lower, flags=re.IGNORECASE).strip()
        clean_title = re.sub(r'\b(?:needs?|for)?\s*\d+\s*(?:h|hr|hours?|m|mins|minutes?)\b', '', clean_title).strip()
        clean_title = re.sub(r'\b(?:at|around|before|by)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b', '', clean_title).strip()
        title_str = clean_title.strip().capitalize()
        if not title_str or len(title_str) < 3:
            title_str = "Urgent work"
        if len(title_str) > MAX_TITLE_LENGTH:
            raise _invalid_request(
                "title", "title_too_long",
                f"Task names can be up to {MAX_TITLE_LENGTH} characters. Please shorten it.")

        operations.append(ReplanOperation(
            op="add_task", title=title_str, duration_minutes=dur_mins, priority="urgent",
            task_type="deep_work", target_time=target_time_str, constraint_type=constraint_type,
        ))
        return operations

    @staticmethod
    def _ai_understand(db: Session, user: User, message: str, entities: List[PlanItem], now_local: datetime,
                       tz: ZoneInfo):
        """Semantic understanding (language model) for a message the deterministic layers could not read.

        Metered: per-minute guard + a daily budget separate from Build My Day credits. Over budget, disabled or on
        any provider problem it returns None and the deterministic answer stands (never an error of its own).
        """
        from . import ai_gateway, replan_ai
        from .ai_economy_service import AIEconomyService, effective_is_pro

        if not (settings.REPLAN_AI_ENABLED and settings.GEMINI_API_KEY) or not entities:
            return None
        if not replan_ai.allow_request(str(user.id)):
            return None
        try:
            is_pro = effective_is_pro(AIEconomyService.get_or_create_usage(db, user.id))
            cap = replan_ai.PRO_REPLAN_AI_PER_DAY if is_pro else replan_ai.FREE_REPLAN_AI_PER_DAY
            allowed = ai_gateway.consume_period(db, user.id, "replan_day", cap)
            db.commit()  # also ends the transaction: no pooled connection is held during the provider call
        except Exception as exc:
            db.rollback()
            logger.warning(f"replan_ai budget check failed: {type(exc).__name__}")
            return None
        if not allowed:
            return None
        return replan_ai.interpret(message, entities, now_local, tz, request_id=uuid.uuid4().hex[:12])

    # words that never name new work on their own ("ugh, behind schedule again")
    _JUNK_TITLE_WORDS = frozenset({"schedule", "again", "behind", "ugh", "hmm", "everything", "stuff", "things",
                                   "something", "whatever"})

    @classmethod
    def _doubtful_new_task(cls, operations: List[ReplanOperation], entities: List[PlanItem],
                           message: str) -> Optional[str]:
        """'existing' when a rule-made new task is really about a task already in the plan, 'nameless' when its
        title names nothing, else None. A message that says "add" / "new task" itself is never doubted."""
        if re.search(r"\b(?:add|new task|create|i have|i've got|i just got)\b", (message or "").lower()):
            return None
        for o in operations:
            if o.op != "add_task" or not o.title:
                continue
            words = {w for w in _words(o.title) if w not in _MATCH_STOPWORDS}
            content = {w for w in words if w not in replan_understanding._NOISE}
            if (content and content <= cls._JUNK_TITLE_WORDS and not re.search(r"\d|urgent", message.lower())):
                return "nameless"
            content -= cls._JUNK_TITLE_WORDS
            if any(content & {w for w in _words(e.title) if w not in _MATCH_STOPWORDS} for e in entities):
                return "existing"
        return None

    def _understand_clauses(self, message: str, entities: List[PlanItem], row_by_id: Dict[str, Task],
                            now_local: datetime, target_is_today: bool):
        """Clause-by-clause reading of a compound message against today's plan.

        Returns None when it does not apply (one clause, or the rules understood every clause: the existing flow
        stands untouched), a ReplanClarification when a recognised task is missing a detail (its options carry the
        other clauses so nothing already understood is lost), else the combined operations. A clause no layer can
        read but that asks for something stays `unparsed` (reported back, or read by the semantic layer).
        """
        clauses = self._split_replan_clauses(message)
        if len(clauses) < 2:
            return None
        meta = lambda it: _words(f"{getattr(row_by_id.get(it.id), 'category', '') or ''} "  # noqa: E731
                                 f"{getattr(row_by_id.get(it.id), 'description', '') or ''}")
        per_clause: List[Optional[List[ReplanOperation]]] = []
        for c in clauses:
            got = self._parse_replan_clause(c, solo=False)
            if got and self._doubtful_new_task(got, entities, c):
                got = None  # "gym at 8" is the existing Gym, not new work
            per_clause.append(got or None)
        if all(per_clause):
            return None

        operations: List[ReplanOperation] = []
        for i, (c, got) in enumerate(zip(clauses, per_clause)):
            if got:
                operations.extend(got)
                continue
            u = replan_understanding.understand(c, entities, meta, now_local, target_is_today)
            if u is not None and u.operations:
                operations.extend(u.operations)
            elif u is not None and u.clarification is not None and not u.vague:
                others = [x for j, x in enumerate(clauses) if j != i]
                return self._carry_clauses(u.clarification, others)
            # a vague fragment ("which task?") is left to the whole-message readers / semantic layer
            elif (u is not None and u.vague) or _CLAUSE_VERB_START.match(c) or replan_understanding.asks_for_change(c):
                operations.append(ReplanOperation(op="unparsed", title=c))
            # else: context only ("I underestimated how long this takes")
        if any(o.op not in ("unparsed", "delay_remaining_schedule") for o in operations):
            operations = [o for o in operations if o.intent != "bare"]
        if not any(o.op != "unparsed" for o in operations):
            return None  # nothing understood clause by clause: the whole-message readers decide
        return operations

    @staticmethod
    def _carry_clauses(clar: ReplanClarification, others: List[str]) -> ReplanClarification:
        """Each option's follow-up message keeps the other clauses, so answering never drops understood work."""
        if not others:
            return clar
        lead = ", ".join(others)
        opts = [o.model_copy(update={
            "message": f"{lead}, {o.message}" if o.message else o.message,
            "prefill": f"{lead}, {o.prefill}" if o.prefill else o.prefill,
        }) for o in clar.options]
        return clar.model_copy(update={"options": opts})

    @staticmethod
    def _is_unrecognized(exc: HTTPException) -> bool:
        detail = exc.detail if isinstance(exc.detail, dict) else {}
        return any(e.get("code") == "unrecognized_instruction" for e in detail.get("errors", []))

    @staticmethod
    def _clarification_response(request: ReplanRequest, plan_id: str, before_schedule: List[DayScheduleItem],
                                tz_name: str, clarification: ReplanClarification) -> ReplanResponse:
        """No proposal yet: Noya asks for the one missing detail (or a choice) and offers task-specific options."""
        diff = PlanDiff(
            plan_id=plan_id, selected_date=request.selected_date, created_at=datetime.now(timezone.utc),
            before_schedule=before_schedule, after_schedule=before_schedule,
            explanation=clarification.question, timezone_used=tz_name, clarification=clarification)
        return ReplanResponse(success=True, plan_diff=diff, user_intent_summary=request.user_message)

    @staticmethod
    def _resolve_dest_date(token: Optional[str], base: date) -> date:
        t = (token or "tomorrow").strip().lower()
        if t == "tomorrow":
            return base + timedelta(days=1)
        if t in WEEKDAYS:
            ahead = (WEEKDAYS.index(t) - base.weekday()) % 7
            return base + timedelta(days=ahead or 7)
        try:
            return datetime.strptime(t, "%Y-%m-%d").date()
        except ValueError:
            return base + timedelta(days=1)

    # ── 3. GENERATE REPLAN (dry run; never writes) ───────────────────────────

    def generate_replan(self, db: Session, user: User, request: ReplanRequest) -> ReplanResponse:
        tz, tz_name = self.resolve(user, request.timezone)
        now_local = self._now(tz, request.current_local_time)
        try:
            target_date = datetime.strptime(request.selected_date, "%Y-%m-%d").date()
        except Exception:
            target_date = now_local.date()
            request.selected_date = target_date.strftime("%Y-%m-%d")

        before_resp = self.get_day_schedule(db, user, request.selected_date, tz_name, now_local=now_local)
        before_schedule = before_resp.timeline

        plan_id = str(uuid.uuid4())

        def _empty(conflict: str, kind: str = "note") -> ReplanResponse:
            diff = PlanDiff(
                plan_id=plan_id, selected_date=request.selected_date, created_at=datetime.now(timezone.utc),
                before_schedule=before_schedule, after_schedule=before_schedule, conflicts=[conflict],
                issues=[ReplanIssue(kind=kind, message=conflict)],
                explanation=conflict, timezone_used=tz_name,
                apply_request=ApplyReplanRequest(plan_id=plan_id, selected_date=request.selected_date, timezone=tz_name),
            )
            return ReplanResponse(success=True, plan_diff=diff, user_intent_summary=request.user_message)

        if target_date < now_local.date():
            return _empty("Past days can't be replanned.", "past")

        # Working set: the SAME query the day view uses (finding 7), plus completed work (immutable busy time).
        d_start, d_end = self._bounds(target_date, tz)
        open_rows = TaskRepository.list_open_for_day(db, user.id, target_date, d_start, d_end, target_date == now_local.date())
        done_rows = TaskRepository.list_completed_for_day(db, user.id, target_date, d_start, d_end)
        row_by_id: Dict[str, Task] = {str(t.id): t for t in open_rows + done_rows}
        items: List[PlanItem] = [planning_service.task_row_to_plan_item(t, tz=tz) for t in open_rows + done_rows]

        qa = request.quick_add
        if qa is not None:
            title = qa.title.strip()
            if not title:
                raise _invalid_request("quick_add", "empty_title", "Give the task a name first.")
            operations = [ReplanOperation(
                op="add_task", title=title, duration_minutes=qa.duration_minutes, priority="urgent",
                task_type="deep_work", target_time=qa.start_time,
                constraint_type="fixed_start" if qa.start_time else "preferred_start")]
        else:
            plan_entities = [i for i in items if not i.is_new and i.status in ("todo", "postponed")]

            def read_plan_aware():
                """Deterministic plan-aware reading, then (only when that is vague or empty) the semantic layer."""
                found = replan_understanding.understand(
                    request.user_message, plan_entities,
                    lambda it: _words(f"{getattr(row_by_id.get(it.id), 'category', '') or ''} "
                                      f"{getattr(row_by_id.get(it.id), 'description', '') or ''}"),
                    now_local, target_date == now_local.date())
                if found is None or found.vague:
                    ai = self._ai_understand(db, user, request.user_message, plan_entities, now_local, tz)
                    if ai is not None:
                        found = ai
                return found

            rules_error: Optional[HTTPException] = None
            operations = []
            try:
                operations = self.parse_replan_instruction(request.user_message)
            except HTTPException as exc:
                # The context-free rules found nothing: look at what the message names in TODAY's plan before giving up.
                if not self._is_unrecognized(exc):
                    raise
                rules_error = exc

            # A compound message ("can't go out, move gym to 8") is read clause by clause against the plan, so a
            # clause the context-free rules skip is neither lost nor allowed to hijack the whole message.
            compound = self._understand_clauses(request.user_message, plan_entities, row_by_id, now_local,
                                                target_date == now_local.date())
            if compound is not None:
                if isinstance(compound, ReplanClarification):
                    return self._clarification_response(request, plan_id, before_schedule, tz_name, compound)
                operations, rules_error = compound, None

            doubtful = (None if rules_error or compound is not None
                        else self._doubtful_new_task(operations, plan_entities, request.user_message))
            if rules_error is not None or doubtful:
                # "gym should happen at 8" names an existing task and "behind schedule again" names nothing: neither
                # is new work, so the message is read against the plan instead of inventing a task from the text.
                understood = read_plan_aware()
                if understood is not None and understood.clarification is not None:
                    return self._clarification_response(
                        request, plan_id, before_schedule, tz_name, understood.clarification)
                if understood is not None and understood.operations:
                    operations = understood.operations
                elif rules_error is not None:
                    raise rules_error
                elif doubtful == "nameless":
                    raise _invalid_request(
                        "user_message", "unrecognized_instruction",
                        "I didn't understand that change. Try “skip gym”, “move essay to friday”, "
                        "“running 20 min late” or “add a 30 min call at 5pm”.")
            elif any(o.op == "unparsed" for o in operations):
                # part of a compound message was not understood: let the semantic layer read the whole message
                ai = self._ai_understand(db, user, request.user_message, plan_entities, now_local, tz)
                if ai is not None and ai.clarification is not None:
                    return self._clarification_response(request, plan_id, before_schedule, tz_name, ai.clarification)
                if ai is not None and ai.operations:
                    operations = ai.operations
        # cancellations first: time a cancelled task frees is available to the moves in the same message,
        # whatever order the user said them in ("move gym to 8 and I can't go out")
        operations = sorted(operations, key=lambda o: o.op != "cancel_task")
        conflicts: List[str] = []
        issues: List[ReplanIssue] = []
        failed_queries: set = set()
        unparsed_ops: List[ReplanOperation] = []

        def note(kind: str, message: str) -> None:
            conflicts.append(message)
            issues.append(ReplanIssue(kind=kind, message=message))

        def ambiguous(query: Optional[str], message: str) -> None:
            failed_queries.add((query or "").strip().lower())
            note("ambiguous", message)

        cancelled_items: List[TaskDiffItem] = []
        cancel_ids: List[str] = []
        date_moves: Dict[str, date] = {}
        explicit_ops: set = set()  # item ids whose lock may be overridden (user named the task)
        extra_pinned: List[PlanItem] = []
        protected_blocks: List[Tuple[datetime, datetime]] = []  # windows the user said to keep clear
        intents: Dict[str, str] = {}  # task_id -> why the user changed it (learning signal, skip history)

        def idx_of(item_id: str) -> int:
            return next(n for n, i in enumerate(items) if i.id == item_id)

        def note_missing(query: Optional[str]) -> None:
            q = (query or "").strip().lower()
            failed_queries.add(q)
            words = [w for w in _words(q) if w not in _MATCH_STOPWORDS]
            fixed = [i for i in items if i.is_commitment and words and all(w in _words(i.title) for w in words)]
            if fixed:
                note("protected", f"\u201c{fixed[0].title}\u201d is a fixed commitment, so I left it exactly as it is.")
            else:
                note("not_found", f"I couldn't find a task matching '{query}'.")

        time_moves: set = set()
        duration_changes: Dict[str, int] = {}

        def match(query: Optional[str], commitments: bool = False, task_id: Optional[str] = None) -> List[PlanItem]:
            """Resolve what the user said to open tasks. Never needs the exact title.

            1. the phrase is inside a title; 2. every meaningful word is in the title, category or description
            (so "college observations" finds "Write two observations" filed under College); 3. otherwise the single
            task sharing the most distinctive words. More than one best match is returned as is: the caller
            asks which one (ambiguity protection).
            """
            # a commitment is only matched when the operation may act on it (cancel / move, named by the user)
            open_items = [i for i in items if i.status in ("todo", "postponed") and not i.is_new
                          and (commitments or not i.is_commitment)]
            if task_id:  # already resolved against this plan (validated understanding): exact, never fuzzy
                return [i for i in open_items if i.id == task_id]
            q = (query or "").strip().lower()
            if not q:
                return []
            exact = [i for i in open_items if q in i.title.lower()]
            if exact:
                return exact
            words = [w for w in _words(q) if w not in _MATCH_STOPWORDS]
            if not words:
                return []

            def meta(it: PlanItem) -> List[str]:
                row = row_by_id.get(it.id)
                return _words(f"{getattr(row, 'category', '') or ''} {getattr(row, 'description', '') or ''}")

            full = [i for i in open_items if all(w in _words(i.title) or w in meta(i) for w in words)]
            if full:
                return full
            distinctive = [w for w in words if w not in _MATCH_GENERIC]
            scored = [(sum(1 for w in distinctive if w in _words(i.title)), i) for i in open_items]
            best = max((n for n, _ in scored), default=0)
            return [i for n, i in scored if best > 0 and n == best]

        # prioritised tasks resolve first so a blanket delay can never push them later
        prioritized_ids: set = set()
        for op in operations:
            if op.op == "prioritize":
                found = match(op.task_query, task_id=op.task_id)
                if len(found) == 1:
                    prioritized_ids.add(found[0].id)

        for op in operations:
            if op.op == "delay_remaining_schedule":
                delta = timedelta(minutes=op.delay_minutes or 30)
                for it in list(items):
                    if (it.status in ("todo", "postponed") and not it.time_locked and not it.is_new
                            and it.id not in prioritized_ids
                            and it.start is not None and it.start >= now_local):
                        end = it.end or (it.start + timedelta(minutes=it.estimated_minutes))
                        items[idx_of(it.id)] = replace(it, origin_start=it.origin_start or it.start,
                                                       start=it.start + delta, end=end + delta)
                        intents.setdefault(it.id, "delayed")

            elif op.op == "redo_task":
                q = (op.task_query or "").strip().lower()
                if q in REDO_GENERIC_QUERIES:
                    found = [i for i in items if i.status in ("todo", "postponed") and not i.is_new and not i.is_commitment
                             and i.start is not None and (i.end or i.start) < now_local]
                else:
                    found = match(q)
                if not found:
                    if q in REDO_GENERIC_QUERIES:
                        note("note", "Nothing is missed right now.")
                    else:
                        note_missing(op.task_query)
                    continue
                if len(found) > 1:
                    names = ", ".join(f"'{f.title}'" for f in found[:4])
                    ambiguous(op.task_query, f"More than one task matches ({names}). Say which one to redo.")
                    continue
                it = found[0]
                explicit_ops.add(it.id)
                intents[it.id] = op.intent or "rescheduled"
                items[idx_of(it.id)] = replace(
                    it, origin_start=it.start, start=None, end=None, force_replace=True, time_locked=False,
                    temporal=PlanTemporal(target_date=target_date))

            elif op.op in ("cancel_task", "move_task_date", "move_task_time", "change_duration",
                           "shift_task_preference", "add_constraint"):
                # a commitment is acted on only when the user plainly cancels or moves it (never skip/defer/redo)
                found = match(op.task_query, commitments=op.op in ("cancel_task", "move_task_time")
                              or (op.op == "move_task_date" and op.intent == "rescheduled"), task_id=op.task_id)
                if not found:
                    note_missing(op.task_query)
                    continue
                if len(found) > 1:
                    names = ", ".join(f"'{f.title}'" for f in found[:4])
                    ambiguous(op.task_query, f"More than one task matches '{op.task_query}' ({names}). Be more specific.")
                    continue
                it = found[0]
                row = row_by_id.get(it.id)
                if op.op in ("shift_task_preference", "add_constraint"):
                    intents[it.id] = "preference_shift"
                if op.op == "cancel_task":
                    items.remove(it)
                    cancel_ids.append(it.id)
                    cancelled_items.append(TaskDiffItem(
                        task_id=it.id, title=it.title, change_type="cancelled",
                        old_time=clock_label(it.start, tz) if it.start else None,
                        old_start=it.start, time_locked=it.time_locked, duration_minutes=it.estimated_minutes,
                        reason="Cancelled by user request.", expected_updated_at=row.updated_at if row else None))
                elif (op.op == "move_task_time" and op.target_time and op.constraint_type in ("not_before", "latest_end")
                      and not it.is_commitment):
                    # "move X to after 10:30" (lower bound) / "before 5" (upper bound): the planner picks the slot
                    th, tm = map(int, op.target_time.split(":"))
                    bound = datetime.combine(target_date, time(th, tm), tzinfo=tz)
                    date_moves[it.id] = target_date
                    explicit_ops.add(it.id)
                    intents[it.id] = op.intent or "rescheduled"
                    temporal = (PlanTemporal(target_date=target_date, earliest_start=max(bound, now_local))
                                if op.constraint_type == "not_before"
                                else PlanTemporal(target_date=target_date, latest_end=bound))
                    items[idx_of(it.id)] = replace(
                        it, origin_start=it.start, start=None, end=None, force_replace=True, time_locked=False,
                        temporal=temporal)
                elif op.op == "move_task_time" and op.target_time:
                    th, tm = map(int, op.target_time.split(":"))
                    new_start = datetime.combine(target_date, time(th, tm), tzinfo=tz)
                    new_end = new_start + timedelta(minutes=it.estimated_minutes)
                    clash = next((o for o in items if o.id != it.id and o.start is not None and not o.is_new
                                  and (o.is_commitment or o.time_locked or o.status == "completed")
                                  and o.start < new_end and new_start < (o.end or o.start + timedelta(minutes=o.estimated_minutes))), None)
                    if clash is not None:
                        # the user's own fixed block wins: say so instead of proposing an overlap
                        note("conflict", f"{clash.title} is fixed at {_range_label(clash.start, clash.end, tz)}, so I can't put "
                                         f"{it.title} at {clock_label(new_start, tz)}. Choose another time.")
                        continue
                    date_moves[it.id] = target_date
                    time_moves.add(it.id)
                    explicit_ops.add(it.id)
                    intents[it.id] = op.intent or "rescheduled"
                    # the user named the time: it is fixed there, and may cross midnight (end lands on the next day)
                    items[idx_of(it.id)] = replace(
                        it, origin_start=it.start, start=new_start,
                        end=new_start + timedelta(minutes=it.estimated_minutes), time_locked=True, force_replace=False)
                elif op.op == "change_duration":
                    new_minutes = min(MAX_TASK_MINUTES, it.estimated_minutes + (op.delay_minutes or 0))
                    duration_changes[it.id] = new_minutes
                    explicit_ops.add(it.id)
                    keep_from = it.start if it.start is not None and it.start >= now_local else None
                    items[idx_of(it.id)] = replace(
                        it, estimated_minutes=new_minutes, origin_start=it.start, start=None, end=None,
                        force_replace=True, time_locked=False,
                        temporal=PlanTemporal(target_date=target_date, earliest_start=keep_from))
                elif op.op == "move_task_date":
                    dest = self._resolve_dest_date(op.target_date, target_date)
                    date_moves[it.id] = dest
                    explicit_ops.add(it.id)
                    intents[it.id] = op.intent or "rescheduled"
                    if it.time_locked and it.start is not None:
                        local = it.start.astimezone(tz)
                        new_start = datetime.combine(dest, local.time(), tzinfo=tz)
                        items[idx_of(it.id)] = replace(it, origin_start=it.start, start=new_start,
                                                       end=new_start + timedelta(minutes=it.estimated_minutes))
                    else:
                        items[idx_of(it.id)] = replace(
                            it, origin_start=it.start, start=None, end=None, force_replace=True,
                            temporal=PlanTemporal(target_date=dest))
                    # the destination day's existing tasks are busy time the planner must respect
                    dd_s, dd_e = self._bounds(dest, tz)
                    have = {i.id for i in items} | {i.id for i in extra_pinned}
                    for r in TaskRepository.list_open_for_day(db, user.id, dest, dd_s, dd_e, False):
                        if str(r.id) not in have:
                            extra_pinned.append(replace(planning_service.task_row_to_plan_item(r, tz=tz), pinned=True))
                elif op.op == "shift_task_preference":
                    win = {"morning": (9, 12), "afternoon": (14, 17), "evening": (18, 21), "night": (18, 21)}[op.preferred_window or "evening"]
                    t = PlanTemporal(
                        target_date=target_date,
                        preferred_window_start=datetime.combine(target_date, time(win[0]), tzinfo=tz),
                        preferred_window_end=datetime.combine(target_date, time(win[1]), tzinfo=tz),
                        # "tonight" is a firm request, not just a preference
                        earliest_start=datetime.combine(target_date, time(win[0]), tzinfo=tz) if op.constraint_value == "tonight" else None)
                    items[idx_of(it.id)] = replace(it, origin_start=it.start, start=None, end=None,
                                                   force_replace=True, temporal=t, time_locked=False)
                else:  # add_constraint (after a meal)
                    t = PlanTemporal(target_date=target_date, relative_after=op.constraint_value,
                                     earliest_start=datetime.combine(target_date, time(20, 0), tzinfo=tz)
                                     if op.constraint_value == "dinner" else None)
                    items[idx_of(it.id)] = replace(it, origin_start=it.start, start=None, end=None,
                                                   force_replace=True, temporal=t, time_locked=False)

            elif op.op == "protect_block" and op.block_start and op.block_end:
                bs_h, bs_m = map(int, op.block_start.split(":"))
                be_h, be_m = map(int, op.block_end.split(":"))
                protected_blocks.append((
                    datetime.combine(target_date, time(bs_h, bs_m), tzinfo=tz),
                    datetime.combine(target_date, time(be_h, be_m), tzinfo=tz)))

            elif op.op == "protect_task":
                words = [w for w in _words(op.task_query or "") if w not in _MATCH_STOPWORDS]
                named = ([i for i in items if i.id == op.task_id] if op.task_id else
                         [i for i in items if i.status in ("todo", "postponed") and not i.is_new and words
                          and all(w in _words(i.title) for w in words)])
                if not named:
                    note("not_found", f"I couldn't find '{op.task_query}' to keep untouched.")
                elif len(named) == 1:
                    keep = named[0]
                    if not keep.is_commitment and keep.start is not None:
                        items[idx_of(keep.id)] = replace(keep, time_locked=True)

            elif op.op == "unparsed":
                unparsed_ops.append(op)

            elif op.op in ("prioritize", "move_later"):
                found = match(op.task_query, task_id=op.task_id)
                if not found:
                    note_missing(op.task_query)
                    continue
                if len(found) > 1:
                    names = ", ".join(f"'{f.title}'" for f in found[:4])
                    ambiguous(op.task_query, f"More than one task matches '{op.task_query}' ({names}). Be more specific.")
                    continue
                it = found[0]
                if op.op == "prioritize":
                    items[idx_of(it.id)] = replace(it, rank=0)
                else:
                    was_end = it.end or (it.start + timedelta(minutes=it.estimated_minutes) if it.start else None)
                    earliest = max(now_local, was_end) if was_end else now_local + timedelta(minutes=30)
                    explicit_ops.add(it.id)
                    intents[it.id] = "delayed"
                    items[idx_of(it.id)] = replace(
                        it, origin_start=it.start, start=None, end=None, force_replace=True, time_locked=False,
                        temporal=PlanTemporal(target_date=target_date, earliest_start=earliest))

            elif op.op == "add_task":
                new_id = f"new-{uuid.uuid4().hex[:12]}"
                minutes = op.duration_minutes or 45
                start = end = None
                locked = False
                temporal = PlanTemporal()  # the replan scope supplies the target date
                if op.target_time:
                    th, tm = map(int, op.target_time.split(":"))
                    desired = datetime.combine(target_date, time(th, tm), tzinfo=tz)
                    if op.constraint_type == "fixed_start":
                        start, end, locked = desired, desired + timedelta(minutes=minutes), True
                    elif op.constraint_type == "latest_end":
                        temporal = replace(temporal, latest_end=desired)
                    else:
                        temporal = replace(temporal, preferred_start=desired)
                items.append(PlanItem(
                    id=new_id, title=op.title or "New task", estimated_minutes=minutes, status="todo",
                    priority=op.priority or "urgent", task_type=op.task_type or "deep_work",
                    start=start, end=end, time_locked=locked, temporal=temporal, is_new=True,
                    yield_to_fixed=True))

        # "I didn't act on X" only when X really went unhandled: a clause that names a task another operation
        # already resolved was satisfied, so it is not reported.
        handled_words = {
            w for o in operations
            if o.op != "unparsed" and o.task_query and (o.task_query or "").strip().lower() not in failed_queries
            for w in _words(o.task_query) if w not in _MATCH_STOPWORDS}
        for o in unparsed_ops:
            clause_words = {w for w in _words(o.title or "") if w not in _MATCH_STOPWORDS}
            if clause_words & handled_words:
                continue
            note("unparsed", f"I didn't act on \u201c{o.title}\u201d.")

        profile = self._profile(db, user)
        result = plan(items + extra_pinned, now_local=now_local, tz=tz, profile=profile, mode="replan",
                      extra_busy=protected_blocks,
                      scope_date=target_date, tz_name=tz_name)
        return self._build_response(request, result, items, row_by_id, before_resp, tz, tz_name, now_local, target_date,
                                    plan_id, conflicts, cancelled_items, cancel_ids, date_moves, explicit_ops, intents,
                                    issues=issues, duration_changes=duration_changes)

    @staticmethod
    def _needs_title(item: PlanItem, request: ReplanRequest) -> bool:
        """The parser's generic fallback name ("Urgent work") must be replaced by the user before Apply."""
        return request.quick_add is None and item.is_new and item.title == "Urgent work"

    def _build_response(
        self, request: ReplanRequest, result: PlanResult, items: List[PlanItem], row_by_id: Dict[str, Task],
        before_resp: DayScheduleResponse, tz: ZoneInfo, tz_name: str, now_local: datetime, target_date: date,
        plan_id: str, conflicts: List[str], cancelled_items: List[TaskDiffItem], cancel_ids: List[str],
        date_moves: Dict[str, date], explicit_ops: set, intents: Optional[Dict[str, str]] = None,
        issues: Optional[List[ReplanIssue]] = None, duration_changes: Optional[Dict[str, int]] = None,
    ) -> ReplanResponse:
        by_id = {i.id: i for i in items}
        duration_changes = duration_changes or {}
        issues = issues if issues is not None else []

        def note(kind: str, message: str) -> None:
            conflicts.append(message)
            issues.append(ReplanIssue(kind=kind, message=message))

        for cf in result.conflicts:
            titles = [by_id[i].title for i in cf.item_ids if i in by_id]
            if cf.code == "explicit_time_conflicts_with_fixed":
                new_t = by_id[cf.item_ids[0]]
                fixed = [by_id[i] for i in cf.item_ids[1:] if i in by_id]
                if fixed:
                    f = fixed[0]
                    when = clock_label(f.start, tz) if f.start else "its time"
                    note("conflict", f"Your {f.title} is fixed at {when}, so {new_t.title} conflicts with it. "
                                     f"Scheduled in a feasible flexible slot instead.")
            elif cf.code == "locked_overlap":
                note("conflict", f"{' and '.join(titles)} overlap; neither was moved.")
            elif cf.code == "explicit_time_in_past":
                t = by_id.get(cf.item_ids[0])
                when = clock_label(t.start, tz) if t and t.start else "that time"
                note("past", f"“{t.title if t else 'This task'}” is set for {when}, which has already passed. Choose a new time.")
            else:
                note("note", cf.message)

        moved: List[TaskDiffItem] = []
        newly: List[TaskDiffItem] = []
        unchanged: List[TaskDiffItem] = []
        protected: List[TaskDiffItem] = []
        unscheduled: List[TaskDiffItem] = []
        updates: List[TaskScheduleUpdate] = []
        new_tasks: List[TaskCreate] = []
        after: List[DayScheduleItem] = []

        def row_token(item_id: str) -> Optional[datetime]:
            r = row_by_id.get(item_id)
            return r.updated_at if r else None

        for p in result.placements:
            it = by_id[p.item_id]
            local_date = p.start.astimezone(tz).date()
            on_day = local_date == target_date
            if on_day:
                after.append(self._render(it, p.start, p.end, tz, locked=False, active=False,
                                          reason=p.primary_reason, explanation=p.explanation, updated_at=row_token(it.id)))
            label = None
            if local_date != target_date:
                label = "Tomorrow" if local_date == target_date + timedelta(days=1) else p.start.astimezone(tz).strftime("%A")
            common = dict(
                task_id=it.id, title=it.title, new_time=clock_label(p.start, tz), new_start=p.start, new_end=p.end,
                is_fixed=False, time_locked=False, task_type=it.task_type, priority=it.priority,
                duration_minutes=it.estimated_minutes, expected_updated_at=row_token(it.id),
                new_date=label, new_date_iso=local_date.isoformat() if not on_day else None,
                new_time_range=_range_label(p.start, p.end, tz), is_commitment=it.is_commitment,
            )
            if it.is_new:
                newly.append(TaskDiffItem(change_type="new", reason=p.explanation or "New task scheduled.",
                                          apply_index=len(new_tasks), needs_title=self._needs_title(it, request), **common))
                new_tasks.append(TaskCreate(
                    title=it.title, task_type=TaskType(it.task_type), priority=TaskPriority(it.priority),
                    difficulty=TaskDifficulty.medium, estimated_minutes=it.estimated_minutes,
                    scheduled_start=p.start, scheduled_end=p.end, source=TaskSource.manual))
            elif p.moved or local_date != target_date:
                prev = p.previous_start
                moved.append(TaskDiffItem(
                    change_type="moved", old_time=clock_label(prev, tz) if prev else None, old_start=prev,
                    old_time_range=_range_label(prev, prev + timedelta(minutes=it.estimated_minutes), tz) if prev else None,
                    old_date=request.selected_date if local_date != target_date else None,
                    reason=(f"Moved to {label}." if label and it.id in date_moves else (p.explanation or "Rescheduled around other tasks.")),
                    **common))
                updates.append(TaskScheduleUpdate(
                    task_id=it.id, scheduled_start=p.start, scheduled_end=p.end,
                    expected_updated_at=row_token(it.id), user_override=False))
            else:
                unchanged.append(TaskDiffItem(
                    change_type="unchanged", old_time=clock_label(p.start, tz), old_start=p.start, old_end=p.end,
                    old_time_range=_range_label(p.start, p.end, tz), reason="Time unchanged.", **common))

        for im in result.immutable:
            it = by_id.get(im.item_id)
            if it is None or im.kind == K_OUT_OF_SCOPE and im.start is None:
                continue
            if im.kind == K_OUT_OF_SCOPE and it.id not in date_moves:
                continue
            if im.start is None or im.end is None:
                continue
            on_day = im.start.astimezone(tz).date() == target_date
            if im.kind == K_COMPLETED:
                after.append(self._render(it, im.start, im.end, tz, locked=True, completed=True,
                                          reason="completed_session", explanation="Completed task session.",
                                          updated_at=row_token(it.id)))
                protected.append(TaskDiffItem(task_id=it.id, title=it.title, change_type="protected",
                                              old_time=clock_label(im.start, tz), is_fixed=True,
                                              old_start=im.start, old_end=im.end, new_start=im.start, new_end=im.end,
                                              old_time_range=_range_label(im.start, im.end, tz),
                                              new_time_range=_range_label(im.start, im.end, tz),
                                              duration_minutes=it.estimated_minutes, reason="Completed — not changed."))
            elif im.kind == K_IN_PROGRESS:
                after.append(self._render(it, im.start, im.end, tz, locked=False, active=True,
                                          reason="in_progress", explanation="In progress.", updated_at=row_token(it.id)))
                protected.append(TaskDiffItem(task_id=it.id, title=it.title, change_type="protected",
                                              old_time=clock_label(im.start, tz), duration_minutes=it.estimated_minutes,
                                              old_start=im.start, old_end=im.end, new_start=im.start, new_end=im.end,
                                              old_time_range=_range_label(im.start, im.end, tz),
                                              new_time_range=_range_label(im.start, im.end, tz),
                                              reason="In progress — not changed."))
            elif im.kind == K_LOCKED and it.is_new:
                # a NEW user-fixed item ("urgent call at 6"): scheduled exactly as asked, created locked on apply
                after.append(self._render(it, im.start, im.end, tz, locked=True, reason="explicit_time",
                                          explanation=f"Scheduled at your requested time ({clock_label(im.start, tz)}).",
                                          updated_at=None))
                newly.append(TaskDiffItem(
                    task_id=it.id, title=it.title, change_type="new", new_time=clock_label(im.start, tz), new_start=im.start,
                    new_end=im.end, is_fixed=True, time_locked=True, task_type=it.task_type, priority=it.priority,
                    duration_minutes=it.estimated_minutes, reason=f"Scheduled at your requested time ({clock_label(im.start, tz)}).",
                    apply_index=len(new_tasks), needs_title=self._needs_title(it, request)))
                new_tasks.append(TaskCreate(
                    title=it.title, task_type=TaskType(it.task_type), priority=TaskPriority(it.priority),
                    difficulty=TaskDifficulty.medium, estimated_minutes=it.estimated_minutes,
                    scheduled_start=im.start, scheduled_end=im.end, time_locked=True, source=TaskSource.manual))
            elif im.kind == K_LOCKED or (im.kind == K_OUT_OF_SCOPE and it.id in date_moves):
                moved_by_op = it.id in date_moves and it.origin_start is not None and it.origin_start != im.start
                if moved_by_op:
                    dest = im.start.astimezone(tz).date()
                    same_day = dest == target_date
                    moved.append(TaskDiffItem(
                        task_id=it.id, title=it.title, change_type="moved", old_time=clock_label(it.origin_start, tz),
                        old_start=it.origin_start, new_time=clock_label(im.start, tz), new_start=im.start, new_end=im.end,
                        old_time_range=_range_label(it.origin_start, it.origin_start + timedelta(minutes=it.estimated_minutes), tz),
                        new_time_range=_range_label(im.start, im.end, tz),
                        old_date=None if same_day else request.selected_date,
                        new_date=None if same_day else (
                            "Tomorrow" if dest == target_date + timedelta(days=1) else im.start.astimezone(tz).strftime("%A")),
                        new_date_iso=None if same_day else dest.isoformat(), is_fixed=True, time_locked=True,
                        is_commitment=it.is_commitment, task_type=it.task_type,
                        duration_minutes=it.estimated_minutes,
                        reason=f"Moved to {clock_label(im.start, tz)}." if same_day else "Moved to the same time on the new day.",
                        expected_updated_at=row_token(it.id)))
                    if same_day:
                        after.append(self._render(it, im.start, im.end, tz, locked=True, commitment=it.is_commitment,
                                                  reason="explicit_time", explanation=f"Fixed at {clock_label(im.start, tz)}.",
                                                  updated_at=row_token(it.id)))
                    updates.append(TaskScheduleUpdate(
                        task_id=it.id, scheduled_start=im.start, scheduled_end=im.end,
                        expected_updated_at=row_token(it.id), user_override=True))
                elif on_day:
                    after.append(self._render(it, im.start, im.end, tz, locked=True, commitment=it.is_commitment,
                                              reason="explicit_time",
                                              explanation=f"Fixed at {clock_label(im.start, tz)}.", updated_at=row_token(it.id)))
                    unchanged.append(TaskDiffItem(
                        task_id=it.id, title=it.title, change_type="unchanged", old_time=clock_label(im.start, tz),
                        new_time=clock_label(im.start, tz), old_start=im.start, old_end=im.end,
                        new_start=im.start, new_end=im.end,
                        old_time_range=_range_label(im.start, im.end, tz), new_time_range=_range_label(im.start, im.end, tz),
                        is_commitment=it.is_commitment, is_fixed=True, time_locked=True, task_type=it.task_type,
                        duration_minutes=it.estimated_minutes, reason="Fixed — not moved."))

        for u in result.unscheduled:
            it = by_id[u.item_id]
            if u.reason == "no_capacity":
                msg = f"I can't fit '{it.title}' ({it.estimated_minutes} min) today without breaking a fixed commitment or bedtime."
            elif u.reason == "explicit_time_in_past":
                msg = None  # already reported in conflicts
            else:
                msg = u.message
            if msg:
                note("capacity" if u.reason == "no_capacity" else "note", msg)
            sug = u.suggestion
            unscheduled.append(TaskDiffItem(
                task_id=it.id, title=it.title, change_type="unscheduled", duration_minutes=it.estimated_minutes,
                task_type=it.task_type, priority=it.priority, reason=u.message,
                suggestion_start=sug.start if sug else None, suggestion_end=sug.end if sug else None,
                expected_updated_at=row_token(it.id)))
            # apply behaviour for unscheduled items (user sees them in the diff before confirming)
            dest = date_moves.get(it.id)
            if it.is_new:
                unscheduled[-1].apply_index = len(new_tasks)
                unscheduled[-1].needs_title = self._needs_title(it, request)
                new_tasks.append(TaskCreate(
                    title=it.title, task_type=TaskType(it.task_type), priority=TaskPriority(it.priority),
                    difficulty=TaskDifficulty.medium, estimated_minutes=it.estimated_minutes,
                    scheduled_start=sug.start if sug else None, scheduled_end=sug.end if sug else None,
                    planned_date=(sug.start.astimezone(tz).date() if sug else target_date), source=TaskSource.manual))
            elif dest is not None and (sug is None or sug.start.astimezone(tz).date() != dest):
                # The user asked for that day: it goes there unslotted rather than silently staying here.
                note("capacity", f"No free slot for '{it.title}' on {dest.strftime('%A')} yet; it's on that day without a time.")
                updates.append(TaskScheduleUpdate.model_validate({
                    "task_id": it.id, "scheduled_start": None, "scheduled_end": None,
                    "planned_date": dest.isoformat(), "expected_updated_at": row_token(it.id)}))
            elif sug is not None:
                updates.append(TaskScheduleUpdate(task_id=it.id, scheduled_start=sug.start, scheduled_end=sug.end,
                                                  expected_updated_at=row_token(it.id)))
            elif it.start is not None:
                # keeping a stale slot could overlap what was just placed: keep the day, drop the time
                updates.append(TaskScheduleUpdate.model_validate({
                    "task_id": it.id, "scheduled_start": None, "scheduled_end": None,
                    "planned_date": target_date.isoformat(), "expected_updated_at": row_token(it.id)}))

        # "takes longer": the new duration is persisted even when the task keeps its start
        placed = {p.item_id: p for p in result.placements}
        for tid, minutes in duration_changes.items():
            p = placed.get(tid)
            if p is None:
                continue
            upd = next((u for u in updates if u.task_id == tid), None)
            if upd is None:
                upd = TaskScheduleUpdate(task_id=tid, scheduled_start=p.start, scheduled_end=p.end,
                                         expected_updated_at=row_token(tid))
                updates.append(upd)
                unchanged_row = next((u for u in unchanged if u.task_id == tid), None)
                if unchanged_row is not None:
                    unchanged.remove(unchanged_row)
                it = by_id[tid]
                moved.append(TaskDiffItem(
                    task_id=tid, title=it.title, change_type="moved", old_time=clock_label(p.start, tz), old_start=p.start,
                    old_time_range=unchanged_row.old_time_range if unchanged_row is not None else None,
                    new_time=clock_label(p.start, tz), new_start=p.start, new_end=p.end,
                    new_time_range=_range_label(p.start, p.end, tz), task_type=it.task_type, priority=it.priority,
                    duration_minutes=minutes, reason=f"Now {minutes} min.", expected_updated_at=row_token(tid)))
            upd.estimated_minutes = minutes

        # explicit-op moves of locked tasks are the one case where a lock may be overridden
        for upd in updates:
            if upd.task_id in explicit_ops and by_id[upd.task_id].time_locked:
                upd.user_override = True

        after.sort(key=lambda x: x.start_time)
        exp_parts: List[str] = list(conflicts)
        if moved:
            exp_parts.append(f"Moved {len(moved)} task{'s' if len(moved) != 1 else ''}.")
        if newly:
            exp_parts.append(f"Scheduled {len(newly)} new task{'s' if len(newly) != 1 else ''}.")
        if cancelled_items:
            exp_parts.append(f"Cancelled {len(cancelled_items)} task{'s' if len(cancelled_items) != 1 else ''}.")
        fixed_unchanged = [u.title for u in unchanged if u.is_fixed]
        if fixed_unchanged:
            exp_parts.append(f"{', '.join(fixed_unchanged)} remain{'s' if len(fixed_unchanged) == 1 else ''} unchanged.")
        explanation = " ".join(exp_parts) if exp_parts else "Schedule updated to match your changes."

        apply_request = ApplyReplanRequest(
            plan_id=plan_id, selected_date=request.selected_date, task_updates=updates,
            new_tasks=new_tasks, cancelled_task_ids=cancel_ids, timezone=tz_name,
            intents={k: v for k, v in (intents or {}).items() if k in {u.task_id for u in updates}})
        diff = PlanDiff(
            plan_id=plan_id, selected_date=request.selected_date, created_at=datetime.now(timezone.utc),
            before_schedule=before_resp.timeline, after_schedule=after, moved_tasks=moved,
            newly_scheduled_tasks=newly, unchanged_tasks=unchanged, cancelled_tasks=cancelled_items,
            unscheduled_tasks=unscheduled, skipped_immutable=protected, conflicts=conflicts, issues=issues,
            explanation=explanation, timezone_used=tz_name, apply_request=apply_request)
        return ReplanResponse(success=True, plan_diff=diff, user_intent_summary=request.user_message)

    # ── 4. APPLY REPLAN (atomic, idempotent, re-validated) ───────────────────

    def apply_replan(self, db: Session, user: User, request: ApplyReplanRequest) -> ApplyReplanResponse:
        replay = self._stored_replay(db, user.id, request.plan_id)
        if replay is not None:
            return replay

        tz, _ = self.resolve(user, request.timezone)
        now = self._now(tz, request.current_local_time)

        ids = {u.task_id for u in request.task_updates} | set(request.cancelled_task_ids)
        rows: Dict[str, Task] = {}
        if ids:
            for t in db.query(Task).filter(Task.user_id == user.id, Task.id.in_(ids)).all():
                rows[str(t.id)] = t

        skipped: List[Dict[str, Any]] = []
        stale: List[str] = []
        accepted: List[Tuple[TaskScheduleUpdate, Task]] = []
        for upd in request.task_updates:
            row = rows.get(upd.task_id)
            if row is None:
                skipped.append({"task_id": upd.task_id, "reason": "not_found"})
            elif row.status == TaskStatus.completed:
                skipped.append({"task_id": upd.task_id, "reason": "completed"})
            elif row.status == TaskStatus.in_progress:
                skipped.append({"task_id": upd.task_id, "reason": "in_progress"})
            elif row.status in (TaskStatus.cancelled, TaskStatus.archived):
                skipped.append({"task_id": upd.task_id, "reason": "terminal"})
            elif row.is_commitment and not upd.user_override:
                # a commitment only moves when the user named it (the server marks that op user_override)
                skipped.append({"task_id": upd.task_id, "reason": "commitment"})
            elif row.time_locked and not upd.user_override:
                skipped.append({"task_id": upd.task_id, "reason": "locked"})
            else:
                if upd.expected_updated_at is not None and row.updated_at is not None and \
                        abs((row.updated_at - upd.expected_updated_at).total_seconds()) > 0.001:
                    stale.append(upd.task_id)
                accepted.append((upd, row))
        if stale:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={
                "code": "stale_plan", "task_ids": stale,
                "message": "Your schedule changed since this plan was made. Replan to continue."})

        cancel_rows: List[Task] = []
        for cid in request.cancelled_task_ids:
            row = rows.get(cid)
            if row is None:
                skipped.append({"task_id": cid, "reason": "not_found"})
            elif row.status == TaskStatus.completed:
                skipped.append({"task_id": cid, "reason": "completed"})
            elif row.status == TaskStatus.in_progress:
                skipped.append({"task_id": cid, "reason": "in_progress"})
            elif row.status in (TaskStatus.cancelled, TaskStatus.archived):
                skipped.append({"task_id": cid, "reason": "terminal"})
            else:
                # includes a commitment the user named ("I won't be able to go out"): the row is kept as cancelled
                cancel_rows.append(row)

        # Server-side re-validation: never trust a client-computed diff.
        changed: List[PlanItem] = []
        for upd, row in accepted:
            fields = upd.model_fields_set
            new_start = upd.scheduled_start if "scheduled_start" in fields else row.scheduled_start
            new_end = upd.scheduled_end if "scheduled_end" in fields else row.scheduled_end
            if new_start is not None and new_start.tzinfo is None:
                new_start = new_start.replace(tzinfo=timezone.utc)
            if new_end is not None and new_end.tzinfo is None:
                new_end = new_end.replace(tzinfo=timezone.utc)
            base = planning_service.task_row_to_plan_item(row, tz=tz)
            minutes = upd.estimated_minutes or base.estimated_minutes
            changed.append(replace(base, estimated_minutes=minutes, start=new_start,
                                   end=new_end or (new_start + timedelta(minutes=minutes) if new_start else None)))
        for nt in request.new_tasks:
            s = nt.scheduled_start
            if s is not None and s.tzinfo is None:
                s = s.replace(tzinfo=timezone.utc)
            e = nt.scheduled_end or (s + timedelta(minutes=nt.estimated_minutes) if s else None)
            changed.append(PlanItem(
                id=f"new-{len(changed)}", title=nt.title, estimated_minutes=nt.estimated_minutes, status="todo",
                priority=nt.priority.value, task_type=nt.task_type.value, start=s, end=e,
                time_locked=bool(nt.time_locked and s), deadline_at=nt.deadline_at, is_new=True))

        touched = {c.id for c in changed} | {str(r.id) for r in cancel_rows}
        starts = [c.start for c in changed if c.start is not None]
        since = min([datetime.combine(now.date(), time.min, tzinfo=tz).astimezone(timezone.utc)] +
                    [datetime.combine(s.astimezone(tz).date(), time.min, tzinfo=tz).astimezone(timezone.utc) for s in starts])
        others = [planning_service.task_row_to_plan_item(t, tz=tz)
                  for t in TaskRepository.list_for_planning(db, user.id, since) if str(t.id) not in touched]
        violations = validate_placements(changed, others, now_local=now)
        if violations:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail={
                "code": "invariant_violation",
                "errors": [{"task_id": v.item_id if not v.item_id.startswith("new-") else None, "code": v.code, "message": v.message}
                           for v in violations]})

        intents = {k: v for k, v in request.intents.items() if v in REPLAN_INTENTS}
        try:
            selected_day = datetime.strptime(request.selected_date, "%Y-%m-%d").date()
        except ValueError:
            selected_day = now.astimezone(tz).date()
        updated_ids: List[str] = []
        created_rows: List[Task] = []
        deviations: List[TaskDeviation] = []
        try:
            for upd, row in accepted:
                intent = intents.get(str(row.id))
                if intent in ("skipped", "deferred"):
                    kind, dev_day = intent, selected_day
                elif (self._slot_missed(row, now) and "scheduled_start" in upd.model_fields_set
                      and upd.scheduled_start != row.scheduled_start):
                    # the user replans a task whose time already passed: keep that fact at its original slot
                    kind, dev_day = "missed", row.scheduled_start.astimezone(tz).date()
                else:
                    kind = dev_day = None
                if kind and not self._deviation_recorded(db, deviations, str(row.id), kind, row.scheduled_start):
                    # history captured before the row moves
                    deviations.append(TaskDeviation(
                        user_id=user.id, task_id=str(row.id), deviation_date=dev_day,
                        kind=kind, original_start=row.scheduled_start,
                        original_end=row.scheduled_end, plan_id=request.plan_id))
                fields = upd.model_fields_set
                if "scheduled_start" in fields:
                    row.scheduled_start = upd.scheduled_start
                if "scheduled_end" in fields:
                    row.scheduled_end = upd.scheduled_end
                if upd.deadline_at is not None:
                    row.deadline_at = upd.deadline_at
                if upd.estimated_minutes is not None:
                    row.estimated_minutes = upd.estimated_minutes
                if "planned_date" in fields:
                    row.planned_date = upd.planned_date
                # The user applied this replan: an explicit reschedule. A slot fixes the owning day.
                row.planned_date = owning_date(row.planned_date, row.scheduled_start, tz)
                row.updated_at = datetime.now(timezone.utc)
                updated_ids.append(str(row.id))
            for nt in request.new_tasks:
                t = Task(
                    user_id=user.id, title=nt.title, description=nt.description, category=nt.category,
                    task_type=nt.task_type, difficulty=nt.difficulty, priority=nt.priority,
                    estimated_minutes=nt.estimated_minutes, scheduled_start=nt.scheduled_start,
                    scheduled_end=nt.scheduled_end, deadline_at=nt.deadline_at, source=nt.source,
                    time_locked=bool(nt.time_locked and nt.scheduled_start),
                    planned_date=owning_date(nt.planned_date, nt.scheduled_start, tz) or now.astimezone(tz).date(),
                    status=TaskStatus.todo)
                TaskRepository.add_no_commit(db, t)
                created_rows.append(t)
            for row in cancel_rows:
                row.status = TaskStatus.cancelled
                row.updated_at = datetime.now(timezone.utc)
            for dev in deviations:
                dev.moved_to_date = next(r.planned_date for _, r in accepted if str(r.id) == dev.task_id)
                db.add(dev)
            db.flush()

            self._record_replan_signal(db, user.id, {i: intents.get(i, "collateral") for i in updated_ids},
                                       [str(r.id) for r in cancel_rows])

            touched_rows = [r for _, r in accepted] + created_rows + cancel_rows
            response = ApplyReplanResponse(
                success=True,
                updated_count=len(updated_ids), created_count=len(created_rows), cancelled_count=len(cancel_rows),
                message=(f"Applied plan: {len(updated_ids)} updated, {len(created_rows)} created, "
                         f"{len(cancel_rows)} cancelled" + (f", {len(skipped)} skipped." if skipped else ".")),
                updated=updated_ids, created=[str(t.id) for t in created_rows],
                cancelled=[str(r.id) for r in cancel_rows], skipped=skipped,
                persisted_tasks=[TaskResponse.model_validate(t) for t in touched_rows],
            )
            plan_applications.stage(db, user.id, request.plan_id, "replan", response.model_dump(mode="json"))
            db.commit()
            return response
        except IntegrityError:
            db.rollback()
            replay = self._stored_replay(db, user.id, request.plan_id)
            if replay is not None:
                return replay
            raise
        except Exception as e:
            db.rollback()
            logger.error(f"Failed to apply plan {request.plan_id}: {type(e).__name__}")
            raise

    @staticmethod
    def _slot_missed(row: Task, now: datetime) -> bool:
        """A stored slot that ended unstarted (derived; never persisted)."""
        return task_slot_elapsed(row, now)

    @staticmethod
    def _deviation_recorded(db: Session, pending: List[TaskDeviation], task_id: str, kind: str,
                            original_start: Optional[datetime]) -> bool:
        """One history row per (task, kind, original slot): replays and rebuilds never duplicate it."""
        if original_start is None:
            return False
        if any(d.task_id == task_id and d.kind == kind and d.original_start == original_start for d in pending):
            return True
        return db.query(TaskDeviation.id).filter(
            TaskDeviation.task_id == task_id, TaskDeviation.kind == kind,
            TaskDeviation.original_start == original_start).first() is not None

    @staticmethod
    def _record_replan_signal(db: Session, user_id: str, changed: Dict[str, str], cancelled_ids: List[str]) -> None:
        """Learning signal for an applied replan, in the same transaction (a replayed apply returns before this).

        ``changed`` maps task_id -> intent. What the user asked for ("skipped", "deferred", ...) is kept apart
        from "collateral": tasks the planner only shuffled to make room.
        """
        if not changed and not cancelled_ids:
            return
        decision = RecommendationDecision(user_id=user_id, engine_version="replan_v1", strategy="replan",
                                          candidate_scores_json="[]", recommendation_reasons_json="[]")
        db.add(decision)
        db.flush()
        for task_id, action in [(t, f"replan_{i}") for t, i in changed.items()] + [(t, "replan_cancelled") for t in cancelled_ids]:
            db.add(RecommendationOutcome(decision_id=decision.id, user_id=user_id, task_id=task_id, user_action=action))

    @staticmethod
    def _stored_replay(db: Session, user_id: str, plan_id: str) -> Optional[ApplyReplanResponse]:
        data = plan_applications.load_stored(db, user_id, plan_id)
        return ApplyReplanResponse(**data) if data is not None else None
