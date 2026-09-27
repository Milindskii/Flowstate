import re
import json
import httpx
import time as clock
from typing import List, Optional, Dict, Tuple, Any
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo
from ..models.task import TaskType, TaskDifficulty, TaskPriority, TaskSource
from ..schemas.task import TaskCandidateResponse, FieldProvenance, TemporalConstraints
from ..core.config import settings
from ..core.logging import logger

def sanitize_task_title(title: str) -> str:
    """
    Ensures task titles are concise, natural, and user-faithful.
    Strips awkward filler ('to do', 'task for', 'task', 'my ...', 'the ...', 'go to', conversational openers).
    """
    if not title:
        return "Task"
    t = title.strip()
    # Strip leading/trailing punctuation or bullet marks
    t = re.sub(r'^[,\s\-•*:]+|[,\s\-•*:]+$', '', t).strip()
    # Strip conversational openers
    t = re.sub(r'^(?:i have|i\'ve got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+', '', t, flags=re.IGNORECASE).strip()
    # Strip prefixes like "task for ", "task: ", "to do: "
    t = re.sub(r'^(?:task\s+for|task\s*:|to\s*do\s*:)\s*', '', t, flags=re.IGNORECASE).strip()
    # Strip suffixes like " to do", " todo", " task"
    t = re.sub(r'\s+(?:to\s+do|todo|task)$', '', t, flags=re.IGNORECASE).strip()
    # Strip filler like 'my' or 'the' after action verbs (e.g. 'finish my assignment' -> 'Finish assignment')
    t = re.sub(r'\b(?:my|the)\s+(?=assignment|project|lab|homework|thesis|work|task|exam|quiz|session|workout)\b', '', t, flags=re.IGNORECASE)
    # Strip leading filler words ("and", "to", "go to", "also", "then", "the", "my")
    t = re.sub(r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+|the\s+|my\s+)', '', t, flags=re.IGNORECASE).strip()
    # Strip extra whitespace
    t = re.sub(r'\s+', ' ', t).strip()
    # Capitalize first letter
    if len(t) > 1:
        t = t[0].upper() + t[1:]
    elif len(t) == 1:
        t = t.upper()
    return t or "Task"

class AIService:
    """
    Service responsible for Natural Language Task Parsing ('What's on your plate?')
    Strictly suggests structured task candidates for quick user confirmation.
    Includes Confidence and Provenance metadata.
    NEVER creates tasks directly or makes unilateral scheduling decisions.
    """

    @staticmethod
    def _split_clauses(text: str) -> List[str]:
        # Strip conversational openers
        clean = text.strip()
        clean = re.sub(
            r'^(?:i have|i\'ve got|i need to do|i need to|i have to|on my plate:?|my tasks are:?|plan for today:?|today i have|today:?)\s+',
            '',
            clean,
            flags=re.IGNORECASE,
        ).strip()

        # 0. Paragraph detection: if input is a multi-sentence paragraph (3+ sentences)
        #    we must split on sentence boundaries FIRST before any other processing.
        #    Without this step, a 9-task paragraph produces ONE massive chunk, which
        #    then gets classified as a single task (causing the "Physical · 90 min" bug).
        sentence_candidates = [s.strip() for s in re.split(r'(?<=[.!?])\s+', clean) if s.strip()]
        if len(sentence_candidates) >= 3:
            # This is a paragraph brain dump. Use sentence boundaries as primary chunks.
            primary_chunks = sentence_candidates
        else:
            # 1. Primary delimiters: newlines, semicolons, bullets
            primary_chunks = [c.strip() for c in re.split(r'[\n;•\*\-]+', clean) if c.strip()]
        clauses: List[str] = []

        # Known standalone activity words / nouns
        act_words = r'(?:gym|workout|work|assignments?|homework|dentist|doctor|groceries|meeting|emails?)'
        action_verbs = (
            r'(?:finish|study|go\s+to|gym|workout|review|call|email|buy|read|write|prep|pay|'
            r'meet|clean|submit|update|complete|walk|exercise|run|dentist|doctor|work|fix|'
            r'spend|reply|check|prepare|schedule)'
        )

        for chunk in primary_chunks:
            lower = chunk.strip().lower()

            # Task Segmentation: independently executable activities
            # e.g. "I have gym work and assignments" -> ["Gym", "Work", "Assignments"]
            # e.g. "gym work assignment" -> ["Gym", "Work", "Assignment"]
            # e.g. "gym, work, assignment" -> ["Gym", "Work", "Assignment"]
            # Preserves single outcome phrases like "finish my work assignment" or "finish my python assignment and submit it"
            is_single_transitive = bool(re.match(r'^(?:finish|complete|submit|review|write|read|work on)\b', lower))
            has_pronoun_ref = bool(re.search(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', lower))

            if not is_single_transitive and not has_pronoun_ref:
                # Insert comma between adjacent standalone activities, e.g. "gym work assignment" -> "gym, work, assignment"
                norm_chunk = chunk
                for _ in range(3):
                    norm_chunk = re.sub(rf'\b({act_words})\s+({act_words})\b', r'\1, \2', norm_chunk, flags=re.IGNORECASE)

                # Check for comma / 'and' separated list of activities
                list_match = re.split(r'(?:,\s*(?:and\s+)?|\s+and\s+)', norm_chunk, flags=re.IGNORECASE)
                valid_list = [p.strip() for p in list_match if p.strip()]
                if len(valid_list) > 1 and all(len(p) > 1 for p in valid_list):
                    clauses.extend(valid_list)
                    continue

            # Split on compound sentence dividers:
            # - ", and " or ", then " or " and then "
            # - ", " followed by action verb
            # - " and " followed by action verb (unless followed by "it" or "them", e.g. "and submit it")
            pattern = rf'(?:,\s*(?:and|then|and then)\s+|\s+(?:and then|then)\s+|,\s*(?:(?:maybe|probably|also|i should)\s+)?(?={action_verbs}\b)|\s+and\s+(?={action_verbs}\b(?!\s+(?:it|them)\b)))'
            parts = [p.strip() for p in re.split(pattern, chunk, flags=re.IGNORECASE) if p.strip()]
            clauses.extend(parts)

        return clauses or [clean.strip() or text.strip()]


    @classmethod
    def validate_and_segment_candidates(
        cls,
        candidates: List[TaskCandidateResponse],
        now_local: datetime,
        tz: ZoneInfo,
    ) -> List[TaskCandidateResponse]:
        """
        Enforce task segmentation outside the prompt.
        Checks if any candidate contains multiple independent activities,
        and splits them into separate valid candidates before scheduling.
        """
        valid_candidates: List[TaskCandidateResponse] = []
        for c in candidates:
            # Check for multiple activities combined in title
            lower_title = c.title.lower()
            is_single_transitive = bool(re.match(r'^(?:finish|complete|submit|review|write|read|work on)\b', lower_title))
            has_pronoun_ref = bool(re.search(r'\b(?:and\s+(?:then\s+)?(?:submit|send|review|file)\s+it)\b', lower_title))

            act_words = r'(?:gym|workout|work|assignments?|homework|dentist|doctor|groceries|meeting|emails?)'
            has_multi = bool(re.search(rf'\b{act_words}\b.*?\b(?:and\s+)?{act_words}\b', lower_title))

            if not is_single_transitive and not has_pronoun_ref and has_multi:
                # Sub-split this candidate
                sub_clauses = cls._split_clauses(c.title)
                if len(sub_clauses) > 1:
                    for sc in sub_clauses:
                        sub_cand = cls._parse_single_clause(sc, now_local, tz)
                        if sub_cand:
                            valid_candidates.append(sub_cand)
                    continue

            valid_candidates.append(c)

        return valid_candidates

    @classmethod
    def parse_task_dump(
        cls,
        raw_text: str,
        user_timezone_str: str = "UTC",
        force_ai: bool = False,
    ) -> List[TaskCandidateResponse]:
        """
        Parses user task notes or brain dumps into candidate tasks with confidence and provenance.
        Deterministic parser runs first for instant zero-token parsing.
        Google Gemini Cloud API runs if force_ai is requested, or as a resilient fallback
        when deterministic splitting yields 0 valid candidates.
        Ollama is retained as secondary local fallback.
        """
        if not raw_text or not raw_text.strip():
            return []

        try:
            tz = ZoneInfo(user_timezone_str)
        except Exception:
            tz = timezone.utc

        now_local = datetime.now(tz)

        # If user/caller explicitly requested cloud AI extraction:
        if force_ai and settings.GEMINI_API_KEY:
            gemini_candidates = cls._try_gemini_fallback(raw_text, now_local, tz)
            if gemini_candidates:
                return cls.validate_and_segment_candidates(gemini_candidates, now_local, tz)

        clauses = cls._split_clauses(raw_text)
        candidates: List[TaskCandidateResponse] = []

        for raw_clause in clauses:
            candidate = cls._parse_single_clause(raw_clause, now_local, tz)
            if candidate:
                candidates.append(candidate)

        candidates = cls.validate_and_segment_candidates(candidates, now_local, tz)

        # Scoped Fallback: ONLY when deterministic parsing yielded 0 candidates from non-empty text
        if not candidates and len(raw_text.strip()) > 2:
            # 1. Google Gemini Cloud API
            if settings.GEMINI_API_KEY:
                gemini_candidates = cls._try_gemini_fallback(raw_text, now_local, tz)
                if gemini_candidates:
                    return cls.validate_and_segment_candidates(gemini_candidates, now_local, tz)

            # 2. Local Ollama Fallback
            llm_candidates = cls._try_ollama_fallback(raw_text, now_local, tz)
            if llm_candidates:
                return cls.validate_and_segment_candidates(llm_candidates, now_local, tz)

            # Final resilient fallback if Ollama is offline
            return [
                TaskCandidateResponse(
                    title=sanitize_task_title(raw_text.strip()[:100]),
                    estimated_minutes=45,
                    task_type=TaskType.deep_work,
                    difficulty=TaskDifficulty.medium,
                    priority=TaskPriority.medium,
                    category="General",
                    confidence=0.40,
                    missing_fields=["duration", "deadline", "priority"],
                    ambiguities=[],
                    source=TaskSource.ai_parsed,
                )
            ]

        return candidates

    @classmethod
    def _parse_single_clause(cls, clause: str, now_local: datetime, tz: ZoneInfo) -> Optional[TaskCandidateResponse]:
        title = clause.strip()
        lower = clause.lower()

        missing_fields: List[str] = []
        ambiguities: List[str] = []
        provenance: Dict[str, FieldProvenance] = {}

        # 1. Duration Extraction
        duration = 45
        duration_found = False

        # Numeric units: e.g. "90 min", "1 hr", "1 hour", "30m", "45 mins", "1.5 hours"
        num_match = re.search(r'\b(?:for\s+)?(\d+(?:\.\d+)?)\s*(mins?|minutes?|m|hrs?|hours?|h)\b', lower)
        if num_match:
            qty = float(num_match.group(1))
            unit = num_match.group(2)
            if 'h' in unit:
                duration = min(480, int(qty * 60))
            else:
                duration = min(480, max(5, int(qty)))
            duration_found = True
            provenance["duration"] = FieldProvenance(source="explicit", confidence=1.0)
            title = re.sub(r'\b(?:for\s+)?\d+(?:\.\d+)?\s*(?:mins?|minutes?|m|hrs?|hours?|h)\b', '', title, flags=re.IGNORECASE).strip()
        else:
            # Word numbers: e.g. "half an hour", "one hour", "two hours", "three hours"
            word_match = re.search(r'\b(?:for\s+)?(half an hour|an hour|one hour|two hours|three hours|four hours)\b', lower)
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
                title = re.sub(r'\b(?:for\s+)?(?:half an hour|an hour|one hour|two hours|three hours|four hours)\b', '', title, flags=re.IGNORECASE).strip()

        if not duration_found:
            missing_fields.append("duration")
            provenance["duration"] = FieldProvenance(source="default", confidence=0.50)

        # 2. Time of Day Extraction & Temporal Constraints
        scheduled_start: Optional[datetime] = None
        scheduled_end: Optional[datetime] = None
        temporal = TemporalConstraints(confidence=1.0)

        target_date = now_local.date() + timedelta(days=1) if "tomorrow" in lower else now_local.date()
        if "tomorrow" in lower:
            temporal.target_date = target_date
            temporal.provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)
            provenance["target_date"] = FieldProvenance(source="explicit", confidence=1.0)

        time_match = re.search(r'\b(?:at|around)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b', lower)
        if time_match:
            raw_hour = int(time_match.group(1))
            raw_min = int(time_match.group(2)) if time_match.group(2) else 0
            ampm = time_match.group(3)

            target_hour = raw_hour
            if ampm:
                if ampm == "pm" and raw_hour < 12:
                    target_hour += 12
                elif ampm == "am" and raw_hour == 12:
                    target_hour = 0
                provenance["scheduled_time"] = FieldProvenance(source="explicit", confidence=1.0)
            else:
                # Bare time without AM/PM (e.g. "gym at 6")
                # Mark confidence = medium (0.70), flag ambiguity so UI shows AM/PM toggle
                ambiguities.append("time_am_pm")
                provenance["scheduled_time"] = FieldProvenance(source="inferred", confidence=0.70)
                if 1 <= raw_hour <= 7:
                    target_hour = raw_hour + 12  # default 6 -> 18:00 (6 PM) for evening context
                else:
                    target_hour = raw_hour

            sched_local = datetime.combine(target_date, time(target_hour, raw_min), tzinfo=tz)
            if lower[time_match.start():].startswith("around"):
                temporal.preferred_start = sched_local
                temporal.preferred_window_start = sched_local - timedelta(minutes=45)
                temporal.preferred_window_end = sched_local + timedelta(minutes=45)
                temporal.flexibility = "preferred"
                temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.95)
            else:
                scheduled_start = sched_local
                scheduled_end = scheduled_start + timedelta(minutes=duration)
                temporal.fixed_start = sched_local
                temporal.flexibility = "fixed"
                temporal.provenance["fixed_start"] = FieldProvenance(source="explicit", confidence=1.0)

            title = re.sub(r'\b(?:at|around)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b', '', title, flags=re.IGNORECASE).strip()

        # Preserve flexible language as constraints rather than inventing a calendar slot.
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
        elif "after dinner" in lower:
            temporal.earliest_start = datetime.combine(target_date, time(20, 0), tzinfo=tz)
            temporal.relative_after = "dinner"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.9)

        if "before dinner" in lower:
            temporal.latest_end = datetime.combine(target_date, time(20, 0), tzinfo=tz)
            temporal.relative_before = "dinner"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=0.9)
        elif re.search(r'\bbefore (?:i )?(?:sleep|bed)\b', lower):
            temporal.relative_before = "bedtime"
            temporal.flexibility = "constrained"
            temporal.provenance["relative_before"] = FieldProvenance(source="explicit", confidence=1.0)
        elif "in the evening" in lower:
            temporal.preferred_window_start = datetime.combine(target_date, time(17, 0), tzinfo=tz)
            temporal.preferred_window_end = datetime.combine(target_date, time(21, 0), tzinfo=tz)
            temporal.flexibility = "preferred"
            temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.9)
        elif "morning" in lower:
            temporal.preferred_window_start = datetime.combine(target_date, time(8, 0), tzinfo=tz)
            temporal.preferred_window_end = datetime.combine(target_date, time(12, 0), tzinfo=tz)
            temporal.flexibility = "preferred"
            temporal.provenance["preferred_window"] = FieldProvenance(source="explicit", confidence=0.9)

        # 3. Deadline / Date Extraction
        deadline_at: Optional[datetime] = None
        deadline_found = False

        deadline_match = re.search(r'\b(?:by|due)\s+(?:(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s+)?tomorrow\b', lower)
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
            title = re.sub(r'\b(?:by|due)\s+(?:\d{1,2}(?::\d{2})?\s*(?:am|pm)?\s+)?tomorrow\b', '', title, flags=re.IGNORECASE).strip()
        elif re.search(r'\b(?:by|due)\s+(?:today|tonight)\b', lower):
            d_local = datetime.combine(now_local.date(), time(23, 59), tzinfo=tz)
            deadline_at = d_local
            deadline_found = True
            provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
            title = re.sub(r'\b(?:by|due|on|before)?\s*(?:today|tonight)\b', '', title, flags=re.IGNORECASE).strip()
        elif "friday" in lower:
            days_ahead = (4 - now_local.weekday()) % 7
            if days_ahead == 0:
                days_ahead = 7
            d_local = datetime.combine(now_local.date() + timedelta(days=days_ahead), time(17, 0), tzinfo=tz)
            deadline_at = d_local.astimezone(timezone.utc)
            deadline_found = True
            provenance["deadline"] = FieldProvenance(source="explicit", confidence=0.95)
            title = re.sub(r'\b(?:by|due|on|before)?\s*friday\b', '', title, flags=re.IGNORECASE).strip()

        # Remove timing words from the display title only after their structured values are retained.
        title = re.sub(
            r'\b(?:sometime\s+)?after\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b|'
            r'\b(?:after|before)\s+dinner\b|\bbefore\s+(?:i\s+)?(?:sleep|bed)\b|'
            r'\b(?:tomorrow|today|tonight)(?:\s+(?:morning|evening|night))?\b|\bin\s+the\s+evening\b',
            '',
            title,
            flags=re.IGNORECASE,
        ).strip()

        if not deadline_found and not scheduled_start and not temporal.target_date:
            missing_fields.append("deadline")

        # 4. Priority Extraction (Explicit user input ALWAYS wins)
        explicit_priority = None
        if re.search(r'\b(?:urgent|critical|p0|asap)\b', lower):
            explicit_priority = TaskPriority.urgent
            title = re.sub(r'\b(?:urgent|critical|p0|asap)\b', '', title, flags=re.IGNORECASE).strip()
        elif re.search(r'\b(?:high\s+priority|p1|important|top\s+priority)\b', lower):
            explicit_priority = TaskPriority.high
            title = re.sub(r'\b(?:high\s+priority|p1|important|top\s+priority)\b', '', title, flags=re.IGNORECASE).strip()
        elif re.search(r'\b(?:low\s+priority|p3|optional)\b', lower):
            explicit_priority = TaskPriority.low
            title = re.sub(r'\b(?:low\s+priority|p3|optional)\b', '', title, flags=re.IGNORECASE).strip()
        elif re.search(r'\b(?:medium\s+priority|p2|normal\s+priority)\b', lower):
            explicit_priority = TaskPriority.medium
            title = re.sub(r'\b(?:medium\s+priority|p2|normal\s+priority)\b', '', title, flags=re.IGNORECASE).strip()

        # 5. Classification Priors (Starting Priors, NOT rigid ground truth)
        task_type = TaskType.deep_work
        difficulty = TaskDifficulty.medium
        # Priority default is ONLY for internal scheduler scoring weight, NEVER displayed as user choice
        priority = explicit_priority or TaskPriority.medium
        category = "General"

        # 6. Title Cleanup & Normalization: Concise and User-Faithful
        title = re.sub(r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+)', '', title, flags=re.IGNORECASE).strip()
        title = sanitize_task_title(title)
        lower_title = title.lower()

        if any(w in lower_title for w in ["gym", "workout", "run", "lift", "stretch", "walk", "exercise", "training"]):
            task_type = TaskType.physical
            difficulty = TaskDifficulty.physical
            category = "Fitness"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.92)
        elif any(w in lower_title for w in ["assignment", "assignments", "code", "coding", "paper", "research", "build", "design", "ml", "math", "develop", "thesis", "algorithm", "work", "meeting", "sync", "project"]):
            task_type = TaskType.deep_work
            difficulty = TaskDifficulty.high if any(w in lower_title for w in ["assignment", "thesis", "ml", "algorithm"]) else TaskDifficulty.medium
            category = "College" if any(w in lower_title for w in ["assignment", "assignments", "thesis"]) else "Work"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.88)
        elif any(w in lower_title for w in ["study", "review", "read", "reading", "notes", "quiz", "prep", "exam", "dbms", "lecture", "homework"]):
            task_type = TaskType.study
            difficulty = TaskDifficulty.medium
            category = "College"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        elif any(w in lower_title for w in ["email", "reply", "pay", "submit", "file", "call", "organize", "grocery", "groceries", "buy", "dentist", "doctor"]):
            task_type = TaskType.admin
            difficulty = TaskDifficulty.light
            category = "Personal"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        else:
            provenance["task_type"] = FieldProvenance(source="default", confidence=0.50)

        # Track priority provenance: user explicit vs unspecified
        if explicit_priority is not None:
            provenance["priority"] = FieldProvenance(source="explicit", confidence=1.0)
        else:
            # User did NOT specify priority; must display 'Priority not specified'
            missing_fields.append("priority")
            provenance["priority"] = FieldProvenance(source="unspecified", confidence=0.0)

        if not title:
            return None

        # 6. Overall Confidence Calculation
        conf_scores = [p.confidence for p in provenance.values() if p.source != "unspecified"]
        avg_conf = sum(conf_scores) / len(conf_scores) if conf_scores else 0.80
        if ambiguities:
            avg_conf *= 0.88
        if "duration" in missing_fields:
            avg_conf *= 0.90
        overall_confidence = round(min(1.0, max(0.20, avg_conf)), 2)

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
            source=TaskSource.ai_parsed,
            confidence=overall_confidence,
            missing_fields=missing_fields,
            ambiguities=ambiguities,
            field_provenance=provenance,
            temporal=temporal if temporal.provenance else None,
        )

    @classmethod
    def _try_gemini_fallback(cls, raw_text: str, now_local: datetime, tz: ZoneInfo) -> Optional[List[TaskCandidateResponse]]:
        """
        Secure Google Gemini Cloud API fallback for unstructured, complex, or natural language brain dumps.
        """
        try:
            candidates, _, _ = cls.extract_structured_plan_with_gemini(raw_text, user_timezone_str=str(tz))
            return candidates
        except Exception:
            return None

    @classmethod
    def extract_structured_plan_with_gemini(
        cls,
        raw_text: str,
        user_timezone_str: str = "UTC",
    ) -> Tuple[List[TaskCandidateResponse], List[str], bool]:
        """
        Server-side Gemini task extractor conforming to strict JSON contract:
        - NEVER invents deadlines or fixed times.
        - Explicit user input overrides inference.
        - Sets priority_source = explicit | inferred.
        - Sets needs_confirmation when appropriate.
        - Retries once with strict repair prompt if JSON is malformed.
        - Returns (candidates, ambiguities, needs_confirmation).
        - Raises RuntimeError if extraction completely fails.
        """
        api_key = settings.GEMINI_API_KEY
        if not api_key:
            raise RuntimeError("Gemini API key is not configured on server.")

        try:
            tz = ZoneInfo(user_timezone_str)
        except Exception:
            tz = timezone.utc

        now_local = datetime.now(tz)
        today_str = now_local.strftime("%Y-%m-%d")

        prompt = (
            "You are an intelligent task planner.\n"
            f"Current date: {today_str}\n"
            f"Current user timezone: {user_timezone_str}\n\n"
            "Extract structured task items from this user text:\n"
            f'"{raw_text}"\n\n'
            "CRITICAL INSTRUCTIONS:\n"
            "1. Return ONLY valid JSON in this exact structure:\n"
            "{\n"
            '  "tasks": [\n'
            "    {\n"
            '      "title": "concise task title",\n'
            '      "description": null,\n'
            '      "type": "deep_work" or "shallow_work" or "study" or "creative" or "admin" or "physical" or "meeting" or "personal",\n'
            '      "estimated_minutes": 45,\n'
            '      "difficulty": "high" or "medium" or "light" or "physical",\n'
            '      "priority": "low" or "medium" or "high" or "urgent" or null,\n'
            '      "priority_source": "explicit" or "inferred" or "unspecified",\n'
            '      "deadline": "YYYY-MM-DD" or null,\n'
            '      "fixed_start": "HH:MM" or null,\n'
            '      "preferred_start_hhmm": "HH:MM" or null,\n'
            '      "preferred_window": "morning" or "afternoon" or "evening" or "after_dinner" or null,\n'
            '      "earliest_start_hhmm": "HH:MM" or null,\n'
            '      "relative_after": "dinner" or null,\n'
            '      "is_recurring": false,\n'
            '      "dependencies": [],\n'
            '      "confidence": 0.95,\n'
            '      "needs_confirmation": false\n'
            "    }\n"
            "  ],\n"
            '  "ambiguities": []\n'
            "}\n\n"
            "STRICT RULES:\n"
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
            "  * Class/commute blocks like 'class at 12:40 PM' and 'need to leave home by 11:50' are FIXED EVENTS. Include them as type='meeting' with fixed_start set.\n"
            "- TASK TITLES MUST BE CONCISE, NATURAL, AND USER-FAITHFUL:\n"
            "  * Structure the user's input, DO NOT rewrite it into unnatural or awkward task names.\n"
            "  * Examples:\n"
            "    - 'gym around 6 PM' -> title: 'Gym session', type: 'physical', fixed_start: null, preferred_start_hhmm: '18:00', preferred_window: null\n"
            "    - 'finish my ML assignment and submit it before 11 AM, probably 90 minutes' -> title: 'Finish ML assignment', type: 'deep_work', estimated_minutes: 90, deadline: today\n"
            "    - 'fix the authentication bug, preferably in the afternoon' -> title: 'Fix auth bug', type: 'deep_work', estimated_minutes: 120, preferred_window: 'afternoon'\n"
            "    - 'after dinner I want to review DSA for 45 minutes' -> title: 'Review DSA', type: 'study', estimated_minutes: 45, preferred_window: 'after_dinner', relative_after: 'dinner', earliest_start_hhmm: '20:00'\n"
            "    - 'call my mom sometime in the evening, probably 15 minutes' -> title: 'Call mom', type: 'admin', estimated_minutes: 15, preferred_window: 'evening'\n"
            "    - 'clean my room' -> title: 'Clean room', type: 'admin', estimated_minutes: 30, priority: 'low'\n"
            "  * DO NOT generate titles like 'Gym to do', 'Work to do', 'Assignment task', or 'Task for gym'.\n"
            "  * Keep task category/type SEPARATE from title. Do not encode category into the title.\n"
            "- PRIORITY RULES:\n"
            "  * If user explicitly specifies priority ('urgent', 'high priority', 'low priority', 'optional', 'absolutely don't sacrifice', etc.): set priority accordingly and priority_source='explicit'.\n"
            "  * If user does NOT explicitly specify priority: DO NOT silently invent medium priority. Set priority_source='unspecified' and needs_confirmation=true.\n"
            "- TIME & DEADLINE RULES:\n"
            "  * NEVER invent deadlines or times. If user says 'study Python tomorrow', deadline is the date of tomorrow, fixed_start MUST be null. NEVER invent '10 AM'.\n"
            "  * If user explicitly mentions a time like 'at 5 PM' or 'at 6 PM', set fixed_start to 'HH:MM' in 24-hour format. 6 PM = '18:00'.\n"
            "  * 'around 6 PM' means preferred/flexible, NOT fixed. Do NOT set fixed_start. Set preferred_start_hhmm: '18:00' instead.\n"
            "  * 'before 11 AM' means deadline constraint, NOT fixed_start.\n"
            "  * 'sometime in the afternoon' -> preferred_window: 'afternoon'. Do NOT set fixed_start.\n"
            "  * 'in the evening' -> preferred_window: 'evening'. Do NOT set fixed_start.\n"
            "  * 'after dinner' -> preferred_window: 'after_dinner', relative_after: 'dinner', earliest_start_hhmm: '20:00'. Do NOT set fixed_start.\n"
            "  * 'morning' -> preferred_window: 'morning'. Do NOT set fixed_start.\n"
            "- FLOWSTATE DETERMINISTIC SCHEDULER is the final calendar scheduler. Never make rigid calendar choices for non-fixed tasks.\n"
        )

        headers = {
            "x-goog-api-key": api_key,
            "Content-Type": "application/json",
        }
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.1,
            },
        }

        models_to_try = []
        for m in [settings.GEMINI_MODEL, "gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"]:
            if m and m not in models_to_try:
                models_to_try.append(m)

        for model in models_to_try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
            try:
                with httpx.Client(timeout=12.0) as client:
                    started_at = clock.perf_counter()
                    resp = client.post(url, headers=headers, json=payload)
                    if resp.status_code != 200:
                        continue

                    data = resp.json()
                    usage = data.get("usageMetadata", {}) or {}
                    logger.info(
                        "Gemini plan request model=%s request_count=1 latency_ms=%s input_tokens=%s output_tokens=%s total_tokens=%s",
                        model,
                        round((clock.perf_counter() - started_at) * 1000),
                        usage.get("promptTokenCount"),
                        usage.get("candidatesTokenCount"),
                        usage.get("totalTokenCount"),
                    )
                    candidates_data = data.get("candidates", [])
                    if not candidates_data:
                        continue
                    parts = candidates_data[0].get("content", {}).get("parts", [])
                    if not parts:
                        continue
                    raw_json_str = parts[0].get("text", "{}")

                    # Parse JSON with 1 repair retry if malformed
                    parsed = None
                    try:
                        parsed = json.loads(raw_json_str)
                    except json.JSONDecodeError:
                        repair_prompt = (
                            f"The following text is NOT valid JSON:\n{raw_json_str}\n\n"
                            "Repair it and output ONLY valid JSON matching this schema:\n"
                            '{"tasks": [{"title": "...", "type": "...", "estimated_minutes": 45, "difficulty": "...", "priority": "...", "priority_source": "explicit", "deadline": null, "fixed_start": null, "confidence": 0.9, "needs_confirmation": false}], "ambiguities": []}'
                        )
                        repair_payload = {
                            "contents": [{"parts": [{"text": repair_prompt}]}],
                            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.0},
                        }
                        repair_started_at = clock.perf_counter()
                        repair_resp = client.post(url, headers=headers, json=repair_payload)
                        if repair_resp.status_code == 200:
                            try:
                                repair_usage = repair_resp.json().get("usageMetadata", {}) or {}
                                logger.info(
                                    "Gemini plan JSON-repair model=%s request_count=1 latency_ms=%s input_tokens=%s output_tokens=%s total_tokens=%s",
                                    model,
                                    round((clock.perf_counter() - repair_started_at) * 1000),
                                    repair_usage.get("promptTokenCount"),
                                    repair_usage.get("candidatesTokenCount"),
                                    repair_usage.get("totalTokenCount"),
                                )
                                repair_parts = repair_resp.json().get("candidates", [{}])[0].get("content", {}).get("parts", [{}])
                                parsed = json.loads(repair_parts[0].get("text", "{}"))
                            except Exception:
                                parsed = None

                    if not isinstance(parsed, dict) or "tasks" not in parsed:
                        if isinstance(parsed, list):
                            parsed = {"tasks": parsed, "ambiguities": []}
                        else:
                            continue

                    tasks_raw = parsed.get("tasks", [])
                    ambiguities = parsed.get("ambiguities", [])
                    if not isinstance(tasks_raw, list) or not tasks_raw:
                        continue

                    candidate_objects: List[TaskCandidateResponse] = []
                    overall_needs_confirmation = False

                    for item in tasks_raw:
                        raw_title = str(item.get("title", "")).strip()
                        if not raw_title:
                            continue
                        title = sanitize_task_title(raw_title)
                        try:
                            dur = int(item.get("estimated_minutes", 45))
                            dur = max(5, min(480, dur))
                        except Exception:
                            dur = 45

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

                        raw_prio = str(item.get("priority", "medium")).lower() if item.get("priority") else "medium"
                        try:
                            priority = TaskPriority(raw_prio)
                        except Exception:
                            priority = TaskPriority.medium

                        prio_src = str(item.get("priority_source", "unspecified")).lower()
                        if prio_src not in ["explicit", "inferred", "unspecified"]:
                            prio_src = "unspecified"

                        deadline_str = item.get("deadline")
                        deadline_at = None
                        if deadline_str and isinstance(deadline_str, str) and len(deadline_str) >= 8:
                            try:
                                d_date = datetime.strptime(deadline_str[:10], "%Y-%m-%d").date()
                                deadline_at = datetime.combine(d_date, time(23, 59, 59), tzinfo=tz)
                            except Exception:
                                deadline_at = None

                        fixed_start_str = item.get("fixed_start")
                        scheduled_start = None
                        scheduled_end = None
                        if fixed_start_str and isinstance(fixed_start_str, str) and ":" in fixed_start_str:
                            try:
                                time_parts = fixed_start_str.split(":")
                                hour = int(time_parts[0])
                                minute = int(time_parts[1][:2])
                                scheduled_start = datetime.combine(now_local.date(), time(hour, minute), tzinfo=tz)
                                scheduled_end = scheduled_start + timedelta(minutes=dur)
                            except Exception:
                                scheduled_start = None
                                scheduled_end = None

                        task_needs_conf = bool(item.get("needs_confirmation", False))
                        conf_score = float(item.get("confidence", 0.90))
                        if task_needs_conf or conf_score < 0.75 or prio_src in ["inferred", "unspecified"]:
                            overall_needs_confirmation = True
                        if prio_src == "unspecified" and "priority_unspecified" not in ambiguities:
                            ambiguities.append("priority_unspecified")
                        elif prio_src == "inferred" and "inferred_priority" not in ambiguities:
                            ambiguities.append("inferred_priority")

                        provenance = {
                            "title": FieldProvenance(source="gemini", confidence=conf_score),
                            "duration": FieldProvenance(source="gemini", confidence=conf_score),
                            "task_type": FieldProvenance(source="gemini", confidence=conf_score),
                            "difficulty": FieldProvenance(source="gemini", confidence=conf_score),
                            "priority": FieldProvenance(source=prio_src, confidence=conf_score),
                        }
                        if deadline_at:
                            provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
                        if scheduled_start:
                            provenance["scheduled_time"] = FieldProvenance(source="explicit", confidence=1.0)

                        missing_fields = []
                        if not deadline_at:
                            missing_fields.append("deadline")
                        if not scheduled_start:
                            missing_fields.append("scheduled_time")

                        # ── Build TemporalConstraints from Gemini temporal fields ──────────────
                        # This is the critical step: Gemini's preferred_window / preferred_start
                        # / earliest_start / relative_after must be captured in TemporalConstraints
                        # so the deterministic scheduler can apply them as soft/hard bounds.
                        temporal_constraints = None
                        temporal_provenance: Dict[str, Any] = {}

                        preferred_start_str = item.get("preferred_start_hhmm")
                        preferred_window_val = str(item.get("preferred_window") or "").lower().strip()
                        earliest_start_str = item.get("earliest_start_hhmm")
                        relative_after_val = str(item.get("relative_after") or "").lower().strip() or None

                        tc_preferred_start = None
                        tc_preferred_window_start = None
                        tc_preferred_window_end = None
                        tc_earliest_start = None
                        tc_relative_after = None

                        # Resolve preferred_start_hhmm -> preferred_start + ±45min window
                        if preferred_start_str and ":" in str(preferred_start_str):
                            try:
                                ps_parts = str(preferred_start_str).split(":")
                                ps_h, ps_m = int(ps_parts[0]), int(ps_parts[1][:2])
                                ps_dt = datetime.combine(now_local.date(), time(ps_h, ps_m), tzinfo=tz)
                                tc_preferred_start = ps_dt
                                tc_preferred_window_start = ps_dt - timedelta(minutes=45)
                                tc_preferred_window_end = ps_dt + timedelta(minutes=45)
                                temporal_provenance["preferred_start"] = FieldProvenance(source="explicit", confidence=0.95)
                            except Exception:
                                pass

                        # Resolve preferred_window keyword -> window start/end datetimes
                        if preferred_window_val and not tc_preferred_window_start:
                            base_date = now_local.date()
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
                                temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.90)

                        # Resolve explicit earliest_start_hhmm (hard lower bound)
                        if earliest_start_str and ":" in str(earliest_start_str) and not tc_earliest_start:
                            try:
                                es_parts = str(earliest_start_str).split(":")
                                es_h, es_m = int(es_parts[0]), int(es_parts[1][:2])
                                tc_earliest_start = datetime.combine(now_local.date(), time(es_h, es_m), tzinfo=tz)
                                temporal_provenance["earliest_start"] = FieldProvenance(source="explicit", confidence=1.0)
                            except Exception:
                                pass

                        # Capture relative_after field
                        if relative_after_val and not tc_relative_after:
                            tc_relative_after = relative_after_val
                            temporal_provenance["relative_after"] = FieldProvenance(source="explicit", confidence=0.90)

                        # Construct TemporalConstraints if any field was populated
                        has_temporal = any([
                            tc_preferred_start, tc_preferred_window_start,
                            tc_earliest_start, tc_relative_after,
                        ])
                        if has_temporal:
                            flex = "preferred"
                            if tc_earliest_start or tc_relative_after:
                                flex = "constrained"
                            temporal_constraints = TemporalConstraints(
                                preferred_start=tc_preferred_start,
                                preferred_window_start=tc_preferred_window_start,
                                preferred_window_end=tc_preferred_window_end,
                                earliest_start=tc_earliest_start,
                                relative_after=tc_relative_after,
                                flexibility=flex,
                                confidence=conf_score,
                                provenance=temporal_provenance,
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
                                confidence=conf_score,
                                missing_fields=missing_fields,
                                ambiguities=ambiguities if ambiguities else [],
                                source=TaskSource.ai_parsed,
                                field_provenance=provenance,
                                temporal=temporal_constraints,
                            )
                        )

                    if candidate_objects:
                        return candidate_objects, ambiguities, overall_needs_confirmation
            except Exception:
                continue

        raise RuntimeError("Gemini AI was unable to structure the task list. Please check your text or try again.")

    @classmethod
    def _try_ollama_fallback(cls, raw_text: str, now_local: datetime, tz: ZoneInfo) -> Optional[List[TaskCandidateResponse]]:
        """
        Optional local LLM fallback (strictly scoped for unparseable text).
        Protected by tight timeout (2.0s) and fails safely to ₹0.
        """
        try:
            prompt = (
                f"Extract task items from this text: '{raw_text}'. "
                f"Return ONLY valid JSON array with objects containing: title, estimated_minutes, category, priority."
            )
            with httpx.Client(timeout=2.0) as client:
                resp = client.post(
                    "http://localhost:11434/api/generate",
                    json={"model": "llama3.2", "prompt": prompt, "stream": False, "format": "json"},
                )
                if resp.status_code == 200:
                    data = resp.json()
                    # If valid JSON array returned, map into TaskCandidateResponse
                    import json
                    parsed = json.loads(data.get("response", "[]"))
                    if isinstance(parsed, list) and parsed:
                        results = []
                        for item in parsed:
                            title = item.get("title", "Task").strip()
                            dur = int(item.get("estimated_minutes", 45))
                            results.append(
                                TaskCandidateResponse(
                                    title=title,
                                    estimated_minutes=dur,
                                    task_type=TaskType.deep_work,
                                    difficulty=TaskDifficulty.medium,
                                    priority=TaskPriority.medium,
                                    category=item.get("category", "General"),
                                    confidence=0.75,
                                    missing_fields=[],
                                    ambiguities=[],
                                    source=TaskSource.ai_parsed,
                                    field_provenance={
                                        "title": FieldProvenance(source="ollama", confidence=0.75),
                                        "duration": FieldProvenance(source="ollama", confidence=0.70),
                                    }
                                )
                            )
                        return results
        except Exception:
            pass
        return None
