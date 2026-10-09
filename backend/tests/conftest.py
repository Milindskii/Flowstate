"""
Test harness: isolate the test run from the developer database (spec finding 19).

``DATABASE_URL`` must be set *before* ``app`` is imported anywhere, because
``app.db.session`` builds the engine at import time. pytest imports this
conftest before collecting any test module, so setting it here is sufficient.
"""
import atexit
import os
import shutil
import tempfile

# RELEASE GATE (docs/superpowers/specs/build-my-day-replan.md section 18): the suite must also pass on PostgreSQL
# before the production migration. Point FLOWSTATE_TEST_DATABASE_URL at a DISPOSABLE database whose name contains
# "test"; its tables are dropped and recreated for the run. Without the variable the suite uses a temp SQLite file.
_PG_URL = os.environ.get("FLOWSTATE_TEST_DATABASE_URL")
_TEST_DB_DIR = tempfile.mkdtemp(prefix="flowstate-tests-")
_TEST_DB_PATH = os.path.join(_TEST_DB_DIR, "flowstate_test.db")
if _PG_URL:
    from sqlalchemy.engine import make_url

    _db_name = (make_url(_PG_URL).database or "").lower()
    if "test" not in _db_name:
        raise RuntimeError(
            f"Refusing to run: FLOWSTATE_TEST_DATABASE_URL must name a disposable database containing 'test' (got '{_db_name}'). "
            "The tables in it are DROPPED."
        )
    os.environ["DATABASE_URL"] = _PG_URL
else:
    os.environ["DATABASE_URL"] = "sqlite:///" + _TEST_DB_PATH.replace("\\", "/")

# The app fails closed (an unset ENVIRONMENT means production), so the suite declares itself a test environment
# and turns the per-IP limiter off (it is exercised directly in test_security_guard.py).
os.environ["ENVIRONMENT"] = "development"
os.environ["RATE_LIMIT_ENABLED"] = "false"
os.environ["GEMINI_BACKOFF_BASE_SECONDS"] = "0"  # no real sleeping between provider retries in tests
# A real key may be in backend/.env: Replan never calls the model unless a test enables it and stubs the transport.
os.environ["REPLAN_AI_ENABLED"] = "false"

import pytest  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _postgres_schema():
    """On the PostgreSQL gate run, build the schema through the real Alembic chain and tear it down afterwards.

    PostgreSQL (Supabase) never uses create_all, so the gate must exercise the migrations themselves.
    """
    if not _PG_URL:
        yield
        return
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import text

    from app.db.backfill import ALEMBIC_INI
    from app.db.session import engine

    with engine.begin() as conn:  # disposable DB (name checked above): start from an empty public schema
        conn.execute(text("DROP SCHEMA public CASCADE"))
        conn.execute(text("CREATE SCHEMA public"))
    cfg = Config(str(ALEMBIC_INI))
    command.upgrade(cfg, "head")
    yield
    engine.dispose()
    command.downgrade(cfg, "base")


def _cleanup() -> None:
    try:
        from app.db.session import engine

        engine.dispose()
    except Exception:
        pass
    shutil.rmtree(_TEST_DB_DIR, ignore_errors=True)


atexit.register(_cleanup)


@pytest.fixture(autouse=True)
def _reset_ai_gateway_state():
    """Fresh circuit breaker / concurrency slots and empty DB rate-limit windows for every test."""
    from sqlalchemy import delete

    import app.main  # noqa: F401  (creates the dev schema on SQLite)
    from app.core.ai_limits import reset_ai_limits
    from app.db.session import SessionLocal
    from app.models.ai_usage import RateLimitWindow

    def _clear():
        reset_ai_limits()
        from app.services.replan_ai import reset_rate_limit
        reset_rate_limit()
        with SessionLocal() as db:
            db.execute(delete(RateLimitWindow))
            db.commit()

    _clear()
    yield
    _clear()


@pytest.fixture
def one_free_plan(monkeypatch):
    """Accounts created in this test hold one complimentary AI plan.

    The product no longer gives one (Shields pay for AI planning), but the gateway still supports a free allowance
    (a support grant), and the refund / idempotency / concurrency tests exercise that mechanism."""
    import app.services.ai_economy_service as economy

    monkeypatch.setattr(economy, "FREE_BMD_PLANS", 1)
