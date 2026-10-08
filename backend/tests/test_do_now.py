""""Do this now" (POST /today/do-now/{id}): a real, deterministic move to the current minute, from anywhere.

Before this endpoint the Calendar's "Do this now" only recorded an override against Today's recommendation: with no
decision, or for a missed task, nothing moved and the tap looked dead.
"""
from datetime import datetime, timedelta, timezone

import pytest

from app.api.routes import today as today_routes
from app.db.session import SessionLocal
from app.models.flow_progression import FlowProfile
from app.models.task_deviation import TaskDeviation
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import get, seed

NOW = datetime(2026, 10, 8, 10, 0, tzinfo=IST)


class _FixedDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return NOW.astimezone(tz) if tz else NOW.replace(tzinfo=None)


@pytest.fixture(autouse=True)
def _frozen(monkeypatch):
    monkeypatch.setattr(today_routes, "datetime", _FixedDatetime)


def _aware(dt):
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


async def _do_now(ac, h, task_id):
    return await ac.post(f"/api/v1/today/do-now/{task_id}", headers=h, json={"timezone": "Asia/Kolkata"})


@pytest.mark.asyncio
async def test_missed_task_moves_to_now_and_keeps_its_miss_on_record():
    uid, h = make_user()
    b = seed(uid, "Bravo", NOW - timedelta(hours=2), 45)
    async with client() as ac:
        res = await _do_now(ac, h, b)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["moved"] is True
    start = _aware(get(b).scheduled_start)
    assert abs((start - NOW).total_seconds()) <= 5 * 60
    db = SessionLocal()
    try:
        kinds = [d.kind for d in db.query(TaskDeviation).filter(TaskDeviation.task_id == b).all()]
    finally:
        db.close()
    assert kinds == ["missed"]


@pytest.mark.asyncio
async def test_works_without_any_today_recommendation_and_is_idempotent():
    uid, h = make_user()
    c = seed(uid, "Charlie", NOW + timedelta(hours=4), 30)
    async with client() as ac:
        first = await _do_now(ac, h, c)
        start1 = _aware(get(c).scheduled_start)
        second = await _do_now(ac, h, c)
        start2 = _aware(get(c).scheduled_start)
    assert first.json()["moved"] is True and second.json()["moved"] is True
    assert start1 == start2
    assert abs((start1 - NOW).total_seconds()) <= 5 * 60


@pytest.mark.asyncio
async def test_never_moves_another_users_task_or_a_commitment():
    uid, h = make_user()
    other_uid, _ = make_user()
    foreign = seed(other_uid, "Theirs", NOW + timedelta(hours=1), 30)
    fixed = seed(uid, "Dinner out", NOW + timedelta(hours=3), 60, is_commitment=True)
    async with client() as ac:
        assert (await _do_now(ac, h, foreign)).status_code == 404
        assert (await _do_now(ac, h, fixed)).status_code == 409


@pytest.mark.asyncio
async def test_do_now_never_touches_shields():
    uid, h = make_user()
    t = seed(uid, "Delta", NOW + timedelta(hours=2), 30)
    async with client() as ac:
        await ac.get("/api/v1/flow/overview", headers=h)
        db = SessionLocal()
        try:
            before = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available
        finally:
            db.close()
        assert (await _do_now(ac, h, t)).status_code == 200
    db = SessionLocal()
    try:
        assert db.query(FlowProfile).filter(FlowProfile.user_id == uid).one().shields_available == before
    finally:
        db.close()
