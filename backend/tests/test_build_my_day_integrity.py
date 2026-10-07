"""Build My Day integrity (M3), from a real Gemini run on messy input (2026-10-03):

* every preview candidate carries an explicit planned_date, so confirm persists the owning day;
* the client's clock (not the server's) anchors "today"/"tmrw" for extraction;
* an empty extraction or a failed schedule is an error/flag and is never charged;
* an urgent task that cannot be placed (its deadline already passed) never evicts other tasks from
  their confirmed slots ("call mom in the evening" was moved from 17:00 to 14:00 at confirm).
"""
from datetime import datetime, timedelta

import pytest

from app.engines.planner import PlanItem, plan
from app.engines.scheduling_engine import PlanningProfile
from app.services import planning_service
from tests.plan_helpers import IST, cand, client, make_user, post_plan, stub_extraction

NOW = datetime(2026, 10, 3, 22, 4, tzinfo=IST)  # Saturday 22:04


async def _free_remaining(ac, h):
    return (await ac.get("/api/v1/ai/status", headers=h)).json()["free_uses_remaining"]


@pytest.mark.asyncio
async def test_preview_candidates_carry_explicit_planned_date(monkeypatch):
    tomorrow = (NOW + timedelta(days=1)).date()
    stub_extraction(monkeypatch, [cand("Finish DBMS assignment", 120, target_date=tomorrow), cand("Read ch 4", 45)])
    _, h = make_user()
    async with client() as ac:
        body = (await post_plan(ac, h, NOW)).json()
    by = {t["title"]: t for t in body["tasks"]}
    assert by["Finish DBMS assignment"]["planned_date"] == tomorrow.isoformat()
    for t in body["tasks"]:
        assert t["planned_date"] is not None
        if t["recommended_slot_date"]:
            assert t["planned_date"] == t["recommended_slot_date"], "a slot fixes the owning day"


@pytest.mark.asyncio
async def test_extraction_uses_the_client_clock(monkeypatch):
    seen = {}
    from app.services.ai_service import AIService

    def fake(cls, raw_text, user_timezone_str="UTC", request_id=None, now_local=None):
        seen["now"] = now_local
        return ([cand("Task", 30)], [], False, None)

    monkeypatch.setattr(AIService, "extract_structured_plan_with_gemini", classmethod(fake))
    _, h = make_user()
    async with client() as ac:
        await post_plan(ac, h, NOW)
    assert seen["now"] == NOW


@pytest.mark.asyncio
async def test_empty_extraction_is_an_error_and_not_charged(monkeypatch):
    stub_extraction(monkeypatch, [])
    _, h = make_user()
    async with client() as ac:
        before = await _free_remaining(ac, h)
        r = await post_plan(ac, h, NOW)
        assert r.status_code == 422
        assert await _free_remaining(ac, h) == before


@pytest.mark.asyncio
async def test_failed_schedule_is_flagged_and_not_charged(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    monkeypatch.setattr(planning_service, "schedule_candidates", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    _, h = make_user()
    async with client() as ac:
        before = await _free_remaining(ac, h)
        body = (await post_plan(ac, h, NOW)).json()
        assert body["scheduling_error"] == "scheduling_failed"
        assert body["free_consumed"] is False and body["shield_consumed"] is False
        assert await _free_remaining(ac, h) == before


def test_unplaceable_urgent_task_does_not_evict_confirmed_slots():
    def proposed(id_, title, start, m):
        return PlanItem(id=id_, title=title, estimated_minutes=m, start=start, end=start + timedelta(minutes=m))

    call_mom = datetime(2026, 10, 4, 17, 0, tzinfo=IST)
    dbms = datetime(2026, 10, 4, 9, 30, tzinfo=IST)
    items = [
        proposed("dbms", "Finish DBMS assignment", dbms, 120),
        proposed("mom", "Call mom", call_mom, 15),
        PlanItem(id="form", title="Submit internship form", estimated_minutes=15, priority="urgent",
                 deadline_at=datetime(2026, 10, 3, 22, 0, tzinfo=IST)),  # already passed at NOW
    ]
    res = plan(items, now_local=NOW, tz=IST, profile=PlanningProfile(), mode="replan", scope_date=None, tz_name="Asia/Kolkata")
    starts = {p.item_id: p.start for p in res.placements}
    assert starts["mom"] == call_mom and starts["dbms"] == dbms
    assert {u.item_id for u in res.unscheduled} == {"form"}
