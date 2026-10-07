"""POST /ai/plan through the shared planner: contract, explicit-time handling, no silent failures."""
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task, TaskStatus
from app.services import planning_service
from tests.plan_helpers import IST, cand, client, fixed_cand, make_user, post_plan, stub_extraction


def _dt(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))


NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)


@pytest.mark.asyncio
async def test_plan_success_has_no_scheduling_error_and_slots_everywhere(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60), cand("Email", 30, task_type="admin")])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, NOW)
    body = r.json()
    assert r.status_code == 200 and body["scheduling_error"] is None
    assert all(t["recommended_slot_start"] for t in body["tasks"])
    assert all(t["time_locked"] is False for t in body["tasks"]), "scheduler recommendations are never locked"
    assert all(t["recommended_slot_date"] == "2026-10-05" or t["recommended_slot_date"] == "2026-10-06" for t in body["tasks"])


@pytest.mark.asyncio
async def test_scheduler_exception_reported_not_swallowed(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    monkeypatch.setattr(planning_service, "schedule_candidates", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, NOW)
    body = r.json()
    assert r.status_code == 200
    assert body["scheduling_error"] == "scheduling_failed"
    assert len(body["tasks"]) == 1 and body["tasks"][0]["recommended_slot_start"] is None


@pytest.mark.asyncio
async def test_explicit_time_candidate_not_displaced_by_earlier_flexible_candidate(monkeypatch):
    fixed_start = datetime(2026, 10, 5, 10, 0, tzinfo=IST)
    stub_extraction(monkeypatch, [cand("Write report", 60), fixed_cand("Call mom", fixed_start, 60)])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, NOW)
    tasks = {t["title"]: t for t in r.json()["tasks"]}
    mom, rep = tasks["Call mom"], tasks["Write report"]
    assert mom["time_locked"] is True and _dt(mom["recommended_slot_start"]) == fixed_start
    rs, re_ = _dt(rep["recommended_slot_start"]), _dt(rep["recommended_slot_end"])
    assert not (rs < fixed_start + timedelta(hours=1) and re_ > fixed_start)


@pytest.mark.asyncio
async def test_past_explicit_time_flagged_not_moved(monkeypatch):
    past = datetime(2026, 10, 5, 7, 0, tzinfo=IST)
    stub_extraction(monkeypatch, [fixed_cand("Call mom", past, 30)])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, NOW)
    t = r.json()["tasks"][0]
    assert t["recommended_slot_start"] is None
    assert t["unscheduled_reason"] == "explicit_time_in_past"
    issue = t["validation_issues"][0]
    assert issue["code"] == "explicit_time_in_past" and "already passed" in issue["message"] and "7:00 AM" in issue["message"]


@pytest.mark.asyncio
async def test_explicit_candidate_conflicting_with_own_task_reports_conflict_but_not_other_users_tasks(monkeypatch):
    stub_extraction(monkeypatch, [fixed_cand("Standup", datetime(2026, 10, 5, 10, 0, tzinfo=IST), 60)])
    uid_a, ha = make_user(prefix="own")
    uid_c, hc = make_user(prefix="clean")
    db = SessionLocal()
    s = datetime(2026, 10, 5, 10, 0, tzinfo=IST).astimezone(timezone.utc)
    db.add(Task(user_id=uid_a, title="Existing", estimated_minutes=60, scheduled_start=s, scheduled_end=s + timedelta(hours=1)))
    db.commit()
    db.close()
    async with client() as ac:
        ra = await post_plan(ac, ha, NOW)
        rc = await post_plan(ac, hc, NOW)
    ca = ra.json()["conflicts"]
    assert any(c["code"] == "locked_overlap" for c in ca), ca       # A: overlaps A's own task
    assert rc.json()["conflicts"] == []                              # C: A's task is invisible to C
    # the user's explicit time is kept in both cases (never moved)
    for r in (ra, rc):
        assert _dt(r.json()["tasks"][0]["recommended_slot_start"]) == datetime(2026, 10, 5, 10, 0, tzinfo=IST)


@pytest.mark.asyncio
async def test_flexible_candidate_avoids_own_existing_task_only(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    uid_a, ha = make_user(prefix="busyA")
    uid_b, hb = make_user(prefix="freeB")
    db = SessionLocal()
    # A is busy 09:15-23:00 today (everything); B has nothing
    s = datetime(2026, 10, 5, 9, 15, tzinfo=IST).astimezone(timezone.utc)
    db.add(Task(user_id=uid_a, title="Wall", estimated_minutes=13 * 60 + 45, scheduled_start=s,
                scheduled_end=s + timedelta(minutes=13 * 60 + 45), time_locked=True))
    db.commit()
    db.close()
    async with client() as ac:
        ra = await post_plan(ac, ha, NOW)
        rb = await post_plan(ac, hb, NOW)
    a_start = _dt(ra.json()["tasks"][0]["recommended_slot_start"])
    b_start = _dt(rb.json()["tasks"][0]["recommended_slot_start"])
    assert a_start.astimezone(IST).date() == datetime(2026, 10, 6).date(), "A's day is full; B's busy time must not matter to A"
    assert b_start.astimezone(IST).date() == NOW.date(), "B must not be blocked by A's task"


@pytest.mark.asyncio
async def test_target_date_tomorrow_keeps_tomorrow_in_preview(monkeypatch):
    from app.schemas.task import TemporalConstraints

    c = cand("Study DSA", 60, temporal=TemporalConstraints(target_date=datetime(2026, 10, 6).date()))
    stub_extraction(monkeypatch, [c])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, NOW)
    t = r.json()["tasks"][0]
    assert t["recommended_slot_date"] == "2026-10-06" and t["recommended_slot_display"].startswith("Tomorrow")
    assert _dt(t["recommended_slot_start"]).astimezone(IST).date() == datetime(2026, 10, 6).date()
