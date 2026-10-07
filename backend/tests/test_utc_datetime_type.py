"""Finding 14: SQLite drops tzinfo without converting; every reader must see the same instant."""
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from app.db.session import SessionLocal
from app.models.task import Task
from app.models.user import User

IST = ZoneInfo("Asia/Kolkata")


@pytest.fixture
def db_user():
    db = SessionLocal()
    uid = f"utc-{uuid.uuid4().hex[:8]}"
    db.add(User(id=uid, email=f"{uid}@flowstate.local"))
    db.commit()
    yield db, uid
    db.close()


def _roundtrip(db, uid, **fields):
    t = Task(user_id=uid, title="rt", **fields)
    db.add(t)
    db.commit()
    db.expire_all()
    return db.query(Task).filter(Task.id == t.id).one()


def test_aware_ist_roundtrips_to_same_instant(db_user):
    db, uid = db_user
    start = datetime(2026, 10, 3, 15, 0, tzinfo=IST)
    row = _roundtrip(db, uid, scheduled_start=start)
    assert row.scheduled_start.tzinfo is not None
    assert row.scheduled_start == start
    assert row.scheduled_start.utcoffset() == timedelta(0)


def test_naive_treated_as_utc(db_user):
    db, uid = db_user
    row = _roundtrip(db, uid, scheduled_start=datetime(2026, 10, 3, 9, 30))
    assert row.scheduled_start == datetime(2026, 10, 3, 9, 30, tzinfo=timezone.utc)


def test_all_datetime_columns_return_aware_utc(db_user):
    db, uid = db_user
    stamp = datetime(2026, 10, 3, 10, 0, tzinfo=IST)
    row = _roundtrip(
        db, uid,
        scheduled_start=stamp, scheduled_end=stamp + timedelta(hours=1),
        deadline_at=stamp + timedelta(hours=5), started_at=stamp, completed_at=stamp + timedelta(minutes=50),
    )
    for col in ("scheduled_start", "scheduled_end", "deadline_at", "started_at", "completed_at"):
        v = getattr(row, col)
        assert v.tzinfo is not None and v.utcoffset() == timedelta(0), col


def test_between_day_bounds_after_roundtrip(db_user):
    db, uid = db_user
    # 00:30 IST on Oct 3 == 19:00 UTC on Oct 2: belongs to the IST day Oct 3, not the UTC day Oct 3.
    early = datetime(2026, 10, 3, 0, 30, tzinfo=IST)
    _roundtrip(db, uid, scheduled_start=early)
    lo = datetime(2026, 10, 3, 0, 0, tzinfo=IST).astimezone(timezone.utc)
    hi = datetime(2026, 10, 3, 23, 59, 59, tzinfo=IST).astimezone(timezone.utc)
    assert db.query(Task).filter(Task.user_id == uid, Task.scheduled_start.between(lo, hi)).count() == 1
    lo2 = datetime(2026, 10, 2, 0, 0, tzinfo=IST).astimezone(timezone.utc)
    hi2 = datetime(2026, 10, 2, 23, 59, 59, tzinfo=IST).astimezone(timezone.utc)
    assert db.query(Task).filter(Task.user_id == uid, Task.scheduled_start.between(lo2, hi2)).count() == 0


def test_none_stays_none(db_user):
    db, uid = db_user
    row = _roundtrip(db, uid)
    assert row.scheduled_start is None and row.deadline_at is None
