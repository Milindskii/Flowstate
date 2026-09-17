from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "Flowstate"
    API_V1_STR: str = "/api/v1"
    VERSION: str = "1.0.0"

    # Database: SQLite default fallback for local zero-config testing; PostgreSQL via Supabase in production
    DATABASE_URL: str = "sqlite:///./flowstate.db"

    # Supabase / Auth credentials
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""
    SUPABASE_JWT_SECRET: str = "flowstate-local-dev-secret-replace-in-production"

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
    READINESS_MODEL_VERSION: str = "v1.0.0-deterministic"
    SCHEDULING_MODEL_VERSION: str = "v1.0.0-deterministic"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="allow",
    )

settings = Settings()
