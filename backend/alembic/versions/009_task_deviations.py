"""task_deviations: per-day skip/defer history (Replan My Day)

Revision ID: 009_task_deviations
Revises: 008_backfill_planned_date
Create Date: 2026-10-03 00:00:00.000000

A skipped/deferred task's planned_date moves forward; this table keeps what happened on the
original day so that day's path can still show it. RLS on, no policies (007 convention).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "009_task_deviations"
down_revision: Union[str, None] = "008_backfill_planned_date"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "task_deviations",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("task_id", sa.String(), sa.ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True),
        sa.Column("deviation_date", sa.Date(), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("original_start", sa.DateTime(timezone=True), nullable=True),
        sa.Column("original_end", sa.DateTime(timezone=True), nullable=True),
        sa.Column("moved_to_date", sa.Date(), nullable=True),
        sa.Column("plan_id", sa.String(100), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_task_deviations_user_date", "task_deviations", ["user_id", "deviation_date"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute(sa.text('ALTER TABLE "task_deviations" ENABLE ROW LEVEL SECURITY'))


def downgrade() -> None:
    op.drop_index("ix_task_deviations_user_date", table_name="task_deviations")
    op.drop_table("task_deviations")
