"""Task planning columns: time_locked, planned_date, plan_applications

Revision ID: 006_task_planning_columns
Revises: 005_privacy_grievances
Create Date: 2026-10-02 00:00:00.000000

ALTER-only. Requires an existing ``tasks`` table and fails loudly without one
(see docs/superpowers/specs/build-my-day-replan.md section 11).

Options:
  alembic -x skip_lock_backfill=1 upgrade head   # add columns, skip the backfill entirely
  alembic upgrade head --sql                     # offline: print statements, touch nothing
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import context, op

from app.db.backfill import (
    LOCK_BACKFILL_UPDATE_SQL,
    apply_lock_backfill,
    upgrade_planning_columns,
)

revision: str = "006_task_planning_columns"
down_revision: Union[str, None] = "005_privacy_grievances"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _skip_backfill() -> bool:
    return str(context.get_x_argument(as_dictionary=True).get("skip_lock_backfill", "")).lower() in ("1", "true", "yes")


def upgrade() -> None:
    if context.is_offline_mode():
        op.execute("ALTER TABLE tasks ADD COLUMN time_locked BOOLEAN NOT NULL DEFAULT FALSE")
        op.execute("ALTER TABLE tasks ADD COLUMN planned_date DATE")
        op.execute("CREATE INDEX ix_tasks_user_scheduled_start ON tasks (user_id, scheduled_start)")
        op.create_table(
            "plan_applications",
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
            sa.Column("plan_id", sa.String(100), primary_key=True),
            sa.Column("kind", sa.String(20), nullable=False),
            sa.Column("response_json", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )
        if not _skip_backfill():
            op.execute(LOCK_BACKFILL_UPDATE_SQL)
        return

    conn = op.get_bind()
    added = upgrade_planning_columns(conn)  # raises if 'tasks' is missing

    if "plan_applications" not in sa.inspect(conn).get_table_names():
        op.create_table(
            "plan_applications",
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
            sa.Column("plan_id", sa.String(100), primary_key=True),
            sa.Column("kind", sa.String(20), nullable=False),
            sa.Column("response_json", sa.Text(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        )

    # Backfill only when the column was just created (so reruns never re-lock rows
    # the user later unlocked) and only if not explicitly skipped.
    if "time_locked" in added and not _skip_backfill():
        apply_lock_backfill(conn)


def downgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)
    if "plan_applications" in insp.get_table_names():
        op.drop_table("plan_applications")
    if "tasks" in insp.get_table_names():
        if "ix_tasks_user_scheduled_start" in {i["name"] for i in insp.get_indexes("tasks")}:
            op.drop_index("ix_tasks_user_scheduled_start", table_name="tasks")
        cols = {c["name"] for c in insp.get_columns("tasks")}
        with op.batch_alter_table("tasks") as batch:
            if "time_locked" in cols:
                batch.drop_column("time_locked")
            if "planned_date" in cols:
                batch.drop_column("planned_date")
