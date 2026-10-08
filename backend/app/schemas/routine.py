from datetime import date, datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

RoutineKind = Literal["fixed", "preferred", "earliest", "avoid"]
Recurrence = Literal["daily", "weekly"]

_HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"


class RoutineBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    task_type: str = Field(default="personal", max_length=32)
    category: str = Field(default="General", max_length=50)
    estimated_minutes: int = Field(default=45, ge=5, le=480)
    kind: RoutineKind = "fixed"
    recurrence: Recurrence = "daily"
    weekdays: Optional[List[int]] = None            # Monday=0 .. Sunday=6; required for weekly
    start_hhmm: Optional[str] = Field(default=None, pattern=_HHMM)
    end_hhmm: Optional[str] = Field(default=None, pattern=_HHMM)


class RoutineProposal(RoutineBase):
    """A routine detected in a Build My Day dump. Nothing is saved until the user confirms it."""
    proposal_id: str
    candidate_id: Optional[str] = None               # the dump task it came from (removed from the one-time list)
    summary: str                                     # "Every day · 4:00 PM"
    plan_dates: List[date] = Field(default_factory=list)   # the dates a confirm would plan (bounded horizon)
    horizon_days: int = 7


class RoutineCreate(RoutineBase):
    idempotency_key: Optional[str] = Field(default=None, max_length=100)
    timezone: Optional[str] = Field(default=None, max_length=64)
    current_local_time: Optional[datetime] = None


class RoutineUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=1, max_length=255)
    estimated_minutes: Optional[int] = Field(default=None, ge=5, le=480)
    recurrence: Optional[Recurrence] = None
    weekdays: Optional[List[int]] = None
    start_hhmm: Optional[str] = Field(default=None, pattern=_HHMM)
    end_hhmm: Optional[str] = Field(default=None, pattern=_HHMM)
    timezone: Optional[str] = Field(default=None, max_length=64)
    current_local_time: Optional[datetime] = None


class RoutineResponse(RoutineBase):
    id: str
    summary: str
    effective_from: date
    materialized_through: Optional[date] = None
    skipped_dates: List[str] = Field(default_factory=list)
    # Weekly cycle: planned through this date; `continuation_due` asks "Continue your routine next week?" once.
    confirmed_through: Optional[date] = None
    continuation_due: bool = False
    paused: bool = False   # the user said "Not now" and the confirmed cycle is over: defined, nothing planned


class RoutineApplyResult(BaseModel):
    routine: RoutineResponse
    planned_dates: List[date] = Field(default_factory=list)
    created_count: int = 0
    replayed: bool = False


class RoutineContinuation(BaseModel):
    decision: Literal["continue", "not_now"]
    cycle_end: date                                  # the cycle end the app showed (replay protection)
    timezone: Optional[str] = Field(default=None, max_length=64)
    current_local_time: Optional[datetime] = None
