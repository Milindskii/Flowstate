from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "Flowstate"
    API_V1_STR: str = "/api/v1"
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development" # "development", "staging", "production"

    DEBUG: bool = False

    # Database: SQLite default fallback for local zero-config testing; PostgreSQL via Supabase in production
    DATABASE_URL: str = "sqlite:///./flowstate.db"

    # Supabase / Auth credentials (configured via .env)
    SUPABASE_URL: str = "https://drfjprhnynktjkiplbzy.supabase.co"
    SUPABASE_KEY: str = "sb_publishable_LDiD72aRDOVKMwD5AMoU5Q_oNntJRrv"
    SUPABASE_JWKS_URL: str = "https://drfjprhnynktjkiplbzy.supabase.co/auth/v1/.well-known/jwks.json"
    SUPABASE_JWT_SECRET: str = "flowstate-local-dev-secret-replace-in-production"

    # Dev auth bypass: STRICTLY forbidden in production
    DEV_BYPASS_AUTH: bool = False

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

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="allow",
    )

settings = Settings()
