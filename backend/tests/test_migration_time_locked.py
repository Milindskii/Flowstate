"""Migration 006 + time_locked backfill predicate (spec section 11; decision D2).

The fixture DB is built from the PRE-006 tasks schema (explicit DDL, frozen here) and
migrated with the real Alembic revision, so the migration itself is what is tested.
"""
import hashlib
import importlib.util
import os
import shutil
import sqlite3
import tempfile
from argparse import Namespace
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


@pytest.fixture
def tmp_path():
    """Own scratch dir: pytest's tmp_path cleanup hits a Windows symlink permission error here."""
    d = Path(tempfile.mkdtemp(prefix="flowstate-mig-"))
    yield d
    shutil.rmtree(d, ignore_errors=True)


BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PRE_006_TASKS_DDL = """
CREATE TABLE tasks (
    id VARCHAR PRIMARY KEY, user_id VARCHAR NOT NULL, title VARCHAR(255) NOT NULL, description TEXT,
    category VARCHAR(50) NOT NULL DEFAULT 'General', task_type VARCHAR(12) NOT NULL DEFAULT 'deep_work',
    difficulty VARCHAR(8) NOT NULL DEFAULT 'medium', priority VARCHAR(6) NOT NULL DEFAULT 'medium',
    estimated_minutes INTEGER NOT NULL DEFAULT 45, deadline_at DATETIME, scheduled_start DATETIME,
    scheduled_end DATETIME, status VARCHAR(11) NOT NULL DEFAULT 'todo', source VARCHAR(9) NOT NULL DEFAULT 'manual',
    started_at DATETIME, completed_at DATETIME, created_at DATETIME NOT NULL DEFAULT '2026-10-01 00:00:00',
    updated_at DATETIME NOT NULL DEFAULT '2026-10-01 00:00:00'
)"""
START = "2026-10-05 10:00:00"

# (id, source, status, task_type, title, scheduled_start, expected_locked)
MATRIX = [
    ("cal-todo", "calendar", "todo", "meeting", "Standup", START, True),
    ("imp-prog", "imported", "in_progress", "deep_work", "Imported block", START, True),
    ("cal-post", "calendar", "postponed", "deep_work", "Moved event", START, True),
    ("cal-nostart", "calendar", "todo", "meeting", "No start", None, False),
    ("cal-done", "calendar", "completed", "meeting", "Done event", START, False),
    ("cal-canc", "calendar", "cancelled", "meeting", "Cancelled event", START, False),
    ("cal-arch", "calendar", "archived", "meeting", "Archived event", START, False),
    ("man-todo", "manual", "todo", "deep_work", "Write report", START, False),
    ("ai-dentist", "ai_parsed", "todo", "personal", "Dentist at 6 PM", START, False),
    ("ai-meeting", "ai_parsed", "todo", "meeting", "Sync", START, False),
    ("man-meeting", "manual", "todo", "meeting", "Team meeting", START, False),
]


@pytest.fixture
def old_db(tmp_path, monkeypatch):
    path = tmp_path / "old.db"
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE users (id VARCHAR PRIMARY KEY, email VARCHAR)")
    con.execute("INSERT INTO users VALUES ('u1', 'u1@x.local')")
    con.execute(PRE_006_TASKS_DDL)
    for tid, src, st, tt, title, start, _ in MATRIX:
        con.execute(
            "INSERT INTO tasks (id, user_id, title, source, status, task_type, scheduled_start) VALUES (?,?,?,?,?,?,?)",
            (tid, "u1", title, src, st, tt, start),
        )
    con.commit()
    con.close()
    url = "sqlite:///" + str(path).replace("\\", "/")
    from app.core.config import settings

    monkeypatch.setattr(settings, "DATABASE_URL", url)
    return path, url


def _cfg(skip_backfill=False):
    cfg = Config(os.path.join(BACKEND, "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(BACKEND, "alembic"))
    cfg.cmd_opts = Namespace(x=["skip_lock_backfill=1"] if skip_backfill else [])
    return cfg


def _upgrade(url, skip_backfill=False):
    cfg = _cfg(skip_backfill)
    command.stamp(cfg, "005_privacy_grievances")
    command.upgrade(cfg, "006_task_planning_columns")


def _locked(url):
    eng = create_engine(url)
    with eng.connect() as c:
        rows = dict(c.execute(text("SELECT id, time_locked FROM tasks")).fetchall())
    eng.dispose()
    return rows


def test_backfill_matrix_exact(old_db):
    _, url = old_db
    _upgrade(url)
    got = _locked(url)
    for tid, *_rest, expected in MATRIX:
        assert bool(got[tid]) is expected, tid
    assert {t for t, v in got.items() if v} == {"cal-todo", "imp-prog", "cal-post"}


def test_default_is_unlocked_and_planned_date_null(old_db):
    _, url = old_db
    _upgrade(url)
    eng = create_engine(url)
    with eng.connect() as c:
        assert c.execute(text("SELECT count(*) FROM tasks WHERE planned_date IS NOT NULL")).scalar() == 0
        c.execute(text("INSERT INTO tasks (id,user_id,title) VALUES ('new','u1','x')"))
        assert c.execute(text("SELECT time_locked FROM tasks WHERE id='new'")).scalar() in (0, False)
    eng.dispose()


def test_no_other_column_changes(old_db):
    path, url = old_db
    con = sqlite3.connect(path)
    before = con.execute("SELECT id,user_id,title,description,category,task_type,difficulty,priority,estimated_minutes,"
                         "deadline_at,scheduled_start,scheduled_end,status,source,started_at,completed_at,created_at,updated_at "
                         "FROM tasks ORDER BY id").fetchall()
    con.close()
    _upgrade(url)
    con = sqlite3.connect(path)
    after = con.execute("SELECT id,user_id,title,description,category,task_type,difficulty,priority,estimated_minutes,"
                        "deadline_at,scheduled_start,scheduled_end,status,source,started_at,completed_at,created_at,updated_at "
                        "FROM tasks ORDER BY id").fetchall()
    con.close()
    assert before == after


def test_skip_flag_leaves_everything_unlocked(old_db):
    _, url = old_db
    _upgrade(url, skip_backfill=True)
    assert not any(_locked(url).values())


def test_creates_plan_applications_and_index(old_db):
    _, url = old_db
    _upgrade(url)
    eng = create_engine(url)
    insp = inspect(eng)
    assert "plan_applications" in insp.get_table_names()
    assert {c["name"] for c in insp.get_columns("plan_applications")} >= {"user_id", "plan_id", "kind", "response_json", "created_at"}
    assert "ix_tasks_user_scheduled_start" in {i["name"] for i in insp.get_indexes("tasks")}
    eng.dispose()


def test_column_helper_is_idempotent_and_never_relocks(old_db):
    path, url = old_db
    _upgrade(url)
    from app.db.backfill import apply_lock_backfill, upgrade_planning_columns

    eng = create_engine(url)
    with eng.begin() as conn:
        conn.execute(text("UPDATE tasks SET time_locked = FALSE WHERE id = 'cal-todo'"))  # user unlocked it
        assert upgrade_planning_columns(conn) == set()  # second run adds nothing
    assert _locked(url)["cal-todo"] in (0, False)  # and did not re-lock
    eng.dispose()


def test_report_section_a_equals_rows_changed_and_is_read_only(old_db, capsys):
    path, url = old_db
    spec = importlib.util.spec_from_file_location("report_script", os.path.join(BACKEND, "scripts", "report_time_lock_backfill.py"))
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)

    h_before = hashlib.sha256(path.read_bytes()).hexdigest()
    eng = create_engine(url)
    with eng.connect() as c:
        section_a = {r[0] for r in report._query_a(c)}
        section_b = {r[0] for r in report._query_b(c)}
    eng.dispose()
    assert report.main(["--database-url", url]) == 0
    assert hashlib.sha256(path.read_bytes()).hexdigest() == h_before  # read-only

    _upgrade(url)
    changed = {t for t, v in _locked(url).items() if v}
    assert section_a == changed == {"cal-todo", "imp-prog", "cal-post"}
    # review list: look-fixed rows that are NOT locked
    assert {"ai-dentist", "ai-meeting", "man-meeting"} <= section_b
    assert not (section_b & changed)


def test_one_predicate_shared_by_migration_shim_and_report():
    from app.db import backfill

    spec = importlib.util.spec_from_file_location("report_script2", os.path.join(BACKEND, "scripts", "report_time_lock_backfill.py"))
    report = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(report)
    assert report.LOCK_BACKFILL_WHERE is backfill.LOCK_BACKFILL_WHERE
    assert backfill.LOCK_BACKFILL_WHERE in backfill.LOCK_BACKFILL_UPDATE_SQL

    mig_spec = importlib.util.spec_from_file_location("mig006", os.path.join(BACKEND, "alembic", "versions", "006_task_planning_columns.py"))
    mig = importlib.util.module_from_spec(mig_spec)
    mig_spec.loader.exec_module(mig)
    assert mig.LOCK_BACKFILL_UPDATE_SQL is backfill.LOCK_BACKFILL_UPDATE_SQL

    # The dev startup path goes through ensure_planning_columns, which uses the very same two shared functions.
    main_src = open(os.path.join(BACKEND, "app", "main.py"), encoding="utf-8").read()
    assert "ensure_planning_columns" in main_src
    import inspect as _inspect

    guard_src = _inspect.getsource(backfill.ensure_planning_columns)
    assert "apply_lock_backfill" in guard_src and "upgrade_planning_columns" in guard_src
    # The predicate text itself is exactly the approved one (D2): nothing inferred from task_type/title.
    assert backfill.LOCK_BACKFILL_WHERE == (
        "scheduled_start IS NOT NULL AND source IN ('calendar', 'imported') "
        "AND status IN ('todo', 'postponed', 'in_progress')"
    )
    assert "task_type" not in backfill.LOCK_BACKFILL_WHERE and "title" not in backfill.LOCK_BACKFILL_WHERE


def test_006_fails_loudly_without_tasks_table(tmp_path, monkeypatch):
    path = tmp_path / "empty.db"
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE users (id VARCHAR PRIMARY KEY)")
    con.commit()
    con.close()
    url = "sqlite:///" + str(path).replace("\\", "/")
    from app.core.config import settings

    monkeypatch.setattr(settings, "DATABASE_URL", url)
    cfg = _cfg()
    command.stamp(cfg, "005_privacy_grievances")
    with pytest.raises(RuntimeError, match="requires an existing 'tasks' table"):
        command.upgrade(cfg, "006_task_planning_columns")


def test_downgrade_removes_additive_objects(old_db):
    _, url = old_db
    _upgrade(url)
    command.downgrade(_cfg(), "005_privacy_grievances")
    eng = create_engine(url)
    insp = inspect(eng)
    cols = {c["name"] for c in insp.get_columns("tasks")}
    assert "time_locked" not in cols and "planned_date" not in cols
    assert "plan_applications" not in insp.get_table_names()
    with eng.connect() as c:
        assert c.execute(text("SELECT count(*) FROM tasks")).scalar() == len(MATRIX)
    eng.dispose()


def test_dev_shim_upgrades_existing_sqlite_db(old_db):
    """The startup shim (create_all path) must produce the same result as the migration."""
    _, url = old_db
    from app.db.backfill import apply_lock_backfill, upgrade_planning_columns

    eng = create_engine(url)
    with eng.begin() as conn:
        added = upgrade_planning_columns(conn)
        assert {"time_locked", "planned_date"} <= added
        apply_lock_backfill(conn)
    assert {t for t, v in _locked(url).items() if v} == {"cal-todo", "imp-prog", "cal-post"}
    eng.dispose()
