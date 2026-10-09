"""Shields earned outside the free refill: rewarded-ad sessions, paid packs, ad progress

Revision ID: 019_shield_rewards
Revises: 018_shields_pay_for_ai
Create Date: 2026-10-09 11:00:00.000000

* shield_ad_sessions: one row per rewarded ad the app is about to show; AdMob's signed server-side verification names
  it (custom_data) and its transaction_id is unique, so a replayed callback pays nothing.
* shield_purchases: one row per Google Play purchase token (unique), written only after the server verified it.
* flow_profiles.ad_reward_progress: verified ads not yet turned into a Shield. Existing rows start at 0.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "019_shield_rewards"
down_revision: Union[str, None] = "018_shields_pay_for_ai"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("flow_profiles") as batch:
        batch.add_column(sa.Column("ad_reward_progress", sa.Integer(), server_default="0", nullable=False))

    op.create_table(
        "shield_ad_sessions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("transaction_id", sa.String(), nullable=True),
        sa.Column("shields_granted", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("transaction_id", name="uq_shield_ad_sessions_transaction"),
    )
    op.create_index("ix_shield_ad_sessions_user_id", "shield_ad_sessions", ["user_id"])

    op.create_table(
        "shield_purchases",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("user_id", sa.String(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("store", sa.String(), nullable=False),
        sa.Column("product_id", sa.String(), nullable=False),
        sa.Column("purchase_token", sa.String(), nullable=False),
        sa.Column("order_id", sa.String(), nullable=True),
        sa.Column("units", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("purchase_token", name="uq_shield_purchases_token"),
    )
    op.create_index("ix_shield_purchases_user_id", "shield_purchases", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_shield_purchases_user_id", table_name="shield_purchases")
    op.drop_table("shield_purchases")
    op.drop_index("ix_shield_ad_sessions_user_id", table_name="shield_ad_sessions")
    op.drop_table("shield_ad_sessions")
    with op.batch_alter_table("flow_profiles") as batch:
        batch.drop_column("ad_reward_progress")
