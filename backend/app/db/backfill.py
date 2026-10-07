"""
Planning-column schema upgrade + the single `time_locked` backfill predicate (spec §11.3).

Shared by (a) the Alembic revision 006, (b) the development SQLite startup shim and
(c) the read-only report script, so the three can never drift apart.

Safety rules (D2): every task defaults to *unlocked*. Nothing is inferred from a
scheduled_start alone, from task_type, or from titles. Only high-confidence
externally-fixed events (source calendar/imported) that are still open are locked.
"""
from typing import Set

from sqlalchemy import inspect, text
from sqlalchemy.engine import Connection

OPEN_STATUSES = ("todo", "postponed", "in_progress")

# THE predicate. Used verbatim by migration, dev shim and report.
LOCK_BACKFILL_WHERE = (
    "scheduled_start IS NOT NULL "
    "AND source IN ('calendar', 'imported') "
    "AND status IN ('todo', 'postponed', 'in_progress')"
)
LOCK_BACKFILL_UPDATE_SQL = f"UPDATE tasks SET time_locked = TRUE WHERE {LOCK_BACKFILL_WHERE}"

# Informational only (report section B). These rows are NEVER auto-locked.
REVIEW_KEYWORDS = ("dentist", "doctor", "appointment", "meeting", "interview", "flight", "exam", "class")


def _bool_default(conn: Connection) -> str:
    return "0" if conn.dialect.name == "sqlite" else "FALSE"


def upgrade_planning_columns(conn: Connection) -> Set[str]:
    """Idempotently add tasks.time_locked / tasks.planned_date and the day-query index.

    Returns the set of objects that were newly added. Raises if ``tasks`` is missing:
    Alembic cannot create it, and silently skipping would hide a mis-bootstrapped DB.
    """
    insp = inspect(conn)
    if "tasks" not in insp.get_table_names():
        raise RuntimeError(
            "006_task_planning_columns requires an existing 'tasks' table; Alembic does not "
            "create it (see docs/superpowers/specs/build-my-day-replan.md section 11.1). "
            "Bootstrap the base schema first."
        )
    cols = {c["name"] for c in insp.get_columns("tasks")}
    added: Set[str] = set()
    if "time_locked" not in cols:
        conn.execute(text(f"ALTER TABLE tasks ADD COLUMN time_locked BOOLEAN NOT NULL DEFAULT {_bool_default(conn)}"))
        added.add("time_locked")
    if "planned_date" not in cols:
        conn.execute(text("ALTER TABLE tasks ADD COLUMN planned_date DATE"))
        added.add("planned_date")
    indexes = {i["name"] for i in insp.get_indexes("tasks")}
    if "ix_tasks_user_scheduled_start" not in indexes:
        conn.execute(text("CREATE INDEX ix_tasks_user_scheduled_start ON tasks (user_id, scheduled_start)"))
        added.add("ix_tasks_user_scheduled_start")
    return added


def apply_lock_backfill(conn: Connection) -> int:
    """Run the backfill UPDATE; returns affected row count."""
    return conn.execute(text(LOCK_BACKFILL_UPDATE_SQL)).rowcount or 0


class MigrationRequired(RuntimeError):
    """The development database predates migration 006 and the developer has not opted in to applying it."""


PLANNING_COLUMNS = ("time_locked", "planned_date")


def missing_planning_columns(conn: Connection) -> Set[str]:
    """Planning columns absent from an EXISTING ``tasks`` table (empty when the table does not exist yet)."""
    insp = inspect(conn)
    if "tasks" not in insp.get_table_names():
        return set()
    cols = {c["name"] for c in insp.get_columns("tasks")}
    return {c for c in PLANNING_COLUMNS if c not in cols}


def ensure_planning_columns(engine, *, auto_migrate: bool) -> Set[str]:
    """Development-startup guard for migration 006. Never changes a database unless ``auto_migrate``.

    * no ``tasks`` table (fresh DB)  -> nothing to do; ``create_all`` builds the current schema;
    * columns present                -> nothing to do;
    * columns missing, not opted in  -> raise :class:`MigrationRequired` having touched NOTHING;
    * columns missing, opted in      -> apply the same reviewed steps as the Alembic revision
      (ALTERs, then the strict backfill) in one transaction.
    """
    with engine.connect() as conn:
        missing = missing_planning_columns(conn)
    if not missing:
        return set()
    if not auto_migrate:
        raise MigrationRequired(
            "The development database needs migration 006 (tasks.time_locked / tasks.planned_date). Nothing was changed.\n"
            "  1. Review what would be locked:  python scripts/report_time_lock_backfill.py\n"
            "  2. Back up the database file.\n"
            "  3. Apply it:  alembic upgrade head   (or set FLOWSTATE_DEV_AUTO_MIGRATE=1 and restart)."
        )
    with engine.begin() as conn:
        added = upgrade_planning_columns(conn)
        if "time_locked" in added:
            apply_lock_backfill(conn)
    return added


ALEMBIC_INI = __import__("pathlib").Path(__file__).resolve().parents[2] / "alembic.ini"


def alembic_heads_status(engine) -> tuple:
    """(database revisions, script head revisions) for the Alembic chain in ``backend/alembic``."""
    from alembic.config import Config
    from alembic.runtime.migration import MigrationContext
    from alembic.script import ScriptDirectory

    script_heads = set(ScriptDirectory.from_config(Config(str(ALEMBIC_INI))).get_heads())
    with engine.connect() as conn:
        db_heads = set(MigrationContext.configure(conn).get_current_heads())
    return db_heads, script_heads


def assert_schema_at_head(engine) -> None:
    """Non-SQLite startup guard: the schema comes only from Alembic, so refuse to serve a stale or empty DB."""
    db_heads, script_heads = alembic_heads_status(engine)
    if db_heads != script_heads:
        raise MigrationRequired(
            f"Database schema is at {sorted(db_heads) or 'no revision (empty)'}, code expects {sorted(script_heads)}.\n"
            "  Run from backend/:  alembic upgrade head"
        )
