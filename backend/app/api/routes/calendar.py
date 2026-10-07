from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ...db.session import get_db
from ...core.security import get_current_user
from ...models.user import User
from ...schemas.calendar import (
    DayScheduleResponse,
    ReplanRequest,
    ReplanResponse,
    ApplyReplanRequest,
    ApplyReplanResponse,
)
from ...services.calendar_service import CalendarService

router = APIRouter(prefix="/calendar", tags=["Calendar & Replan"])
calendar_service = CalendarService()

@router.get("/day", response_model=DayScheduleResponse)
def get_day_schedule(
    date: str = Query(..., description="Target date in YYYY-MM-DD format"),
    timezone: Optional[str] = Query(None, description="IANA timezone e.g. 'Asia/Kolkata' (abbreviations fall back to the stored preference)"),
    current_local_time: Optional[datetime] = Query(None, description="Aware client clock; makes the response deterministic"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns the authoritative execution schedule for a specific date:
    - Fixed commitments (Dentist, appointments, meetings)
    - Scheduled Flowstate tasks
    - Completed tasks
    - Remaining tasks
    - Remaining capacity and focus window
    """
    return calendar_service.get_day_schedule(
        db=db,
        user=current_user,
        target_date_str=date,
        timezone_str=timezone,
        now_local=current_local_time,
    )

@router.post("/replan", response_model=ReplanResponse)
def generate_replan_calendar_alias(
    request: ReplanRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Dry-run Replan endpoint. Generates a PlanDiff comparing Before vs After.
    Does NOT mutate the database.
    """
    return calendar_service.generate_replan(
        db=db,
        user=current_user,
        request=request,
    )

@router.post("/apply-replan", response_model=ApplyReplanResponse)
def apply_replan(
    request: ApplyReplanRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Atomically applies a confirmed PlanDiff in a single database transaction.

    Idempotent per `plan_id`; the server re-validates every change (no past starts, no overlaps,
    deadlines) and never touches completed, in-progress or time-locked tasks.
    409 `stale_plan` => a task changed since the dry run; 422 `invariant_violation` => the proposed
    result breaks the scheduling contract. In both cases nothing is persisted.
    """
    from ...services.ai_economy_service import AIEconomyService

    with AIEconomyService.get_user_request_lock(current_user.id):
        return calendar_service.apply_replan(
            db=db,
            user=current_user,
            request=request,
        )
