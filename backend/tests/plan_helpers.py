"""Shared helpers for Build My Day / Replan API tests (deterministic: no Gemini, explicit client clock)."""
import uuid
from datetime import datetime, timedelta
from typing import List, Optional
from zoneinfo import ZoneInfo

from httpx import ASGITransport, AsyncClient

from app.core.security import create_access_token
from app.db.session import SessionLocal
from app.main import app
from app.models.user import User
from app.models.user_preferences import UserPreferences
from app.schemas.task import FieldProvenance, TaskCandidateResponse, TemporalConstraints
from app.services.ai_service import AIService

IST = ZoneInfo("Asia/Kolkata")
LA = ZoneInfo("America/Los_Angeles")


def make_user(tz: Optional[str] = "Asia/Kolkata", prefix: str = "plan"):
    """Create a DB user (+ optional preference row) and return (user_id, headers)."""
    uid = f"{prefix}-{uuid.uuid4().hex[:10]}"
    db = SessionLocal()
    try:
        db.add(User(id=uid, email=f"{uid}@flowstate.local", name=prefix))
        if tz:
            db.add(UserPreferences(user_id=uid, timezone=tz))
        db.commit()
    finally:
        db.close()
    token = create_access_token({"sub": uid, "email": f"{uid}@flowstate.local"})
    return uid, {"Authorization": f"Bearer {token}"}


def client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


def stub_extraction(monkeypatch, candidates: List[TaskCandidateResponse], planning_context=None):
    """Replace Gemini extraction with fixed candidates."""
    def fake(cls, raw_text, user_timezone_str="UTC", request_id=None, now_local=None):
        return ([c.model_copy(deep=True) for c in candidates], [], False, planning_context)

    monkeypatch.setattr(AIService, "extract_structured_plan_with_gemini", classmethod(fake))


def stub_deterministic_extraction(monkeypatch):
    """Use the real deterministic parser as the 'extractor' (no network)."""
    def fake(cls, raw_text, user_timezone_str="UTC", request_id=None, now_local=None):
        return (AIService.parse_task_dump(raw_text, user_timezone_str), [], False, None)

    monkeypatch.setattr(AIService, "extract_structured_plan_with_gemini", classmethod(fake))


def cand(title: str, minutes: int = 45, **kw) -> TaskCandidateResponse:
    return TaskCandidateResponse(title=title, estimated_minutes=minutes, **kw)


def fixed_cand(title: str, start: datetime, minutes: int = 60) -> TaskCandidateResponse:
    """A candidate carrying an explicit user-stated clock time (lock source L1)."""
    return TaskCandidateResponse(
        title=title,
        estimated_minutes=minutes,
        scheduled_start=start,
        scheduled_end=start + timedelta(minutes=minutes),
        temporal=TemporalConstraints(
            fixed_start=start,
            flexibility="fixed",
            provenance={"fixed_start": FieldProvenance(source="explicit", confidence=1.0)},
        ),
        field_provenance={"scheduled_time": FieldProvenance(source="explicit", confidence=1.0)},
    )


def iso(dt: datetime) -> str:
    return dt.isoformat()


async def post_plan(ac, headers, now_local: datetime, tz: Optional[str] = "Asia/Kolkata", text: str = "plan my day", **extra):
    # The app always sends consume_shield=True now (the Shield price is shown before Build My Day is pressed).
    body = {"raw_text": text, "idempotency_key": uuid.uuid4().hex, "current_local_time": iso(now_local),
            "consume_shield": True, **extra}
    if tz is not None:
        body["timezone"] = tz
    return await ac.post("/api/v1/ai/plan", headers=headers, json=body)
