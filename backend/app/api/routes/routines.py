from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ...core.security import get_current_user
from ...core.timezone import resolve_user_timezone
from ...db.session import get_db
from ...models.routine import Routine
from ...models.user import User
from ...schemas.routine import RoutineApplyResult, RoutineCreate, RoutineResponse, RoutineUpdate
from ...services import routine_service as svc

router = APIRouter(prefix="/routines", tags=["Routines"])


def _now(user: User, tz_name: Optional[str], client_now: Optional[datetime]):
    tz, name = resolve_user_timezone(user, tz_name)
    if client_now is not None:
        now = client_now.replace(tzinfo=tz) if client_now.tzinfo is None else client_now.astimezone(tz)
    else:
        now = datetime.now(tz)
    return tz, now


def _out(r: Routine) -> RoutineResponse:
    return RoutineResponse(
        id=r.id, title=r.title, task_type=r.task_type, category=r.category, estimated_minutes=r.estimated_minutes,
        kind=r.kind, recurrence=r.recurrence, weekdays=r.weekdays, start_hhmm=r.start_hhmm, end_hhmm=r.end_hhmm,
        summary=svc.summarize(r.kind, r.recurrence, r.weekdays, r.start_hhmm, r.end_hhmm),
        effective_from=r.effective_from, materialized_through=r.materialized_through,
        skipped_dates=list(r.skipped_dates or []),
    )


def _get(db: Session, user: User, routine_id: str) -> Routine:
    r = db.query(Routine).filter(Routine.id == routine_id, Routine.user_id == user.id,
                                 Routine.deleted_at.is_(None)).first()
    if r is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Routine not found")
    return r


@router.get("", response_model=List[RoutineResponse])
def list_routines(timezone: Optional[str] = None, current_local_time: Optional[datetime] = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Active routines. Also tops the rolling horizon up so the next 7 days stay planned after an app restart."""
    tz, now = _now(user, timezone, current_local_time)
    svc.ensure_horizon(db, user.id, tz, now)
    db.commit()
    return [_out(r) for r in svc.active_routines(db, user.id)]


@router.post("", response_model=RoutineApplyResult, status_code=status.HTTP_201_CREATED)
def create_routine(body: RoutineCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Confirm a routine: save the template and plan the next 7 days. Safe to repeat with the same idempotency_key."""
    tz, now = _now(user, body.timezone, body.current_local_time)
    try:
        r, dates, replayed = svc.create_routine(db, user.id, body, tz, now)
        db.commit()
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(e))
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "That routine was already added.")
    return RoutineApplyResult(routine=_out(r), planned_dates=dates, created_count=len(dates), replayed=replayed)


@router.patch("/{routine_id}", response_model=RoutineApplyResult)
def update_routine(routine_id: str, body: RoutineUpdate, user: User = Depends(get_current_user),
                   db: Session = Depends(get_db)):
    """Change the template. Only future occurrences change; completed, missed and past tasks are never rewritten."""
    r = _get(db, user, routine_id)
    tz, now = _now(user, body.timezone, body.current_local_time)
    try:
        dates = svc.update_routine(db, r, body, tz, now)
        db.commit()
    except ValueError as e:
        db.rollback()
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(e))
    return RoutineApplyResult(routine=_out(r), planned_dates=dates, created_count=len(dates))


@router.delete("/{routine_id}", status_code=status.HTTP_200_OK)
def delete_routine(routine_id: str, timezone: Optional[str] = None, current_local_time: Optional[datetime] = None, user: User = Depends(get_current_user),
                   db: Session = Depends(get_db)):
    """Stop future occurrences. History stays."""
    r = _get(db, user, routine_id)
    tz, now = _now(user, timezone, current_local_time)
    removed = svc.delete_routine(db, r, tz, now)
    db.commit()
    return {"deleted": True, "future_occurrences_removed": removed}
