"""One timezone rule for every path (integrity-review defect 2).

RULE (documented in app/core/timezone.py, enforced here):
    zone = valid IANA `timezone` supplied with the request (body field or query param)
         else the user's stored preference (if valid)
         else UTC (logged)
Abbreviations such as "IST" are ignored (never an excuse to fall back to UTC when a preference exists).
Only app/core/timezone.py may construct a ZoneInfo from a user-supplied or stored name.
"""
import os
import re
import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task import Task
from app.services.ai_service import AIService
from tests.plan_helpers import IST, LA, client, make_user

# 2026-10-06 00:30 IST == 2026-10-05 19:00 UTC == 2026-10-05 12:00 LA  -> the local DATE differs
INSTANT = datetime(2026, 10, 5, 19, 0, tzinfo=timezone.utc)


@pytest.fixture
def frozen(monkeypatch):
    import app.api.routes.today as today_mod
    import app.services.task_service as task_service_mod

    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return INSTANT if tz is None else INSTANT.astimezone(tz)

    monkeypatch.setattr(today_mod, "datetime", Frozen)
    monkeypatch.setattr(task_service_mod, "datetime", Frozen)


@pytest.mark.asyncio
async def test_today_uses_request_zone_then_preference(frozen):
    _, h = make_user(tz="Asia/Kolkata")
    async with client() as ac:
        default = (await ac.get("/api/v1/today", headers=h)).json()
        la = (await ac.get("/api/v1/today", headers=h, params={"timezone": "America/Los_Angeles"})).json()
        abbrev = (await ac.get("/api/v1/today", headers=h, params={"timezone": "IST"})).json()
    assert default["date"] == "2026-10-06" and default["user"]["timezone"] == "Asia/Kolkata"
    assert la["date"] == "2026-10-05" and la["user"]["timezone"] == "America/Los_Angeles"
    assert abbrev["date"] == "2026-10-06" and abbrev["user"]["timezone"] == "Asia/Kolkata", "abbreviation falls back to the preference"


@pytest.mark.asyncio
async def test_today_and_calendar_agree_when_the_device_zone_differs_from_the_preference(frozen):
    """Both receive the same device zone from Flutter, so both must describe the same local day."""
    _, h = make_user(tz="Asia/Kolkata")
    async with client() as ac:
        today = (await ac.get("/api/v1/today", headers=h, params={"timezone": "America/Los_Angeles"})).json()
        day = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": today["date"], "timezone": "America/Los_Angeles", "current_local_time": INSTANT.astimezone(LA).isoformat()})).json()
    assert day["date"] == today["date"] == "2026-10-05" and day["timezone_used"] == today["user"]["timezone"]


@pytest.mark.asyncio
async def test_tasks_today_uses_the_same_rule(frozen):
    uid, h = make_user(tz="Asia/Kolkata")
    start = datetime(2026, 10, 5, 10, 0, tzinfo=timezone.utc)  # Oct 5 in LA, Oct 5 15:30 in IST (IST "today" is Oct 6)
    db = SessionLocal()
    db.add(Task(user_id=uid, title="LA-day task", estimated_minutes=30, scheduled_start=start, scheduled_end=start + timedelta(minutes=30)))
    db.commit()
    db.close()
    async with client() as ac:
        ist = (await ac.get("/api/v1/tasks/today", headers=h)).json()
        la = (await ac.get("/api/v1/tasks/today", headers=h, params={"timezone": "America/Los_Angeles"})).json()
    assert [t["title"] for t in ist] == []
    assert [t["title"] for t in la] == ["LA-day task"]


@pytest.mark.asyncio
@pytest.mark.parametrize("prefs,body_tz,expected", [
    ("Asia/Kolkata", None, "Asia/Kolkata"),
    ("Asia/Kolkata", "IST", "Asia/Kolkata"),
    ("Asia/Kolkata", "America/Los_Angeles", "America/Los_Angeles"),
    (None, None, "UTC"),
])
async def test_tasks_parse_resolves_zone_with_the_shared_rule(monkeypatch, prefs, body_tz, expected):
    seen = {}

    def spy(cls, raw_text, user_timezone_str="UTC", force_ai=False, ai_gate=None):
        seen["tz"] = user_timezone_str
        return []

    monkeypatch.setattr(AIService, "parse_task_dump", classmethod(spy))
    _, h = make_user(tz=prefs)
    body = {"text": "write the report"}
    if body_tz:
        body["timezone"] = body_tz
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/parse", headers=h, json=body)
    assert r.status_code == 200, r.text
    assert seen["tz"] == expected


def test_flow_service_uses_the_shared_rule():
    from app.services.flow_service import FlowService

    uid_la, _ = make_user(tz="America/Los_Angeles")
    uid_none, _ = make_user(tz=None)
    db = SessionLocal()
    try:
        assert FlowService()._get_user_timezone(db, uid_la).key == "America/Los_Angeles"
        assert FlowService()._get_user_timezone(db, uid_none).key == "UTC", "no preference => UTC, same as every other path"
    finally:
        db.close()


def test_parse_task_dump_tolerates_an_abbreviation_without_crashing():
    assert isinstance(AIService.parse_task_dump("write the report", "IST"), list)


def test_only_core_timezone_constructs_zoneinfo_from_names():
    """Guard: a second, divergent zone-resolution path must not creep back in."""
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
    offenders = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x != "__pycache__"]
        for f in files:
            if not f.endswith(".py"):
                continue
            path = os.path.join(d, f)
            rel = os.path.relpath(path, root).replace("\\", "/")
            if rel == "core/timezone.py":
                continue
            for n, line in enumerate(open(path, encoding="utf-8-sig").read().splitlines(), 1):
                if re.search(r"\bZoneInfo\(", line) and not line.strip().startswith("#"):
                    offenders.append(f"{rel}:{n}: {line.strip()}")
    assert offenders == [], "build zones with core.timezone.resolve_timezone only:\n" + "\n".join(offenders)
