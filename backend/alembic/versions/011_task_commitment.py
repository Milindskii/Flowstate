"""tasks.is_commitment: a fixed block the user is away for (e.g. "Going out 6:30-8:30")

Revision ID: 011_task_commitment
Revises: 010_build_my_day_quality
Create Date: 2026-10-04 00:00:00.000000

Additive and idempotent in effect: NOT NULL with a false server default, so every existing row stays a normal
task. A commitment is always also time_locked; it blocks scheduling but is never work (no remaining minutes,
never current, never missed, not completable, untouched by Replan).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "011_task_commitment"
down_revision: Union[str, None] = "010_build_my_day_quality"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("tasks") as batch:
        batch.add_column(sa.Column("is_commitment", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade() -> None:
    with op.batch_alter_table("tasks") as batch:
        batch.drop_column("is_commitment")
