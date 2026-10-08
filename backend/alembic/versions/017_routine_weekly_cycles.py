"""Weekly routine cycles: routines.confirmed_through, routines.continuation_declined_for

Revision ID: 017_routine_weekly_cycles
Revises: 016_shield_refill_cooldown
Create Date: 2026-10-08 15:00:00.000000

A routine plans its occurrences one weekly cycle at a time and never extends itself silently: `confirmed_through` is
the last local date the user agreed to plan; at the end of the cycle the app asks "Continue your routine next week?".
`continuation_declined_for` remembers a "Not now" for one cycle (the question is asked once per cycle).
Existing routines are treated as confirmed through what they already planned.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "017_routine_weekly_cycles"
down_revision: Union[str, None] = "016_shield_refill_cooldown"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("routines") as batch:
        batch.add_column(sa.Column("confirmed_through", sa.Date(), nullable=True))
        batch.add_column(sa.Column("continuation_declined_for", sa.Date(), nullable=True))
    op.execute("UPDATE routines SET confirmed_through = materialized_through WHERE confirmed_through IS NULL")


def downgrade() -> None:
    with op.batch_alter_table("routines") as batch:
        batch.drop_column("continuation_declined_for")
        batch.drop_column("confirmed_through")
