"""Routine templates + routine occurrence columns on tasks

Revision ID: 015_routines
Revises: 014_shield_economy
Create Date: 2026-10-08 00:00:00.000000

A routine is a recurrence TEMPLATE; its occurrences are ordinary task rows generated inside a bounded horizon.
tasks.routine_id/routine_date identify an occurrence (unique per routine per day).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "015_routines"
down_revision: Union[str, None] = "014_shield_economy"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "routines",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("task_type", sa.String(32), nullable=False, server_default="personal"),
        sa.Column("category", sa.String(50), nullable=False, server_default="General"),
        sa.Column("estimated_minutes", sa.Integer(), nullable=False, server_default="45"),
        sa.Column("kind", sa.String(16), nullable=False, server_default="fixed"),
        sa.Column("recurrence", sa.String(16), nullable=False, server_default="daily"),
        sa.Column("weekdays", sa.JSON(), nullable=True),
        sa.Column("start_hhmm", sa.String(5), nullable=True),
        sa.Column("end_hhmm", sa.String(5), nullable=True),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("materialized_through", sa.Date(), nullable=True),
        sa.Column("skipped_dates", sa.JSON(), nullable=True),
        sa.Column("idempotency_key", sa.String(100), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_routines_user_id", "routines", ["user_id"])
    with op.batch_alter_table("tasks") as batch:
        batch.add_column(sa.Column("routine_id", sa.String(), nullable=True))
        batch.add_column(sa.Column("routine_date", sa.Date(), nullable=True))
        batch.create_foreign_key("fk_tasks_routine_id", "routines", ["routine_id"], ["id"], ondelete="SET NULL")
    op.create_index("uq_tasks_routine_occurrence", "tasks", ["routine_id", "routine_date"], unique=True)


def downgrade() -> None:
    op.drop_index("uq_tasks_routine_occurrence", table_name="tasks")
    with op.batch_alter_table("tasks") as batch:
        batch.drop_constraint("fk_tasks_routine_id", type_="foreignkey")
        batch.drop_column("routine_date")
        batch.drop_column("routine_id")
    op.drop_index("ix_routines_user_id", table_name="routines")
    op.drop_table("routines")
