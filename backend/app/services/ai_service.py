import re
import json
import httpx
from typing import List, Optional, Dict, Tuple, Any
from datetime import datetime, timedelta, timezone, time
from zoneinfo import ZoneInfo
from ..models.task import TaskType, TaskDifficulty, TaskPriority, TaskSource
from ..schemas.task import TaskCandidateResponse, FieldProvenance
from ..core.config import settings

def sanitize_task_title(title: str) -> str:
    """
    Ensures task titles are concise, natural, and user-faithful.
    Strips awkward filler ('to do', 'task for', 'task', 'my ...', 'the ...', 'go to').
    """
    if not title:
        return "Task"
    t = title.strip()
    # Strip leading/trailing punctuation or bullet marks
    t = re.sub(r'^[,\s\-•*:]+|[,\s\-•*:]+$', '', t).strip()
    # Strip prefixes like "task for ", "task: ", "to do: "
    t = re.sub(r'^(?:task\s+for|task\s*:|to\s*do\s*:)\s*', '', t, flags=re.IGNORECASE).strip()
    # Strip suffixes like " to do", " todo", " task"
    t = re.sub(r'\s+(?:to\s+do|todo|task)$', '', t, flags=re.IGNORECASE).strip()
    # Strip filler like 'my' or 'the' after action verbs (e.g. 'finish my assignment' -> 'Finish assignment')
    t = re.sub(r'\b(?:my|the)\s+(?=assignment|project|lab|homework|thesis|work|task|exam|quiz|session|workout)\b', '', t, flags=re.IGNORECASE)
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
        # 1. Primary delimiters: newlines, semicolons, bullets
        primary_chunks = [c.strip() for c in re.split(r'[\n;•\*\-]+', text) if c.strip()]
        clauses: List[str] = []

        action_verbs = r'(?:finish|study|go to|gym|workout|review|call|email|buy|read|write|prep|pay|meet|clean|submit|update|complete|walk|exercise|run|dentist|doctor)'

        for chunk in primary_chunks:
            lower = chunk.strip().lower()

            # Task Segmentation: independently executable activities
            # e.g. "gym work assignment" -> ["Gym", "Work", "Assignment"]
            # Preserves single outcome phrases like "finish my work assignment" or "finish my python assignment and submit it"
            if not re.match(r'^(?:finish|complete|submit|do|start|review|write|read)\b', lower) and not re.search(r'\b(?:and\s+submit\s+it|and\s+send\s+it)\b', lower):
                seg_match3 = re.match(r'^(gym|workout|exercise|run)\s+(work|meeting|emails?)\s+(assignment|study|homework|thesis)$', lower)
                if seg_match3:
                    clauses.extend([seg_match3.group(1).capitalize(), seg_match3.group(2).capitalize(), seg_match3.group(3).capitalize()])
                    continue

                seg_match2 = re.match(r'^(gym|workout|exercise|run)\s+(work|meeting|emails?|assignment|study|homework|thesis|dentist|groceries)$', lower)
                if seg_match2:
                    clauses.extend([seg_match2.group(1).capitalize(), seg_match2.group(2).capitalize()])
                    continue

            # Split on compound sentence dividers:
            # - ", and " or ", then " or " and then "
            # - ", " followed by action verb
            # - " and " followed by action verb (unless followed by "it" or "them", e.g. "and submit it")
            pattern = rf'(?:,\s*(?:and|then|and then)\s+|\s+(?:and then|then)\s+|,\s*(?={action_verbs}\b)|\s+and\s+(?={action_verbs}\b(?!\s+(?:it|them)\b)))'
            parts = [p.strip() for p in re.split(pattern, chunk, flags=re.IGNORECASE) if p.strip()]
            clauses.extend(parts)

        return clauses or [text.strip()]

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
                return gemini_candidates

        clauses = cls._split_clauses(raw_text)
        candidates: List[TaskCandidateResponse] = []

        for raw_clause in clauses:
            candidate = cls._parse_single_clause(raw_clause, now_local, tz)
            if candidate:
                candidates.append(candidate)

        # Scoped Fallback: ONLY when deterministic parsing yielded 0 candidates from non-empty text
        if not candidates and len(raw_text.strip()) > 2:
            # 1. Google Gemini Cloud API
            if settings.GEMINI_API_KEY:
                gemini_candidates = cls._try_gemini_fallback(raw_text, now_local, tz)
                if gemini_candidates:
                    return gemini_candidates

            # 2. Local Ollama Fallback
            llm_candidates = cls._try_ollama_fallback(raw_text, now_local, tz)
            if llm_candidates:
                return llm_candidates

            # Final resilient fallback if Ollama is offline
            return [
                TaskCandidateResponse(
                    title=raw_text.strip()[:100],
                    estimated_minutes=45,
                    task_type=TaskType.deep_work,
                    difficulty=TaskDifficulty.medium,
                    priority=TaskPriority.medium,
                    category="General",
                    confidence=0.40,
                    missing_fields=["duration", "deadline"],
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

        # 2. Time of Day Extraction & Ambiguity Tracking
        scheduled_start: Optional[datetime] = None
        scheduled_end: Optional[datetime] = None

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

            sched_local = datetime.combine(now_local.date(), time(target_hour, raw_min), tzinfo=tz)
            scheduled_start = sched_local.astimezone(timezone.utc)
            scheduled_end = scheduled_start + timedelta(minutes=duration)

            title = re.sub(r'\b(?:at|around)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?\b', '', title, flags=re.IGNORECASE).strip()

        # 3. Deadline / Date Extraction
        deadline_at: Optional[datetime] = None
        deadline_found = False

        if "tomorrow" in lower:
            d_local = datetime.combine(now_local.date() + timedelta(days=1), time(18, 0), tzinfo=tz)
            deadline_at = d_local.astimezone(timezone.utc)
            deadline_found = True
            provenance["deadline"] = FieldProvenance(source="explicit", confidence=1.0)
            title = re.sub(r'\b(?:by|due|on|before)?\s*tomorrow(?:\s+night|\s+morning)?\b', '', title, flags=re.IGNORECASE).strip()
        elif "today" in lower or "tonight" in lower:
            d_local = datetime.combine(now_local.date(), time(23, 59), tzinfo=tz)
            deadline_at = d_local.astimezone(timezone.utc)
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

        if not deadline_found and not scheduled_start:
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
        priority = explicit_priority or TaskPriority.medium
        category = "General"

        if any(w in lower for w in ["assignment", "code", "coding", "paper", "research", "build", "design", "ml", "math", "develop", "thesis", "algorithm"]):
            task_type = TaskType.deep_work
            difficulty = TaskDifficulty.high
            if explicit_priority is None:
                priority = TaskPriority.high
            category = "College"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.88)
        elif any(w in lower for w in ["study", "review", "read", "reading", "notes", "quiz", "prep", "exam", "dbms", "lecture"]):
            task_type = TaskType.study
            difficulty = TaskDifficulty.medium
            if explicit_priority is None:
                priority = TaskPriority.medium
            category = "College"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        elif any(w in lower for w in ["gym", "workout", "run", "lift", "stretch", "walk", "exercise", "training"]):
            task_type = TaskType.physical
            difficulty = TaskDifficulty.physical
            if explicit_priority is None:
                priority = TaskPriority.low
            category = "Fitness"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.92)
        elif any(w in lower for w in ["email", "reply", "pay", "submit", "file", "call", "sync", "organize", "grocery", "groceries", "buy", "dentist", "doctor"]):
            task_type = TaskType.admin
            difficulty = TaskDifficulty.light
            if explicit_priority is None:
                priority = TaskPriority.low
            category = "Personal"
            provenance["task_type"] = FieldProvenance(source="inferred", confidence=0.85)
        else:
            provenance["task_type"] = FieldProvenance(source="default", confidence=0.50)

        # Track priority provenance
        if explicit_priority is not None:
            provenance["priority"] = FieldProvenance(source="explicit", confidence=1.0)
        else:
            # Priority was inferred from context or default
            provenance["priority"] = FieldProvenance(source="inferred", confidence=0.80)

        # 6. Title Cleanup & Normalization: Concise and User-Faithful
        title = re.sub(r'^(?:and\s+|then\s+|also\s+|go\s+to\s+|to\s+)', '', title, flags=re.IGNORECASE).strip()
        title = sanitize_task_title(title)

        if not title:
            return None

        # 6. Overall Confidence Calculation
        conf_scores = [p.confidence for p in provenance.values()]
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
            "  * Identify independently executable activities. Semantic independence is more important than commas or punctuation.\n"
            "  * When multiple independent activities appear in a single sentence or unpunctuated stream, split them into separate task candidates.\n"
            "  * Examples:\n"
            "    - 'gym work assignment' -> MUST become 3 separate tasks: 'Gym' (type: physical), 'Work' (type: admin), 'Assignment' (type: study).\n"
            "    - 'finish my work assignment' -> MUST remain 1 task: 'Finish work assignment'.\n"
            "    - 'finish my Python assignment and submit it' -> MUST remain 1 task (single unified outcome): 'Finish Python assignment and submit'.\n"
            "- TASK TITLES MUST BE CONCISE, NATURAL, AND USER-FAITHFUL:\n"
            "  * Structure the user's input, DO NOT rewrite it into unnatural or awkward task names.\n"
            "  * Examples:\n"
            "    - 'gym tomorrow' -> title: 'Gym', type: 'physical'\n"
            "    - 'finish my assignment' -> title: 'Finish assignment', type: 'study'\n"
            "    - 'work tomorrow' -> title: 'Work', type: 'admin'\n"
            "    - 'call dentist at 5' -> title: 'Call dentist', fixed_start: '17:00'\n"
            "  * DO NOT generate titles like 'Gym to do', 'Work to do', 'Assignment task', or 'Task for gym'.\n"
            "  * Keep task category/type SEPARATE from title. Do not encode category into the title.\n"
            "- PRIORITY RULES:\n"
            "  * If user explicitly specifies priority ('urgent', 'high priority', 'low priority', etc.): set priority accordingly and priority_source='explicit'.\n"
            "  * If user does NOT explicitly specify priority: DO NOT silently invent medium priority. Set priority_source='unspecified' (or 'inferred' if strong context) and needs_confirmation=true.\n"
            "- TIME & DEADLINE RULES:\n"
            "  * NEVER invent deadlines or times. If user says 'study Python tomorrow', deadline is the date of tomorrow, fixed_start MUST be null. NEVER invent '10 AM'.\n"
            "  * If user explicitly mentions a time like 'at 5 PM' or 'at 6', set fixed_start to 'HH:MM' (24-hour format).\n"
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
                    resp = client.post(url, headers=headers, json=payload)
                    if resp.status_code != 200:
                        continue

                    data = resp.json()
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
                        repair_resp = client.post(url, headers=headers, json=repair_payload)
                        if repair_resp.status_code == 200:
                            try:
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
