"""Add onboarding_completed to users

Revision ID: 002_user_onboarding_completed
Revises: 001_readiness
Create Date: 2026-09-21 22:40:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '002_user_onboarding_completed'
down_revision: Union[str, None] = '001_readiness'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'onboarding_completed' not in columns:
        op.add_column('users', sa.Column('onboarding_completed', sa.Boolean(), server_default='0', nullable=False))

def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'onboarding_completed' in columns:
        op.drop_column('users', 'onboarding_completed')
