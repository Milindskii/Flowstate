"""Add privacy_grievances table for verifiable privacy requests

Revision ID: 005_privacy_grievances
Revises: 004_compliance_and_consent
Create Date: 2026-09-24 22:40:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '005_privacy_grievances'
down_revision: Union[str, None] = '004_compliance_and_consent'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'privacy_grievances' not in tables:
        op.create_table(
            'privacy_grievances',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
            sa.Column('email', sa.String(), nullable=False),
            sa.Column('request_type', sa.String(), nullable=False, server_default='general_grievance'),
            sa.Column('message', sa.Text(), nullable=False),
            sa.Column('status', sa.String(), nullable=False, server_default='received'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        )
        op.create_index('ix_privacy_grievances_email', 'privacy_grievances', ['email'])
        op.create_index('ix_privacy_grievances_user_id', 'privacy_grievances', ['user_id'])


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = inspector.get_table_names()

    if 'privacy_grievances' in tables:
        op.drop_table('privacy_grievances')
