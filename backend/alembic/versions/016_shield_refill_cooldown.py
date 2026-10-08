"""Shield free-refill cooldown: flow_profiles.shield_refill_at

Revision ID: 016_shield_refill_cooldown
Revises: 015_routines
Create Date: 2026-10-08 12:00:00.000000

The account-level timestamp of the next free Shield. NULL means "no cooldown running" (balance at the maximum, or
not started yet); the Shield ledger starts the clock on the first read/debit that finds the balance below the cap.
Existing rows stay NULL, so nobody receives a surprise grant on upgrade.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "016_shield_refill_cooldown"
down_revision: Union[str, None] = "015_routines"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.add_column(sa.Column("shield_refill_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.drop_column("shield_refill_at")
