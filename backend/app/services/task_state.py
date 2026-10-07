"""Derived task state: one pure rule shared by the Calendar day view and Today.

"Missed" is never stored. It follows from the stored slot, the clock and the sleep boundary, so reopening the
app (or a restart) recomputes it and nothing is written when a screen renders.
"""
from datetime import datetime, time, timedelta
from typing import Optional
from zoneinfo import ZoneInfo


# The two numbers below are part of the contract shared with Flutter (lib/engines/task_state.dart);
# shared/task_state_vectors.json pins both sides to them.
MISSED_GRACE_MINUTES = 0                    # a task is missed the moment its slot ends unstarted
BEDTIME_AFTER_MIDNIGHT_BELOW_HOURS = 6.0    # a bedtime earlier than 06:00 means after midnight (next calendar day)


def slot_has_ended(end: Optional[datetime], now: datetime) -> bool:
    """The one "slot ended" predicate (grace included). derive_task_state, Today's do-this-now filter and the
    Replan history all call it, so they can never disagree about the instant a task becomes missed."""
    return end is not None and now >= end + timedelta(minutes=MISSED_GRACE_MINUTES)


def task_slot_elapsed(row, now: datetime) -> bool:
    """A stored slot that ended unstarted (derived; never persisted): the missed-or-failed half of derive_task_state.
    Started (in progress), finished and cancelled tasks never count. One predicate for Replan history and Today's workload."""
    from ..models.task import TaskStatus

    if getattr(row, "is_commitment", False):
        return False
    if row.scheduled_start is None or row.status not in (TaskStatus.todo, TaskStatus.postponed):
        return False
    end = row.scheduled_end or (row.scheduled_start + timedelta(minutes=row.estimated_minutes))
    return slot_has_ended(end, now)


def day_boundary(day, tz: ZoneInfo, bedtime_hours: float) -> datetime:
    """End of the allowed recovery window for ``day``: the user's bedtime (may run past midnight)."""
    hours = float(bedtime_hours)
    if hours < BEDTIME_AFTER_MIDNIGHT_BELOW_HOURS:
        hours += 24.0
    return datetime.combine(day, time.min, tzinfo=tz) + timedelta(hours=hours)


def derive_task_state(
    *, completed: bool, cancelled: bool, active: bool,
    start: Optional[datetime], end: Optional[datetime], now: datetime, day_boundary: datetime,
    commitment: bool = False,
) -> str:
    """completed | cancelled | active | unscheduled | scheduled | missed | failed | commitment.

    commitment: a fixed block (going out), never work: it is never missed or failed, whatever the clock says.

    scheduled: not started and its slot has not ended (before, or inside, its time).
    missed:    the slot ended unstarted, still inside the recovery window: recoverable.
    failed:    the recovery window (the slot day's bedtime) is over.
    """
    if commitment:
        return "commitment"
    if completed:
        return "completed"
    if cancelled:
        return "cancelled"
    if active:
        return "active"
    if start is None or end is None:
        return "unscheduled"
    if not slot_has_ended(end, now):
        return "scheduled"
    return "missed" if now < day_boundary else "failed"
