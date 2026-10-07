"""Backfill tasks.planned_date so every existing task has an explicit owning day

Revision ID: 008_backfill_planned_date
Revises: 007_schema_reconciliation
Create Date: 2026-10-03 00:00:00.000000

Rows written before the date invariant can have planned_date NULL. Same order as new writes
(TaskService.create_task), in the user's stored timezone:
  1. the local date of scheduled_start (a stored slot fixes the day)
  2. the local date of deadline_at ("due Friday" belongs to Friday)
  3. the local date of created_at: the day the task was added. This is a one-time, fixed
     assignment for legacy rows; it is stored and never re-derived. completed_at is never used.

Data-only and idempotent (touches planned_date IS NULL rows only). Downgrade is a no-op: the
values are indistinguishable from user-set ones.
"""
from datetime import datetime, timezone
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.core.timezone import local_date, resolve_timezone

revision: str = "008_backfill_planned_date"
down_revision: Union[str, None] = "007_schema_reconciliation"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _instant(value):
    if value is None or isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value))  # SQLite returns text


def upgrade() -> None:
    bind = op.get_bind()
    rows = bind.execute(sa.text(
        "SELECT t.id, t.scheduled_start, t.deadline_at, t.created_at, p.timezone "
        "FROM tasks t LEFT JOIN user_preferences p ON p.user_id = t.user_id "
        "WHERE t.planned_date IS NULL"
    )).all()
    update = sa.text("UPDATE tasks SET planned_date = :d WHERE id = :id AND planned_date IS NULL")
    for task_id, start, deadline, created, tz_name in rows:
        tz, _ = resolve_timezone(None, tz_name)
        anchor = _instant(start) or _instant(deadline) or _instant(created) or datetime.now(timezone.utc)
        bind.execute(update, {"d": local_date(anchor, tz), "id": task_id})


def downgrade() -> None:
    pass
