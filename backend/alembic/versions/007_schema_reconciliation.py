"""Schema reconciliation: model columns/indexes that only the dev SQLite shim created, plus RLS

Revision ID: 007_schema_reconciliation
Revises: 006_task_planning_columns
Create Date: 2026-10-03 00:00:00.000000

* readiness_profiles: bedtime, draining_work_types, fatigue_symptom,
  routine_shift_preference (previously only added by app/main.py on SQLite).
* Indexes declared on the readiness models but never migrated (on PostgreSQL the unique
  index replaces 001's equivalent readiness_profiles.user_id unique constraint).
* PostgreSQL only: enable row level security on every application table, with no
  policies. The backend connects as the table owner (bypasses RLS); the Supabase
  anon/authenticated roles (PostgREST) get no access to Flowstate tables.

Idempotent: every step is skipped when already present.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "007_schema_reconciliation"
down_revision: Union[str, None] = "006_task_planning_columns"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

PROFILE_COLUMNS = (
    ("bedtime", sa.String(), "23:00", False),
    ("draining_work_types", sa.String(), "coding,studying", True),
    ("fatigue_symptom", sa.String(), "distracted", True),
    ("routine_shift_preference", sa.String(), "quick_recovery", True),
)

# (index name, table, columns, unique)
INDEXES = (
    ("ix_readiness_profiles_user_id", "readiness_profiles", ["user_id"], True),
    ("ix_readiness_obs_user_observed", "readiness_observations", ["user_id", "observed_at"], False),
    ("ix_readiness_obs_user_source", "readiness_observations", ["user_id", "source"], False),
    ("ix_readiness_pred_user_created", "readiness_predictions", ["user_id", "created_at"], False),
    ("ix_readiness_eval_user_created", "readiness_evaluations", ["user_id", "created_at"], False),
)


def _app_tables(insp) -> list:
    return sorted(insp.get_table_names())


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    existing = {c["name"] for c in insp.get_columns("readiness_profiles")}
    for name, type_, default, nullable in PROFILE_COLUMNS:
        if name not in existing:
            # server_default backfills existing rows; the model supplies the value on insert.
            op.add_column("readiness_profiles", sa.Column(name, type_, server_default=default, nullable=nullable))

    for name, table, cols, unique in INDEXES:
        if name not in {i["name"] for i in insp.get_indexes(table)}:
            op.create_index(name, table, cols, unique=unique)

    if bind.dialect.name == "postgresql":
        # 001 made readiness_profiles.user_id unique via a constraint; the model declares a unique
        # index (created above). Keep one: drop the now-redundant constraint.
        for uc in insp.get_unique_constraints("readiness_profiles"):
            if uc["column_names"] == ["user_id"] and uc["name"]:
                op.drop_constraint(uc["name"], "readiness_profiles", type_="unique")
        for table in _app_tables(insp):
            op.execute(sa.text(f'ALTER TABLE "{table}" ENABLE ROW LEVEL SECURITY'))


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    if bind.dialect.name == "postgresql":
        for table in _app_tables(insp):
            op.execute(sa.text(f'ALTER TABLE "{table}" DISABLE ROW LEVEL SECURITY'))
        if not any(uc["column_names"] == ["user_id"] for uc in insp.get_unique_constraints("readiness_profiles")):
            op.create_unique_constraint("readiness_profiles_user_id_key", "readiness_profiles", ["user_id"])

    for name, table, _cols, _unique in INDEXES:
        if name in {i["name"] for i in insp.get_indexes(table)}:
            op.drop_index(name, table_name=table)

    existing = {c["name"] for c in insp.get_columns("readiness_profiles")}
    with op.batch_alter_table("readiness_profiles") as batch:
        for name, *_ in PROFILE_COLUMNS:
            if name in existing:
                batch.drop_column(name)
