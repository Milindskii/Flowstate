"""Build My Day: "after that" / "then" are ordering constraints (manual verification 2026-10-06).

Real input: "Do ml observation after that then stick pictures for cn observation".
The deterministic parser must keep the order as `depends_on`, the planner must honour it, and the
dependency must survive persistence (confirm -> DB -> later replans).
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.engines.scheduling_engine import PlanningProfile
from app.models.task import Task
from app.services import planning_service
from app.services.ai_service import AIService
from app.services.candidate_dependencies import link_sequential_from_text
from tests.plan_helpers import IST, cand, client, make_user, post_plan, stub_deterministic_extraction

NOW = datetime(2026, 10, 6, 9, 0, tzinfo=IST)


def _parse(text):
    return AIService.parse_task_dump(text, "Asia/Kolkata")


def _chain(cands):
    """[(title, [index of each dependency])] in candidate order."""
    index = {c.candidate_id: i for i, c in enumerate(cands)}
    return [(c.title, [index[d] for d in c.depends_on]) for c in cands]


def _schedule(cands):
    planning_service.schedule_candidates(
        cands, None, [], profile=PlanningProfile(), tz=IST, tz_name="Asia/Kolkata", now_local=NOW)
    return cands


# ── parsing ──────────────────────────────────────────────────────────────────

def test_real_input_after_that_then_makes_a_dependency():
    cands = _parse("Do ml observation after that then stick pictures for cn observation")
    assert [c.title for c in cands] == ["Do ml observation", "Stick pictures for cn observation"]
    assert cands[0].depends_on == []
    assert cands[1].depends_on == [cands[0].candidate_id]


def test_a_after_that_b_then_c_is_a_chain():
    cands = _parse("Write report after that review slides then email professor")
    assert _chain(cands) == [("Write report", []), ("Review slides", [0]), ("Email professor", [1])]


@pytest.mark.parametrize("text", [
    "Write report. Then review slides. After that email professor",
    "Write report, then review slides, and after that email professor",
    "Write report once that's done review slides following that email professor",
    "Write report and then review slides after that email professor",
])
def test_sequencing_variants(text):
    cands = _parse(text)
    assert _chain(cands) == [("Write report", []), ("Review slides", [0]), ("Email professor", [1])]


@pytest.mark.parametrize("text", [
    "Email professor after I finish the report, write report",
    "Email professor when I'm done with the report, write report",
    "Email professor once the report is done, write report",
    "After I finish the report, email professor. Write report",
])
def test_named_predecessor_links_to_the_task_it_names(text):
    cands = {c.title: c for c in _parse(text)}
    assert set(cands) == {"Email professor", "Write report"}
    assert cands["Email professor"].depends_on == [cands["Write report"].candidate_id]
    assert cands["Write report"].depends_on == []


def test_unmatched_named_predecessor_invents_nothing():
    cands = _parse("Call mom when I'm done with the nonexistent thing")
    assert len(cands) == 1 and cands[0].depends_on == []


@pytest.mark.parametrize("text,count", [
    ("gym and work", 2),
    ("After dinner read book", 1),
    ("call mom after 5pm", 1),
    ("Study DBMS, go to the gym", 2),
])
def test_text_without_sequencing_gets_no_dependencies(text, count):
    cands = _parse(text)
    assert len(cands) == count and all(not c.depends_on for c in cands)


def test_titles_do_not_keep_linker_words():
    for c in _parse("Do ml observation after that then stick pictures for cn observation"):
        assert "after that" not in c.title.lower() and " then " not in f" {c.title.lower()} "


# ── model output with no ordering keeps the order the user wrote ─────────────

def test_link_sequential_from_text_only_when_counts_match_and_nothing_linked():
    a, b, c = cand("A"), cand("B"), cand("C")
    assert link_sequential_from_text([a, b, c], [False, True, True]) is True
    assert b.depends_on == [a.candidate_id] and c.depends_on == [b.candidate_id]

    x, y = cand("X"), cand("Y")
    assert link_sequential_from_text([x, y], [False, True, True]) is False   # count mismatch: guess nothing
    assert x.depends_on == [] and y.depends_on == []

    p, q = cand("P"), cand("Q", depends_on=["keep"])
    assert link_sequential_from_text([p, q], [False, True]) is False         # the model's own ordering wins
    assert q.depends_on == ["keep"]


# ── scheduling honours the order ─────────────────────────────────────────────

def test_scheduled_a_before_b_before_c():
    cands = _schedule(_parse("Write report after that review slides then email professor"))
    a, b, c = cands
    assert a.recommended_slot_end <= b.recommended_slot_start
    assert b.recommended_slot_end <= c.recommended_slot_start


# ── route -> confirm -> DB -> replan ─────────────────────────────────────────

def _batch_item(t: dict) -> dict:
    keys = ("title", "task_type", "priority", "estimated_minutes", "deadline_at", "time_locked", "planned_date",
            "candidate_id", "depends_on", "focus_level", "deadline_kind", "priority_source", "duration_source",
            "focus_source", "preferred_start", "preferred_window_start", "preferred_window_end")
    item = {k: t.get(k) for k in keys}
    item["client_ref"] = t["candidate_id"]
    item["scheduled_start"] = t.get("recommended_slot_start") or t.get("scheduled_start")
    item["scheduled_end"] = t.get("recommended_slot_end") or t.get("scheduled_end")
    return item


@pytest.mark.asyncio
async def test_dependency_survives_preview_confirm_and_persistence(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    uid, h = make_user(prefix="seq")
    text = "Do ml observation after that then stick pictures for cn observation"
    async with client() as ac:
        r = await post_plan(ac, h, NOW, text=text)
        assert r.status_code == 200, r.text
        preview = r.json()["tasks"]
        assert [t["title"] for t in preview] == ["Do ml observation", "Stick pictures for cn observation"]
        assert preview[1]["depends_on"] == [preview[0]["candidate_id"]]
        assert preview[0]["recommended_slot_end"] <= preview[1]["recommended_slot_start"]

        body = {"tasks": [_batch_item(t) for t in preview], "plan_id": uuid.uuid4().hex,
                "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()}
        c = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body)
        assert c.status_code == 201, c.text
        created = c.json()["tasks"]

    db = SessionLocal()
    try:
        first, second = (db.get(Task, t["id"]) for t in created)
        assert second.depends_on == [first.id]                      # real task id, saved
        assert second.scheduled_start >= first.scheduled_end
        # "app restart": a fresh row -> PlanItem still carries the order, so a replan keeps it
        item = planning_service.task_row_to_plan_item(second, tz=timezone.utc)
        assert item.depends_on == (str(first.id),)
    finally:
        db.close()
