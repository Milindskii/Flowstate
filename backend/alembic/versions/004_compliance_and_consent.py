"""Add legal compliance, consent, and email preference columns to users table

Revision ID: 004_compliance_and_consent
Revises: 003_flow_inventory_weekly_grind
Create Date: 2026-09-23 22:30:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '004_compliance_and_consent'
down_revision: Union[str, None] = '003_flow_inventory_weekly_grind'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_cols = [c['name'] for c in inspector.get_columns('users')]

    if 'terms_accepted' not in existing_cols:
        op.add_column('users', sa.Column('terms_accepted', sa.Boolean(), server_default='0', nullable=False))
    if 'privacy_accepted' not in existing_cols:
        op.add_column('users', sa.Column('privacy_accepted', sa.Boolean(), server_default='0', nullable=False))
    if 'age_confirmed' not in existing_cols:
        op.add_column('users', sa.Column('age_confirmed', sa.Boolean(), server_default='0', nullable=False))
    if 'marketing_emails_enabled' not in existing_cols:
        op.add_column('users', sa.Column('marketing_emails_enabled', sa.Boolean(), server_default='0', nullable=False))
    if 'consent_at' not in existing_cols:
        op.add_column('users', sa.Column('consent_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_cols = [c['name'] for c in inspector.get_columns('users')]

    if 'consent_at' in existing_cols:
        op.drop_column('users', 'consent_at')
    if 'marketing_emails_enabled' in existing_cols:
        op.drop_column('users', 'marketing_emails_enabled')
    if 'age_confirmed' in existing_cols:
        op.drop_column('users', 'age_confirmed')
    if 'privacy_accepted' in existing_cols:
        op.drop_column('users', 'privacy_accepted')
    if 'terms_accepted' in existing_cols:
        op.drop_column('users', 'terms_accepted')
