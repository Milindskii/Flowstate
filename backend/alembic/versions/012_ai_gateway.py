"""AI gateway: ai_requests (reservation + idempotency), ai_usage_periods (Pro caps), rate_limit_windows

Revision ID: 012_ai_gateway
Revises: 011_task_commitment
Create Date: 2026-10-04 00:00:00.000000

Purely additive: three new tables, no change to existing data. RLS is enabled on PostgreSQL like every other
public table (007), so the Supabase anon/authenticated roles can read nothing; the backend connects as the table
owner. ``ai_planning_requests`` (the old global-key idempotency cache) is left in place, unused.

Optional pg_cron housekeeping (run in the Supabase SQL editor once, not part of this migration):
  -- refund stuck reservations is done by the API itself; these only trim data
  select cron.schedule('flowstate-ai-requests-purge', '17 3 * * *', $$
    update ai_requests set response_json = null where created_at < now() - interval '24 hours' and response_json is not null;
    delete from ai_requests where created_at < now() - interval '90 days';
    delete from rate_limit_windows where window_start < extract(epoch from now() - interval '2 days');
    delete from ai_usage_periods where period_start < (current_date - interval '400 days') $$);
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

from app.db.types import UTCDateTime

revision: str = "012_ai_gateway"
down_revision: Union[str, None] = "011_task_commitment"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_TABLES = ("ai_requests", "ai_usage_periods", "rate_limit_windows")


def upgrade() -> None:
    op.create_table(
        "ai_requests",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("idempotency_key", sa.String(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False, server_default="plan"),
        sa.Column("status", sa.String(), nullable=False, server_default="reserved"),
        sa.Column("charge_source", sa.String(), nullable=False, server_default="none"),
        sa.Column("request_sha256", sa.String(64), nullable=False),
        sa.Column("deadline_at", UTCDateTime(), nullable=False),
        sa.Column("finished_at", UTCDateTime(), nullable=True),
        sa.Column("error_code", sa.String(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("response_json", sa.Text(), nullable=True),
        sa.Column("created_at", UTCDateTime(), nullable=False),
        sa.UniqueConstraint("user_id", "idempotency_key", name="uq_ai_requests_user_key"),
    )
    op.create_index("ix_ai_requests_user_id", "ai_requests", ["user_id"])
    # At most one in-flight AI request per user, across every API instance.
    op.create_index(
        "uq_ai_requests_one_inflight", "ai_requests", ["user_id"], unique=True,
        postgresql_where=sa.text("status = 'reserved'"), sqlite_where=sa.text("status = 'reserved'"),
    )

    op.create_table(
        "ai_usage_periods",
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("period_kind", sa.String(), primary_key=True),
        sa.Column("period_start", sa.Date(), primary_key=True),
        sa.Column("used", sa.Integer(), nullable=False, server_default="0"),
    )

    op.create_table(
        "rate_limit_windows",
        sa.Column("bucket_key", sa.String(), primary_key=True),
        sa.Column("window_start", sa.Integer(), primary_key=True),
        sa.Column("count", sa.Integer(), nullable=False, server_default="0"),
    )

    if op.get_bind().dialect.name == "postgresql":
        for table in _TABLES:
            op.execute(sa.text(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY'))


def downgrade() -> None:
    op.drop_table("rate_limit_windows")
    op.drop_table("ai_usage_periods")
    op.drop_index("uq_ai_requests_one_inflight", table_name="ai_requests")
    op.drop_index("ix_ai_requests_user_id", table_name="ai_requests")
    op.drop_table("ai_requests")
