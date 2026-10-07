"""No unreviewed migration may be applied to a development database (integrity-review side effect).

Importing the app against an existing development SQLite file used to ALTER it and run a backfill silently.
Now the planning-column change is applied only when the developer opts in
(FLOWSTATE_DEV_AUTO_MIGRATE=1) or runs Alembic after reviewing scripts/report_time_lock_backfill.py.
"""
import hashlib
import os
import shutil
import sqlite3
import tempfile
from pathlib import Path

import pytest
from sqlalchemy import create_engine, inspect

from app.db.backfill import MigrationRequired, ensure_planning_columns

BACKEND = Path(__file__).resolve().parent.parent

OLD_TASKS_DDL = """
CREATE TABLE tasks (
    id VARCHAR PRIMARY KEY, user_id VARCHAR NOT NULL, title VARCHAR(255) NOT NULL,
    estimated_minutes INTEGER NOT NULL DEFAULT 45, scheduled_start DATETIME, status VARCHAR(11) NOT NULL DEFAULT 'todo',
    source VARCHAR(9) NOT NULL DEFAULT 'manual'
)"""


@pytest.fixture
def old_dev_db():
    d = Path(tempfile.mkdtemp(prefix="flowstate-devdb-"))
    path = d / "dev.db"
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE users (id VARCHAR PRIMARY KEY)")
    con.execute(OLD_TASKS_DDL)
    con.execute("INSERT INTO tasks (id, user_id, title, scheduled_start, status, source) VALUES "
                "('c1','u','Imported event','2026-10-05 10:00:00','todo','calendar'), "
                "('m1','u','Manual','2026-10-05 11:00:00','todo','manual')")
    con.commit()
    con.close()
    engine = create_engine("sqlite:///" + str(path).replace("\\", "/"))
    yield path, engine
    engine.dispose()
    shutil.rmtree(d, ignore_errors=True)


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_without_opt_in_the_dev_database_is_refused_and_left_byte_identical(old_dev_db):
    path, engine = old_dev_db
    before = _digest(path)
    with pytest.raises(MigrationRequired) as exc:
        ensure_planning_columns(engine, auto_migrate=False)
    msg = str(exc.value)
    assert "report_time_lock_backfill.py" in msg and "alembic upgrade head" in msg and "FLOWSTATE_DEV_AUTO_MIGRATE=1" in msg
    assert "nothing was changed" in msg.lower()
    engine.dispose()
    assert _digest(path) == before, "the refusal itself must not modify the database"


def test_opt_in_applies_the_reviewed_migration_and_the_strict_backfill(old_dev_db):
    path, engine = old_dev_db
    added = ensure_planning_columns(engine, auto_migrate=True)
    assert {"time_locked", "planned_date"} <= added
    con = sqlite3.connect(path)
    rows = dict(con.execute("SELECT id, time_locked FROM tasks").fetchall())
    con.close()
    assert rows == {"c1": 1, "m1": 0}, "only the calendar-sourced event is locked; nothing is inferred"


def test_second_call_is_a_no_op(old_dev_db):
    _, engine = old_dev_db
    ensure_planning_columns(engine, auto_migrate=True)
    assert ensure_planning_columns(engine, auto_migrate=False) == set()


def test_fresh_database_without_a_tasks_table_is_not_blocked(tmp_path_factory=None):
    d = Path(tempfile.mkdtemp(prefix="flowstate-fresh-"))
    try:
        engine = create_engine("sqlite:///" + str(d / "fresh.db").replace("\\", "/"))
        assert ensure_planning_columns(engine, auto_migrate=False) == set()   # create_all will build everything
        assert "tasks" not in inspect(engine).get_table_names()
        engine.dispose()
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_app_startup_runs_the_guard_before_create_all_and_only_opts_in_via_the_env_var():
    src = (BACKEND / "app" / "main.py").read_text(encoding="utf-8")
    assert "ensure_planning_columns" in src and "FLOWSTATE_DEV_AUTO_MIGRATE" in src
    assert src.index("ensure_planning_columns") < src.index("Base.metadata.create_all"), \
        "the guard must run before anything is created or altered"
    assert "upgrade_planning_columns(conn)" not in src, "the silent ALTER shim must be gone"
    assert "apply_lock_backfill(conn)" not in src, "no silent backfill at startup"
