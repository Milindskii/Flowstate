"""Shields pay for AI planning: retire the separate free-plan trial

Revision ID: 018_shields_pay_for_ai
Revises: 017_routine_weekly_cycles
Create Date: 2026-10-09 01:00:00.000000

One mental model: a Build My Day plan costs Shields, and nothing else. An account's unused free trial plan is
retired (free_uses_total is lowered to what was already consumed, so history is kept and the allowance left is 0).
The Shield balance is untouched.
"""
from typing import Sequence, Union

from alembic import op

revision: str = "018_shields_pay_for_ai"
down_revision: Union[str, None] = "017_routine_weekly_cycles"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("UPDATE ai_usage_records SET free_uses_total = free_uses_consumed WHERE free_uses_total > free_uses_consumed")


def downgrade() -> None:
    # the retired trial plan is not restored: a downgrade must not hand out free plans
    pass
