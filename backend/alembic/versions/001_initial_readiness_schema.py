"""Initial readiness, personalization, and evaluation schema

Revision ID: 001_readiness
Revises: 
Create Date: 2026-09-21 20:50:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '001_readiness'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

def upgrade() -> None:
    # 1. Add is_admin column to users if not present
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('users')]
    if 'is_admin' not in columns:
        op.add_column('users', sa.Column('is_admin', sa.Boolean(), server_default='0', nullable=False))

    # 2. Create readiness_profiles table
    if 'readiness_profiles' not in inspector.get_table_names():
        op.create_table(
            'readiness_profiles',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True),
            sa.Column('version', sa.Integer(), default=1, nullable=False),
            sa.Column('preferred_peak_start', sa.String(), nullable=False, default='09:30'),
            sa.Column('preferred_peak_end', sa.String(), nullable=False, default='11:45'),
            sa.Column('preferred_dip_start', sa.String(), nullable=False, default='14:00'),
            sa.Column('preferred_dip_end', sa.String(), nullable=False, default='15:30'),
            sa.Column('typical_sleep_minutes', sa.Integer(), nullable=False, default=480),
            sa.Column('weekday_wake_time', sa.String(), nullable=False, default='07:00'),
            sa.Column('weekend_wake_time', sa.String(), nullable=False, default='08:30'),
            sa.Column('wake_variability', sa.Float(), nullable=False, default=1.5),
            sa.Column('sleep_inertia_minutes', sa.Integer(), nullable=False, default=30),
            sa.Column('preferred_session_minutes', sa.Integer(), nullable=False, default=45),
            sa.Column('energy_predictability', sa.String(), nullable=False, default='mostly_predictable'),
            sa.Column('optimization_goal', sa.String(), nullable=False, default='start_difficult_work'),
            sa.Column('personalization_enabled', sa.Boolean(), nullable=False, default=True),
            sa.Column('confidence_level', sa.Float(), nullable=False, default=0.20),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        )

    # 3. Create readiness_observations table
    if 'readiness_observations' not in inspector.get_table_names():
        op.create_table(
            'readiness_observations',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('task_id', sa.String(), sa.ForeignKey('tasks.id', ondelete='SET NULL'), nullable=True, index=True),
            sa.Column('observed_at', sa.DateTime(timezone=True), nullable=False, index=True),
            sa.Column('wake_time', sa.String(), nullable=True),
            sa.Column('sleep_minutes', sa.Integer(), nullable=True),
            sa.Column('sleep_quality', sa.Integer(), nullable=True),
            sa.Column('time_since_waking', sa.Integer(), nullable=True),
            sa.Column('energy_rating', sa.Integer(), nullable=True),
            sa.Column('focus_rating', sa.Integer(), nullable=True),
            sa.Column('difficulty_rating', sa.Integer(), nullable=True),
            sa.Column('distraction_rating', sa.Integer(), nullable=True),
            sa.Column('environment_type', sa.String(), nullable=True),
            sa.Column('task_type', sa.String(), nullable=True),
            sa.Column('task_difficulty', sa.String(), nullable=True),
            sa.Column('planned_minutes', sa.Integer(), nullable=True),
            sa.Column('actual_minutes', sa.Integer(), nullable=True),
            sa.Column('outcome', sa.String(), nullable=True),
            sa.Column('source', sa.String(), nullable=False, default='observed', index=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        )

    # 4. Create readiness_predictions table
    if 'readiness_predictions' not in inspector.get_table_names():
        op.create_table(
            'readiness_predictions',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('task_id', sa.String(), sa.ForeignKey('tasks.id', ondelete='SET NULL'), nullable=True, index=True),
            sa.Column('slot_start', sa.DateTime(timezone=True), nullable=True),
            sa.Column('slot_end', sa.DateTime(timezone=True), nullable=True),
            sa.Column('readiness_score', sa.Integer(), nullable=False),
            sa.Column('task_fit_score', sa.Integer(), nullable=False),
            sa.Column('confidence', sa.Float(), nullable=False),
            sa.Column('recommendation_band', sa.String(), nullable=False),
            sa.Column('model_version', sa.String(), nullable=False),
            sa.Column('top_factors', sa.String(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        )

    # 5. Create readiness_evaluations table
    if 'readiness_evaluations' not in inspector.get_table_names():
        op.create_table(
            'readiness_evaluations',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('prediction_id', sa.String(), sa.ForeignKey('readiness_predictions.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('observation_id', sa.String(), sa.ForeignKey('readiness_observations.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('predicted_band', sa.String(), nullable=False),
            sa.Column('actual_outcome', sa.String(), nullable=False),
            sa.Column('planned_minutes', sa.Integer(), nullable=False, default=45),
            sa.Column('actual_minutes', sa.Integer(), nullable=False, default=45),
            sa.Column('duration_ratio', sa.Float(), nullable=False, default=1.0),
            sa.Column('brier_score', sa.Float(), nullable=False, default=0.0),
            sa.Column('is_successful', sa.Boolean(), nullable=False, default=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        )

    # 6. Create personalization_settings table
    if 'personalization_settings' not in inspector.get_table_names():
        op.create_table(
            'personalization_settings',
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
            sa.Column('personalization_enabled', sa.Boolean(), default=True, nullable=False),
            sa.Column('context_capture_enabled', sa.Boolean(), default=True, nullable=False),
            sa.Column('use_task_history', sa.Boolean(), default=True, nullable=False),
            sa.Column('use_focus_feedback', sa.Boolean(), default=True, nullable=False),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        )

def downgrade() -> None:
    op.drop_table('personalization_settings')
    op.drop_table('readiness_evaluations')
    op.drop_table('readiness_predictions')
    op.drop_table('readiness_observations')
    op.drop_table('readiness_profiles')
    op.drop_column('users', 'is_admin')
