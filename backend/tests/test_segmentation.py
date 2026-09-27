"""
Flowstate Build My Day - Segmentation Regression Tests.

ROOT CAUSE FIXED:
  - _split_clauses did not split on sentence boundaries for paragraph input,
    causing a 9-task brain dump to collapse into 1 task: "Physical * 90 min".
  - requiresAiEnrichment (Flutter) returned False for multi-sentence paragraphs
    because deterministicFallbackParse returned non-empty (but collapsed) results.
"""

import pytest
from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.ai_service import AIService, sanitize_task_title
from app.schemas.task import TaskCandidateResponse
from app.models.task import TaskType, TaskDifficulty, TaskPriority

TZ = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 9, 28, 8, 0, tzinfo=TZ)

FAILING_BRAIN_DUMP = (
    "Tomorrow is going to be chaotic. "
    "I have class at 12:40 PM and I need to leave home by 11:50, "
    "so don't schedule anything that needs serious focus right before I leave. "
    "I need to finish my ML assignment and submit it before 11 AM, probably 90 minutes of work. "
    "I also need to fix the authentication bug in my project, around 2 hours, "
    "preferably sometime in the afternoon. "
    "I have a gym session around 6 PM, but if I'm really tired it's okay to move it later. "
    "After dinner I want to spend about 45 minutes reviewing DSA. "
    "I need to call my mom sometime in the evening, probably 15 minutes. "
    "I should clean my room too, but that's optional and shouldn't interfere with the important stuff. "
    "Also remind me that I shouldn't work too late because I want to sleep by 11:30 PM. "
    "If something has to be sacrificed, sacrifice cleaning my room first, then gym, "
    "but absolutely don't sacrifice the ML assignment deadline."
)


class TestParagraphDetection:
    def test_paragraph_produces_multiple_chunks(self):
        clauses = AIService._split_clauses(FAILING_BRAIN_DUMP)
        assert len(clauses) >= 5, f"Expected >= 5 clauses, got {len(clauses)}: {clauses}"

    def test_short_input_not_split_on_sentences(self):
        clauses = AIService._split_clauses("Finish my ML assignment tomorrow.")
        assert len(clauses) == 1

    def test_three_sentence_input_triggers_paragraph_path(self):
        text = "Finish my assignment. Call my dentist. Go to the gym."
        clauses = AIService._split_clauses(text)
        assert len(clauses) >= 3


class TestFailingBrainDump:
    def test_failing_input_not_collapsed_to_one_task(self):
        candidates = AIService.parse_task_dump(FAILING_BRAIN_DUMP, user_timezone_str="Asia/Kolkata")
        assert len(candidates) >= 3, (
            f"Expected >= 3 tasks, got {len(candidates)}. Titles: {[c.title for c in candidates]}"
        )

    def test_no_single_physical_90_blob(self):
        candidates = AIService.parse_task_dump(FAILING_BRAIN_DUMP, user_timezone_str="Asia/Kolkata")
        physical_tasks = [c for c in candidates if c.task_type == TaskType.physical]
        for t in physical_tasks:
            assert len(t.title) < 80, f"Physical task looks like blob: '{t.title}'"

    def test_ml_assignment_extracted(self):
        candidates = AIService.parse_task_dump(FAILING_BRAIN_DUMP, user_timezone_str="Asia/Kolkata")
        titles_lower = [c.title.lower() for c in candidates]
        has_ml = any("ml" in t or "assignment" in t for t in titles_lower)
        assert has_ml, f"ML assignment not found in: {[c.title for c in candidates]}"


class TestSimpleSegmentation:
    def test_dbms_and_clean_room(self):
        text = "Submit my DBMS assignment by 8 PM tomorrow, maybe clean my room later"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2, f"Expected 2 tasks, got {len(candidates)}: {[c.title for c in candidates]}"

    def test_single_coherent_task_not_split(self):
        text = "finish my assignment and submit it"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1, f"Expected 1 task, got {len(candidates)}: {[c.title for c in candidates]}"

    def test_three_independent_tasks(self):
        text = "finish my assignment, reply to Rahul and clean my room"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2, f"Expected >= 2 tasks, got {len(candidates)}"


class TestTemporalConstraints:
    def test_at_time_is_fixed(self):
        text = "gym at 6 PM"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1
        assert candidates[0].scheduled_start is not None
        assert candidates[0].scheduled_start.hour == 18

    def test_no_deadline_invented_for_clean_room(self):
        text = "clean my room later"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 1
        c = candidates[0]
        assert c.deadline_at is None, f"Must not invent deadline, got: {c.deadline_at}"

    def test_task_with_no_time_has_no_scheduled_start(self):
        text = "clean my room"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1
        assert candidates[0].scheduled_start is None, f"Must not invent time: {candidates[0].scheduled_start}"


class TestAdversarialCases:
    def test_and_separator_produces_multiple(self):
        text = "gym and study and call dentist"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2, f"Expected >= 2, got {len(candidates)}: {[c.title for c in candidates]}"

    def test_then_separator(self):
        text = "gym then study"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2

    def test_also_separator(self):
        text = "finish assignment, also call dentist"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2

    def test_multiple_durations_correct(self):
        text = "fix auth bug for 2 hours, review DSA for 45 minutes"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2
        durations = {c.estimated_minutes for c in candidates}
        assert 120 in durations, f"120 min not found: {durations}"
        assert 45 in durations, f"45 min not found: {durations}"

    def test_probably_is_not_task_splitter(self):
        text = "finish ML assignment, probably 90 minutes"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1
        assert candidates[0].estimated_minutes == 90

    def test_speech_to_text_style(self):
        text = "i need to finish my assignment then go to the gym and also call my mom"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2, f"Got {len(candidates)}: {[c.title for c in candidates]}"

    def test_messy_punctuation(self):
        text = "gym... assignment!!! call mom?? clean room."
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) >= 2


class TestSingleCandidatePreservation:
    def test_finish_and_submit_it(self):
        text = "finish my assignment and submit it"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1

    def test_single_task_with_duration(self):
        text = "Review DSA for 45 minutes"
        candidates = AIService.parse_task_dump(text)
        assert len(candidates) == 1
        assert candidates[0].estimated_minutes == 45


class TestSanitizeTaskTitle:
    def test_empty_string(self):
        assert sanitize_task_title("") == "Task"

    def test_strips_leading_and(self):
        result = sanitize_task_title("and then do the thing")
        assert not result.lower().startswith("and")

    def test_preserves_meaningful_content(self):
        result = sanitize_task_title("Finish ML assignment")
        assert "assignment" in result.lower() or "ml" in result.lower()

    def test_capitalizes_first_letter(self):
        result = sanitize_task_title("gym session")
        assert result[0].isupper()


class TestValidateAndSegmentCandidates:
    def test_multi_activity_title_split(self):
        candidates = [
            TaskCandidateResponse(
                title="Gym workout assignment",
                estimated_minutes=45,
                task_type=TaskType.deep_work,
                difficulty=TaskDifficulty.medium,
                priority=TaskPriority.medium,
            )
        ]
        result = AIService.validate_and_segment_candidates(candidates, NOW, TZ)
        assert len(result) >= 2, f"Expected split, got {len(result)}"

    def test_single_activity_not_split(self):
        candidates = [
            TaskCandidateResponse(
                title="Finish ML assignment",
                estimated_minutes=90,
                task_type=TaskType.deep_work,
                difficulty=TaskDifficulty.high,
                priority=TaskPriority.high,
            )
        ]
        result = AIService.validate_and_segment_candidates(candidates, NOW, TZ)
        assert len(result) == 1, f"Expected 1, got {len(result)}"
