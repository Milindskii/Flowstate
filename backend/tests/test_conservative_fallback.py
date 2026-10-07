"""
Build My Day — conservative, lossless deterministic fallback (milestone 1).

The deterministic parser used to fragment natural language: duration
phrases were regex-deleted from titles ("Which may take about ."), every
comma/"and" produced a candidate ("Spend about there.", "Around ."), and
instruction sentences became tasks. "around 90 minutes" was read as clock
hour 90 and raised ValueError.

These tests pin the conservative behaviour:
  * one intention -> one candidate (attribute sentences attach to their task)
  * no orphan / broken-prose titles
  * instruction and mood sentences never become tasks
  * duration phrases are never clock times
  * Gemini-derived candidates are never re-split
"""

import re
from datetime import datetime
from zoneinfo import ZoneInfo

from app.models.task import TaskDifficulty, TaskPriority, TaskType
from app.schemas.task import FieldProvenance, TaskCandidateResponse
from app.services.ai_service import AIService

TZ = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 9, 28, 8, 0, tzinfo=TZ)

# Reconstructed from the fragments recorded in
# docs/superpowers/specs/build-my-day-intelligence-v2.md §4.1 / §26.1.
BENCHMARK_DUMP = (
    "Tomorrow I have class at 12:40 PM. Leave home by 11:50 AM. "
    "I should finish my machine learning assignment because I need to submit it tomorrow before 11 AM. "
    "It will probably take around 90 minutes. "
    "I also want to fix a backend authentication bug in my project, which may take about 2 hours. "
    "I'd like to do that when I'm mentally fresh. "
    "I want to go to the gym around 6 PM and spend about an hour there. "
    "Review DSA for at least 45 minutes, preferably earlier in the day but it can be moved. "
    "Call my mom sometime in the evening, around 15 minutes. "
    "I also need to clean my room, which will take about 30 minutes, but this is low priority. "
    "Can be skipped if the day gets too full. "
    "Don't schedule tasks on top of each other. "
    "Keep enough travel/preparation time around class and gym. "
    "Prioritize assignment, class, backend bug, gym, and DSA in that order if there isn't enough time for everything."
)

_DANGLING_END = {
    "about", "around", "for", "at", "by", "take", "takes", "least", "most", "than",
    "the", "a", "an", "to", "and", "or", "but", "which", "is", "of", "with", "sometime",
    "approximately", "roughly", "probably", "spend",
}
_DEPENDENT_START = re.compile(
    r"^(?:which|it|this|that|but|so|because|preferably|around|about|spend\s+about|can\s+be)\b",
    re.IGNORECASE,
)
_INSTRUCTION = re.compile(
    r"\b(?:don'?t schedule|prioriti[sz]e|keep enough|in that order|on top of each other)\b",
    re.IGNORECASE,
)


def assert_well_formed(title: str) -> None:
    t = title.strip()
    assert t, "empty title"
    assert not re.search(r"\s[.,;:!?]", t), f"broken prose (space before punctuation): {t!r}"
    assert not re.search(r"[,;:]$", t), f"dangling punctuation: {t!r}"
    last = re.sub(r"[.!?]+$", "", t).split()[-1].lower()
    assert last not in _DANGLING_END, f"dangling final word {last!r}: {t!r}"
    assert not _DEPENDENT_START.match(t), f"orphan dependent fragment: {t!r}"
    assert not _INSTRUCTION.search(t), f"instruction became a task: {t!r}"


def _parse(text: str):
    return AIService.parse_task_dump(text, user_timezone_str="Asia/Kolkata")


def _find(cands, *words):
    for c in cands:
        low = c.title.lower()
        if all(w in low for w in words):
            return c
    raise AssertionError(f"no candidate with {words}: {[c.title for c in cands]}")


class TestBenchmarkDump:
    def test_no_crash_and_no_fragments(self):
        cands = _parse(BENCHMARK_DUMP)
        for c in cands:
            assert_well_formed(c.title)

    def test_entity_count_is_not_fragmented(self):
        # Gold: 7 tasks + 1 attached travel block = 8; fallback may be <= 1.3x gold.
        cands = _parse(BENCHMARK_DUMP)
        assert 6 <= len(cands) <= 10, [c.title for c in cands]

    def test_durations_stay_attached_to_their_own_task(self):
        cands = _parse(BENCHMARK_DUMP)
        assert _find(cands, "assignment").estimated_minutes == 90
        assert _find(cands, "authentication").estimated_minutes == 120
        assert _find(cands, "gym").estimated_minutes == 60
        assert _find(cands, "dsa").estimated_minutes == 45
        assert _find(cands, "mom").estimated_minutes == 15
        assert _find(cands, "room").estimated_minutes == 30

    def test_attribute_sentences_attach_to_their_task(self):
        cands = _parse(BENCHMARK_DUMP)
        room = _find(cands, "room")
        assert room.priority == TaskPriority.low
        gym = _find(cands, "gym")
        assert gym.scheduled_start is None, "around 6 PM must not lock gym"
        assert gym.temporal is not None and gym.temporal.preferred_start is not None
        assert gym.temporal.preferred_start.hour == 18

    def test_duration_is_never_a_clock_time(self):
        cands = _parse(BENCHMARK_DUMP)
        mom = _find(cands, "mom")
        pref = mom.temporal.preferred_start if mom.temporal else None
        assert pref is None or pref.hour != 15, "'around 15 minutes' read as 15:00"
        assignment = _find(cands, "assignment")
        assert assignment.scheduled_start is None


class TestDurationPhrases:
    def test_probably_take_around_90_minutes_does_not_crash(self):
        c = AIService._parse_single_clause("It will probably take around 90 minutes", NOW, TZ)
        # A pure attribute sentence on its own carries no task; it must not raise
        # and must not invent a clock time.
        if c is not None:
            assert c.scheduled_start is None
            assert c.temporal is None or c.temporal.preferred_start is None

    def test_duration_attaches_to_previous_sentence(self):
        cands = _parse("Finish my ML assignment. It will probably take around 90 minutes.")
        assert len(cands) == 1, [c.title for c in cands]
        c = cands[0]
        assert c.estimated_minutes == 90
        assert c.scheduled_start is None
        assert c.temporal is None or c.temporal.preferred_start is None
        assert_well_formed(c.title)
        assert "assignment" in c.title.lower()

    def test_around_with_decimal_hours_is_not_a_clock_time(self):
        c = AIService._parse_single_clause("Write report around 1.5 hours", NOW, TZ)
        assert c.estimated_minutes == 90
        assert c.temporal is None or c.temporal.preferred_start is None

    def test_title_keeps_meaning_when_duration_removed(self):
        c = AIService._parse_single_clause(
            "Review DSA for at least 45 minutes, preferably earlier in the day", NOW, TZ
        )
        assert c.estimated_minutes == 45
        assert_well_formed(c.title)
        assert "dsa" in c.title.lower()


class TestOneIntentionOneCandidate:
    def test_and_spend_about_an_hour_there(self):
        cands = _parse("I want to go to the gym around 6 PM and spend about an hour there.")
        assert len(cands) == 1, [c.title for c in cands]
        assert cands[0].estimated_minutes == 60
        assert_well_formed(cands[0].title)

    def test_which_clause_is_not_a_new_task(self):
        cands = _parse("I also want to fix a backend bug in my project, which may take about 2 hours.")
        assert len(cands) == 1, [c.title for c in cands]
        assert cands[0].estimated_minutes == 120

    def test_preference_sentence_is_not_a_task(self):
        cands = _parse("Fix the login bug for 2 hours. I'd like to do that when I'm mentally fresh.")
        assert len(cands) == 1, [c.title for c in cands]

    def test_instruction_sentences_are_not_tasks(self):
        cands = _parse(
            "Call the dentist. Don't schedule tasks on top of each other. "
            "Prioritize the dentist in that order."
        )
        assert [c.title for c in cands] == ["Call the dentist"]

    def test_attached_clause_about_other_tasks_does_not_raise_priority(self):
        cands = _parse(
            "I should clean my room too, but that's optional and shouldn't "
            "interfere with the important stuff."
        )
        assert len(cands) == 1, [c.title for c in cands]
        assert cands[0].priority == TaskPriority.low

    def test_real_lists_still_split(self):
        assert len(_parse("gym and study and call dentist")) == 3
        assert len(_parse("finish my assignment, reply to Rahul and clean my room")) == 3

    def test_finish_and_submit_it_stays_one(self):
        assert len(_parse("finish my assignment and submit it")) == 1


class TestGeminiCandidateImmutability:
    def _gemini(self, title: str) -> TaskCandidateResponse:
        prov = FieldProvenance(source="gemini", confidence=0.9)
        return TaskCandidateResponse(
            title=title,
            estimated_minutes=90,
            task_type=TaskType.deep_work,
            difficulty=TaskDifficulty.high,
            priority=TaskPriority.high,
            field_provenance={"title": prov, "duration": prov},
        )

    def test_long_multi_sentence_gemini_title_is_not_resplit(self):
        title = (
            "Finish the ML assignment. Then go to the gym and also call mom. "
            "Review DSA notes after that, which may take about an hour."
        )
        cand = self._gemini(title)
        out = AIService.validate_and_segment_candidates([cand], NOW, TZ)
        assert len(out) == 1
        assert out[0] is cand
        assert out[0].title == title
        assert out[0].estimated_minutes == 90

    def test_gemini_multi_activity_title_is_not_resplit(self):
        cand = self._gemini("Gym workout and assignment review")
        out = AIService.validate_and_segment_candidates([cand], NOW, TZ)
        assert out == [cand]
