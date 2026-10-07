"""The Alembic chain builds the full model schema from an EMPTY database (spec section 11.1, "D4").

Before 000_base_schema the chain assumed users/tasks already existed, so a fresh
PostgreSQL (Supabase) database could not be migrated at all. On PostgreSQL the gate run
(FLOWSTATE_TEST_DATABASE_URL, see conftest) builds its schema through this same chain.
"""
import os
import shutil
import tempfile
from argparse import Namespace
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect

import app.models  # noqa: F401  (register every table)
from app.db.session import Base

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@pytest.fixture
def empty_db(monkeypatch):
    d = Path(tempfile.mkdtemp(prefix="flowstate-base-"))
    url = "sqlite:///" + str(d / "empty.db").replace("\\", "/")
    from app.core.config import settings

    monkeypatch.setattr(settings, "DATABASE_URL", url)
    yield url
    shutil.rmtree(d, ignore_errors=True)


def _cfg():
    cfg = Config(os.path.join(BACKEND, "alembic.ini"))
    cfg.cmd_opts = Namespace(x=[])
    return cfg


def test_chain_is_linear_with_single_root_and_head():
    script = ScriptDirectory.from_config(_cfg())
    assert script.get_bases() == ["000_base_schema"]
    assert len(script.get_heads()) == 1


def test_upgrade_from_empty_matches_models_and_downgrades_clean(empty_db):
    cfg = _cfg()
    command.upgrade(cfg, "head")

    eng = create_engine(empty_db)
    try:
        with eng.connect() as conn:
            assert set(Base.metadata.tables) <= set(inspect(conn).get_table_names())
            ctx = MigrationContext.configure(conn, opts={"compare_type": True})
            assert compare_metadata(ctx, Base.metadata) == []

        command.downgrade(cfg, "base")
        with eng.connect() as conn:
            assert set(inspect(conn).get_table_names()) <= {"alembic_version"}
    finally:
        eng.dispose()
