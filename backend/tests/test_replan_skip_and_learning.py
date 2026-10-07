"""Replan My Day (M4): "skip" is a real, persisted reschedule, and applying a replan records a learning signal.

The learning signal reuses the recommendation audit tables: one RecommendationDecision per applied
replan (engine_version="replan_v1") and one RecommendationOutcome per affected task.
"""
from datetime import date

import pytest

from app.db.session import SessionLocal
from app.models.recommendation import RecommendationDecision, RecommendationOutcome
from app.models.task import TaskStatus
from tests.plan_helpers import client, make_user
from tests.test_apply_replan_semantics import NOW, apply, at, get, replan, seed

TOMORROW = date(2026, 10, 6)


def outcomes(uid):
    db = SessionLocal()
    try:
        return {(o.task_id, o.user_action) for o in db.query(RecommendationOutcome).filter(RecommendationOutcome.user_id == uid)}
    finally:
        db.close()


def replan_decisions(uid):
    db = SessionLocal()
    try:
        return db.query(RecommendationDecision).filter(
            RecommendationDecision.user_id == uid, RecommendationDecision.engine_version == "replan_v1").count()
    finally:
        db.close()


@pytest.mark.asyncio
async def test_skip_moves_the_task_to_the_next_day_and_persists():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(18), 60, planned_date=date(2026, 10, 5))
    async with client() as ac:
        diff = await replan(ac, h, "skip gym today")
        assert not diff["conflicts"], diff["conflicts"]
        r = await apply(ac, h, diff["apply_request"])
    assert r.status_code == 200, r.text
    row = get(gym)
    assert row.planned_date == TOMORROW
    assert row.status == TaskStatus.todo


@pytest.mark.asyncio
async def test_applied_replan_records_one_learning_signal_per_affected_task():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(18), 60, planned_date=date(2026, 10, 5))
    essay = seed(uid, "Essay", at(11), 60, planned_date=date(2026, 10, 5))
    async with client() as ac:
        moved = await apply(ac, h, (await replan(ac, h, "move gym to tomorrow"))["apply_request"])
        cancelled = await apply(ac, h, (await replan(ac, h, "cancel essay"))["apply_request"])
    assert moved.status_code == 200 and cancelled.status_code == 200
    assert (gym, "replan_rescheduled") in outcomes(uid)
    assert (essay, "replan_cancelled") in outcomes(uid)
    assert replan_decisions(uid) == 2


@pytest.mark.asyncio
async def test_replayed_apply_does_not_record_the_signal_twice():
    uid, h = make_user()
    seed(uid, "Gym", at(18), 60, planned_date=date(2026, 10, 5))
    async with client() as ac:
        req = (await replan(ac, h, "move gym to tomorrow"))["apply_request"]
        await apply(ac, h, req)
        await apply(ac, h, req)
    assert replan_decisions(uid) == 1
