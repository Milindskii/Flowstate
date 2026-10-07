"""GET /insights/summary carries real history: learned weekly routines from completed tasks, honest "learning"
states for a new user, and legacy rows (made-up completion scores) never count as focus evidence."""
from datetime import datetime, time, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task, TaskStatus
from app.models.task_performance import TaskPerformance
from tests.plan_helpers import IST, client, make_user


def _seed_completed(uid, title, local_start, minutes=60, category="Exercise"):
    db = SessionLocal()
    try:
        s = local_start.astimezone(timezone.utc)
        t = Task(user_id=uid, title=title, category=category, estimated_minutes=minutes,
                 scheduled_start=s, scheduled_end=s + timedelta(minutes=minutes), planned_date=local_start.date(),
                 status=TaskStatus.completed, started_at=s, completed_at=s + timedelta(minutes=minutes + 15))
        db.add(t)
        db.commit()
        return str(t.id)
    finally:
        db.close()


async def _summary(h):
    async with client() as ac:
        r = await ac.get("/api/v1/insights/summary", headers=h)
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.asyncio
async def test_new_user_sees_still_learning_everywhere():
    _, h = make_user()
    body = await _summary(h)
    assert body["has_sufficient_history"] is False
    assert body["history"] and all(s["status"] == "learning" for s in body["history"].values())
    assert body["timezone_used"] == "Asia/Kolkata"


@pytest.mark.asyncio
async def test_weekly_gym_routine_and_planned_vs_actual_from_real_history():
    uid, h = make_user()
    today = datetime.now(IST).date()
    for weeks_ago in range(1, 5):
        d = today - timedelta(weeks=weeks_ago)
        _seed_completed(uid, "Gym", datetime.combine(d, time(19, 0), tzinfo=IST))
    body = await _summary(h)
    routines = body["history"]["routines"]
    assert routines["status"] == "ready"
    gym = routines["items"][0]
    assert gym["title"] == "Gym" and gym["start_label"] == "7:00 PM" and gym["weeks_seen"] == 4
    assert gym["weekday_index"] == today.weekday()
    dur = body["history"]["durations"]
    assert dur["status"] == "ready" and dur["categories"][0]["ratio"] == 1.25  # 75 real minutes for 60 planned


@pytest.mark.asyncio
async def test_legacy_made_up_scores_are_not_focus_evidence():
    uid, h = make_user()
    today = datetime.now(IST).date()
    db = SessionLocal()
    try:
        for i in range(8):
            tid = _seed_completed(uid, f"Task {i}", datetime.combine(today - timedelta(days=i + 1), time(10, 0), tzinfo=IST))
            db.add(TaskPerformance(task_id=tid, user_id=uid, estimated_minutes=60, actual_minutes=60, focus_score=5,
                                   energy_score=5, difficulty_score=3, provenance="legacy",
                                   completed_at=datetime.now(timezone.utc) - timedelta(days=i + 1)))
        db.commit()
    finally:
        db.close()
    body = await _summary(h)
    assert body["history"]["focus"]["status"] == "learning"
    assert body["history"]["focus"]["sample_size"] == 0


@pytest.mark.asyncio
async def test_feedback_without_ratings_is_timestamps_not_reflection():
    uid, h = make_user()
    tid = _seed_completed(uid, "Read", datetime.now(IST) - timedelta(hours=3), category="Study")
    async with client() as ac:
        r1 = await ac.post(f"/api/v1/tasks/{tid}/feedback", headers=h, json={"actual_minutes": 50})
        r2 = await ac.post(f"/api/v1/tasks/{tid}/feedback", headers=h,
                           json={"actual_minutes": 50, "focus_score": 4, "energy_score": 3})
    assert r1.status_code == 201 and r1.json()["provenance"] == "timestamps"
    assert r1.json()["focus_score"] is None  # never a made-up default
    assert r2.status_code == 201 and r2.json()["provenance"] == "reflection"
