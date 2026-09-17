import re
from typing import List, Optional
from datetime import datetime, timedelta, timezone
from ..models.task import TaskType, TaskDifficulty, TaskPriority, TaskSource
from ..schemas.task import TaskCreate

class AIService:
    """
    Service responsible for Natural Language Task Parsing ('What's on your plate?')
    Strictly suggests structured task candidates for user confirmation.
    NEVER creates tasks directly or makes unilateral scheduling decisions.
    """

    @staticmethod
    def parse_task_dump(raw_text: str) -> List[TaskCreate]:
        """
        Parses unorganized user task notes or brain dumps into candidate tasks.
        Uses intelligent heuristic parsing with LLM extensibility.
        """
        if not raw_text or not raw_text.strip():
            return []

        # Split on line breaks, bullets, or semicolons
        lines = [line.strip() for line in re.split(r'[\n;•\*\-]+', raw_text) if line.strip()]
        candidates: List[TaskCreate] = []

        now = datetime.now(timezone.utc)

        for line in lines:
            title = line
            duration = 45
            difficulty = TaskDifficulty.medium
            task_type = TaskType.deep_work
            priority = TaskPriority.medium
            deadline: Optional[datetime] = None

            lower = line.lower()

            # Duration detection (e.g. 90 min, 1 hr, 30m)
            duration_match = re.search(r'(\d+)\s*(min|m|hr|hour|h)', lower)
            if duration_match:
                qty = int(duration_match.group(1))
                unit = duration_match.group(2)
                if 'h' in unit:
                    duration = min(480, qty * 60)
                else:
                    duration = min(480, max(10, qty))
                # Clean duration from title
                title = re.sub(r'\(?\d+\s*(min|m|hr|hour|h)\)?', '', title, flags=re.IGNORECASE).strip()

            # Deadline detection
            if "tomorrow" in lower:
                deadline = (now + timedelta(days=1)).replace(hour=18, minute=0, second=0, microsecond=0)
            elif "today" in lower or "tonight" in lower:
                deadline = now.replace(hour=23, minute=59, second=0, microsecond=0)
            elif "friday" in lower:
                days_ahead = (4 - now.weekday()) % 7
                if days_ahead == 0:
                    days_ahead = 7
                deadline = (now + timedelta(days=days_ahead)).replace(hour=17, minute=0, second=0, microsecond=0)

            # Task Type & Difficulty classification
            if any(w in lower for w in ["assignment", "code", "paper", "research", "build", "design", "ml", "math"]):
                task_type = TaskType.deep_work
                difficulty = TaskDifficulty.high
                priority = TaskPriority.high
            elif any(w in lower for w in ["study", "review", "read", "notes", "quiz", "prep", "exam"]):
                task_type = TaskType.study
                difficulty = TaskDifficulty.medium
            elif any(w in lower for w in ["gym", "workout", "run", "lift", "stretch", "walk"]):
                task_type = TaskType.physical
                difficulty = TaskDifficulty.physical
            elif any(w in lower for w in ["email", "reply", "pay", "submit", "file", "call", "sync", "organize"]):
                task_type = TaskType.admin
                difficulty = TaskDifficulty.light
                priority = TaskPriority.low

            # Clean extra trailing punctuation
            title = title.strip(' .,-')
            if not title:
                continue

            candidates.append(
                TaskCreate(
                    title=title,
                    estimated_minutes=duration,
                    task_type=task_type,
                    difficulty=difficulty,
                    priority=priority,
                    deadline_at=deadline,
                    source=TaskSource.ai_parsed,
                )
            )

        return candidates
