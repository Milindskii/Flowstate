"""
Plan-aware understanding of a Replan message the rule parser could not read on its own.

Pure and deterministic (no I/O, no clock besides the ``now`` it is given). It only runs AFTER the context-free
rules found nothing, and it only speaks up when the message names something that really is in today's plan:
the entity is resolved against the plan, never against arbitrary keywords.

Outcomes:
  * one obvious operation  -> ``operations`` (the normal proposal flow shows it before anything is applied)
  * recognised, detail missing / several readings -> ``clarification`` (a question + options specific to the task)
  * nothing recognised     -> ``None`` (the caller keeps the generic message)
"""
import re
from dataclasses import dataclass
from datetime import datetime, time
from typing import Callable, List, Optional, Sequence

from ..engines.planner import PlanItem
from ..schemas.calendar import ReplanClarification, ReplanClarificationOption, ReplanOperation

_LEMMA = {"going": "go", "goes": "go", "gone": "go", "went": "go", "gym's": "gym"}
_FIXES = (("wont", "won't"), ("cant", "can't"), ("dont", "don't"), ("isnt", "isn't"), ("im", "i'm"))
_STOP = frozenset({"the", "my", "a", "an", "of", "on", "to", "and", "or", "at", "for", "in", "up", "by", "with"})
_NOISE = _STOP | frozenset({
    "i", "i'm", "me", "we", "you", "it", "its", "is", "am", "are", "be", "been", "being", "able", "not", "no", "can", "can't",
    "cannot", "won't", "will", "would", "unable", "make", "do", "today", "tonight", "this", "that", "please", "pls", "just",
    "really", "now", "later", "tomorrow", "need", "needs", "gonna", "longer", "take", "takes", "taking", "more", "time",
    "move", "moving", "push", "shift", "reschedule", "postpone", "delay", "bump", "cancel", "remove", "drop", "attend",
    "come", "join", "have", "has", "had", "should", "must", "want", "wanna", "sorry", "afraid", "unfortunately",
    "extra", "extend", "over", "run", "running", "minutes", "minute", "mins", "min", "hour", "hours", "moved",
    "don't", "isn't", "longer", "again", "instead", "somewhere", "else",
    "than", "expected", "thought", "planned", "anymore", "enough", "getting", "after", "before", "from",
})
_GENERIC = frozenset({"work", "task", "tasks", "thing", "things", "stuff", "session", "one", "time"})

_CANT = re.compile(
    r"\b(?:can'?t|cannot|can not|won'?t|will not|unable to|not able to|not going to|not gonna|no longer|"
    r"don'?t (?:want|feel like)|isn'?t happening|am not|i'?m not|"
    r"(?:don'?t|do not) have (?:the |enough |any )?time (?:for|to)|no time (?:for|to)|can'?t fit)\b")
# "I don't have time for X": X leaves today's remaining plan (deferred), it is not abandoned
_NO_TIME = re.compile(r"\b(?:(?:don'?t|do not) have (?:the |enough |any )?time|no time|can'?t fit)\b")
_MOVE = re.compile(
    r"\b(?:move|moving|push|pushing|shift|reschedule|rescheduling|postpone|bump|delay)\b|"
    r"\b(?:needs?|has|have|should|must|got) to (?:be )?mov")
_CANCEL = re.compile(r"\b(?:cancel|remove|drop|delete|scrap|call off)\b")
_LONGER = re.compile(r"\b(?:longer|more time|extra time|running over|run over|runs over|extend|overrun)\b|\bmore (?:minutes?|mins?|hours?)\b")
_TIME = re.compile(r"\b(?:to|at|for|around)\s+(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?!\s*(?:min|mins|minutes?|h|hr|hrs|hours?)\b)")
# "after 10:30" / "not before 6" / "no earlier than 9 pm": a lower bound, not an exact time
_NOT_BEFORE = re.compile(r"\b(?:after|not before|no earlier than)\s+(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?(?!\s*(?:min|mins|minutes?|h|hr|hrs|hours?)\b)")
_DAY = re.compile(r"\b(tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b")
_LATER = re.compile(r"\blater\b")
_AMOUNT = re.compile(r"(\d+(?:\.\d+)?)\s*(?:more\s*)?(h|hr|hrs|hours?|m|mins?|minutes?)\b")


def asks_for_change(clause: str) -> bool:
    """True when a clause asks for something (can't / move / cancel / longer), as opposed to pure context."""
    text = normalise(clause)
    return bool(_CANT.search(text) or _MOVE.search(text) or _CANCEL.search(text) or _LONGER.search(text))


@dataclass
class Understanding:
    operations: Optional[List[ReplanOperation]] = None
    clarification: Optional[ReplanClarification] = None
    # True when the rules could not tell what the user wants (a generic question): a smarter reader may do better
    vague: bool = False


def normalise(message: str) -> str:
    text = (message or "").lower().replace("’", "'").replace("‘", "'")
    text = text.replace("a.m.", "am").replace("p.m.", "pm")
    # keep the ":" of 10:30 and the "." of 1.5; every other punctuation mark is just a separator
    text = re.sub(r"[?!,;]+|(?<!\d)[.:]|[.:](?!\d)", " ", text)
    for bad, good in _FIXES:
        text = re.sub(rf"\b{bad}\b", good, text)
    return re.sub(r"\s+", " ", text).strip()


def _tok(word: str) -> str:
    word = _LEMMA.get(word, word)
    if len(word) >= 6 and word.endswith("ing"):  # cleaning -> clean (applied to titles and messages alike)
        return word[:-3]
    return word[:-1] if len(word) > 3 and word.endswith("s") and not word.endswith("ss") else word


def _tokens(text: str) -> List[str]:
    return [_tok(w) for w in re.findall(r"[a-z0-9']+", (text or "").lower())]


# parts of the day say WHEN, never WHICH task ("move dsa to tomorrow morning")
_WHEN = frozenset({"morning", "afternoon", "evening", "night"})


def _content(message: str) -> List[str]:
    raw = re.findall(r"[a-z0-9']+", (message or "").lower())
    return [_tok(w) for w in raw
            if w not in _NOISE and _tok(w) not in _NOISE and not w.isdigit() and w not in {"am", "pm"}
            and w not in _WHEN]


def resolve_entities(message: str, entities: Sequence[PlanItem], meta: Callable[[PlanItem], List[str]]) -> List[PlanItem]:
    """Plan items the message names: its content words are part of a title/category, or a whole title is in it."""
    msg_tokens = set(_tokens(message))
    content = _content(message)
    scored = []
    for it in entities:
        title_words = [w for w in _tokens(it.title) if w not in _STOP]
        if not title_words:
            continue
        distinctive = [w for w in title_words if w not in _GENERIC] or title_words
        pool = set(title_words) | set(meta(it))
        score = 0
        if content and all(w in pool for w in content) and any(w in title_words for w in content):
            score = max(score, 2 * len(content))
        if all(w in msg_tokens for w in distinctive):
            score = max(score, 2 * len(distinctive) + 1)
        if score:
            scored.append((score, it))
    if not scored:
        return []
    best = max(s for s, _ in scored)
    matches = [it for s, it in scored if s == best]
    if len(matches) > 1:
        m_t = re.search(r'\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\bat\s+(\d{1,2})(?::(\d{2}))?\b|\b(\d{1,2}):(\d{2})\b', message, re.IGNORECASE)
        if m_t:
            h = int(m_t.group(1) or m_t.group(4) or m_t.group(6))
            mi = int(m_t.group(2) or m_t.group(5) or m_t.group(7) or 0)
            ampm = (m_t.group(3) or "").lower() if m_t.group(3) else None
            if ampm:
                if ampm == "pm" and h < 12:
                    h += 12
                elif ampm == "am" and h == 12:
                    h = 0
            time_matches = [e for e in matches if (e.start or e.origin_start) is not None and (
                (((e.start or e.origin_start).hour, (e.start or e.origin_start).minute) == (h, mi))
                or (((e.start or e.origin_start).hour % 12, (e.start or e.origin_start).minute) == (h % 12, mi))
            )]
            if time_matches:
                return time_matches
    return matches


def _resolve_clock(hour: int, minute: int, ampm: Optional[str], now: datetime, same_day: bool) -> Optional[str]:
    if not (0 <= minute <= 59):
        return None
    if ampm:
        pm = ampm.startswith("p")
        if not (1 <= hour <= 12):
            return None
        hour = hour % 12 + (12 if pm else 0)
    elif hour > 23:
        return None
    elif 1 <= hour <= 12 and hour != 12:
        # no am/pm: the next occurrence today, otherwise the usual daytime reading
        candidates = [hour, hour + 12]
        if same_day:
            future = [h for h in candidates if time(h, minute) > now.timetz().replace(tzinfo=None)]
            hour = future[0] if future else hour + 12
        else:
            hour = hour + 12 if hour <= 7 else hour
    return f"{hour:02d}:{minute:02d}"


def _extra_minutes(text: str) -> Optional[int]:
    if re.search(r"\bhalf an? hour\b|\bhalf hour\b", text):
        return 30
    if re.search(r"\ban hour\b|\bone hour\b", text):
        return 60
    m = _AMOUNT.search(text)
    if not m:
        return None
    value = float(m.group(1))
    return int(round(value * 60)) if m.group(2).startswith("h") else int(round(value))


def _opts_for(item: PlanItem) -> List[ReplanClarificationOption]:
    t = item.title
    options = [
        ReplanClarificationOption(label="Move to a time", prefill=f"move {t} to "),
        ReplanClarificationOption(label="Move to tomorrow", message=f"move {t} to tomorrow"),
    ]
    if not item.is_commitment:
        options.append(ReplanClarificationOption(label="Move later today", message=f"move {t} later"))
    options.append(ReplanClarificationOption(label=f"Cancel {t}", message=f"cancel {t}"))
    return options


def understand(message: str, entities: Sequence[PlanItem], meta: Callable[[PlanItem], List[str]],
               now: datetime, target_is_today: bool) -> Optional[Understanding]:
    text = normalise(message)
    if not text:
        return None
    wants_longer = bool(_LONGER.search(text))
    wants_move = bool(_MOVE.search(text))
    cant = bool(_CANT.search(text))
    wants_cancel = bool(_CANCEL.search(text))
    action = wants_longer or wants_move or cant or wants_cancel

    found = resolve_entities(text, entities, meta)

    if not found:
        if not action:
            return None
        # a clear action on something that is not in the plan: offer the real options instead of an error
        # a fixed commitment is never offered as "the task" to move / extend / skip
        movable = [e for e in entities if e.status in ("todo", "postponed") and not e.is_commitment][:4]
        if not movable:
            return None
        if wants_move or wants_longer:
            return Understanding(vague=True, clarification=ReplanClarification(
                question="Which task should I move?" if wants_move else "Which task is taking longer?",
                options=[ReplanClarificationOption(label=e.title, prefill=f"{'move' if wants_move else ''} {e.title}".strip()
                                                   + (" to " if wants_move else " will take longer"))
                         for e in movable]))
        return Understanding(vague=True, clarification=ReplanClarification(
            question="Which task can't you do?",
            options=[ReplanClarificationOption(label=e.title, message=f"cancel {e.title}") for e in movable]))

    if len(found) > 1:
        verb = "move" if wants_move else ("cancel" if (cant or wants_cancel) else "move")
        has_duplicate_titles = len({e.title for e in found}) < len(found)

        def _lbl(e: PlanItem) -> str:
            dt = e.start or e.origin_start
            if has_duplicate_titles and dt is not None:
                t_str = dt.strftime("%I:%M %p").lstrip("0")
                return f"{e.title} at {t_str}"
            return e.title

        names = [_lbl(e) for e in found[:4]]
        m_day = _DAY.search(text) if wants_move else None
        opts = []
        for e in found[:4]:
            lbl = _lbl(e)
            if verb == "move":
                if m_day:
                    opts.append(ReplanClarificationOption(label=lbl, message=f"move {lbl} to {m_day.group(1)}"))
                else:
                    opts.append(ReplanClarificationOption(label=lbl, prefill=f"move {lbl} to "))
            else:
                opts.append(ReplanClarificationOption(label=lbl, message=f"cancel {lbl}"))
        return Understanding(clarification=ReplanClarification(
            question=f"Which one do you mean: {', '.join(names)}?",
            options=opts))

    it = found[0]
    title = it.title

    def ask(question: str, options: List[ReplanClarificationOption]) -> Understanding:
        return Understanding(clarification=ReplanClarification(
            question=question, options=options, task_id=it.id, task_title=title))

    if wants_longer and not it.is_commitment:
        extra = _extra_minutes(text)
        if extra is None:
            return ask(f"How much longer will {title} take?", [
                ReplanClarificationOption(label="+15 min", message=f"{title} will take 15 minutes longer"),
                ReplanClarificationOption(label="+30 min", message=f"{title} will take 30 minutes longer"),
                ReplanClarificationOption(label="+1 hour", message=f"{title} will take 60 minutes longer"),
            ])
        return Understanding(operations=[ReplanOperation(op="change_duration", task_query=title, delay_minutes=extra)])

    if wants_move:
        m_after = _NOT_BEFORE.search(text)
        if m_after and not it.is_commitment:
            hh = _resolve_clock(int(m_after.group(1)), int(m_after.group(2) or 0), m_after.group(3), now, target_is_today)
            if hh is None:
                return ask(f"I couldn't read that time. What time should I move {title} to?", _opts_for(it))
            return Understanding(operations=[ReplanOperation(
                op="move_task_time", task_query=title, target_time=hh, constraint_type="not_before", intent="rescheduled")])
        m_time = _TIME.search(text)
        if m_time:
            hh = _resolve_clock(int(m_time.group(1)), int(m_time.group(2) or 0), (m_time.group(3) or "").replace(".", "") or None,
                                now, target_is_today)
            if hh is None:
                return ask(f"I couldn't read that time. What time should I move {title} to?", _opts_for(it))
            return Understanding(operations=[ReplanOperation(op="move_task_time", task_query=title, target_time=hh, intent="rescheduled")])
        m_day = _DAY.search(text)
        if m_day:
            return Understanding(operations=[ReplanOperation(
                op="move_task_date", task_query=title, target_date=m_day.group(1), intent="rescheduled")])
        if _LATER.search(text) and not it.is_commitment:
            return Understanding(operations=[ReplanOperation(op="move_later", task_query=title, intent="delayed")])
        return ask(f"Sure. What time should I move {title} to?", _opts_for(it))

    if cant or wants_cancel:
        if it.is_commitment or wants_cancel:
            return Understanding(operations=[ReplanOperation(op="cancel_task", task_query=title)])
        if _NO_TIME.search(text):
            return Understanding(operations=[ReplanOperation(
                op="move_task_date", task_query=title, target_date="tomorrow", intent="deferred")])
        # can't do a task today: the same as saying "skip it": it moves to tomorrow and today keeps a skipped node
        return Understanding(operations=[ReplanOperation(
            op="move_task_date", task_query=title, target_date="tomorrow", intent="skipped")])

    # The task is named but nothing says what to do with it.
    vague = ask(f"What would you like to do with {title}?", _opts_for(it))
    vague.vague = True
    return vague
