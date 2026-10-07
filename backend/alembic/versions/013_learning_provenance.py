"""Learning provenance: task_performance / readiness_observations say where each row came from

Revision ID: 013_learning_provenance
Revises: 012_ai_gateway
Create Date: 2026-10-07 00:00:00.000000

Until 2026-10-07 every task completion posted made-up ratings (focus 5, "Energized", planned minutes as actual)
and onboarding wrote a 4/4 baseline observation, so the existing rows are not real evidence. Additive: every
existing row becomes ``legacy`` (kept, never deleted, but learning ignores it as rating evidence) and the
onboarding baseline rows are marked ``onboarding``. task_performance ratings become nullable so "not rated" is
stored as NULL instead of a default 3.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "013_learning_provenance"
down_revision: Union[str, None] = "012_ai_gateway"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("task_performance") as batch:
        batch.add_column(sa.Column("provenance", sa.String(length=20), nullable=False, server_default="legacy"))
        for col in ("focus_score", "energy_score", "difficulty_score"):
            batch.alter_column(col, existing_type=sa.Integer(), nullable=True)
    with op.batch_alter_table("readiness_observations") as batch:
        batch.add_column(sa.Column("provenance", sa.String(length=20), nullable=False, server_default="legacy"))
    # the onboarding baseline had a fixed fingerprint: no task, 480 min sleep, energy 4 / focus 4, self_report
    op.execute("UPDATE readiness_observations SET provenance = 'onboarding' WHERE task_id IS NULL "
               "AND sleep_minutes = 480 AND energy_rating = 4 AND focus_rating = 4 AND source = 'self_report'")


def downgrade() -> None:
    with op.batch_alter_table("readiness_observations") as batch:
        batch.drop_column("provenance")
    op.execute("UPDATE task_performance SET focus_score = 3 WHERE focus_score IS NULL")
    op.execute("UPDATE task_performance SET energy_score = 3 WHERE energy_score IS NULL")
    op.execute("UPDATE task_performance SET difficulty_score = 3 WHERE difficulty_score IS NULL")
    with op.batch_alter_table("task_performance") as batch:
        for col in ("focus_score", "energy_score", "difficulty_score"):
            batch.alter_column(col, existing_type=sa.Integer(), nullable=False)
        batch.drop_column("provenance")
