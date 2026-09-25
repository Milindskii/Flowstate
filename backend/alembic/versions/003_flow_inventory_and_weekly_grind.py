"""Add flow inventory items and weekly grind progress tables

Revision ID: 003_flow_inventory_weekly_grind
Revises: 002_user_onboarding_completed
Create Date: 2026-09-23 22:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '003_flow_inventory_weekly_grind'
down_revision: Union[str, None] = '002_user_onboarding_completed'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_tables = inspector.get_table_names()

    # ─── 1. flow_companions ───────────────────────────────────────────────────
    if 'flow_companions' not in existing_tables:
        op.create_table(
            'flow_companions',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('species', sa.String(), nullable=False, server_default='fox'),
            sa.Column('name', sa.String(), nullable=False, server_default='Noya'),
            sa.Column('level', sa.Integer(), nullable=False, server_default='1'),
            sa.Column('stage', sa.String(), nullable=False, server_default='Baby'),
            sa.Column('companion_xp', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('xp_to_next_level', sa.Integer(), nullable=False, server_default='60'),
            sa.Column('is_evolution_ready', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
            sa.Column('cosmetic_state', sa.Text(), nullable=False, server_default='{}'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('last_progress_at', sa.DateTime(timezone=True), nullable=False),
        )

    # ─── 2. flow_profiles ─────────────────────────────────────────────────────
    if 'flow_profiles' not in existing_tables:
        op.create_table(
            'flow_profiles',
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
            sa.Column('flow_balance', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('lifetime_flow', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('current_streak', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('longest_streak', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('streak_start_date', sa.String(), nullable=True),
            sa.Column('last_qualifying_date', sa.String(), nullable=True),
            sa.Column('shield_progress_days', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('shields_available', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('shields_used_count', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('last_shield_used_date', sa.String(), nullable=True),
            sa.Column('weekly_flow_points', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('current_week_identifier', sa.String(), nullable=True),
            sa.Column('league_tier', sa.String(), nullable=False, server_default='Bronze'),
            sa.Column('is_pro', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        )

    # ─── 3. flow_focus_sessions ───────────────────────────────────────────────
    if 'flow_focus_sessions' not in existing_tables:
        op.create_table(
            'flow_focus_sessions',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('task_id', sa.String(), nullable=True, index=True),
            sa.Column('server_start_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('server_completed_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('duration_minutes', sa.Integer(), nullable=True),
            sa.Column('status', sa.String(), nullable=False, server_default='started'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        )

    # ─── 4. flow_challenges ───────────────────────────────────────────────────
    if 'flow_challenges' not in existing_tables:
        op.create_table(
            'flow_challenges',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('week_identifier', sa.String(), nullable=False, index=True),
            sa.Column('title', sa.String(), nullable=False, server_default='Complete 5 priority tasks'),
            sa.Column('target_count', sa.Integer(), nullable=False, server_default='5'),
            sa.Column('current_count', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('reward_flow', sa.Integer(), nullable=False, server_default='100'),
            sa.Column('is_completed', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('is_claimed', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('challenge_type', sa.String(), nullable=False, server_default='priority_tasks'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        )

    # ─── 5. flow_economic_events ──────────────────────────────────────────────
    if 'flow_economic_events' not in existing_tables:
        op.create_table(
            'flow_economic_events',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('idempotency_key', sa.String(), nullable=False, index=True),
            sa.Column('event_type', sa.String(), nullable=False, index=True),
            sa.Column('reference_id', sa.String(), nullable=False, index=True),
            sa.Column('flow_awarded', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('xp_awarded', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('metadata_json', sa.Text(), nullable=False, server_default='{}'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint('user_id', 'event_type', 'reference_id', name='uq_user_event_reference'),
        )

    # ─── 6. flow_daily_quests ─────────────────────────────────────────────────
    if 'flow_daily_quests' not in existing_tables:
        op.create_table(
            'flow_daily_quests',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('quest_date', sa.String(), nullable=False, index=True),
            sa.Column('quest_key', sa.String(), nullable=False),
            sa.Column('title', sa.String(), nullable=False),
            sa.Column('description', sa.String(), nullable=False, server_default=''),
            sa.Column('target_count', sa.Integer(), nullable=False, server_default='1'),
            sa.Column('current_count', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('reward_flow', sa.Integer(), nullable=False, server_default='15'),
            sa.Column('is_completed', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('is_claimed', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint('user_id', 'quest_date', 'quest_key', name='uq_user_daily_quest'),
        )

    # ─── 7. flow_achievements ─────────────────────────────────────────────────
    if 'flow_achievements' not in existing_tables:
        op.create_table(
            'flow_achievements',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('achievement_key', sa.String(), nullable=False),
            sa.Column('title', sa.String(), nullable=False),
            sa.Column('description', sa.String(), nullable=False),
            sa.Column('icon', sa.String(), nullable=False, server_default='star'),
            sa.Column('reward_flow', sa.Integer(), nullable=False, server_default='25'),
            sa.Column('is_unlocked', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('unlocked_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint('user_id', 'achievement_key', name='uq_user_achievement'),
        )

    # ─── 8. flow_inventory_items [NEW] ────────────────────────────────────────
    if 'flow_inventory_items' not in existing_tables:
        op.create_table(
            'flow_inventory_items',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('item_type', sa.String(), nullable=False),
            sa.Column('item_key', sa.String(), nullable=False),
            sa.Column('flow_spent', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('purchased_at', sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint('user_id', 'item_type', 'item_key', name='uq_user_inventory_item'),
        )

    # ─── 9. flow_weekly_progress [NEW] ────────────────────────────────────────
    if 'flow_weekly_progress' not in existing_tables:
        op.create_table(
            'flow_weekly_progress',
            sa.Column('id', sa.String(), primary_key=True),
            sa.Column('user_id', sa.String(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('week_identifier', sa.String(), nullable=False, index=True),
            sa.Column('sessions_completed', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('focus_minutes_logged', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('priority_tasks_completed', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('feedback_given', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('flow_points_earned', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('adaptive_session_target', sa.Integer(), nullable=False, server_default='3'),
            sa.Column('adaptive_minutes_target', sa.Integer(), nullable=False, server_default='60'),
            sa.Column('weekly_goal_hit', sa.Boolean(), nullable=False, server_default='0'),
            sa.Column('goal_hit_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
            sa.UniqueConstraint('user_id', 'week_identifier', name='uq_user_weekly_progress'),
        )


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_tables = inspector.get_table_names()

    for table in ['flow_weekly_progress', 'flow_inventory_items']:
        if table in existing_tables:
            op.drop_table(table)
