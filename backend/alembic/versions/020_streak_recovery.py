"""Streak recovery 7-hour window deadline and ad progress

Revision ID: 020_streak_recovery
Revises: 019_shield_rewards
Create Date: 2026-10-09 14:00:00.000000

* flow_profiles.streak_recovery_deadline_at: server instant the persistent 7-hour recovery window expires.
* flow_profiles.streak_recovery_ad_progress: verified ads watched toward restoring the broken streak.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "020_streak_recovery"
down_revision: Union[str, None] = "019_shield_rewards"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.add_column(sa.Column("streak_recovery_deadline_at", sa.DateTime(timezone=True), nullable=True))
        batch.add_column(sa.Column("streak_recovery_ad_progress", sa.Integer(), server_default="0", nullable=False))


def downgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.drop_column("streak_recovery_ad_progress")
        batch.drop_column("streak_recovery_deadline_at")
