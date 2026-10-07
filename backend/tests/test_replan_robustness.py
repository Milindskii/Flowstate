"""Replan must never answer a malformed request with HTTP 500 (integrity-review defect 1).

Invalid durations, times, titles and messages produce a deterministic, user-safe 422:
    {"detail": {"code": "invalid_replan_request", "errors": [{"field", "code", "message"}]}}
User requests are never silently clamped into a different task.
"""
from datetime import datetime

import pytest

from app.schemas.task import TaskCreate
from tests.plan_helpers import IST, client, make_user

NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)
ENDPOINTS = ["/api/v1/ai/replan", "/api/v1/calendar/replan"]


async def post(ac, h, message, endpoint="/api/v1/ai/replan"):
    return await ac.post(endpoint, headers=h, json={
        "selected_date": "2026-10-05", "user_message": message,
        "current_local_time": NOW.isoformat(), "timezone": "Asia/Kolkata"})


INVALID = [
    # (message, expected error code, expected field)
    ("urgent 20 hour task", "invalid_duration", "duration"),            # probe: used to 500
    ("urgent thing needs 500 minutes", "invalid_duration", "duration"),  # probe: used to 500
    ("urgent thing needs 481 minutes", "invalid_duration", "duration"),
    ("urgent 1 minute thing", "invalid_duration", "duration"),          # probe: used to 500
    ("urgent report needs 0 minutes", "invalid_duration", "duration"),  # probe: used to 500
    ("call vendor at 25", "invalid_time", "time"),                      # probe: used to raise ValueError
    ("urgent thing at 13pm", "invalid_time", "time"),
    ("urgent thing at 6:75 pm", "invalid_time", "time"),
    ("urgent thing at 24", "invalid_time", "time"),
    ("", "empty_message", "user_message"),
    ("   \n\t ", "empty_message", "user_message"),
    ("x" * 5000, "message_too_long", "user_message"),                   # probe: used to 500
    ("urgent " + "a" * 300, "title_too_long", "title"),
    ("I'm running 5000 minutes late", "invalid_delay", "delay"),
    ("I'm running 0 minutes late", "invalid_delay", "delay"),
    # Text with no recognizable change is refused, never turned into an invented task.
    ("cancel", "unrecognized_instruction", "user_message"),
    ("move to tomorrow", "unrecognized_instruction", "user_message"),
    ("'; DROP TABLE tasks; --", "unrecognized_instruction", "user_message"),
    ("move gym to someday", "unrecognized_instruction", "user_message"),
]

VALID = [
    "urgent ☃ task needs 30 minutes",
    "urgent line one\nline two needs 20 minutes",
    "urgent thing at 12 am needs 15 minutes",
    "urgent thing at 12pm needs 5 minutes",       # lower boundary (5 min) is valid
    "urgent thing needs 8 hours",                 # upper boundary (480 min) is valid
    "urgent thing needs 480 minutes",
    "I'm running 720 minutes late",               # upper boundary of the delay range
    "cancel the thing that does not exist",
    "urgent thing at 6:59 pm needs 10 minutes",
]


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ENDPOINTS)
@pytest.mark.parametrize("message,code,field", INVALID)
async def test_invalid_replan_input_is_a_deterministic_422(message, code, field, endpoint):
    _, h = make_user()
    async with client() as ac:
        r = await post(ac, h, message, endpoint)
    assert r.status_code == 422, (message[:40], r.status_code, r.text[:200])
    detail = r.json()["detail"]
    assert detail["code"] == "invalid_replan_request"
    err = detail["errors"][0]
    assert err["code"] == code and err["field"] == field
    assert isinstance(err["message"], str) and len(err["message"]) < 300, "user-safe, bounded message"
    assert "Traceback" not in r.text and "ValidationError" not in r.text, "no internal details leak"


@pytest.mark.asyncio
@pytest.mark.parametrize("message", VALID)
async def test_valid_or_odd_replan_input_never_500s(message):
    _, h = make_user()
    async with client() as ac:
        r = await post(ac, h, message)
    assert r.status_code == 200, (message[:40], r.status_code, r.text[:200])
    assert r.json()["success"] is True


@pytest.mark.asyncio
async def test_error_responses_are_deterministic():
    _, h = make_user()
    async with client() as ac:
        a = await post(ac, h, "urgent 20 hour task")
        b = await post(ac, h, "urgent 20 hour task")
    assert a.status_code == b.status_code == 422 and a.json() == b.json()


@pytest.mark.asyncio
async def test_invalid_request_is_not_clamped_into_a_different_task():
    """A 20-hour request must be refused, not turned into an 8-hour task."""
    uid, h = make_user()
    async with client() as ac:
        r = await post(ac, h, "urgent 20 hour task")
        listing = await ac.get("/api/v1/tasks", headers=h)
    assert r.status_code == 422
    assert listing.json()["total"] == 0


@pytest.mark.asyncio
async def test_boundary_durations_are_taken_literally():
    _, h = make_user()
    async with client() as ac:
        lo = (await post(ac, h, "urgent thing at 3 pm needs 5 minutes")).json()["plan_diff"]
        hi = (await post(ac, h, "urgent thing needs 8 hours")).json()["plan_diff"]
    assert lo["newly_scheduled_tasks"][0]["duration_minutes"] == 5
    assert hi["newly_scheduled_tasks"][0]["duration_minutes"] == 480 or hi["unscheduled_tasks"][0]["duration_minutes"] == 480


@pytest.mark.asyncio
async def test_apply_with_out_of_range_new_task_is_422_not_500():
    uid, h = make_user()
    body = {"plan_id": "bad-new", "selected_date": "2026-10-05",
            "new_tasks": [{"title": "Too long", "estimated_minutes": 5000}]}
    async with client() as ac:
        r = await ac.post("/api/v1/calendar/apply-replan", headers=h, json={
            **body, "current_local_time": NOW.isoformat(), "timezone": "Asia/Kolkata"})
    assert r.status_code == 422


def test_replan_limits_match_the_task_schema():
    """The validation constants and TaskCreate's own constraints must never drift apart."""
    from app.services import calendar_service as cs

    meta = {name: f for name, f in TaskCreate.model_fields.items()}
    ge = next(m.ge for m in meta["estimated_minutes"].metadata if hasattr(m, "ge"))
    le = next(m.le for m in meta["estimated_minutes"].metadata if hasattr(m, "le"))
    mx = next(m.max_length for m in meta["title"].metadata if hasattr(m, "max_length"))
    assert (cs.MIN_TASK_MINUTES, cs.MAX_TASK_MINUTES, cs.MAX_TITLE_LENGTH) == (ge, le, mx)
