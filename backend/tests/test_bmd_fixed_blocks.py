"""Build My Day: a stated "I'm out 6:30 to 8:30" is persisted as a commitment, so every later plan (Replan, Today,
Calendar) sees it. Real-world input of 2026-10-04 with the recorded Gemini shape (fixtures/gemini_bmd/real_world_outing.json).
"""
import json
import uuid
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from app.services import ai_service as ais
from tests.plan_helpers import IST, client, make_user, post_plan
from tests.test_apply_replan_semantics import replan
from tests.test_build_my_day_quality import _gemini_returns

NOW = datetime(2026, 10, 4, 13, 12, tzinfo=IST)
OUT_S, OUT_E = datetime(2026, 10, 4, 18, 30, tzinfo=IST), datetime(2026, 10, 4, 20, 30, tzinfo=IST)
FIX = Path(__file__).parent / "fixtures" / "gemini_bmd" / "real_world_outing.json"
REAL_TEXT = (
    "I woke up kinda confused about what to do today. I have two college things that need doing. First I have to "
    "write two observations, probably takes 2 to 2.5 hours. Then I have a project for Tuesday. I also really want "
    "to finish the remaining Flowstate work. I'm going out from 6:30 to 8:30 so don't schedule anything then. "
    "I usually sleep around 11. I don't want everything packed minute by minute with no breaks.")


def payload():
    return json.loads(FIX.read_text())


def dt(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))


def overlaps(a, b, c, d):
    return a < d and c < b


async def plan_preview(ac, h, text=REAL_TEXT):
    r = await post_plan(ac, h, NOW, text=text)
    assert r.status_code == 200, r.text
    return r.json()["tasks"]


def batch_item(t):
    """What Flutter's confirm sends for one preview candidate (now including is_commitment)."""
    keys = ("title", "task_type", "priority", "estimated_minutes", "deadline_at", "time_locked", "is_commitment",
            "planned_date", "candidate_id", "depends_on", "focus_level", "deadline_kind", "priority_source",
            "duration_source", "focus_source")
    item = {k: t.get(k) for k in keys}
    item["client_ref"] = t["candidate_id"]
    item["scheduled_start"] = t.get("recommended_slot_start") or t.get("scheduled_start")
    item["scheduled_end"] = t.get("recommended_slot_end") or t.get("scheduled_end")
    return item


@pytest.mark.asyncio
async def test_stated_outing_becomes_a_locked_commitment_candidate(monkeypatch):
    _gemini_returns(monkeypatch, payload())
    _, h = make_user(prefix="bmdfix")
    async with client() as ac:
        tasks = await plan_preview(ac, h)
    out = [t for t in tasks if t["title"] == "Going out"]
    assert len(out) == 1, [t["title"] for t in tasks]
    o = out[0]
    assert o["is_commitment"] is True and o["time_locked"] is True
    assert dt(o["recommended_slot_start"] or o["scheduled_start"]) == OUT_S
    assert dt(o["recommended_slot_end"] or o["scheduled_end"]) == OUT_E
    for t in tasks:
        if t is o or not t.get("recommended_slot_start"):
            continue
        assert not overlaps(dt(t["recommended_slot_start"]), dt(t["recommended_slot_end"]), OUT_S, OUT_E), t["title"]


@pytest.mark.asyncio
async def test_confirm_persists_the_commitment_and_replan_cannot_touch_it(monkeypatch):
    _gemini_returns(monkeypatch, payload())
    _, h = make_user(prefix="bmdfix")
    async with client() as ac:
        tasks = await plan_preview(ac, h)
        c = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json={
            "tasks": [batch_item(t) for t in tasks], "plan_id": uuid.uuid4().hex, "timezone": "Asia/Kolkata",
            "current_local_time": NOW.isoformat()})
        assert c.status_code == 201, c.text
        saved = {t["title"]: t for t in c.json()["tasks"]}
        listed = {t["title"]: t for t in (await ac.get("/api/v1/tasks?limit=100", headers=h)).json()["items"]}
        diff = await replan(ac, h, "skip gym session and leave the 6:30 to 8:30 outing untouched", now=NOW, day="2026-10-04")
    assert saved["Going out"]["is_commitment"] is True and listed["Going out"]["is_commitment"] is True
    assert listed["Going out"]["time_locked"] is True
    assert not any(listed[n]["is_commitment"] for n in listed if n != "Going out")
    assert all(u["task_id"] != listed["Going out"]["id"] for u in diff["apply_request"]["task_updates"])
    for it in diff["after_schedule"]:
        if it["title"] != "Going out":
            assert not overlaps(dt(it["start_time"]), dt(it["end_time"]), OUT_S, OUT_E), it["title"]


@pytest.mark.asyncio
async def test_event_whose_time_the_user_never_wrote_is_not_converted(monkeypatch):
    _gemini_returns(monkeypatch, payload())
    _, h = make_user(prefix="bmdfix")
    async with client() as ac:
        tasks = await plan_preview(ac, h, text="plan my day: observations, project, flowstate, gym")
    assert "Going out" not in [t["title"] for t in tasks]
    for t in tasks:  # still honoured as busy time for this plan
        if t.get("recommended_slot_start"):
            assert not overlaps(dt(t["recommended_slot_start"]), dt(t["recommended_slot_end"]), OUT_S, OUT_E), t["title"]


@pytest.mark.asyncio
async def test_event_already_listed_as_a_meeting_task_is_not_duplicated(monkeypatch):
    p = payload()
    p["tasks"].append({"ref": "t5", "title": "Going out", "type": "meeting", "category": "Personal", "estimated_minutes": 120,
                       "duration_source": "explicit", "priority": "medium", "priority_source": "inferred", "depends_on": [],
                       "target_date": "2026-10-04", "fixed_start": "18:30", "confidence": 0.9})
    _gemini_returns(monkeypatch, p)
    _, h = make_user(prefix="bmdfix")
    async with client() as ac:
        tasks = await plan_preview(ac, h)
    assert [t["title"] for t in tasks].count("Going out") == 1


def test_prompt_forbids_invented_tasks_and_rates_stated_goals_high():
    prompt = ais._build_initial_gemini_prompt("x", "2026-10-04", "Asia/Kolkata")
    assert "NEVER INVENT TASKS" in prompt
    assert "STATED GOALS" in prompt and "really want" in prompt
    assert "UNAVAILABLE BLOCKS" in prompt and "fixed_events" in prompt


@pytest.mark.asyncio
async def test_spacious_day_leaves_a_break_after_each_long_focus_block(monkeypatch):
    _gemini_returns(monkeypatch, payload())
    _, h = make_user(prefix="bmdfix")
    async with client() as ac:
        tasks = await plan_preview(ac, h)
    slots = sorted(
        ((dt(t["recommended_slot_start"]), dt(t["recommended_slot_end"]), t) for t in tasks if t.get("recommended_slot_start")),
        key=lambda x: x[0])
    assert slots, "nothing was scheduled"
    for (s1, e1, t1), (s2, e2, t2) in zip(slots, slots[1:]):
        if t1["focus_level"] == "high" and t1["estimated_minutes"] >= 90 and not t2["time_locked"]:
            assert s2 - e1 >= timedelta(minutes=15), (t1["title"], t2["title"], s2 - e1)
        assert e2 <= datetime(2026, 10, 4, 23, 0, tzinfo=IST)
