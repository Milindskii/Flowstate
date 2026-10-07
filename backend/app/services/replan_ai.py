"""
Semantic understanding of a Replan message with the language model, for requests the deterministic rules could not
read on their own.

The model only TRANSLATES the message into a small set of structured intents about tasks that are really in today's
plan. It never writes to the database and never picks final slots: every intent is validated here against the plan
and converted into the existing ``ReplanOperation`` contract; the deterministic planner then builds the proposal, and
nothing is persisted until the user applies it.

Never trusted blindly:
  * a task reference must be one of the refs we sent (resolved to the real task id here);
  * every number the model uses (a clock time, minutes, a duration) must appear in the user's own message;
  * dates are limited to the next 14 days; amounts to sane ranges;
  * a move without a destination, a duration change without an amount, or low confidence becomes a clarification.
Any failure (provider error, timeout, malformed JSON, nothing usable) returns None and the caller keeps the
deterministic result.
"""
import json
import re
import time as clock
from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from ..core.config import settings
from ..core.logging import logger
from ..engines.planner import PlanItem
from ..schemas.calendar import ReplanClarification, ReplanClarificationOption, ReplanOperation
from .replan_understanding import Understanding, _opts_for, asks_for_change, normalise, resolve_entities

FREE_REPLAN_AI_PER_DAY = 15
PRO_REPLAN_AI_PER_DAY = 100
MAX_REPLAN_AI_PER_MINUTE = 6
MIN_CONFIDENCE = 0.6
MAX_DAYS_AHEAD = 14

OPS = ("move_task", "defer_task", "skip_task", "cancel_task", "change_duration", "delay_task",
       "preserve_priority", "preserve_commitment", "add_task")
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
WINDOWS = ("morning", "afternoon", "evening", "night")

_RECENT: Dict[str, List[float]] = defaultdict(list)


def allow_request(user_id: str, now: Optional[float] = None) -> bool:
    """In-process per-minute guard (the daily budget is the DB-backed limit)."""
    t = clock.time() if now is None else now
    recent = [s for s in _RECENT[user_id] if t - s < 60]
    _RECENT[user_id] = recent
    if len(recent) >= MAX_REPLAN_AI_PER_MINUTE:
        return False
    recent.append(t)
    return True


def reset_rate_limit() -> None:
    _RECENT.clear()


# ── prompt ──────────────────────────────────────────────────────────────────

def build_prompt(message: str, refs: Sequence[Tuple[str, PlanItem]], now_local: datetime, tz: ZoneInfo) -> str:
    lines = []
    for ref, it in refs:
        when = "no time set"
        if it.start is not None:
            s = it.start.astimezone(tz)
            e = (it.end or it.start + timedelta(minutes=it.estimated_minutes)).astimezone(tz)
            when = f"{s:%H:%M}-{e:%H:%M}"
        kind = "fixed commitment" if it.is_commitment else "task"
        lines.append(f'  {ref}: "{it.title}" ({kind}, {when}, {it.estimated_minutes} min)')
    plan = "\n".join(lines) or "  (no open tasks)"
    return (
        "You turn ONE message from a user about today's plan into structured intents. You do NOT schedule anything.\n"
        f"Now: {now_local:%A %Y-%m-%d %H:%M} ({tz.key}).\n"
        "Today's open plan:\n"
        f"{plan}\n\n"
        f"User message: {json.dumps(message)}\n\n"
        "Return ONLY JSON:\n"
        "{\n"
        '  "operations": [{"op": "move_task|defer_task|skip_task|cancel_task|change_duration|delay_task|'
        'preserve_priority|preserve_commitment|add_task", "task_ref": "t1"|null, '
        '"target_date": "tomorrow"|"monday".."sunday"|"YYYY-MM-DD"|null, "target_time": "HH:MM" (24h)|null, '
        '"time_mode": "at"|"not_before"|"before"|"later"|null,"part_of_day": "morning"|"afternoon"|"evening"|"night"|null, '
        '"minutes": integer|null, "title": string|null}],\n'
        '  "clarification": {"question": string, "task_ref": "t1"|null, '
        '"options": [{"label": string, "message": string}]} | null,\n'
        '  "confidence": number between 0 and 1\n'
        "}\n"
        "Rules:\n"
        "- task_ref must be one of the refs above. Never invent a task. add_task only when the user clearly adds new work "
        "(title in the user's words).\n"
        "- Never invent a time, a date, a duration or an amount. Use only numbers the user wrote. If something needed "
        "is missing, leave it null.\n"
        "- \"after 10:30\" means time_mode not_before; \"at 8\" means at; \"move X later\" means move_task with time_mode later.\n"
        "- \"I can't go / won't be able to make X\" about a fixed commitment -> cancel_task. About a task -> skip_task.\n"
        "- \"I don't have time for X\" -> defer_task. \"X is taking longer\" -> change_duration (minutes only if stated).\n"
        "- \"keep X first / X is priority\" -> preserve_priority. \"don't touch / leave X\" -> preserve_commitment.\n"
        "- \"running late\" WITHOUT an amount is NOT a delay: do not output delay_task.\n"
        "- One operation per requested change; a message may contain several.\n"
        "- Never change a fixed commitment the user did not mention.\n"
        "Examples (refs are illustrative):\n"
        "- \"can't make it out tonight\" + commitment t1 \"Going out\" -> cancel_task t1.\n"
        "- \"bail on gym\" / \"not doing gym today\" -> skip_task on Gym.\n"
        "- \"push laundry\" (no time or day) -> no operation; clarification asking when, options for that task.\n"
        "- \"no time for cleaning\" + task \"Clean room\" -> defer_task on Clean room.\n"
        "- \"essay after lunch\" -> move_task, time_mode not_before, part_of_day afternoon, target_time null.\n"
        "- \"skip gym and do DSA tomorrow morning\" -> skip_task Gym; move_task DSA target_date tomorrow, part_of_day "
        "morning.\n"
        "- If you cannot tell which task the user means or what to do, return no operations and a short clarification "
        "question with up to 4 options specific to that task (each option's message is a full instruction the user "
        "could send, e.g. \"move Gym to tomorrow\").\n"
    )


# ── validation ──────────────────────────────────────────────────────────────

_WORD_NUMBERS = {"quarter": 15, "half": 30, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10,
                 "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty five": 45, "an hour": 60}


def numbers_in(message: str) -> set:
    """Every number the user actually wrote (digits, 10.30 / 10:30 parts, common number words)."""
    text = normalise(message)
    nums = {int(n) for n in re.findall(r"\d+", text)}
    for word, value in _WORD_NUMBERS.items():
        if re.search(rf"\b{word}\b", text):
            nums.add(value)
    if re.search(r"\bhalf an? hour\b|\bhalf hour\b", text):
        nums.add(30)
    if re.search(r"\b(?:an|one) hour\b", text):
        nums.add(60)
    return nums


def _minutes_said(minutes: int, said: set) -> bool:
    return minutes in said or (minutes % 60 == 0 and minutes // 60 in said)


def _time_said(hh: int, mm: int, said: set) -> bool:
    hour_ok = hh in said or (hh % 12 or 12) in said or (hh == 0 and 12 in said)
    return hour_ok and (mm == 0 or mm in said)


def _clean_time(value: Any) -> Optional[Tuple[int, int]]:
    m = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*", str(value or ""))
    if not m:
        return None
    hh, mm = int(m.group(1)), int(m.group(2))
    return (hh, mm) if 0 <= hh <= 23 and 0 <= mm <= 59 else None


def _clean_date(value: Any, today: date) -> Optional[str]:
    v = str(value or "").strip().lower()
    if not v:
        return None
    if v == "tomorrow" or v in WEEKDAYS:
        return v
    if v == "today":
        return today.isoformat()
    try:
        d = datetime.strptime(v, "%Y-%m-%d").date()
    except ValueError:
        return None
    return v if today <= d <= today + timedelta(days=MAX_DAYS_AHEAD) else None


def _ask_for(item: PlanItem, question: str, options: Optional[List[ReplanClarificationOption]] = None) -> Understanding:
    return Understanding(clarification=ReplanClarification(
        question=question, options=options or _opts_for(item), task_id=item.id, task_title=item.title))


def _longer_options(title: str) -> List[ReplanClarificationOption]:
    return [ReplanClarificationOption(label="+15 min", message=f"{title} will take 15 minutes longer"),
            ReplanClarificationOption(label="+30 min", message=f"{title} will take 30 minutes longer"),
            ReplanClarificationOption(label="+1 hour", message=f"{title} will take 60 minutes longer")]


def validate(payload: Any, message: str, refs: Sequence[Tuple[str, PlanItem]], now_local: datetime,
             tz: ZoneInfo) -> Optional[Understanding]:
    """Model JSON -> Understanding over real plan items, or None when nothing trustworthy is in it."""
    if not isinstance(payload, dict):
        return None
    by_ref = {ref: it for ref, it in refs}
    said = numbers_in(message)
    today = now_local.date()
    msg_words = set(re.findall(r"[a-z0-9']+", normalise(message)))
    try:
        confidence = float(payload.get("confidence", 0))
    except (TypeError, ValueError):
        confidence = 0.0

    ops: List[ReplanOperation] = []
    asks: List[Understanding] = []
    raw_ops = payload.get("operations") or []
    if not isinstance(raw_ops, list):
        raw_ops = []

    for raw in raw_ops[:6]:
        if not isinstance(raw, dict) or raw.get("op") not in OPS:
            continue
        kind = raw["op"]
        item = by_ref.get(str(raw.get("task_ref") or ""))
        minutes = raw.get("minutes")
        minutes = int(minutes) if isinstance(minutes, (int, float)) and not isinstance(minutes, bool) else None
        hhmm = _clean_time(raw.get("target_time"))
        dest = _clean_date(raw.get("target_date"), today)
        window = raw.get("part_of_day") if raw.get("part_of_day") in WINDOWS else None
        mode = raw.get("time_mode") if raw.get("time_mode") in ("at", "not_before", "before", "later") else "at"

        if kind == "add_task":
            title = str(raw.get("title") or "").strip()[:80]
            words = [w for w in re.findall(r"[a-z0-9']+", title.lower()) if len(w) > 2]
            if not title or not words or not all(w in msg_words for w in words):
                continue  # never invent new work
            if minutes is not None and not (5 <= minutes <= 720 and _minutes_said(minutes, said)):
                minutes = None
            if hhmm is not None and not _time_said(*hhmm, said):
                hhmm = None
            ops.append(ReplanOperation(
                op="add_task", title=title, duration_minutes=minutes or 45, priority="high", task_type="deep_work",
                target_time=f"{hhmm[0]:02d}:{hhmm[1]:02d}" if hhmm else None,
                constraint_type="fixed_start" if hhmm else "preferred_start"))
            continue

        if kind == "delay_task" and item is None:
            if minutes is None or not (1 <= minutes <= 720) or not _minutes_said(minutes, said):
                continue  # "running late" without an amount is not a delay
            ops.append(ReplanOperation(op="delay_remaining_schedule", delay_minutes=minutes))
            continue

        if item is None:
            continue
        title = item.title
        if item.is_commitment and kind not in ("preserve_commitment", "preserve_priority"):
            # a fixed commitment is only ever changed when the user named it, and never silently shifted a day
            text = normalise(message)
            named = bool(resolve_entities(text, [item], lambda _it: []))
            # "scrap the evening plans with friends" may mean it, but only when the message asks for a change and
            # names no other task the change could be about
            others = [it for _, it in refs if it.id != item.id]
            if not named and not (asks_for_change(message) and not resolve_entities(text, others, lambda _it: [])):
                continue
            if kind in ("skip_task", "defer_task"):
                asks.append(_ask_for(item, f"Should I cancel {title}, or move it to another time?"))
                continue

        if kind == "cancel_task":
            ops.append(ReplanOperation(op="cancel_task", task_id=item.id, task_query=title))
        elif kind == "skip_task":
            ops.append(ReplanOperation(op="move_task_date", task_id=item.id, task_query=title,
                                       target_date="tomorrow", intent="skipped"))
        elif kind == "defer_task":
            ops.append(ReplanOperation(op="move_task_date", task_id=item.id, task_query=title,
                                       target_date=dest or "tomorrow", intent="deferred"))
        elif kind == "preserve_priority":
            ops.append(ReplanOperation(op="prioritize", task_id=item.id, task_query=title))
        elif kind == "preserve_commitment":
            ops.append(ReplanOperation(op="protect_task", task_id=item.id, task_query=title))
        elif kind == "change_duration":
            if item.is_commitment:
                continue
            if minutes is None or not (5 <= minutes <= 480) or not _minutes_said(minutes, said):
                asks.append(_ask_for(item, f"How much longer will {title} take?", _longer_options(title)))
                continue
            ops.append(ReplanOperation(op="change_duration", task_id=item.id, task_query=title, delay_minutes=minutes))
        elif kind == "delay_task":
            if minutes is None or not (1 <= minutes <= 720) or not _minutes_said(minutes, said) or item.start is None:
                asks.append(_ask_for(item, f"Sure. What time should I move {title} to?"))
                continue
            later = (item.start + timedelta(minutes=minutes)).astimezone(tz)
            ops.append(ReplanOperation(op="move_task_time", task_id=item.id, task_query=title,
                                       target_time=f"{later:%H:%M}", constraint_type="not_before", intent="delayed"))
        elif kind == "move_task":
            if hhmm is not None and not _time_said(*hhmm, said):
                hhmm = None  # a time the user never said is never used
            if hhmm is not None and (dest is None or dest == today.isoformat()):
                constraint = {"at": None, "not_before": "not_before", "before": "latest_end"}[mode]
                ops.append(ReplanOperation(op="move_task_time", task_id=item.id, task_query=title,
                                           target_time=f"{hhmm[0]:02d}:{hhmm[1]:02d}", constraint_type=constraint,
                                           intent="rescheduled"))
            elif dest is not None and dest != today.isoformat():
                ops.append(ReplanOperation(op="move_task_date", task_id=item.id, task_query=title, target_date=dest,
                                           intent="rescheduled"))
            elif mode == "later" and not item.is_commitment:
                ops.append(ReplanOperation(op="move_later", task_id=item.id, task_query=title, intent="delayed"))
            elif window is not None and not item.is_commitment:
                ops.append(ReplanOperation(op="shift_task_preference", task_id=item.id, task_query=title,
                                           preferred_window=window))
            else:
                asks.append(_ask_for(item, f"Sure. What time should I move {title} to?"))

    # A missing detail is asked for before anything is proposed: never a partial, guessed plan.
    if asks:
        return asks[0]
    if ops and confidence >= MIN_CONFIDENCE:
        return Understanding(operations=ops)

    clar = payload.get("clarification")
    if isinstance(clar, dict) and str(clar.get("question") or "").strip():
        item = by_ref.get(str(clar.get("task_ref") or ""))
        options = []
        for o in (clar.get("options") or [])[:4]:
            if isinstance(o, dict) and str(o.get("label") or "").strip() and str(o.get("message") or "").strip():
                options.append(ReplanClarificationOption(label=str(o["label"])[:40], message=str(o["message"])[:160]))
        if item is not None and not options:
            options = _opts_for(item)
        if not options:
            movable = [it for _, it in refs if not it.is_commitment][:4]
            options = [ReplanClarificationOption(label=it.title, prefill=f"{it.title} ") for it in movable]
        if options:
            return Understanding(clarification=ReplanClarification(
                question=str(clar["question"]).strip()[:200], options=options,
                task_id=item.id if item else None, task_title=item.title if item else None))
    if ops:  # usable operations but the model was unsure: ask about the first task instead of acting
        first = next((it for _, it in refs if it.id == ops[0].task_id), None)
        if first is not None:
            return _ask_for(first, f"Just to check: what should I do with {first.title}?")
    return None


# ── provider call ───────────────────────────────────────────────────────────

def interpret(message: str, items: Sequence[PlanItem], now_local: datetime, tz: ZoneInfo, *,
              request_id: str) -> Optional[Understanding]:
    """One model call through the AI gateway (breaker, concurrency, deadline). None on any failure."""
    from . import ai_gateway
    from .ai_service import AIService

    if not settings.GEMINI_API_KEY:
        return None
    refs = [(f"t{n + 1}", it) for n, it in enumerate(items)]
    prompt = build_prompt(message, refs, now_local, tz)
    started = clock.perf_counter()
    try:
        text = ai_gateway.call_provider(AIService._gemini_generate, prompt, settings.GEMINI_API_KEY,
                                        request_id=request_id, temperature=0.0)
        payload = _loads(text)
        result = validate(payload, message, refs, now_local, tz)
    except Exception as exc:  # provider failure / busy / timeout: the deterministic path answers instead
        logger.warning(f"replan_ai request_id={request_id} failed={type(exc).__name__} "
                       f"code={getattr(exc, 'code', getattr(exc, 'reason', ''))}")
        return None
    logger.info(f"replan_ai request_id={request_id} result={'none' if result is None else ('ask' if result.clarification else 'ops')} "
                f"latency_ms={round((clock.perf_counter() - started) * 1000)}")
    return result


def _loads(text: Any) -> Any:
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        m = re.search(r"\{.*\}", str(text or ""), re.S)
        if not m:
            return None
        try:
            return json.loads(m.group(0))
        except ValueError:
            return None
