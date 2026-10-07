"""Database pool safety: every API worker process owns its own SQLAlchemy pool, so the Supabase connection budget
is workers x (DB_POOL_SIZE + DB_MAX_OVERFLOW). The defaults keep that small and a saturated pool fails fast."""
import threading
import time

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import TimeoutError as PoolTimeout

from app.core.config import settings
from app.db import session as db_session

PG_URL = "postgresql+psycopg://u:p@aws-0-example.pooler.supabase.com:6543/postgres"


def test_postgres_engine_uses_a_small_bounded_per_process_pool():
    opts = db_session.engine_options(PG_URL)
    assert opts["pool_size"] == settings.DB_POOL_SIZE
    assert opts["max_overflow"] == settings.DB_MAX_OVERFLOW
    assert opts["pool_timeout"] == settings.DB_POOL_TIMEOUT_SECONDS
    assert opts["pool_recycle"] == settings.DB_POOL_RECYCLE_SECONDS
    assert opts["pool_pre_ping"] is True
    per_process = opts["pool_size"] + opts["max_overflow"]
    assert per_process <= 5, "defaults must stay conservative: 3 workers x 5 = 15 connections at most"
    assert db_session.max_connections(workers=3) <= 15, "fits the Supabase session-mode pool on the smallest tier"


def test_sqlite_keeps_its_thread_flag_and_no_pool_sizing():
    opts = db_session.engine_options("sqlite:///./x.db")
    assert opts["connect_args"] == {"check_same_thread": False}
    assert "pool_size" not in opts and "max_overflow" not in opts


def test_max_connections_formula_is_documented():
    assert db_session.max_connections(workers=3) == 3 * (settings.DB_POOL_SIZE + settings.DB_MAX_OVERFLOW)


def test_saturated_pool_never_opens_more_than_size_plus_overflow(tmp_path):
    """20 concurrent requests against a 2+1 pool: at most 3 connections at once, the rest wait then fail fast."""
    eng = create_engine("sqlite:///" + str(tmp_path / "pool.db").replace("\\", "/"),
                        connect_args={"check_same_thread": False},
                        pool_size=2, max_overflow=1, pool_timeout=0.3)
    held, peak, timeouts, lock = [0], [0], [0], threading.Lock()
    barrier = threading.Barrier(20)

    def worker():
        barrier.wait()
        try:
            with eng.connect() as conn:
                with lock:
                    held[0] += 1
                    peak[0] = max(peak[0], held[0])
                conn.execute(text("select 1"))
                time.sleep(0.5)
                with lock:
                    held[0] -= 1
        except PoolTimeout:
            with lock:
                timeouts[0] += 1

    threads = [threading.Thread(target=worker) for _ in range(20)]
    started = time.monotonic()
    [t.start() for t in threads]
    [t.join() for t in threads]
    eng.dispose()
    assert peak[0] <= 3, f"pool opened {peak[0]} connections"
    assert timeouts[0] >= 1, "a saturated pool must refuse instead of queueing forever"
    assert time.monotonic() - started < 5
