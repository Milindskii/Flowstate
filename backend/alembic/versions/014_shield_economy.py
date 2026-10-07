"""Shield economy: ai_requests.charge_units (exact refunds) and a non-negative Shield balance

Revision ID: 014_shield_economy
Revises: 013_learning_provenance
Create Date: 2026-10-07 00:00:00.000000

A Build My Day plan now costs more than one Shield, so a reservation records how many units it took and a refund
returns exactly that many. Every existing row cost one unit (the default). The CHECK keeps the Shield balance from
ever going negative whatever code touches it; any pre-existing negative balance is clamped to 0 first.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "014_shield_economy"
down_revision: Union[str, None] = "013_learning_provenance"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("UPDATE flow_profiles SET shields_available = 0 WHERE shields_available < 0")
    with op.batch_alter_table("ai_requests") as batch:
        batch.add_column(sa.Column("charge_units", sa.Integer(), nullable=False, server_default="1"))
    with op.batch_alter_table("flow_profiles") as batch:
        batch.create_check_constraint("ck_flow_profiles_shields_nonneg", "shields_available >= 0")


def downgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.drop_constraint("ck_flow_profiles_shields_nonneg", type_="check")
    with op.batch_alter_table("ai_requests") as batch:
        batch.drop_column("charge_units")
