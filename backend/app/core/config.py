from pathlib import Path
from typing import List
from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "Flowstate"
    API_V1_STR: str = "/api/v1"
    VERSION: str = "1.0.0"
    # Fail closed: an unset ENVIRONMENT is treated as production. Local dev sets ENVIRONMENT=development in .env.
    ENVIRONMENT: str = "production"  # "development", "test", "staging", "production"

    DEBUG: bool = False

    # Database: SQLite default fallback for local zero-config testing; PostgreSQL via Supabase in production
    DATABASE_URL: str = "sqlite:///./flowstate.db"
    # Per-process pool (PostgreSQL only). Max connections = workers x (DB_POOL_SIZE + DB_MAX_OVERFLOW).
    # DATABASE_URL uses the Supabase pooler in SESSION mode (:5432): each client connection holds a database
    # connection, and the smallest compute tier's pool is ~15. Defaults: 3 workers x (3 + 2) = 15. More workers
    # => lower these, or move to transaction mode (:6543) after checking the plan's limits.
    DB_POOL_SIZE: int = 3
    DB_MAX_OVERFLOW: int = 2
    DB_POOL_TIMEOUT_SECONDS: float = 10.0
    DB_POOL_RECYCLE_SECONDS: int = 300

    # Supabase / Auth credentials (configured via .env)
    SUPABASE_URL: str = "https://drfjprhnynktjkiplbzy.supabase.co"
    SUPABASE_KEY: str = "sb_publishable_LDiD72aRDOVKMwD5AMoU5Q_oNntJRrv"
    SUPABASE_JWKS_URL: str = "https://drfjprhnynktjkiplbzy.supabase.co/auth/v1/.well-known/jwks.json"
    SUPABASE_JWT_SECRET: str = "flowstate-local-dev-secret-replace-in-production"

    # Dev auth bypass: STRICTLY forbidden outside ENVIRONMENT=development/test
    DEV_BYPASS_AUTH: bool = False

    # Per-IP flood protection. TRUSTED_PROXY_CIDRS lists the load balancers whose X-Forwarded-For we believe.
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_PER_MINUTE: int = 150
    TRUSTED_PROXY_CIDRS: List[str] = []

    # CORS configuration
    BACKEND_CORS_ORIGINS: List[str] = [
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:5000",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5000",
        "http://127.0.0.1:8080",
        "http://192.168.1.9:5000",
        "http://192.168.1.9:8080",
    ]

    # Model settings
    READINESS_MODEL_VERSION: str = "v2.0.0-progressive"
    SCHEDULING_MODEL_VERSION: str = "v2.0.0-progressive"
    CALIBRATION_MIN_SESSIONS: int = 30
    LEARNING_MIN_SESSIONS: int = 1

    # Google Gemini AI settings (loaded strictly from environment / .env)
    GEMINI_API_KEY: str = ""
    GEMINI_PROJECT_ID: str = ""
    GEMINI_MODEL: str = "gemini-3.5-flash-lite"
    # Replan: language-model understanding for messages the deterministic rules cannot read (metered, never writes)
    REPLAN_AI_ENABLED: bool = True
    REPLAN_BURST_PER_MINUTE: int = 20  # Replan dry runs per user per minute, AI or not (shared DB counter)

    # --- AI gateway (see services/ai_gateway.py) -------------------------------------------------------------
    AI_MAX_CONCURRENCY: int = 8                 # simultaneous provider calls per API instance
    AI_QUEUE_WAIT_SECONDS: float = 2.0          # how long a request may wait for a slot before a 503
    AI_REQUEST_DEADLINE_SECONDS: float = 25.0   # hard cap on all provider work for one request
    AI_RESERVATION_MARGIN_SECONDS: float = 20.0  # grace after the deadline before a stuck reservation is refunded
    AI_RATE_LIMIT_PER_HOUR_FREE: int = 5
    AI_RATE_LIMIT_PER_HOUR_PRO: int = 20
    AI_PRO_DAILY_CAP: int = 30                  # Pro fair-use caps (successful plans)
    AI_PRO_MONTHLY_CAP: int = 300
    PRO_GRACE_DAYS: int = 3                     # Pro stays on this long after subscription_expires_at
    AI_BREAKER_FAILURE_THRESHOLD: int = 5       # consecutive provider-health failures that open the breaker
    AI_BREAKER_WINDOW_SECONDS: float = 30.0
    AI_BREAKER_OPEN_SECONDS: float = 30.0
    GEMINI_MAX_ATTEMPTS: int = 2                # models tried per call (primary + one fallback)
    GEMINI_REQUEST_TIMEOUT_SECONDS: float = 12.0
    GEMINI_BACKOFF_BASE_SECONDS: float = 0.5    # jittered exponential backoff between transient failures
    GEMINI_MAX_OUTPUT_TOKENS: int = 8192

    @field_validator("DATABASE_URL")
    @classmethod
    def _use_installed_pg_driver(cls, v: str) -> str:
        # Supabase hands out "postgresql://..." (SQLAlchemy's default there is psycopg2); we ship psycopg v3.
        for prefix in ("postgresql://", "postgres://"):
            if v.startswith(prefix):
                return "postgresql+psycopg://" + v[len(prefix):]
        return v

    model_config = SettingsConfigDict(
        # backend/.env regardless of the working directory the server is started from.
        env_file=str(Path(__file__).resolve().parents[2] / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="allow",
    )

settings = Settings()
