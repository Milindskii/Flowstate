from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from ..core.config import settings


def engine_options(url: str) -> dict:
    """Engine kwargs for [url].

    Each API worker process builds its own engine, so the pool is per process. The Supabase connection budget is
    therefore  workers x (DB_POOL_SIZE + DB_MAX_OVERFLOW)  (see max_connections), e.g. 3 workers x (3 + 2) = 15,
    which fits the Supabase session-mode pool (~15 on the smallest tier). Raise the env values only after checking
    that product against the pooler's limit for the plan in use.
    """
    if url.startswith("sqlite"):
        # If using SQLite, add check_same_thread=False
        return {"connect_args": {"check_same_thread": False}, "pool_pre_ping": True}
    return {
        "pool_pre_ping": True,
        "pool_size": settings.DB_POOL_SIZE,
        "max_overflow": settings.DB_MAX_OVERFLOW,
        "pool_timeout": settings.DB_POOL_TIMEOUT_SECONDS,  # fail fast (500) instead of piling up waiting requests
        "pool_recycle": settings.DB_POOL_RECYCLE_SECONDS,  # drop connections the pooler may already have closed
    }


def max_connections(workers: int) -> int:
    """Most database connections the API can open: every worker's pool full, overflow included."""
    return workers * (settings.DB_POOL_SIZE + settings.DB_MAX_OVERFLOW)


engine = create_engine(settings.DATABASE_URL, **engine_options(settings.DATABASE_URL))

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    """Dependency for obtaining database sessions per request"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
