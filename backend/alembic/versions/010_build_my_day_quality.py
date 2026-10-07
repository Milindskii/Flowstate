"""Build My Day quality contract: focus/deadline kind/provenance/dependencies/preferred windows + AI attempts

Revision ID: 010_build_my_day_quality
Revises: 009_task_deviations
Create Date: 2026-10-03 00:00:00.000000

All new task columns are nullable (legacy rows keep NULL = unknown). Preferred-window columns are only
written for user-stated windows. ai_planning_attempts records one row per real Gemini call or
client-reported failure; RLS is enabled on PostgreSQL like every other public table (007).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.db.types import UTCDateTime

revision: str = "010_build_my_day_quality"
down_revision: Union[str, None] = "009_task_deviations"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_STR_COLS = ("focus_level", "deadline_kind", "priority_source", "duration_source", "focus_source")
_TS_COLS = ("preferred_start", "preferred_window_start", "preferred_window_end")


def upgrade() -> None:
    with op.batch_alter_table("tasks") as batch:
        for name in _STR_COLS:
            batch.add_column(sa.Column(name, sa.String(16), nullable=True))
        batch.add_column(sa.Column("depends_on", sa.JSON(), nullable=True))
        for name in _TS_COLS:
            batch.add_column(sa.Column(name, UTCDateTime(), nullable=True))

    op.create_table(
        "ai_planning_attempts",
        sa.Column("attempt_id", sa.String(), primary_key=True),
        sa.Column("request_id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("failure_code", sa.String(), nullable=True),
        sa.Column("failure_reason", sa.Text(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_ai_planning_attempts_request_id", "ai_planning_attempts", ["request_id"])
    op.create_index("ix_ai_planning_attempts_user_id", "ai_planning_attempts", ["user_id"])
    if op.get_bind().dialect.name == "postgresql":
        op.execute(sa.text('ALTER TABLE "ai_planning_attempts" ENABLE ROW LEVEL SECURITY'))


def downgrade() -> None:
    op.drop_index("ix_ai_planning_attempts_user_id", table_name="ai_planning_attempts")
    op.drop_index("ix_ai_planning_attempts_request_id", table_name="ai_planning_attempts")
    op.drop_table("ai_planning_attempts")
    with op.batch_alter_table("tasks") as batch:
        for name in _TS_COLS + ("depends_on",) + _STR_COLS:
            batch.drop_column(name)
