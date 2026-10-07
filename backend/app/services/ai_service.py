import re
import json
import httpx
import time as clock
import random
import uuid
from typing import List, Optional, Dict, Tuple, Any
from datetime import datetime, timedelta, timezone, time, date
from zoneinfo import ZoneInfo
from ..models.task import TaskType, TaskDifficulty, TaskPriority, TaskSource
from ..schemas.task import (
    TaskCandidateResponse,
    FieldProvenance,
    TemporalConstraints,
    PlanningContext,
    FixedEventContext,
    TravelContext,
    ProtectedPeriodContext,
    AvailabilityContext,
    TaskDependencyContext,
)
from ..core.ai_limits import request_deadline
from ..core.config import settings
from ..core.logging import logger
from ..core.timezone import resolve_timezone
from .candidate_dependencies import link_sequential_from_text, prune_dangling, resolve_dependencies


# ─────────────────────────────────────────────────────────────────────────────
# Small validation helpers
# ─────────────────────────────────────────────────────────────────────────────
def _clamp_confidence(value: Any, default: float = 0.5) -> float:
    try:
        v = float(value)
    except (TypeError, ValueError):
        return default
    if v != v:  # NaN
        return default
    return max(0.0, min(1.0, v))


def _safe_int(value: Any, default: int, lo: int, hi: int) -> int:
    try:
        v = int(value)
    except (TypeError, ValueError):
        return default
    return max(lo, min(hi, v))


def _parse_hhmm(value: Any) -> Optional[Tuple[int, int]]:
    """Strictly parse 'HH:MM' or 'HH'. Returns (h, m) or None."""
    if not value or not isinstance(value, str) or ":" not in value:
        return None
    try:
        parts = value.split(":")
        h = int(parts[0])
        m = int(parts[1][:2]) if len(parts) > 1 else 0
    except (ValueError, IndexError):
        return None
    if not (0 <= h <= 23) or not (0 <= m <= 59):
        return None
    return h, m


def _parse_iso_date(value: Any) -> Optional[Any]:
    """Strictly parse 'YYYY-MM-DD' prefix. Returns date or None."""
    if not value or not isinstance(value, str) or len(value) < 8:
        return None
    try:
        return datetime.strptime(value[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


_WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
_WEEKDAY_REGEX = r'(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)'


def _resolve_weekday_date(weekday_name: str, now_local: datetime):
    """
    Return the next occurrence of the named weekday in the user's local tz.
    If today is the named weekday, returns the same day next week (never past).
    """
    try:
        target_wd = _WEEKDAYS.index(weekday_name.lower())
    except ValueError:
        return now_local.date()
    days_ahead = (target_wd - now_local.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7
    return now_local.date() + timedelta(days=days_ahead)


class GeminiFailure(RuntimeError):
    """A Build My Day extraction failure with a diagnostic code (spec §7): gemini_error
    (transport/auth/all models failed), malformed (unparseable after one repair), empty (no tasks)."""

    def __init__(self, code: str, reason: str = ""):
        super().__init__(reason or code)
        self.code = code
        self.reason = reason or code


_LOW_PRIORITY_CUES = re.compile(r"\b(?:optional|if (?:i )?(?:have|get) (?:the )?time|not urgent|no rush|whenever)\b", re.I)


def infer_priority(deadline_at: Optional[datetime], text: str, now_local: datetime) -> TaskPriority:
    """Priority when the user stated none: low cues -> low; deadline today/tomorrow -> high; else medium."""
    if _LOW_PRIORITY_CUES.search(text or ""):
        return TaskPriority.low
    if deadline_at is not None and deadline_at.astimezone(now_local.tzinfo).date() <= now_local.date() + timedelta(days=1):
        return TaskPriority.high
    return TaskPriority.medium


def infer_focus(task_type: TaskType) -> str:
    if task_type in (TaskType.deep_work, TaskType.study):
        return "high"
    if task_type in (TaskType.admin, TaskType.physical):
        return "low"
    return "medium"


def resolve_deadline(date_: Any, time_hhmm: Optional[Tuple[int, int]], phrase: Optional[str], tz: ZoneInfo,
                     today: Optional[Any] = None) -> datetime:
    """A stated time wins; 'before <day>' -> <day> 00:00 (done by the end of the previous day);
    otherwise <day> 23:59. 'before <today>' means next week, never a deadline that already passed."""
    if time_hhmm:
        return datetime.combine(date_, time(*time_hhmm), tzinfo=tz)
    if (phrase or "").lower() == "before":
        if today is not None and date_ <= today:
            date_ = date_ + timedelta(days=7)
        return datetime.combine(date_, time(0, 0), tzinfo=tz)
    return datetime.combine(date_, time(23, 59), tzinfo=tz)


def _loads_or_none(text: Any) -> Any:
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Canonical Gemini schema (single source of truth for initial + repair)
# NOTE: is_recurring and dependencies are intentionally NOT part of the
# contract because TaskCandidateResponse has no corresponding field.
# ─────────────────────────────────────────────────────────────────────────────
_GEMINI_TASK_SCHEMA_FIELDS = (
    '"ref": "t1",\n'
    '      "title": "concise task title",\n'
    '      "description": null,\n'
    '      "type": "deep_work" | "shallow_work" | "study" | "creative" | "admin" | "physical" | "meeting" | "personal",\n'
    '      "category": "College" | "Work" | "Personal" | "Fitness" | "General",\n'
    '      "estimated_minutes": 45,\n'
    '      "difficulty": "high" | "medium" | "light" | "physical",\n'
    '      "duration_source": "explicit" | "inferred",\n'
    '      "priority": "low" | "medium" | "high" | "urgent",\n'
    '      "priority_source": "explicit" | "inferred",\n'
    '      "focus_level": "low" | "medium" | "high",\n'
    '      "focus_source": "explicit" | "inferred",\n'
    '      "depends_on": ["t1"],\n'
    '      "target_date": "YYYY-MM-DD" | null,\n'
    '      "deadline": "YYYY-MM-DD" | null,\n'
    '      "deadline_time": "HH:MM" | null,\n'
    '      "deadline_phrase": "before" | "by" | "due" | null,\n'
    '      "deadline_kind": "hard" | "soft" | null,\n'
    '      "fixed_start": "HH:MM" | null,\n'
    '      "preferred_start_hhmm": "HH:MM" | null,\n'
    '      "preferred_window": "morning" | "afternoon" | "evening" | "after_dinner" | "after_lunch" | "after_breakfast" | null,\n'
    '      "earliest_start_hhmm": "HH:MM" | null,\n'
    '      "latest_end_hhmm": "HH:MM" | null,\n'
    '      "relative_after": "dinner" | "lunch" | "breakfast" | "class" | "meeting" | null,\n'
    '      "relative_before": "dinner" | "lunch" | "breakfast" | "bedtime" | "class" | "meeting" | null,\n'
    '      "confidence": 0.95,\n'
    '      "needs_confirmation": false'
)

_GEMINI_PLANNING_CONTEXT_SCHEMA = (
    '    "fixed_events": [\n'
    '      {"title": "Team meeting", "start_time": "10:00", "end_time": "10:45", "duration_minutes": 45, "target_date": "YYYY-MM-DD" | null}\n'
    '    ],\n'
    '    "travel_segments": [\n'
    '      {"from_location": "home", "to_location": "office", "duration_minutes": 45, "departure_time": "08:30", "target_date": "YYYY-MM-DD" | null}\n'
    '    ],\n'
    '    "protected_periods": [\n'
    '      {"name": "lunch", "preferred_start": "13:00", "duration_minutes": 45, "is_movable": true, "target_date": "YYYY-MM-DD" | null}\n'
    '    ],\n'
    '    "availability_windows": [\n'
    '      {"label": "office_hours", "start_time": "09:30", "end_time": "17:30", "target_date": "YYYY-MM-DD" | null}\n'
    '    ],\n'
    '    "task_dependencies": [\n'
    '      {"predecessor": "Review numbers", "successor": "Finish monthly report"}\n'
    '    ],\n'
    '    "priority_order": ["Finish monthly report", "Send invoice"],\n'
    '    "deferred_tasks": ["Presentation progress"],\n'
    '    "energy_preference": "morning_heavy" | "afternoon_heavy" | "evening_heavy" | null,\n'
    '    "buffer_preference": "spacious" | "standard" | null'
)


def _build_initial_gemini_prompt(raw_text: str, today_str: str, user_timezone_str: str) -> str:
    return (
        "You are an intelligent task planner.\n"
        f"Current date: {today_str}\n"
        f"Current user timezone: {user_timezone_str}\n\n"
        "Extract structured task items AND day-level planning context from this user text:\n"
        f'"{raw_text}"\n\n'
        "CRITICAL INSTRUCTIONS:\n"
        "1. Return ONLY valid JSON in this exact structure:\n"
        "{\n"
        '  "tasks": [\n'
        "    {\n"
        f"      {_GEMINI_TASK_SCHEMA_FIELDS}\n"
        "    }\n"
        "  ],\n"
        '  "planning_context": {\n'
        f"{_GEMINI_PLANNING_CONTEXT_SCHEMA}\n"
        "  },\n"
        '  "ambiguities": []\n'
        "}\n\n"
        "STRICT RULES:\n"
        "- DAY CONTEXT VS TASK CARDS (CRITICAL):\n"
        "  * Only independently executable tasks belong in the 'tasks' list.\n"
        "  * FIXED EVENTS (e.g. meetings, appointments, calls with specific times): include them in 'planning_context.fixed_events'. If they are calendar meetings or appointments (like 'team meeting at 10', 'client call at 3:30'), also include them in 'tasks' as type='meeting' with fixed_start set.\n"
        "  * TRAVEL / COMMUTE (e.g. 'takes 45 minutes to get there, leave around 8:30', '20 minutes from my office'): extract into 'planning_context.travel_segments'. DO NOT create task cards for commuting, driving, or leaving home!\n"
        "  * PROTECTED BREAKS / MEALS (e.g. 'lunch around 1, movable if necessary'): extract into 'planning_context.protected_periods'. DO NOT create a task card for lunch unless user explicitly asks to track lunch as an action item.\n"
        "  * WORK CONTEXT / AVAILABILITY (e.g. 'need to be at office by 9:30', 'bank call only during office hours', 'work from 9 to 6'): extract into 'planning_context.availability_windows'. DO NOT create task cards for 'be at office' or 'office hours'. For tasks constrained to office hours (like the bank call), set earliest_start_hhmm: '09:30', latest_end_hhmm: '17:30'.\n"
        "  * TASK DEPENDENCIES (e.g. 'review numbers before report', 'prepare before client call'): extract into 'planning_context.task_dependencies'. Also set relative_before/relative_after on tasks where applicable.\n"
        "  * DAY-LEVEL ENERGY PREFERENCE (e.g. 'more energy in morning than afternoon'): set energy_preference: 'morning_heavy' in planning_context. DO NOT create task cards for energy statements.\n"
        "  * BUFFER PREFERENCES (e.g. 'don't want every single minute occupied'): set buffer_preference: 'spacious' in planning_context. DO NOT create task cards for buffer preferences.\n"
        "  * DEFERRED / POSTPONED TASKS (e.g. 'presentation for Friday isn't urgent tomorrow, can be pushed to Thursday'): include in 'tasks' with priority='low', and add title to 'planning_context.deferred_tasks'.\n"
        "  * STRESS / RAMBLING / META STATEMENTS (e.g. 'tomorrow is going to be packed and I'm already stressing', 'just make the day realistic'): DO NOT create task cards for emotional, conversational, or meta statements!\n"
        "- TASK SEGMENTATION RULES:\n"
        "  * Identify independently executable activities. Semantic independence is MORE IMPORTANT than commas or punctuation.\n"
        "  * A PARAGRAPH BRAIN DUMP with multiple sentences almost always contains multiple independent tasks. Each sentence likely describes a different activity.\n"
        "  * DO NOT merge multiple independent tasks into a single task. Each distinct activity = one task candidate.\n"
        "  * Examples of independent tasks that MUST be separate:\n"
        "    - 'gym work assignment' -> 3 tasks: 'Gym' (physical), 'Work' (admin), 'Assignment' (study).\n"
        "    - 'finish my ML assignment and submit it before 11 AM' + 'fix the auth bug' + 'gym at 6' + 'review DSA' + 'call mom' + 'clean room'\n"
        "      -> MUST become 6 separate tasks. DO NOT collapse into 1 task.\n"
        "  * Examples of coherent activities that MUST stay as one task:\n"
        "    - 'finish my work assignment' -> 1 task: 'Finish work assignment'.\n"
        "    - 'finish my Python assignment and submit it' -> 1 task: 'Finish Python assignment and submit'.\n"
        "- CONDITIONAL AND OPTIONAL TASKS:\n"
        "  * 'but if I'm really tired it's okay to move it later' -> mark task as flexible, NOT conditional on another task.\n"
        "  * 'that's optional and shouldn't interfere with the important stuff' -> include the task with priority='low' and priority_source='explicit'.\n"
        "  * 'sacrifice cleaning my room first, then gym' -> include both tasks, cleaning with priority='low', gym with priority='low'.\n"
        "  * 'absolutely don't sacrifice the ML assignment deadline' -> ML assignment priority='high' and priority_source='explicit'.\n"
        "  * Scheduling hints like 'don't schedule anything right before I leave' are CONSTRAINTS, NOT tasks. Do NOT create a task for them.\n"
        "  * Sleep boundary 'want to sleep by 11:30 PM' is a SOFT CONSTRAINT, NOT a task. Do NOT create a task for it.\n"
        "  * Commute hints like 'leave home by 11:50' are CONSTRAINTS, NOT tasks. Do NOT create a task for them.\n"
        "  * Class/commute blocks like 'class at 12:40 PM' are FIXED EVENTS. Include them as type='meeting' with fixed_start set.\n"
        "- TASK TITLES MUST BE CONCISE, NATURAL, AND USER-FAITHFUL:\n"
        "  * Structure the user's input, DO NOT rewrite it into unnatural or awkward task names.\n"
        "  * Examples:\n"
        "    - 'gym around 6 PM' -> title: 'Gym session', type: 'physical', fixed_start: null, preferred_start_hhmm: '18:00', preferred_window: null\n"
        "    - 'finish my ML assignment and submit it before 11 AM, probably 90 minutes' -> title: 'Finish ML assignment', type: 'deep_work', estimated_minutes: 90, deadline: today, deadline_time: '11:00'\n"
        "    - 'fix the authentication bug, preferably in the afternoon' -> title: 'Fix auth bug', type: 'deep_work', estimated_minutes: 120, preferred_window: 'afternoon'\n"
        "    - 'after dinner I want to review DSA for 45 minutes' -> title: 'Review DSA', type: 'study', estimated_minutes: 45, preferred_window: 'after_dinner', relative_after: 'dinner', earliest_start_hhmm: '20:00'\n"
        "    - 'call my mom sometime in the evening, probably 15 minutes' -> title: 'Call mom', type: 'admin', estimated_minutes: 15, preferred_window: 'evening'\n"
        "    - 'clean my room' -> title: 'Clean room', type: 'admin', estimated_minutes: 30, priority: 'low'\n"
        "    - 'meeting Friday at 3 PM' -> title: 'Meeting', type: 'meeting', target_date: Friday's date, fixed_start: '15:00', deadline: null\n"
        "    - 'Study DSA Friday morning' -> title: 'Study DSA', target_date: Friday's date, preferred_window: 'morning', deadline: null\n"
        "  * DO NOT generate titles like 'Gym to do', 'Work to do', 'Assignment task', or 'Task for gym'.\n"
        "  * Keep task category/type SEPARATE from title. Do not encode category into the title.\n"
        "- PRIORITY RULES:\n"
        "  * If user explicitly specifies priority ('urgent', 'high priority', 'low priority', 'optional', 'absolutely don't sacrifice', etc.): set priority accordingly and priority_source='explicit'.\n"
        "  * If user does NOT explicitly specify priority: infer it from urgency cues (deadline today/tomorrow -> 'high'; 'optional'/'if I have time' -> 'low'; otherwise 'medium') and set priority_source='inferred'. Never return null.\n"
        "- DURATION / FOCUS RULES:\n"
        "  * duration_source='explicit' only when the user stated a duration ('for 45 minutes', 'about 2 hours'); otherwise estimate it and set 'inferred'.\n"
        "  * focus_level='high' + focus_source='explicit' when the user says it needs deep focus / concentration / no distractions; 'low' + 'explicit' for 'mindless' / 'easy'. Otherwise infer from type (deep_work/study -> high, admin/physical -> low, else medium) with focus_source='inferred'.\n"
        "- TASK REFS & DEPENDENCIES:\n"
        "  * Give every task a unique ref: 't1', 't2', ... in mention order.\n"
        "  * 'after that' / 'then' / 'once X is done' / 'after finishing X' -> depends_on: [ref of that earlier task]. Otherwise depends_on: [].\n"
        "  * 'after class/dinner/lunch' names an event, NOT a task: use relative_after, not depends_on (unless that event is itself a listed task).\n"
        "- FAITHFULNESS, GOALS & UNAVAILABLE BLOCKS:\n"
        "  * NEVER INVENT TASKS: list only work the user actually mentioned. Do not add follow-up, delivery or submission steps they did not ask for (do NOT add 'send to professor' unless they said so).\n"
        "  * STATED GOALS: when the user says they 'really want', 'prefer' or have a 'big goal' to finish or deploy something, that task is a personal goal: priority='high' and priority_source='explicit', even with no deadline.\n"
        "  * UNAVAILABLE BLOCKS: a time range the user is away or tells you not to schedule anything in ('going out from 6:30 to 8:30', 'don't schedule anything then') belongs in planning_context.fixed_events with start_time, end_time and target_date. It is NOT a task.\n"
        "- DEADLINE PHRASE & KIND:\n"
        "  * deadline_phrase records the word used. 'before Tuesday' -> deadline: Tuesday's date, deadline_time: null, deadline_phrase: 'before' (it means finished by the END OF MONDAY, NOT Tuesday 23:59). 'by Friday' / 'due Friday' -> deadline_phrase: 'by' / 'due'.\n"
        "  * deadline_kind='hard' for must / before / by / due / deadline; 'soft' for 'ideally by', 'try to finish by', 'if possible by'.\n"
        "- TIME, DATE & DEADLINE RULES (CRITICAL — preserve user intent exactly):\n"
        "  * TARGET DATE:\n"
        "    - If user says 'tomorrow', set target_date to tomorrow's date (YYYY-MM-DD).\n"
        "    - If user says 'today' or 'tonight', set target_date to today's date.\n"
        "    - If user names a weekday like 'Friday', set target_date to the next occurrence of that weekday.\n"
        "    - Do NOT treat a bare weekday mention as a deadline. 'Friday at 6 PM' means target_date=Friday, fixed_start='18:00', NOT a Friday deadline.\n"
        "    - If no date is mentioned, target_date MUST be null.\n"
        "    - target_date is INDEPENDENT of deadline. A task can have a target_date but no deadline, or vice versa.\n"
        "  * FIXED START (a specific clock time):\n"
        "    - 'Study DSA tomorrow at 9 AM' -> target_date: tomorrow's date, fixed_start: '09:00'.\n"
        "    - 'Friday at 6 PM' -> target_date: Friday's date, fixed_start: '18:00', deadline: null.\n"
        "    - 'gym at 6 PM' -> fixed_start: '18:00'. 6 PM = '18:00'. 12 PM = '12:00'. 12 AM = '00:00'.\n"
        "    - NEVER convert a bare 'at 6' without am/pm into a fixed_start. Set preferred_start_hhmm: '18:00', needs_confirmation: true, fixed_start: null.\n"
        "  * PREFERRED START / WINDOW (flexible around a time or within a period):\n"
        "    - 'around 6 PM' -> preferred_start_hhmm: '18:00'. Do NOT set fixed_start.\n"
        "    - 'sometime in the afternoon' -> preferred_window: 'afternoon'. Do NOT set fixed_start.\n"
        "    - 'in the evening' -> preferred_window: 'evening'. Do NOT set fixed_start.\n"
        "    - 'tonight' -> target_date: today, preferred_window: 'evening'. Do NOT set fixed_start.\n"
        "    - 'Friday night' -> target_date: Friday's date, preferred_window: 'evening'. 'night' always normalizes to 'evening'. Do NOT set fixed_start. Do NOT invent 8 PM or 9 PM.\n"
        "    - 'Friday evening' -> target_date: Friday's date, preferred_window: 'evening'.\n"
        "    - 'tomorrow morning' -> target_date: tomorrow's date, preferred_window: 'morning'.\n"
        "    - 'Friday morning' -> target_date: Friday's date, preferred_window: 'morning'.\n"
        "    - 'after dinner' -> preferred_window: 'after_dinner', relative_after: 'dinner', earliest_start_hhmm: '20:00'. Do NOT set fixed_start.\n"
        "    - 'after lunch' -> preferred_window: 'after_lunch', relative_after: 'lunch', earliest_start_hhmm: '13:00'.\n"
        "    - 'after breakfast' -> preferred_window: 'after_breakfast', relative_after: 'breakfast', earliest_start_hhmm: '07:30'.\n"
        "  * IMPORTANT: 'night' is NEVER a fixed time. Always map 'night' -> preferred_window: 'evening'. Never set fixed_start for 'night'.\n"
        "  * DEADLINE (a hard 'must be done by' boundary):\n"
        "    - 'before 11 AM tomorrow' -> deadline: tomorrow's date, deadline_time: '11:00'. NOT deadline_time: '23:59'.\n"
        "    - 'by Friday' / 'due Friday' -> deadline: Friday's date, deadline_time: null (means end of day).\n"
        "    - 'due tonight' -> deadline: today's date, deadline_time: '23:59'.\n"
        "    - NEVER invent a deadline. If no deadline is stated, deadline MUST be null.\n"
        "  * LATEST END / RELATIVE BEFORE:\n"
        "    - 'before dinner' -> latest_end_hhmm: '20:00', relative_before: 'dinner'.\n"
        "    - 'before lunch' -> latest_end_hhmm: '13:00', relative_before: 'lunch'.\n"
        "    - 'before breakfast' -> latest_end_hhmm: '07:30', relative_before: 'breakfast'.\n"
        "    - 'before bed' / 'before sleep' -> relative_before: 'bedtime'.\n"
        "- FLOWSTATE DETERMINISTIC SCHEDULER is the final calendar scheduler. Never make rigid calendar choices for non-fixed tasks.\n"
    )


def _build_gemini_repair_prompt(malformed_text: str) -> str:
    return (
        f"The following text is NOT valid JSON:\n{malformed_text}\n\n"
        "Repair it and output ONLY valid JSON matching this schema:\n"
        "{\n"
        '  "tasks": [\n'
        "    {\n"
        f"      {_GEMINI_TASK_SCHEMA_FIELDS}\n"
        "    }\n"
        "  ],\n"
        '  "planning_context": {\n'
        f"{_GEMINI_PLANNING_CONTEXT_SCHEMA}\n"
        "  },\n"
        '  "ambiguities": []\n'
        "}\n\n"
        "IMPORTANT: Preserve every semantic field you extracted "
        "(target_date, deadline, deadline_time, fixed_start, preferred_start_hhmm, "
        "preferred_window, earliest_start_hhmm, latest_end_hhmm, relative_after, "
        "relative_before, priority, priority_source, needs_confirmation, planning_context). "
        "Do NOT drop these fields during repair. Do NOT change null to a value "
        "or a value to null.\n"
    )


def sanitize_task_title(title: str) -> str:
    """
    Ensures task titles are concise, natural, and user-faithful.
    """
    if not title:
        return "Task"
    t = title.strip()
    t = re.sub(r'^[,\s\-•*:]+|[,\s\-•*:]+$', '', t).strip()
    t = re.sub(
        r'^(?:i have|i\'ve got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+',
        '', t, flags=re.IGNORECASE,
    ).strip()
    t = re.sub(r'^(?:task\s+for|task\s*:|to\s*do\s*:)\s*', '', t, flags=re.IGNORECASE).strip()
    t = re.sub(r'\s+(?:to\s+do|todo|task)$', '', t, flags=re.IGNORECASE).strip()
    t = re.sub(
        r'\b(?:my|the)\s+(?=assignment|project|lab|homework|thesis|work|task|exam|quiz|session|workout)\b',
        '', t, flags=re.IGNORECASE,
    )
    t = re.sub(r'^(?:after\s+that|following\s+that)\b[\s,]*', '', t, flags=re.IGNORECASE).strip()
    t = re.sub(r'[\s,]*\b(?:after\s+that|following\s+that)$', '', t, flags=re.IGNORECASE).strip()
    t = re.sub(r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+|the\s+|my\s+)', '', t, flags=re.IGNORECASE).strip()
    t = re.sub(r'\s+', ' ', t).strip()
    if len(t) > 1:
        t = t[0].upper() + t[1:]
    elif len(t) == 1:
        t = t.upper()
    return t or "Task"


# ── Conservative deterministic fallback ──────────────────────────────────────
# The fallback may under-split; it must never fragment or invent. A clause that
# only carries attributes of the previous task ("It will probably take around
# 90 minutes.", "which may take about 2 hours", "spend about an hour there") is
# attached to that task, and instruction sentences ("Don't schedule…",
# "Prioritize…") never become tasks.

_DURATION_UNIT = r'(?:mins?|minutes?|hrs?|hours?|h)\b'

# "at 6 PM" / "around 6". Never matches a duration ("around 90 minutes") or a
# decimal ("around 1.5 hours").
_CLOCK_TIME_RE = re.compile(
    r'\b(?:at|around)\s+(\d{1,2})(?::(\d{2}))?(?!\d)(?!\.\d)\s*(am|pm)?\b'
    rf'(?!\s*{_DURATION_UNIT})',
    re.IGNORECASE,
)

# A duration phrase together with its lead-in words, so removing it from a
# title leaves no "take around ." remnant.
_DURATION_PHRASE_RE = re.compile(
    r'(?:,\s*)?'
    r'(?:\b(?:it|this|that)\s+)?'
    r'(?:\b(?:will|should|would|might|may|could)\s+)?'
    r'(?:\b(?:probably|likely|maybe|roughly)\s+)?'
    r'(?:\b(?:take|takes|taking|spend|spending|for|lasting)\s+)?'
    r'(?:\b(?:at\s+least|at\s+most|about|around|roughly|approximately|approx\.?|maybe|probably|up\s+to)\s+)?'
    r'(?:\b\d+(?:\.\d+)?\s*(?:mins?|minutes?|m|hrs?|hours?|h)\b'
    r'|\b(?:half\s+an\s+hour|an\s+hour|one\s+hour|two\s+hours|three\s+hours|four\s+hours)\b)'
    r'(?:\s+(?:of\s+work|there|on\s+it|or\s+so))?',
    re.IGNORECASE,
)

# Subordinate tails that describe a task rather than name it.
_TITLE_TAIL_RE = re.compile(
    r'(?:,\s*(?:which|but|preferably|ideally|so|because|since|though|although|if|when|unless)\b'
    r'|\s+(?:because|so\s+that|since|although|though|unless|but)\b'
    r'|\s+when\s+i(?:\'m|\s+am)\b'
    r'|,\s*(?:it|this|that)\s+(?:will|should|may|might|can|could|would|is)\b).*$',
    re.IGNORECASE | re.DOTALL,
)

_TITLE_OPENER_RE = re.compile(
    r'^(?:also|and|then|plus|'
    r'i\s+(?:also\s+)?(?:should|must|need\s+to|have\s+to|want\s+to|gotta|will|plan\s+to|'
    r'am\s+going\s+to|would\s+like\s+to)|'
    r'i\'(?:ll|d\s+like\s+to|m\s+going\s+to)|'
    r'i\s+(?:also\s+)?have(?:\s+(?:a|an))?|i\'ve\s+got(?:\s+(?:a|an))?|'
    r'don\'?t\s+forget\s+to|remember\s+to|remind\s+me\s+to)\s+',
    re.IGNORECASE,
)

# A clause that cannot stand alone: it refers back to the previous task.
_DEPENDENT_START_RE = re.compile(
    r'^(?:which|it|it\'s|its|but|so|because|since|though|although|'
    r'preferably|ideally|hopefully|otherwise|'
    r'(?:this|that)(?:\'s|\s+(?:is|will|should|can|could|may|might|would))|'
    r'(?:can|could|should|might|may|will|would|must)\s+be|'
    r'shouldn\'?t|should\s+not|won\'?t|can\'?t|cannot|mustn\'?t|must\s+not|doesn\'?t|does\s+not|'
    r'i\'d\s+(?:like|prefer|rather)|i\s+would\s+(?:like|prefer|rather)|'
    r'(?:i\s+)?(?:want|need)\s+to\s+do\s+(?:that|it)|do\s+(?:that|it))\b',
    re.IGNORECASE,
)

# Planning instructions and mood statements: context, never tasks.
_INSTRUCTION_RE = re.compile(
    r'^(?:(?:don\'?t|do\s+not|never)\b(?!\s+forget\b)|'
    r'avoid\s+scheduling|make\s+sure|keep\s+(?:enough|some)\b|'
    r'leave\s+(?:enough|some)\s+(?:time|buffer|gap|room)\b|'
    r'prioriti[sz]e\b|remind\s+me\s+(?:that|about\s+that)\b|'
    r'if\s+(?:something|anything|there|everything|the\s+day)\b|'
    r'(?:tomorrow|today|tonight|my\s+day|the\s+day|this\s+week)\s+'
    r'(?:is|will\s+be|is\s+going\s+to\s+be|looks|seems)\b)',
    re.IGNORECASE,
)

_LEADING_LINKER_RE = re.compile(r'^(?:and|so|but|also|then|please)\s+', re.IGNORECASE)

_NON_CONTENT_WORDS = frozenset("""
a an the and or but so then also too just only really about around approximately approx roughly
probably maybe perhaps likely at least most for of on in by to from until till before after over
under within up it its it's this that these those there here which will would should could can
may might must shall be is are was were been being take takes taking took spend spending spent
need needs i i'm i'll i'd me my we our you min mins minute minutes hr hrs hour hours half today
tonight tomorrow morning afternoon evening night sometime later soon early earlier am pm
monday tuesday wednesday thursday friday saturday sunday high low medium normal priority urgent
important optional one two three four five
""".split())

_LEADING_DANGLING = frozenset(
    "on of for about around at with to by than and or but which it there take takes spend".split()
)
_TRAILING_DANGLING = frozenset(
    "about around for at by take takes least most than the a an to and or but which is of with "
    "sometime approximately roughly probably spend in on".split()
)


def _content_words(text: str) -> List[str]:
    words = re.findall(r"[a-z][a-z']*", text.lower())
    return [w for w in words if len(w) > 1 and w not in _NON_CONTENT_WORDS]


def _is_instruction(text: str) -> bool:
    return bool(_INSTRUCTION_RE.match(_LEADING_LINKER_RE.sub('', text.strip())))


def _is_dependent_fragment(text: str) -> bool:
    """True when a clause only describes the previous task (or describes nothing)."""
    stripped = text.strip()
    if _DEPENDENT_START_RE.match(stripped):
        return True
    without_attrs = _DURATION_PHRASE_RE.sub(' ', stripped)
    without_attrs = _CLOCK_TIME_RE.sub(' ', without_attrs)
    return not _content_words(without_attrs)


# ── Sequencing: "after that" / "then" / "after I finish X" ──────────────────
# These phrases are ordering constraints, not words of the title. A linker makes the clause
# that follows it depend on the clause before it.
_SEQ_LINK_ATOM = (
    r"(?:after\s+that|following\s+that|after\s+which|once\s+that(?:['’]s|\s+is)\s+done|then)"
)
_SEQ_LINK_RE = re.compile(
    rf"(?:,\s*)?(?:\band\s+)?\b{_SEQ_LINK_ATOM}\b"
    rf"(?:(?:\s*,\s*|\s+)(?:and\s+)?{_SEQ_LINK_ATOM}\b)*(?:\s*,)?\s*",
    re.IGNORECASE,
)
_FINISH_PHRASE = r"(?:i(?:['’]m|\s+am)?\s+)?(?:finish(?:ed|ing)?|done\s+with)"
_NAMED_PRED_LEAD_RE = re.compile(
    rf"^(?:after|once|when)\s+{_FINISH_PHRASE}\s+(?P<x>[^,]+?)\s*,\s*(?:then\s+)?(?P<y>.+)$",
    re.IGNORECASE,
)
_NAMED_PRED_TAIL_RE = re.compile(
    rf"\s*,?\s*\b(?:(?:after|once|when)\s+{_FINISH_PHRASE}\s+(?P<x1>.+?)|once\s+(?P<x2>.+?)\s+is\s+done)\s*[.!?]*$",
    re.IGNORECASE,
)


def _split_sequential(chunk: str) -> List[Tuple[str, bool]]:
    """Split a chunk on sequencing linkers. The flag says "this segment follows the previous one"."""
    segments: List[Tuple[str, bool]] = []
    pos, follows = 0, False
    for m in _SEQ_LINK_RE.finditer(chunk):
        seg = chunk[pos:m.start()].strip(' ,')
        if seg:
            segments.append((seg, follows))
        follows, pos = True, m.end()
    tail = chunk[pos:].strip(' ,')
    if tail:
        segments.append((tail, follows))
    return segments


def _normalise_leading_named_predecessor(chunk: str) -> str:
    """"After I finish X, do Y" -> "do Y after I finish X" (one form for the extractor)."""
    m = _NAMED_PRED_LEAD_RE.match(chunk.strip())
    if not m or not _content_words(m.group('y')):
        return chunk
    return f"{m.group('y').strip()} after I finish {m.group('x').strip()}"


def _extract_named_predecessor(clause: str) -> Optional[Tuple[str, str]]:
    """("do Y", "X") for "do Y after I finish X" / "... when I'm done with X" / "... once X is done"."""
    m = _NAMED_PRED_TAIL_RE.search(clause)
    if not m:
        return None
    x = (m.group('x1') or m.group('x2') or '').strip()
    stripped = clause[:m.start()].strip(' ,')
    if not _content_words(x) or not _content_words(stripped):
        return None
    return stripped, x


def _match_predecessor(x: str, candidates: List[TaskCandidateResponse], own_index: int) -> Optional[int]:
    """Index of the other candidate whose title best overlaps the named predecessor, if any."""
    wanted = set(_content_words(x))
    best, best_score = None, 0
    for j, c in enumerate(candidates):
        if j == own_index:
            continue
        score = len(wanted & set(_content_words(c.title)))
        if score > best_score:
            best, best_score = j, score
    return best


def _strip_title_openers(text: str) -> str:
    t = text.strip()
    for _ in range(4):
        nxt = _TITLE_OPENER_RE.sub('', t).strip()
        if nxt == t:
            break
        t = nxt
    return t


def _title_head(clause: str) -> str:
    """The clause's naming part: first sentence, minus a descriptive tail."""
    head = re.split(r'(?<=[.!?])\s+', clause.strip(), maxsplit=1)[0]
    head = re.sub(r'[.!?]+$', '', head).strip()
    cut = _TITLE_TAIL_RE.sub('', head).strip()
    if _content_words(cut):
        head = cut
    return head


def _repair_title(title: str) -> str:
    t = re.sub(r'\s+([.,;:!?])', r'\1', title)
    t = re.sub(r'[,;:\s]+$', '', t)
    t = re.sub(r'[.!?]+$', '', t).strip()
    t = re.sub(r'\s+(?:on|at|by|in)$', '', t, flags=re.IGNORECASE).strip()
    return re.sub(r'\s+', ' ', t)


def _is_malformed_title(title: str) -> bool:
    t = title.strip()
    if not t or not _content_words(t):
        return True
    if re.search(r'\s[.,;:!?]|[,;:]$|^[.,;:!?]', t):
        return True
    words = re.sub(r'[.!?]+$', '', t).lower().split()
    return words[0] in _LEADING_DANGLING or words[-1] in _TRAILING_DANGLING


class AIService:
    """
    Service responsible for Natural Language Task Parsing.
    Strictly suggests structured task candidates for quick user confirmation.
    NEVER creates tasks directly or makes unilateral scheduling decisions.
    """

    @staticmethod
    def _split_clauses(text: str) -> List[str]:
        return [clause for clause, _ in AIService._split_clauses_with_links(text)]

    @staticmethod
    def _split_clauses_with_links(text: str) -> List[Tuple[str, bool]]:
        """(clause, follows_previous) pairs. ``follows_previous`` is set for a clause introduced by a
        sequencing linker ("then", "after that", "once that's done", ...)."""
        clean = text.strip()
        clean = re.sub(
            r'^(?:i have|i\'ve got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+',
            '', clean, flags=re.IGNORECASE,
        ).strip()

        # Split on newlines, semicolons, and bullet markers, then on sentences.
        # IMPORTANT: Do NOT split on hyphens surrounded by word/digit chars
        # (e.g. "9-6", "9am-5pm", "1-on-1" must stay intact).
        # Only split on hyphens that are list-item bullets (preceded by
        # start-of-string or whitespace AND followed by whitespace or end).
        primary_chunks = [
            s.strip()
            for c in re.split(r'[\n;•\*]|(?<!\w)-(?!\w)', clean)
            for s in re.split(r'(?<=[.!?])\s+', c)
            if s.strip()
        ]
        clauses: List[Tuple[str, bool]] = []

        act_words = r'(?:gym|workout|work|assignments?|homework|dentist|doctor|groceries|meeting|emails?)'
        action_verbs = (
            r'(?:finish|study|go\s+to|gym|workout|review|call|email|buy|read|write|prep|pay|'
            r'meet|clean|submit|update|complete|walk|exercise|run|dentist|doctor|work|fix|'
            r'spend|reply|check|prepare|schedule)'
        )

        for chunk in primary_chunks:
            if _is_instruction(chunk):
                continue
            chunk = _normalise_leading_named_predecessor(chunk)
            # "finish X and then submit it" is one intention: never split it on the linker.
            chunk_has_pronoun_ref = bool(
                re.search(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', chunk.lower()))
            segments = [(chunk, False)] if chunk_has_pronoun_ref else _split_sequential(chunk)

            for segment, seg_follows in segments:
                if _is_instruction(segment):
                    continue
                lower = segment.strip().lower()
                is_single_transitive = bool(re.match(r'^(?:finish|complete|submit|review|write|read|work on)\b', lower))
                has_pronoun_ref = bool(re.search(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', lower))

                parts: List[str] = []
                if not is_single_transitive and not has_pronoun_ref:
                    norm_chunk = segment
                    for _ in range(3):
                        norm_chunk = re.sub(
                            rf'\b({act_words})\s+({act_words})\b',
                            r'\1, \2', norm_chunk, flags=re.IGNORECASE,
                        )
                    list_match = re.split(r'(?:,\s*(?:and\s+)?|\s+and\s+)', norm_chunk, flags=re.IGNORECASE)
                    valid_list = [p.strip() for p in list_match if p.strip()]
                    if len(valid_list) > 1 and all(len(p) > 1 for p in valid_list):
                        parts = valid_list

                if not parts:
                    pattern = rf'(?:,\s*(?:and|then|and then)\s+|\s+(?:and then|then)\s+|,\s*(?:(?:maybe|probably|also|i should)\s+)?(?={action_verbs}\b)|\s+and\s+(?={action_verbs}\b(?!\s+(?:it|them)\b)))'
                    parts = [p.strip() for p in re.split(pattern, segment, flags=re.IGNORECASE) if p.strip()]

                for k, part in enumerate(parts):
                    clauses.append((part, seg_follows and k == 0))

        # One intention -> one clause: attribute-only and back-referring parts
        # attach to the clause before them; instructions are dropped. A
        # dependent part with nothing to attach to is an orphan and is dropped.
        units: List[Tuple[str, bool]] = []
        for part, follows in clauses:
            if _is_instruction(part):
                continue
            if _is_dependent_fragment(part):
                if units:
                    joiner = ' ' if re.search(r'[.!?]$', units[-1][0]) else ', '
                    units[-1] = (f"{units[-1][0]}{joiner}{part}", units[-1][1])
                continue
            units.append((part, follows))

        return units

    @classmethod
    def _parse_clauses_with_sequence(
        cls, raw_text: str, now_local: datetime, tz: ZoneInfo
    ) -> List[TaskCandidateResponse]:
        """Parse each clause and wire ordering: a clause after a linker depends on the one before it,
        and "after I finish X" depends on the candidate that names X (when there is one)."""
        candidates: List[TaskCandidateResponse] = []
        meta: List[Tuple[str, bool, Optional[Tuple[str, str]]]] = []
        for raw_clause, follows in cls._split_clauses_with_links(raw_text):
            named = _extract_named_predecessor(raw_clause)
            candidate = cls._parse_single_clause(named[0] if named else raw_clause, now_local, tz)
            if candidate:
                candidates.append(candidate)
                meta.append((raw_clause, follows, named))

        # Pass A: resolve named predecessors. An unmatched phrase is left in the title, untouched.
        pred_of: Dict[int, int] = {}
        for i, (raw_clause, _follows, named) in enumerate(meta):
            if not named:
                continue
            j = _match_predecessor(named[1], candidates, i)
            if j is not None:
                pred_of[i] = j
                continue
            restored = cls._parse_single_clause(raw_clause, now_local, tz)
            if restored:
                restored.candidate_id = candidates[i].candidate_id
                candidates[i] = restored

        # Pass B: assign dependencies.
        for i, c in enumerate(candidates):
            deps: List[str] = []
            if i in pred_of:
                deps.append(candidates[pred_of[i]].candidate_id)
            if meta[i][1] and i > 0 and candidates[i - 1].candidate_id not in deps:
                deps.append(candidates[i - 1].candidate_id)
            if deps:
                c.depends_on = deps
        if any(c.depends_on for c in candidates):
            resolve_dependencies(candidates, {c.candidate_id: c.candidate_id for c in candidates})
        return candidates

    @classmethod
    def _link_from_text(cls, candidates: List[TaskCandidateResponse], raw_text: str) -> None:
        """Safety net for model output that carries no ordering: reuse the order the user wrote."""
        link_sequential_from_text(candidates, [f for _, f in cls._split_clauses_with_links(raw_text)])

    @classmethod
    def validate_and_segment_candidates(
        cls,
        candidates: List[TaskCandidateResponse],
        now_local: datetime,
        tz: ZoneInfo,
    ) -> List[TaskCandidateResponse]:
        valid_candidates: List[TaskCandidateResponse] = []
        for c in candidates:
            provenance_map = c.field_provenance or {}
            is_gemini_derived = any(
                p is not None and getattr(p, "source", None) == "gemini"
                for p in provenance_map.values()
            )
            if is_gemini_derived:
                # The model decided the task boundaries. Never re-split them with
                # the deterministic regex splitter: it orphans attributes and
                # discards the model's durations, priorities and temporal fields.
                valid_candidates.append(c)
                continue

            lower_title = c.title.lower()
            is_single_transitive = bool(re.match(r'^(?:finish|complete|submit|review|write|read|work on)\b', lower_title))
            has_pronoun_ref = bool(re.search(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', lower_title))

            act_words = r'(?:gym|workout|work|assignments?|homework|dentist|doctor|groceries|meeting|emails?)'
            has_multi = bool(re.search(rf'\b{act_words}\b.*?\b(?:and\s+)?{act_words}\b', lower_title))

            if not is_single_transitive and not has_pronoun_ref and has_multi:
                sub_clauses = cls._split_clauses(c.title)
                if len(sub_clauses) > 1:
                    for sc in sub_clauses:
                        sub_cand = cls._parse_single_clause(sc, now_local, tz)
                        if sub_cand:
                            valid_candidates.append(sub_cand)
                    continue

            valid_candidates.append(c)

        prune_dangling(valid_candidates)
        return valid_candidates

    @classmethod
    def parse_task_dump(
        cls,
        raw_text: str,
        user_timezone_str: str = "UTC",
        force_ai: bool = False,
        ai_gate=None,
    ) -> List[TaskCandidateResponse]:
        """``ai_gate`` is an optional zero-arg callable consulted before every cloud call; returning False
        keeps the request on the local parser (used to meter AI parsing per user)."""
        if not raw_text or not raw_text.strip():
            return []

        request_id = uuid.uuid4().hex[:12]
        pipeline_started_at = clock.perf_counter()

        tz, _ = resolve_timezone(user_timezone_str, None)

        now_local = datetime.now(tz)

        if force_ai and settings.GEMINI_API_KEY and (ai_gate is None or ai_gate()):
            gemini_candidates = cls._try_gemini_fallback(
                raw_text, now_local, tz, request_id=request_id
            )
            if gemini_candidates:
                cls._link_from_text(gemini_candidates, raw_text)
                segmented = cls.validate_and_segment_candidates(gemini_candidates, now_local, tz)
                logger.info(
                    "ai_service.parse_task_dump path=force_ai request_id=%s candidates=%s latency_ms=%s",
                    request_id, len(segmented),
                    round((clock.perf_counter() - pipeline_started_at) * 1000),
                )
                return segmented

        candidates = cls._parse_clauses_with_sequence(raw_text, now_local, tz)
        candidates = cls.validate_and_segment_candidates(candidates, now_local, tz)

        if not candidates and len(raw_text.strip()) > 2:
            logger.info(
                "ai_service.parse_task_dump path=deterministic_zero request_id=%s falling_back=true",
                request_id,
            )
            if settings.GEMINI_API_KEY and (ai_gate is None or ai_gate()):
                gemini_candidates = cls._try_gemini_fallback(
                    raw_text, now_local, tz, request_id=request_id
                )
                if gemini_candidates:
                    cls._link_from_text(gemini_candidates, raw_text)
                    segmented = cls.validate_and_segment_candidates(gemini_candidates, now_local, tz)
                    logger.info(
                        "ai_service.parse_task_dump path=gemini_fallback request_id=%s candidates=%s latency_ms=%s",
                        request_id, len(segmented),
                        round((clock.perf_counter() - pipeline_started_at) * 1000),
                    )
                    return segmented

            llm_candidates = cls._try_ollama_fallback(raw_text, now_local, tz)
            if llm_candidates:
                return cls.validate_and_segment_candidates(llm_candidates, now_local, tz)

            logger.warning(
                "ai_service.parse_task_dump path=unparseable request_id=%s",
                request_id,
            )
            return [
                TaskCandidateResponse(
                    title=sanitize_task_title(raw_text.strip()[:100]),
                    estimated_minutes=45,
                    task_type=TaskType.deep_work,
                    difficulty=TaskDifficulty.medium,
                    priority=TaskPriority.medium,  # sentinel — see priority invariant
                    category="General",
                    confidence=0.30,
                    missing_fields=["duration", "deadline", "priority", "task_type"],
                    ambiguities=["parse_failure", "priority_unspecified"],
                    source=TaskSource.ai_parsed,
                    field_provenance={
                        "priority": FieldProvenance(source="unspecified", confidence=0.0),
                        "task_type": FieldProvenance(source="default", confidence=0.40),
                        "duration": FieldProvenance(source="default", confidence=0.40),
                    },
                )
            ]

        logger.info(
            "ai_service.parse_task_dump path=deterministic request_id=%s candidates=%s latency_ms=%s",
            request_id, len(candidates),
            round((clock.perf_counter() - pipeline_started_at) * 1000),
        )
        return candidates

    @classmethod
    def _parse_single_clause(
        cls, clause: str, now_local: datetime, tz: ZoneInfo
    ) -> Optional[TaskCandidateResponse]:
        title = clause.strip()
        lower = clause.lower()

        # ── Context-statement guard ───────────────────────────────────────────
        # Phrases that describe AVAILABILITY or CONTEXT should NOT become task
        # cards. They are handled by the Gemini planning_context path instead.
        # Patterns:
        #   "work from 9-6" / "working 9 to 6" / "office 9 to 5"
        #   "class from 2 to 5" / "I have class from 2-4"
        #   "leave home at 8:30" / "I leave at 8:30"
        #   "lunch at 1" / "lunch around 1"  (standalone with no actionable verb)
        #   "I work from 9 to 5"
        _CONTEXT_PATTERNS = [
            # work/office/class availability window
            r'^\s*(?:i\s+)?(?:work|working|office|in\s+office)\s+(?:from\s+)?(?:\d[\d:apm]*)\s*(?:[-–to]+\s*\d[\d:apm]*)',
            # class/school from X to Y / class from X-Y
            r'^\s*(?:i\s+have\s+)?class\s+(?:from\s+)?(?:\d[\d:apm]*)\s*(?:[-–to]+\s*\d[\d:apm]*)',
            # leave / leaving / leave home at X
            r'^\s*(?:i\s+)?lea(?:ve|ving)(?:\s+home)?\s+at\s+\d',
            # standalone lunch/breakfast/dinner at X (no other verb, no "with")
            r'^\s*(?:lunch|breakfast|dinner)\s+(?:at|around)\s+\d[\d:]*(?: ?[apm]*)?\s*$',
        ]
        for pat in _CONTEXT_PATTERNS:
            if re.match(pat, lower, re.IGNORECASE):
                return None
        # ─────────────────────────────────────────────────────────────────────

        # Orphan guard: a clause with nothing but attributes ("It will probably
        # take around 90 minutes") names no task.
        if not _content_words(_CLOCK_TIME_RE.sub(' ', _DURATION_PHRASE_RE.sub(' ', clause))):
            return None

        # The title comes from the naming part of the clause only. Duration
        # phrases are removed together with their lead-in words so no broken
        # prose ("take around .") is left behind.
        head = _title_head(clause)
        title = re.sub(r'\s+', ' ', _DURATION_PHRASE_RE.sub(' ', head)).strip()

        missing_fields: List[str] = []
        ambiguities: List[str] = []
        provenance: Dict[str, FieldProvenance] = {}

        # 1. Duration Extraction
        duration = 45
        duration_found = False

        num_match = re.search(
            r'\b(?:for\s+)?(\d+(?:\.\d+)?)\s*(mins?|minutes?|m|hrs?|hours?|h)\b', lower
        )
        if num_match:
            qty = float(num_match.group(1))
            unit = num_match.group(2)
            if 'h' in unit:
                duration = min(480, int(qty * 60))
            else:
                duration = min(480, max(5, int(qty)))
            duration_found = True
            provenance["duration"] = FieldProvenance(source="explicit", confidence=1.0)
            title = re.sub(
                r'\b(?:for\s+)?\d+(?:\.\d+)?\s*(?:mins?|minutes?|m|hrs?|hours?|h)\b',
                '', title, flags=re.IGNORECASE,
            ).strip()
        else:
            word_match = re.search(
                r'\b(?:for\s+)?(half an hour|an hour|one hour|two hours|three hours|four hours)\b',
                lower,
            )
            if word_match:
                w = word_match.group(1).lower()
                if "half" in w:
                    duration = 30
                elif "one" in w or "an hour" in w:
                    duration = 60
                elif "two" in w:
                    duration = 120
                elif "three" in w:
                    duration = 180
                elif "four" in w:
                    duration = 240
                duration_found = True
                provenance["duration"] = FieldProvenance(source="explicit", confidence=0.95)
                title = re.sub(
                    r'\b(?:for\s+)?(?:half an hour|an hour|one hour|two hours|three hours|four hours)\b',
                    '', title, flags=re.IGNORECASE,
                ).strip()

        if not duration_found:
            missing_fields.append("duration")
            provenance["duration"] = FieldProvenance(source="default", confidence=0.50)

        # 2. Target Date (today / tonight / tomorrow / weekday)
        scheduled_start: Optional[datetime] = None
        scheduled_end: Optional[datetime] = None
        temporal = TemporalConstraints(confidence=1.0)

        target_date = now_local.date()
        if re.search(r'\btomorrow\b', lower):
            target_date = now_local.date() + timedelta(days=1)
            temporal.target_date = target_date
            temporal.provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)
            provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)
        elif re.search(r'\b(?:today|tonight)\b', lower):
            target_date = now_local.date()
            temporal.target_date = target_date
            temporal.provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)
            provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)
        else:
            weekday_match = re.search(rf'\b({_WEEKDAY_REGEX})\b', lower)
            if weekday_match:
                prefix = lower[:weekday_match.start()]
                is_deadline_prefix = bool(re.search(r'\b(?:by|due|before)\s*$', prefix))
                if not is_deadline_prefix:
                    weekday_name = weekday_match.group(1)
                    target_date = _resolve_weekday_date(weekday_name, now_local)
                    temporal.target_date = target_date
                    temporal.provenance["target_date"] = FieldProvenance(source="explicit", confidence=0.95)
                    provenance["target_date"] = FieldProvenance(source="explicit", confidence=0.95)

        # 3. Time-of-day extraction
        time_match = _CLOCK_TIME_RE.search(lower)
        if time_match and (
            int(time_match.group(1)) > 23 or int(time_match.group(2) or 0) > 59
        ):
            time_match = None
        if time_match:
            raw_hour = int(time_match.group(1))
            raw_min = int(time_match.group(2)) if time_match.group(2) else 0
            ampm = time_match.group(3)

            target_hour = raw_hour
            has_explicit_ampm = ampm is not None
            if has_explicit_ampm:
                if ampm == "pm" and raw_hour < 12:
                    target_hour += 12
                elif ampm == "am" and raw_hour == 12:
                    target_hour = 0
                provenance["scheduled_time"] = FieldProvenance(source="explicit", confidence=1.0)
            else:
                ambiguities.append("time_am_pm")
                provenance["scheduled_time"] = FieldProvenance(source="inferred", confidence=0.70)
                if 1 <= raw_hour <= 7:
                    target_hour = raw_hour + 12
                else:
                    target_hour = raw_hour

            sched_local = datetime.combine(target_date, time(target_hour, raw_min), tzinfo=tz)
            is_around = lower[time_match.start():].startswith("around")

            if is_around or not has_explicit_ampm:
                temporal.preferred_start = sched_local
                temporal.preferred_window_start = sched_local - timedelta(minutes=45)
                temporal.preferred_window_end = sched_local + timedelta(minutes=45)
                temporal.flexibility = "preferred"
                temporal.provenance["preferred_window"] = FieldProvenance(
                    source="inferred" if not has_explicit_ampm else "explicit",
                    confidence=0.70 if not has_explicit_ampm else 0.95,
                )
            else:
                scheduled_start = sched_local
                scheduled_end = scheduled_start + timedelta(minutes=duration)
                temporal.fixed_start = sched_local
                temporal.flexibility = "fixed"
                temporal.provenance["fixed_start"] = FieldProvenance(source="explicit", confidence=1.0)

            title = _CLOCK_TIME_RE.sub('', title).strip()

        # 3b. "before HH:MM [am/pm]" — explicit deadline
        before_time_match = re.search(r'\bbefore\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', lower)
        deadline_at: Optional[datetime] = None
        deadline_found = False
        if before_time_match:
            bh = int(before_time_match.group(1))
            bm = int(before_time_match.group(2) or 0)
            bampm = before_time_match.group(3)
            if bampm == "pm" and bh < 12:
                bh += 12
            elif bampm == "am" and bh == 12:
                bh = 0
            dl = datetime.combine(target_date, time(bh, bm), tzinfo=tz)
            deadline_at = dl
            deadline_found = True
            temporal.latest_end = dl
            if temporal.flexibility != "fixed":
                temporal.flexibility = "constrained"
            temporal.provenance["latest_end"] = FieldProvenance(source="explicit", confidence=1.0)
            provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
            title = re.sub(
                r'\bbefore\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\b',
                '', title, flags=re.IGNORECASE,
            ).strip()

        # 3c. "after HH:MM [am/pm]" -> earliest_start
        after_match = re.search(r'\b(?:sometime\s+)?after\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', lower)
        if after_match:
            h, m, ampm = int(after_match.group(1)), int(after_match.group(2) or 0), after_match.group(3)
            if ampm == "pm" and h < 12:
                h += 12
            elif ampm == "am" and h == 12:
                h = 0
            temporal.earliest_start = datetime.combine(target_date, time(h, m), tzinfo=tz)
            temporal.flexibility = "constrained"
            temporal.provenance["earliest_start"] = FieldProvenance(source="explicit", confidence=1.0)

        # 4. Relative meal anchors (relation is explicit; resolved time is default)
        elif "after dinner" in lower:
            temporal.earliest_start = datetime.combine(target_date, time(20, 0), tzinfo=tz)
            temporal.relative_after = "dinner"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)
        elif "after lunch" in lower:
            temporal.earliest_start = datetime.combine(target_date, time(13, 0), tzinfo=tz)
            temporal.relative_after = "lunch"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)
        elif "after breakfast" in lower:
            temporal.earliest_start = datetime.combine(target_date, time(7, 30), tzinfo=tz)
            temporal.relative_after = "breakfast"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)

        # 5. Relative "before" anchors
        if "before dinner" in lower:
            temporal.latest_end = datetime.combine(target_date, time(20, 0), tzinfo=tz)
            temporal.relative_before = "dinner"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["latest_end"] = FieldProvenance(source="default", confidence=0.60)
        elif "before lunch" in lower:
            temporal.latest_end = datetime.combine(target_date, time(13, 0), tzinfo=tz)
            temporal.relative_before = "lunch"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["latest_end"] = FieldProvenance(source="default", confidence=0.60)
        elif "before breakfast" in lower:
            temporal.latest_end = datetime.combine(target_date, time(7, 30), tzinfo=tz)
            temporal.relative_before = "breakfast"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=0.95)
            temporal.provenance["latest_end"] = FieldProvenance(source="default", confidence=0.60)
        elif re.search(r'\bbefore (?:i )?(?:sleep|bed)\b', lower):
            temporal.relative_before = "bedtime"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=1.0)

        # 6. Day-part windows (only when not already fixed/constrained and no window set)
        # IMPORTANT: "night" normalizes to the evening window. It is NOT a fixed
        # clock time and must NOT invent an 8 PM or 9 PM fixed_start.
        # FIX: The old condition `or not temporal.provenance` blocked this when
        # target_date was already in provenance. Now we gate only on:
        #   - flexibility not already locked to fixed/constrained
        #   - no preferred_window already set
        _no_window_yet = "preferred_window" not in temporal.provenance and temporal.preferred_window_start is None
        if temporal.flexibility not in ("fixed", "constrained") and _no_window_yet:
            if "in the evening" in lower or re.search(r'\b(?:evening|night)\b', lower):
                temporal.preferred_window_start = datetime.combine(target_date, time(17, 0), tzinfo=tz)
                temporal.preferred_window_end = datetime.combine(target_date, time(21, 0), tzinfo=tz)
                temporal.flexibility = "preferred"
                temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.9)
            elif re.search(r'\bafternoon\b', lower):
                temporal.preferred_window_start = datetime.combine(target_date, time(12, 0), tzinfo=tz)
                temporal.preferred_window_end = datetime.combine(target_date, time(17, 0), tzinfo=tz)
                temporal.flexibility = "preferred"
                temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.9)
            elif "morning" in lower:
                temporal.preferred_window_start = datetime.combine(target_date, time(8, 0), tzinfo=tz)
                temporal.preferred_window_end = datetime.combine(target_date, time(12, 0), tzinfo=tz)
                temporal.flexibility = "preferred"
                temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.9)

        # 7. Deadline (by/due/before <tomorrow|today|tonight|weekday>)
        if not deadline_found:
            deadline_match = re.search(
                r'\b(?:by|due)\s+(?:(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+)?tomorrow\b', lower
            )
            if deadline_match:
                hour_text, minute_text, ampm = deadline_match.groups()
                h, m = 23, 59
                if hour_text:
                    h, m = int(hour_text), int(minute_text or 0)
                    if ampm == "pm" and h < 12:
                        h += 12
                    elif ampm == "am" and h == 12:
                        h = 0
                d_local = datetime.combine(target_date, time(h, m), tzinfo=tz)
                deadline_at = d_local
                deadline_found = True
                provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
                title = re.sub(
                    r'\b(?:by|due)\s+(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s+)?tomorrow\b',
                    '', title, flags=re.IGNORECASE,
                ).strip()
            elif re.search(r'\b(?:by|due)\s+(?:today|tonight)\b', lower):
                d_local = datetime.combine(now_local.date(), time(23, 59), tzinfo=tz)
                deadline_at = d_local
                deadline_found = True
                provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
                title = re.sub(
                    r'\b(?:by|due|on|before)?\s*(?:today|tonight)\b',
                    '', title, flags=re.IGNORECASE,
                ).strip()
            else:
                wd_deadline_match = re.search(
                    rf'\b(?:by|due|before)\s+({_WEEKDAY_REGEX})\b', lower
                )
                if wd_deadline_match:
                    weekday_name = wd_deadline_match.group(1)
                    dl_date = _resolve_weekday_date(weekday_name, now_local)
                    phrase = wd_deadline_match.group(0).split()[0]
                    d_local = resolve_deadline(dl_date, None, phrase, tz)
                    deadline_at = d_local
                    deadline_found = True
                    provenance["deadline"] = FieldProvenance(source="explicit", confidence=0.95)
                    title = re.sub(
                        rf'\b(?:by|due|before)\s+{_WEEKDAY_REGEX}\b',
                        '', title, flags=re.IGNORECASE,
                    ).strip()

        # Remove residual timing words from the display title.
        title = re.sub(
            rf'\b{_WEEKDAY_REGEX}\s+(?:morning|afternoon|evening|night)\b',
            '', title, flags=re.IGNORECASE,
        ).strip()
        title = re.sub(
            rf'\b{_WEEKDAY_REGEX}\b',
            '', title, flags=re.IGNORECASE,
        ).strip()

        title = re.sub(
            r'\b(?:sometime\s+)?after\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b|'
            r'\b(?:after|before)\s+(?:dinner|lunch|breakfast)\b|\bbefore\s+(?:i\s+)?(?:sleep|bed)\b|'
            r'\b(?:tomorrow|today|tonight)(?:\s+(?:morning|evening|night))?\b|\b(?:sometime\s+)?in\s+the\s+evening\b|'
            r'\b(?:around|before|after)\s+(?:dinner|lunch|breakfast)\s+time\b|'
            r'\b(?:in\s+the\s+)?night\b',
            '', title, flags=re.IGNORECASE,
        ).strip()

        if not deadline_found and not scheduled_start and not temporal.target_date:
            missing_fields.append("deadline")

        # 8. Priority (explicit only; never silently invent)
        explicit_priority = None
        if re.search(r'\b(?:urgent|critical|p0|asap)\b', lower):
            explicit_priority = TaskPriority.urgent
            title = re.sub(r'\b(?:urgent|critical|p0|asap)\b', '', title, flags=re.IGNORECASE).strip()
        # "the important stuff" refers to other tasks, not to this one.
        elif re.search(r'\b(?:high\s+priority|p1|(?<!the\s)(?<!other\s)(?<!more\s)important|top\s+priority)\b', lower):
            explicit_priority = TaskPriority.high
            title = re.sub(
                r'\b(?:high\s+priority|p1|(?<!the\s)(?<!other\s)(?<!more\s)important|top\s+priority)\b',
                '', title, flags=re.IGNORECASE,
            ).strip()
        elif re.search(r'\b(?:low\s+priority|p3|optional)\b', lower):
            explicit_priority = TaskPriority.low
            title = re.sub(
                r'\b(?:low\s+priority|p3|optional)\b',
                '', title, flags=re.IGNORECASE,
            ).strip()
        elif re.search(r'\b(?:medium\s+priority|p2|normal\s+priority)\b', lower):
            explicit_priority = TaskPriority.medium
            title = re.sub(
                r'\b(?:medium\s+priority|p2|normal\s+priority)\b',
                '', title, flags=re.IGNORECASE,
            ).strip()

        # 9. Classification priors
        task_type = TaskType.deep_work
        difficulty = TaskDifficulty.medium
        # NOTE: priority is set below based on explicit_priority. The
        # TaskPriority.medium sentinel is only used when the user did not
        # specify — see the priority invariant near the end of this method.
        priority = explicit_priority or TaskPriority.medium
        category = "General"

        title = re.sub(
            r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+)', '', title, flags=re.IGNORECASE,
        ).strip()
        title = sanitize_task_title(_repair_title(_strip_title_openers(title)))
        if _is_malformed_title(title):
            # Attribute removal broke the sentence: keep the user's own words
            # (minus a cleanly removable duration phrase).
            title = sanitize_task_title(_repair_title(_strip_title_openers(
                _DURATION_PHRASE_RE.sub(' ', head)
            )))
            if _is_malformed_title(title):
                title = sanitize_task_title(_repair_title(_strip_title_openers(head)))
        lower_title = title.lower()

        meeting_words = ["meeting", "standup", "stand-up", "1:1", "1-on-1", "interview"]
        physical_words = ["gym", "workout", "run", "lift", "stretch", "walk", "exercise", "training"]
        deep_work_words = [
            "assignment", "assignments", "code", "coding", "paper", "research", "build",
            "design", "ml", "math", "develop", "thesis", "algorithm", "work", "sync", "project",
        ]
        study_words = [
            "study", "review", "read", "reading", "notes", "quiz", "prep",
            "exam", "dbms", "lecture", "homework",
        ]
        admin_words = [
            "email", "reply", "pay", "submit", "file", "call", "organize",
            "grocery", "groceries", "buy", "dentist", "doctor",
        ]

        if any(w in lower_title for w in physical_words):
            task_type = TaskType.physical
            difficulty = TaskDifficulty.physical
            category = "Fitness"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.92)
        elif any(w in lower_title for w in meeting_words):
            task_type = TaskType.meeting
            difficulty = TaskDifficulty.medium
            category = "Work"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        elif any(w in lower_title for w in deep_work_words):
            task_type = TaskType.deep_work
            difficulty = (
                TaskDifficulty.high
                if any(w in lower_title for w in ["assignment", "thesis", "ml", "algorithm"])
                else TaskDifficulty.medium
            )
            category = (
                "College"
                if any(w in lower_title for w in ["assignment", "assignments", "thesis"])
                else "Work"
            )
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.88)
        elif any(w in lower_title for w in study_words):
            task_type = TaskType.study
            difficulty = TaskDifficulty.medium
            category = "College"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        elif any(w in lower_title for w in admin_words):
            task_type = TaskType.admin
            difficulty = TaskDifficulty.light
            category = "Personal"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        else:
            provenance["task_type"] = FieldProvenance(source="default", confidence=0.50)

        if explicit_priority is not None:
            provenance["priority"] = FieldProvenance(source="explicit", confidence=1.0)
        else:
            missing_fields.append("priority")
            ambiguities.append("priority_unspecified")
            provenance["priority"] = FieldProvenance(source="unspecified", confidence=0.0)

        if not title:
            return None

        conf_scores = [p.confidence for p in provenance.values() if p.source != "unspecified"]
        avg_conf = sum(conf_scores) / len(conf_scores) if conf_scores else 0.80
        if ambiguities:
            avg_conf *= 0.88
        if "duration" in missing_fields:
            avg_conf *= 0.90
        overall_confidence = _clamp_confidence(avg_conf, default=0.50)

        target_date_out = temporal.target_date if (temporal and temporal.target_date) else None
        fixed_start_out = scheduled_start.strftime("%H:%M") if scheduled_start else None
        deadline_out = deadline_at.strftime("%Y-%m-%d") if deadline_at else None

        return TaskCandidateResponse(
            title=title,
            estimated_minutes=duration,
            task_type=task_type,
            difficulty=difficulty,
            priority=priority,
            category=category,
            deadline_at=deadline_at,
            scheduled_start=scheduled_start,
            scheduled_end=scheduled_end,
            target_date=target_date_out,
            fixed_start=fixed_start_out,
            deadline=deadline_out,
            source=TaskSource.ai_parsed,
            confidence=overall_confidence,
            missing_fields=missing_fields,
            ambiguities=ambiguities,
            field_provenance=provenance,
            temporal=temporal if temporal.provenance else None,
        )

    @classmethod
    def _try_gemini_fallback(
        cls,
        raw_text: str,
        now_local: datetime,
        tz: ZoneInfo,
        request_id: Optional[str] = None,
    ) -> Optional[List[TaskCandidateResponse]]:
        try:
            res = cls.extract_structured_plan_with_gemini(
                raw_text, user_timezone_str=str(tz), request_id=request_id
            )
            return res[0]
        except Exception as e:
            logger.warning(
                "ai_service.gemini_fallback_failed request_id=%s error_class=%s",
                request_id, type(e).__name__,
            )
            return None

    @classmethod
    def extract_structured_plan_with_gemini(
        cls,
        raw_text: str,
        user_timezone_str: str = "UTC",
        request_id: Optional[str] = None,
        now_local: Optional[datetime] = None,
    ) -> Tuple[List[TaskCandidateResponse], List[str], bool, PlanningContext]:
        api_key = settings.GEMINI_API_KEY
        if not api_key:
            raise RuntimeError("Gemini API key is not configured on server.")

        request_id = request_id or uuid.uuid4().hex[:12]

        tz, _ = resolve_timezone(user_timezone_str, None)

        # "today" / "tmrw" / "friday" resolve against the client's clock when it sent one.
        now_local = now_local.astimezone(tz) if now_local is not None else datetime.now(tz)
        today_str = now_local.strftime("%Y-%m-%d")

        prompt = _build_initial_gemini_prompt(raw_text, today_str, user_timezone_str)

        raw_json_str = cls._gemini_generate(prompt, api_key, request_id=request_id)
        parsed = _loads_or_none(raw_json_str)
        if parsed is None:
            # One repair attempt, then fail as malformed (never a silent local fallback).
            repaired = cls._gemini_generate(
                _build_gemini_repair_prompt(raw_json_str), api_key, request_id=request_id, temperature=0.0
            )
            parsed = _loads_or_none(repaired)
        if isinstance(parsed, list):
            parsed = {"tasks": parsed, "ambiguities": []}
        if not isinstance(parsed, dict) or not isinstance(parsed.get("tasks"), list):
            raise GeminiFailure("malformed", "Gemini returned output that could not be read as a task list.")

        top_level_ambiguities = parsed.get("ambiguities", [])
        if not isinstance(top_level_ambiguities, list):
            top_level_ambiguities = []

        ref_map: Dict[str, str] = {}
        candidate_objects = cls._map_gemini_tasks_to_candidates(
            tasks_raw=parsed["tasks"],
            top_level_ambiguities=top_level_ambiguities,
            now_local=now_local,
            tz=tz,
            ref_map=ref_map,
        )
        if not candidate_objects:
            raise GeminiFailure("empty", "Gemini found no tasks in the text.")
        resolve_dependencies(candidate_objects, ref_map)

        planning_context_obj = cls._map_gemini_planning_context(
            ctx_raw=parsed.get("planning_context", {}) or {},
            default_target_date=now_local.date(),
        )
        overall_needs_confirmation = any("needs_confirmation" in (c.ambiguities or []) for c in candidate_objects)
        return candidate_objects, top_level_ambiguities, overall_needs_confirmation, planning_context_obj

    # Most actionable first: when several models fail differently, the earliest-ranked class is reported.
    _GEMINI_FAILURE_RANK = ("provider_quota", "provider_auth", "model_not_found", "provider_unavailable",
                            "timeout", "network", "malformed")
    _GEMINI_FAILURE_REASONS = {
        "provider_quota": "Gemini's usage quota is exhausted (HTTP 429)",
        "provider_auth": "Gemini rejected the API key (HTTP {status})",
        "model_not_found": "The configured Gemini model was not found (HTTP 404)",
        "provider_unavailable": "Gemini is overloaded or unavailable (HTTP {status})",
        "timeout": "Gemini did not answer in time",
        "network": "Could not reach Gemini (network error)",
        "malformed": "Gemini returned an empty or unreadable answer",
    }

    @staticmethod
    def _is_invalid_api_key(resp: "httpx.Response") -> bool:
        try:
            details = resp.json().get("error", {}).get("details", []) or []
        except ValueError:
            return False
        return any(isinstance(d, dict) and d.get("reason") == "API_KEY_INVALID" for d in details)

    @classmethod
    def _gemini_generate(cls, prompt: str, api_key: str, *, request_id: str, temperature: float = 0.1) -> str:
        """The only Gemini transport call. Returns the first model's raw text, trying the fallback models
        on model-specific/transient errors. Quota and auth failures stop immediately (other models share the
        project). On failure raises GeminiFailure with the most actionable class seen across all attempts:
        provider_quota, provider_auth, model_not_found, provider_unavailable, timeout, network, malformed,
        or gemini_error (provider rejected the request itself, e.g. HTTP 400)."""
        headers = {"x-goog-api-key": api_key, "Content-Type": "application/json"}
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": temperature,
                "maxOutputTokens": settings.GEMINI_MAX_OUTPUT_TOKENS,
            },
        }
        models_to_try: List[str] = []
        for m in [settings.GEMINI_MODEL, "gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"]:
            if m and m not in models_to_try:
                models_to_try.append(m)
        models_to_try = models_to_try[:max(1, settings.GEMINI_MAX_ATTEMPTS)]  # bounded attempts per call

        seen: Dict[str, int] = {}  # failure class -> provider HTTP status (0 when none)

        def failure() -> GeminiFailure:
            code = next(c for c in cls._GEMINI_FAILURE_RANK if c in seen)
            logger.error("ai_service.gemini_exhausted request_id=%s classes=%s", request_id, sorted(seen))
            return GeminiFailure(code, cls._GEMINI_FAILURE_REASONS[code].format(status=seen[code]))

        deadline = request_deadline.get()  # monotonic instant set by the AI gateway (None = unbounded)

        def time_left() -> Optional[float]:
            return None if deadline is None else deadline - clock.monotonic()

        with httpx.Client(timeout=settings.GEMINI_REQUEST_TIMEOUT_SECONDS) as client:
            for attempt_no, model in enumerate(models_to_try):
                remaining = time_left()
                if remaining is not None and remaining <= 0.25:
                    seen.setdefault("timeout", 0)  # the request deadline, not the provider, ended the attempts
                    break
                request_timeout = settings.GEMINI_REQUEST_TIMEOUT_SECONDS
                if remaining is not None:
                    request_timeout = max(0.25, min(request_timeout, remaining))
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
                started_at = clock.perf_counter()
                error_class, status_code = None, 0
                retry_after = 0.0
                try:
                    resp = client.post(url, headers=headers, json=payload, timeout=request_timeout)
                except httpx.TimeoutException:
                    error_class = "timeout"
                except httpx.HTTPError:
                    error_class = "network"
                else:
                    status_code = resp.status_code
                    if status_code == 200:
                        try:
                            data = resp.json()
                            text = data["candidates"][0]["content"]["parts"][0]["text"]
                        except (ValueError, KeyError, IndexError, TypeError):
                            error_class = "malformed"
                        else:
                            usage = data.get("usageMetadata", {}) or {}
                            logger.info(
                                "ai_service.gemini_ok request_id=%s model=%s latency_ms=%s input_tokens=%s output_tokens=%s",
                                request_id, model, round((clock.perf_counter() - started_at) * 1000),
                                usage.get("promptTokenCount"), usage.get("candidatesTokenCount"),
                            )
                            return text
                    elif status_code == 429:
                        error_class = "provider_quota"
                    elif status_code in (401, 403):
                        error_class = "provider_auth"
                    elif status_code == 404:
                        error_class = "model_not_found"
                    elif status_code in (500, 502, 503, 504):
                        error_class = "provider_unavailable"
                        try:
                            retry_after = min(5.0, float(resp.headers.get("retry-after", 0)))
                        except (TypeError, ValueError):
                            retry_after = 0.0
                    elif status_code == 400 and cls._is_invalid_api_key(resp):
                        error_class = "provider_auth"  # Google reports a bad key as 400, not 401/403
                    else:  # other 400s and anything else: the provider rejected the request itself
                        logger.error("ai_service.gemini_attempt request_id=%s model=%s status=%s", request_id, model, status_code)
                        raise GeminiFailure("gemini_error", f"Gemini rejected the request (HTTP {status_code}).")
                seen.setdefault(error_class, status_code)
                logger.warning("ai_service.gemini_attempt request_id=%s model=%s error_class=%s status=%s",
                               request_id, model, error_class, status_code)
                if error_class in ("provider_quota", "provider_auth"):
                    raise failure()
                if error_class in ("provider_unavailable", "timeout", "network") and attempt_no < len(models_to_try) - 1:
                    # Transient: jittered exponential backoff, never past the request deadline.
                    pause = max(retry_after, settings.GEMINI_BACKOFF_BASE_SECONDS * (2 ** attempt_no)
                                * (0.5 + random.random() / 2))
                    left = time_left()
                    if left is not None:
                        pause = min(pause, max(0.0, left - 0.25))
                    if pause > 0:
                        clock.sleep(pause)

        raise failure()

    @classmethod
    def _map_gemini_planning_context(
        cls,
        ctx_raw: Any,
        default_target_date: Optional[date] = None,
    ) -> PlanningContext:
        if not isinstance(ctx_raw, dict):
            return PlanningContext()

        fixed_events: List[FixedEventContext] = []
        for fe in ctx_raw.get("fixed_events", []):
            if isinstance(fe, dict) and fe.get("title"):
                fe_date = _parse_iso_date(fe.get("target_date")) or default_target_date
                fixed_events.append(FixedEventContext(
                    title=str(fe["title"]).strip(),
                    start_time=str(fe.get("start_time")) if fe.get("start_time") else None,
                    end_time=str(fe.get("end_time")) if fe.get("end_time") else None,
                    duration_minutes=_safe_int(fe.get("duration_minutes"), 45, 5, 480) if fe.get("duration_minutes") else None,
                    target_date=fe_date,
                ))

        travel_segments: List[TravelContext] = []
        for tr in ctx_raw.get("travel_segments", []):
            if isinstance(tr, dict):
                tr_date = _parse_iso_date(tr.get("target_date")) or default_target_date
                travel_segments.append(TravelContext(
                    from_location=str(tr.get("from_location") or "").strip() or None,
                    to_location=str(tr.get("to_location") or "").strip() or None,
                    duration_minutes=_safe_int(tr.get("duration_minutes"), 30, 5, 240),
                    departure_time=str(tr.get("departure_time")) if tr.get("departure_time") else None,
                    target_date=tr_date,
                ))

        protected_periods: List[ProtectedPeriodContext] = []
        for pp in ctx_raw.get("protected_periods", []):
            if isinstance(pp, dict) and pp.get("name"):
                pp_date = _parse_iso_date(pp.get("target_date")) or default_target_date
                protected_periods.append(ProtectedPeriodContext(
                    name=str(pp["name"]).strip(),
                    preferred_start=str(pp.get("preferred_start")) if pp.get("preferred_start") else None,
                    duration_minutes=_safe_int(pp.get("duration_minutes"), 45, 10, 180),
                    is_movable=bool(pp.get("is_movable", True)),
                    target_date=pp_date,
                ))

        availability_windows: List[AvailabilityContext] = []
        for aw in ctx_raw.get("availability_windows", []):
            if isinstance(aw, dict) and aw.get("label"):
                aw_date = _parse_iso_date(aw.get("target_date")) or default_target_date
                availability_windows.append(AvailabilityContext(
                    label=str(aw["label"]).strip(),
                    start_time=str(aw.get("start_time")) if aw.get("start_time") else None,
                    end_time=str(aw.get("end_time")) if aw.get("end_time") else None,
                    target_date=aw_date,
                ))

        task_dependencies: List[TaskDependencyContext] = []
        for td in ctx_raw.get("task_dependencies", []):
            if isinstance(td, dict) and td.get("predecessor") and td.get("successor"):
                task_dependencies.append(TaskDependencyContext(
                    predecessor=str(td["predecessor"]).strip(),
                    successor=str(td["successor"]).strip(),
                ))

        priority_order: List[str] = []
        for p in ctx_raw.get("priority_order", []):
            if isinstance(p, str) and p.strip():
                priority_order.append(p.strip())

        deferred_tasks: List[str] = []
        for d in ctx_raw.get("deferred_tasks", []):
            if isinstance(d, str) and d.strip():
                deferred_tasks.append(d.strip())

        energy_pref = str(ctx_raw.get("energy_preference") or "").strip() or None
        buffer_pref = str(ctx_raw.get("buffer_preference") or "").strip() or None

        return PlanningContext(
            fixed_events=fixed_events,
            travel_segments=travel_segments,
            protected_periods=protected_periods,
            availability_windows=availability_windows,
            task_dependencies=task_dependencies,
            priority_order=priority_order,
            deferred_tasks=deferred_tasks,
            energy_preference=energy_pref,
            buffer_preference=buffer_pref,
        )

    @classmethod
    def _map_gemini_tasks_to_candidates(
        cls,
        tasks_raw: List[Dict[str, Any]],
        top_level_ambiguities: List[str],
        now_local: datetime,
        tz: ZoneInfo,
        ref_map: Optional[Dict[str, str]] = None,
    ) -> List[TaskCandidateResponse]:
        """ref_map (out): Gemini task ref -> candidate_id. candidate.depends_on holds raw refs until
        candidate_dependencies.resolve_dependencies translates and validates them."""
        candidate_objects: List[TaskCandidateResponse] = []
        ref_map = ref_map if ref_map is not None else {}

        for item in tasks_raw:
            raw_title = str(item.get("title", "")).strip()
            if not raw_title:
                continue
            title = sanitize_task_title(raw_title)

            dur = _safe_int(item.get("estimated_minutes", 45), default=45, lo=5, hi=480)
            # A user-stated duration is never replaced; only a missing value is filled (marked inferred).
            dur_src = "explicit" if (item.get("duration_source") == "explicit" and item.get("estimated_minutes") is not None) else "inferred"

            raw_type = str(item.get("type", "deep_work")).lower()
            try:
                task_type = TaskType(raw_type)
            except Exception:
                task_type = TaskType.deep_work

            raw_diff = str(item.get("difficulty", "medium")).lower()
            try:
                difficulty = TaskDifficulty(raw_diff)
            except Exception:
                difficulty = TaskDifficulty.medium

            # Resolve target_date
            target_date_val = _parse_iso_date(item.get("target_date"))
            base_date = target_date_val if target_date_val else now_local.date()

            # Deadline (date + optional time)
            deadline_at: Optional[datetime] = None
            deadline_date = _parse_iso_date(item.get("deadline"))
            deadline_kind: Optional[str] = None
            if deadline_date is not None:
                deadline_at = resolve_deadline(
                    deadline_date, _parse_hhmm(item.get("deadline_time")), item.get("deadline_phrase"), tz,
                    today=now_local.date(),
                )
                deadline_kind = "soft" if str(item.get("deadline_kind") or "").lower() == "soft" else "hard"

            # Priority: explicit is kept; anything else is inferred (never null / "unspecified").
            raw_prio_input = item.get("priority")
            prio_src = "explicit" if str(item.get("priority_source", "")).lower() == "explicit" else "inferred"
            try:
                priority = TaskPriority(str(raw_prio_input).lower()) if raw_prio_input is not None else None
            except ValueError:
                priority = None
            if priority is None:
                priority = infer_priority(deadline_at, f"{raw_title} {item.get('description') or ''}", now_local)
                prio_src = "inferred"

            focus_level = str(item.get("focus_level") or "").lower()
            if focus_level in ("low", "medium", "high"):
                focus_src = "explicit" if str(item.get("focus_source", "")).lower() == "explicit" else "inferred"
            else:
                focus_level, focus_src = infer_focus(task_type), "inferred"

            # Fixed start
            scheduled_start: Optional[datetime] = None
            scheduled_end: Optional[datetime] = None
            fixed_start_parsed = _parse_hhmm(item.get("fixed_start"))
            if fixed_start_parsed:
                fh, fm = fixed_start_parsed
                scheduled_start = datetime.combine(base_date, time(fh, fm), tzinfo=tz)
                scheduled_end = scheduled_start + timedelta(minutes=dur)

            conf_score = _clamp_confidence(item.get("confidence", 0.90), default=0.90)
            needs_confirmation = bool(item.get("needs_confirmation", False))

            # Per-task ambiguities
            task_ambiguities: List[str] = []
            if prio_src == "inferred":
                task_ambiguities.append("inferred_priority")
            if needs_confirmation:
                task_ambiguities.append("needs_confirmation")

            # Temporal constraints
            temporal_provenance: Dict[str, Any] = {}
            tc_preferred_start: Optional[datetime] = None
            tc_preferred_window_start: Optional[datetime] = None
            tc_preferred_window_end: Optional[datetime] = None
            tc_earliest_start: Optional[datetime] = None
            tc_latest_end: Optional[datetime] = None
            tc_relative_after: Optional[str] = None
            tc_relative_before: Optional[str] = None

            preferred_start_parsed = _parse_hhmm(item.get("preferred_start_hhmm"))
            if preferred_start_parsed:
                ps_h, ps_m = preferred_start_parsed
                ps_dt = datetime.combine(base_date, time(ps_h, ps_m), tzinfo=tz)
                tc_preferred_start = ps_dt
                tc_preferred_window_start = ps_dt - timedelta(minutes=45)
                tc_preferred_window_end = ps_dt + timedelta(minutes=45)
                temporal_provenance["preferred_start"] = FieldProvenance(source="explicit", confidence=0.95)

            preferred_window_val = str(item.get("preferred_window") or "").lower().strip()
            # Normalize "night" -> "evening": "night" is not a valid preferred_window
            # enum value. If Gemini outputs it (or any non-standard night variant),
            # treat it identically to "evening".
            if preferred_window_val == "night":
                preferred_window_val = "evening"
            if preferred_window_val and not tc_preferred_window_start:
                if preferred_window_val == "morning":
                    tc_preferred_window_start = datetime.combine(base_date, time(8, 0), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(12, 0), tzinfo=tz)
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                elif preferred_window_val == "afternoon":
                    tc_preferred_window_start = datetime.combine(base_date, time(12, 0), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(17, 0), tzinfo=tz)
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                elif preferred_window_val == "evening":
                    tc_preferred_window_start = datetime.combine(base_date, time(17, 0), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(21, 0), tzinfo=tz)
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                elif preferred_window_val == "after_dinner":
                    tc_preferred_window_start = datetime.combine(base_date, time(20, 0), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(23, 0), tzinfo=tz)
                    tc_earliest_start = datetime.combine(base_date, time(20, 0), tzinfo=tz)
                    tc_relative_after = "dinner"
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                    temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
                    temporal_provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)
                elif preferred_window_val == "after_lunch":
                    tc_preferred_window_start = datetime.combine(base_date, time(13, 0), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(17, 0), tzinfo=tz)
                    tc_earliest_start = datetime.combine(base_date, time(13, 0), tzinfo=tz)
                    tc_relative_after = "lunch"
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                    temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
                    temporal_provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)
                elif preferred_window_val == "after_breakfast":
                    tc_preferred_window_start = datetime.combine(base_date, time(7, 30), tzinfo=tz)
                    tc_preferred_window_end = datetime.combine(base_date, time(10, 0), tzinfo=tz)
                    tc_earliest_start = datetime.combine(base_date, time(7, 30), tzinfo=tz)
                    tc_relative_after = "breakfast"
                    temporal_provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.90)
                    temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.95)
                    temporal_provenance["earliest_start"] = FieldProvenance(source="default", confidence=0.60)

            earliest_parsed = _parse_hhmm(item.get("earliest_start_hhmm"))
            if earliest_parsed and not tc_earliest_start:
                es_h, es_m = earliest_parsed
                tc_earliest_start = datetime.combine(base_date, time(es_h, es_m), tzinfo=tz)
                temporal_provenance["earliest_start"] = FieldProvenance(source="explicit", confidence=1.0)

            latest_parsed = _parse_hhmm(item.get("latest_end_hhmm"))
            if latest_parsed:
                le_h, le_m = latest_parsed
                tc_latest_end = datetime.combine(base_date, time(le_h, le_m), tzinfo=tz)
                temporal_provenance["latest_end"] = FieldProvenance(source="explicit", confidence=1.0)

            relative_after_val = str(item.get("relative_after") or "").lower().strip() or None
            if relative_after_val and not tc_relative_after:
                tc_relative_after = relative_after_val
                temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.90)

            relative_before_val = str(item.get("relative_before") or "").lower().strip() or None
            if relative_before_val:
                tc_relative_before = relative_before_val
                temporal_provenance["relative_before"] = FieldProvenance(source="explicit", confidence=0.90)

            if tc_latest_end is None and relative_before_val:
                if relative_before_val == "lunch":
                    tc_latest_end = datetime.combine(base_date, time(13, 0), tzinfo=tz)
                    temporal_provenance["latest_end"] = FieldProvenance(source="inferred", confidence=0.75)
                elif relative_before_val == "dinner":
                    tc_latest_end = datetime.combine(base_date, time(20, 0), tzinfo=tz)
                    temporal_provenance["latest_end"] = FieldProvenance(source="inferred", confidence=0.75)
                elif relative_before_val == "breakfast":
                    tc_latest_end = datetime.combine(base_date, time(7, 30), tzinfo=tz)
                    temporal_provenance["latest_end"] = FieldProvenance(source="inferred", confidence=0.75)

            if deadline_at is not None and deadline_kind == "hard" and tc_latest_end is None and scheduled_start is None:
                tc_latest_end = deadline_at
                temporal_provenance["latest_end"] = FieldProvenance(source="explicit", confidence=1.0)

            if target_date_val is not None:
                temporal_provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)

            has_temporal = any([
                target_date_val, scheduled_start, tc_preferred_start,
                tc_preferred_window_start, tc_earliest_start, tc_latest_end,
                tc_relative_after, tc_relative_before,
            ])

            temporal_constraints: Optional[TemporalConstraints] = None
            if has_temporal:
                temporal_constraints = TemporalConstraints(confidence=conf_score)
                try:
                    if target_date_val is not None:
                        temporal_constraints.target_date = target_date_val
                    if scheduled_start is not None:
                        temporal_constraints.fixed_start = scheduled_start
                    if tc_preferred_start is not None:
                        temporal_constraints.preferred_start = tc_preferred_start
                    if tc_preferred_window_start is not None:
                        temporal_constraints.preferred_window_start = tc_preferred_window_start
                    if tc_preferred_window_end is not None:
                        temporal_constraints.preferred_window_end = tc_preferred_window_end
                    if tc_earliest_start is not None:
                        temporal_constraints.earliest_start = tc_earliest_start
                    if tc_latest_end is not None:
                        temporal_constraints.latest_end = tc_latest_end
                    if tc_relative_after is not None:
                        temporal_constraints.relative_after = tc_relative_after
                    if tc_relative_before is not None:
                        temporal_constraints.relative_before = tc_relative_before

                    if scheduled_start is not None:
                        temporal_constraints.flexibility = "fixed"
                    elif tc_earliest_start or tc_relative_after or tc_latest_end or tc_relative_before:
                        temporal_constraints.flexibility = "constrained"
                    else:
                        temporal_constraints.flexibility = "preferred"

                    temporal_constraints.provenance = temporal_provenance
                except Exception:
                    pass

            prio_confidence = 1.0 if prio_src == "explicit" else min(conf_score, 0.7)

            provenance: Dict[str, FieldProvenance] = {
                "title": FieldProvenance(source="gemini", confidence=conf_score),
                "duration": FieldProvenance(source=dur_src, confidence=conf_score),
                "task_type": FieldProvenance(source="gemini", confidence=conf_score),
                "difficulty": FieldProvenance(source="gemini", confidence=conf_score),
                "priority": FieldProvenance(source=prio_src, confidence=prio_confidence),
            }
            if deadline_at:
                provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
            if scheduled_start:
                provenance["scheduled_time"] = FieldProvenance(source="explicit", confidence=1.0)
            if target_date_val:
                provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)

            missing_fields: List[str] = []
            if not deadline_at:
                missing_fields.append("deadline")
            if not scheduled_start:
                missing_fields.append("scheduled_time")

            # Only user-stated preferred times persist (spec rev 2); inferred windows stay scheduling hints.
            explicit_pref = any(
                getattr(temporal_provenance.get(k), "source", None) == "explicit"
                for k in ("preferred_start", "preferred_window")
            )

            candidate_objects.append(
                TaskCandidateResponse(
                    title=title,
                    description=item.get("description"),
                    estimated_minutes=dur,
                    task_type=task_type,
                    difficulty=difficulty,
                    priority=priority,
                    category=item.get("category", "General") or "General",
                    deadline_at=deadline_at,
                    scheduled_start=scheduled_start,
                    scheduled_end=scheduled_end,
                    target_date=target_date_val,
                    fixed_start=item.get("fixed_start") or (scheduled_start.strftime("%H:%M") if scheduled_start else None),
                    deadline=item.get("deadline") or (deadline_at.strftime("%Y-%m-%d") if deadline_at else None),
                    confidence=conf_score,
                    missing_fields=missing_fields,
                    ambiguities=task_ambiguities,
                    source=TaskSource.ai_parsed,
                    field_provenance=provenance,
                    temporal=temporal_constraints,
                    priority_source=prio_src,
                    duration_source=dur_src,
                    focus_level=focus_level,
                    focus_source=focus_src,
                    deadline_kind=deadline_kind,
                    preferred_start=tc_preferred_start if explicit_pref else None,
                    preferred_window_start=tc_preferred_window_start if explicit_pref else None,
                    preferred_window_end=tc_preferred_window_end if explicit_pref else None,
                    depends_on=[str(r) for r in (item.get("depends_on") or []) if r],
                )
            )
            ref_map[str(item.get("ref") or f"t{len(candidate_objects)}")] = candidate_objects[-1].candidate_id

        return candidate_objects

    # ─────────────────────────────────────────────────────────────────────
    # Ollama fallback — honest about what was actually extracted.
    # The Ollama prompt only asks for title / estimated_minutes / category /
    # priority. We must NOT claim type, difficulty, deadline, etc. were
    # extracted. Missing fields and provenance reflect this.
    # ─────────────────────────────────────────────────────────────────────
    @classmethod
    def _try_ollama_fallback(
        cls, raw_text: str, now_local: datetime, tz: ZoneInfo
    ) -> Optional[List[TaskCandidateResponse]]:
        try:
            prompt = (
                f"Extract task items from this text: '{raw_text}'. "
                f"Return ONLY valid JSON array with objects containing: title, estimated_minutes, category, priority."
            )
            with httpx.Client(timeout=2.0) as client:
                resp = client.post(
                    "http://localhost:11434/api/generate",
                    json={
                        "model": "llama3.2",
                        "prompt": prompt,
                        "stream": False,
                        "format": "json",
                    },
                )
                if resp.status_code == 200:
                    data = resp.json()
                    parsed = json.loads(data.get("response", "[]"))
                    if isinstance(parsed, list) and parsed:
                        results = []
                        for item in parsed:
                            title = item.get("title", "Task").strip()
                            dur = _safe_int(item.get("estimated_minutes", 45), default=45, lo=5, hi=480)

                            ollama_priority_raw = item.get("priority")
                            try:
                                ollama_priority = (
                                    TaskPriority(str(ollama_priority_raw).lower())
                                    if ollama_priority_raw
                                    else TaskPriority.medium
                                )
                            except Exception:
                                ollama_priority = TaskPriority.medium
                                ollama_priority_raw = None

                            ollama_ambiguities = ["llm_fallback"]
                            if not ollama_priority_raw:
                                ollama_ambiguities.append("priority_unspecified")

                            ollama_provenance = {
                                "title": FieldProvenance(source="ollama", confidence=0.75),
                                "duration": FieldProvenance(source="ollama", confidence=0.60),
                                "task_type": FieldProvenance(source="default", confidence=0.40),
                                "difficulty": FieldProvenance(source="default", confidence=0.40),
                                "priority": FieldProvenance(
                                    source="ollama" if ollama_priority_raw else "unspecified",
                                    confidence=0.70 if ollama_priority_raw else 0.0,
                                ),
                            }

                            results.append(
                                TaskCandidateResponse(
                                    title=title,
                                    estimated_minutes=dur,
                                    task_type=TaskType.deep_work,   # default; not extracted
                                    difficulty=TaskDifficulty.medium,  # default; not extracted
                                    priority=ollama_priority,
                                    category=item.get("category", "General"),
                                    confidence=0.60,
                                    missing_fields=[
                                        "deadline",
                                        "scheduled_time",
                                        "task_type",
                                        "difficulty",
                                    ],
                                    ambiguities=ollama_ambiguities,
                                    source=TaskSource.ai_parsed,
                                    field_provenance=ollama_provenance,
                                )
                            )
                        return results
        except Exception:
            pass
        return None