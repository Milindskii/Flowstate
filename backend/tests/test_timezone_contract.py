"""Finding 1: one IANA timezone, resolved in one place, reported back (spec section 5)."""
import uuid
from datetime import datetime, timedelta

import pytest

from tests.plan_helpers import IST, LA, cand, client, make_user, post_plan, stub_extraction


@pytest.mark.asyncio
async def test_plan_uses_request_iana_tz(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    _, h = make_user(tz="Asia/Kolkata")
    now = datetime(2026, 10, 5, 9, 0, tzinfo=LA)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz="America/Los_Angeles")
    body = r.json()
    assert r.status_code == 200, r.text
    assert body["timezone_used"] == "America/Los_Angeles" and body["scheduling_error"] is None
    start = datetime.fromisoformat(body["tasks"][0]["recommended_slot_start"].replace("Z", "+00:00"))
    local = start.astimezone(LA)
    assert local.date() == now.date() and 9 <= local.hour < 23 and start >= now


@pytest.mark.asyncio
async def test_plan_user_timezone_alias(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    _, h = make_user(tz="Asia/Kolkata")
    now = datetime(2026, 10, 5, 9, 0, tzinfo=LA)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz=None, user_timezone="America/Los_Angeles")
    assert r.json()["timezone_used"] == "America/Los_Angeles"


@pytest.mark.asyncio
async def test_plan_invalid_abbrev_falls_back_to_preference_not_utc(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    _, h = make_user(tz="Asia/Kolkata")
    now = datetime(2026, 10, 5, 9, 0, tzinfo=IST)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz="IST")
    assert r.json()["timezone_used"] == "Asia/Kolkata"


@pytest.mark.asyncio
async def test_plan_without_any_zone_is_utc_and_says_so(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    _, h = make_user(tz=None)
    now = datetime(2026, 10, 5, 9, 0, tzinfo=IST)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz=None)
    assert r.json()["timezone_used"] == "UTC"


@pytest.mark.asyncio
async def test_plan_response_reports_timezone_used_matches_slot_offset(monkeypatch):
    stub_extraction(monkeypatch, [cand("Write report", 60)])
    _, h = make_user(tz="Asia/Kolkata")
    now = datetime(2026, 10, 5, 9, 0, tzinfo=IST)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz=None)  # falls to stored preference
    body = r.json()
    assert body["timezone_used"] == "Asia/Kolkata"
    start = datetime.fromisoformat(body["tasks"][0]["recommended_slot_start"].replace("Z", "+00:00"))
    assert start.astimezone(IST).date() == now.date()


@pytest.mark.asyncio
async def test_slot_hours_are_in_user_wake_bedtime_window_in_local_time(monkeypatch):
    """The original defect: an IST user got UTC wall-clock hours (e.g. 09:30Z = 15:00 IST)."""
    stub_extraction(monkeypatch, [cand(f"Task {i}", 45) for i in range(4)])
    _, h = make_user(tz="Asia/Kolkata")
    now = datetime(2026, 10, 5, 7, 30, tzinfo=IST)
    async with client() as ac:
        r = await post_plan(ac, h, now, tz="Asia/Kolkata")
    for t in r.json()["tasks"]:
        s = datetime.fromisoformat(t["recommended_slot_start"].replace("Z", "+00:00")).astimezone(IST)
        assert s >= now and (s.hour + s.minute / 60) < 23.0 and s.hour >= 7, t["recommended_slot_display"]
