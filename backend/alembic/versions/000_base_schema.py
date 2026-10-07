"""Base schema: the core tables every later revision assumes already exist

Revision ID: 000_base_schema
Revises:
Create Date: 2026-10-03 00:00:00.000000

Before this revision the chain started at 001, which ALTERs ``users`` and FKs to
``tasks`` without ever creating them; those tables only came from the dev-SQLite
``create_all`` in app/main.py, so ``alembic upgrade head`` failed on an empty
database (spec build-my-day-replan.md section 11.1, "D4").

Shapes mirror the models *minus* the columns later revisions add:
  users: is_admin (001), onboarding_completed (002), consent columns (004)
  tasks: time_locked, planned_date, ix_tasks_user_scheduled_start (006)

Every create is guarded, so existing databases (already at 006) are unaffected.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "000_base_schema"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Same labels and type names SQLAlchemy derives from the model enums (app/models/task.py).
TASK_TYPE = sa.Enum("deep_work", "shallow_work", "study", "creative", "admin", "physical", "meeting", "personal", name="tasktype")
TASK_DIFFICULTY = sa.Enum("high", "medium", "light", "physical", name="taskdifficulty")
TASK_PRIORITY = sa.Enum("low", "medium", "high", "urgent", name="taskpriority")
TASK_STATUS = sa.Enum("todo", "in_progress", "completed", "cancelled", "postponed", "archived", name="taskstatus")
TASK_SOURCE = sa.Enum("manual", "ai_parsed", "calendar", "imported", name="tasksource")
TASK_ENUMS = (TASK_TYPE, TASK_DIFFICULTY, TASK_PRIORITY, TASK_STATUS, TASK_SOURCE)

TZ = sa.DateTime(timezone=True)


def _user_fk(ondelete: str = "CASCADE"):
    return sa.ForeignKey("users.id", ondelete=ondelete)


def upgrade() -> None:
    tables = set(sa.inspect(op.get_bind()).get_table_names())

    if "users" not in tables:
        op.create_table(
            "users",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("email", sa.String(), nullable=False),
            sa.Column("name", sa.String(), nullable=False),
            sa.Column("avatar_url", sa.String(), nullable=True),
            sa.Column("is_active", sa.Boolean(), nullable=False),
            sa.Column("created_at", TZ, nullable=False),
            sa.Column("updated_at", TZ, nullable=False),
        )
        op.create_index("ix_users_email", "users", ["email"], unique=True)

    if "user_preferences" not in tables:
        op.create_table(
            "user_preferences",
            sa.Column("user_id", sa.String(), _user_fk(), primary_key=True),
            sa.Column("timezone", sa.String(), nullable=False),
            sa.Column("wake_time", sa.String(), nullable=False),
            sa.Column("sleep_hours", sa.Float(), nullable=False),
            sa.Column("focus_peak", sa.String(), nullable=False),
            sa.Column("energy_dip_time", sa.String(), nullable=False),
            sa.Column("primary_goal", sa.String(), nullable=False),
            sa.Column("accent_color", sa.String(), nullable=False),
            sa.Column("density_mode", sa.String(), nullable=False),
        )

    if "tasks" not in tables:
        op.create_table(
            "tasks",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), _user_fk(), nullable=False),
            sa.Column("title", sa.String(255), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("category", sa.String(50), nullable=False),
            sa.Column("task_type", TASK_TYPE, nullable=False),
            sa.Column("difficulty", TASK_DIFFICULTY, nullable=False),
            sa.Column("priority", TASK_PRIORITY, nullable=False),
            sa.Column("estimated_minutes", sa.Integer(), nullable=False),
            sa.Column("deadline_at", TZ, nullable=True),
            sa.Column("scheduled_start", TZ, nullable=True),
            sa.Column("scheduled_end", TZ, nullable=True),
            sa.Column("status", TASK_STATUS, nullable=False),
            sa.Column("source", TASK_SOURCE, nullable=False),
            sa.Column("started_at", TZ, nullable=True),
            sa.Column("completed_at", TZ, nullable=True),
            sa.Column("created_at", TZ, nullable=False),
            sa.Column("updated_at", TZ, nullable=False),
        )
        op.create_index("ix_tasks_user_id", "tasks", ["user_id"])
        op.create_index("ix_tasks_status", "tasks", ["status"])

    if "task_performance" not in tables:
        op.create_table(
            "task_performance",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("task_id", sa.String(), sa.ForeignKey("tasks.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id", sa.String(), _user_fk(), nullable=False),
            sa.Column("scheduled_start", TZ, nullable=True),
            sa.Column("actual_start", TZ, nullable=True),
            sa.Column("completed_at", TZ, nullable=False),
            sa.Column("estimated_minutes", sa.Integer(), nullable=False),
            sa.Column("actual_minutes", sa.Integer(), nullable=False),
            sa.Column("focus_score", sa.Integer(), nullable=False),
            sa.Column("energy_score", sa.Integer(), nullable=False),
            sa.Column("difficulty_score", sa.Integer(), nullable=False),
            sa.Column("distraction_score", sa.Integer(), nullable=True),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_at", TZ, nullable=False),
        )
        op.create_index("ix_task_performance_task_id", "task_performance", ["task_id"])
        op.create_index("ix_task_performance_user_id", "task_performance", ["user_id"])

    if "recommendation_decisions" not in tables:
        op.create_table(
            "recommendation_decisions",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), _user_fk(), nullable=False),
            sa.Column("created_at", TZ, nullable=False),
            sa.Column("readiness_score", sa.Float(), nullable=True),
            sa.Column("readiness_confidence", sa.Float(), nullable=True),
            sa.Column("readiness_stage", sa.String(), nullable=True),
            sa.Column("total_pending_tasks", sa.Integer(), nullable=True),
            sa.Column("total_pending_minutes", sa.Integer(), nullable=True),
            sa.Column("available_minutes", sa.Integer(), nullable=True),
            sa.Column("candidate_scores_json", sa.Text(), nullable=True),
            sa.Column("recommended_task_id", sa.String(), sa.ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True),
            sa.Column("recommendation_score", sa.Float(), nullable=True),
            sa.Column("recommendation_reasons_json", sa.Text(), nullable=True),
            sa.Column("engine_version", sa.String(), nullable=True),
            sa.Column("strategy", sa.String(), nullable=True),
            sa.Column("observation_count", sa.Integer(), nullable=True),
        )
        op.create_index("ix_recommendation_decisions_user_id", "recommendation_decisions", ["user_id"])
        op.create_index("ix_recommendation_decisions_created_at", "recommendation_decisions", ["created_at"])
        op.create_index("ix_recommendation_decisions_recommended_task_id", "recommendation_decisions", ["recommended_task_id"])

    if "recommendation_outcomes" not in tables:
        op.create_table(
            "recommendation_outcomes",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("decision_id", sa.String(), sa.ForeignKey("recommendation_decisions.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id", sa.String(), _user_fk(), nullable=False),
            sa.Column("task_id", sa.String(), sa.ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True),
            sa.Column("user_action", sa.String(), nullable=False),
            sa.Column("override_reason", sa.String(), nullable=True),
            sa.Column("override_to_task_id", sa.String(), sa.ForeignKey("tasks.id", ondelete="SET NULL"), nullable=True),
            sa.Column("started_at", TZ, nullable=True),
            sa.Column("completed_at", TZ, nullable=True),
            sa.Column("postponed_at", TZ, nullable=True),
            sa.Column("abandoned_at", TZ, nullable=True),
            sa.Column("actual_minutes", sa.Integer(), nullable=True),
            sa.Column("focus_rating", sa.Integer(), nullable=True),
            sa.Column("energy_rating", sa.Integer(), nullable=True),
            sa.Column("difficulty_rating", sa.Integer(), nullable=True),
            sa.Column("outcome", sa.String(), nullable=True),
            sa.Column("suggested_replan_date", sa.String(), nullable=True),
            sa.Column("suggested_replan_time", sa.String(), nullable=True),
            sa.Column("created_at", TZ, nullable=False),
            sa.Column("updated_at", TZ, nullable=False),
        )
        op.create_index("ix_recommendation_outcomes_decision_id", "recommendation_outcomes", ["decision_id"])
        op.create_index("ix_recommendation_outcomes_user_id", "recommendation_outcomes", ["user_id"])

    if "ai_usage_records" not in tables:
        op.create_table(
            "ai_usage_records",
            sa.Column("user_id", sa.String(), _user_fk(), primary_key=True),
            sa.Column("free_uses_total", sa.Integer(), nullable=False),
            sa.Column("free_uses_consumed", sa.Integer(), nullable=False),
            sa.Column("shield_uses_consumed", sa.Integer(), nullable=False),
            sa.Column("total_ai_uses", sa.Integer(), nullable=False),
            sa.Column("last_ai_use_at", TZ, nullable=True),
            sa.Column("is_pro", sa.Boolean(), nullable=False),
            sa.Column("subscription_tier", sa.String(), nullable=False),
            sa.Column("subscription_status", sa.String(), nullable=False),
            sa.Column("subscription_expires_at", TZ, nullable=True),
            sa.Column("google_play_order_id", sa.String(), nullable=True),
            sa.Column("created_at", TZ, nullable=False),
            sa.Column("updated_at", TZ, nullable=False),
        )

    if "ai_planning_requests" not in tables:
        op.create_table(
            "ai_planning_requests",
            sa.Column("idempotency_key", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), _user_fk(), nullable=False),
            sa.Column("status", sa.String(), nullable=False),
            sa.Column("response_json", sa.Text(), nullable=True),
            sa.Column("shield_used", sa.Boolean(), nullable=False),
            sa.Column("created_at", TZ, nullable=False),
        )
        op.create_index("ix_ai_planning_requests_user_id", "ai_planning_requests", ["user_id"])


def downgrade() -> None:
    bind = op.get_bind()
    tables = set(sa.inspect(bind).get_table_names())
    for name in (
        "ai_planning_requests",
        "ai_usage_records",
        "recommendation_outcomes",
        "recommendation_decisions",
        "task_performance",
        "tasks",
        "user_preferences",
        "users",
    ):
        if name in tables:
            op.drop_table(name)
    if bind.dialect.name == "postgresql":
        for enum_type in TASK_ENUMS:
            enum_type.drop(bind, checkfirst=True)
