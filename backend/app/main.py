from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from .core.config import settings
from .core.logging import setup_logging, logger
from .db.session import get_db, Base, engine

# Ensure all models are registered with Base metadata
from .models.user import User
from .models.user_preferences import UserPreferences
from .models.task import Task
from .models.task_performance import TaskPerformance

from .api.routes import auth, tasks

setup_logging()

# Initialize DB tables
try:
    Base.metadata.create_all(bind=engine)
except Exception as e:
    logger.warning(f"Database initialization warning: {e}")

from contextlib import asynccontextmanager
from .core.security import verify_security_environment

@asynccontextmanager
async def lifespan(app: FastAPI):
    verify_security_environment()
    yield

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Flowstate Non-Medical Personal Productivity Backend",
    lifespan=lifespan,
)

# Configure CORS for Flutter Web, Emulator, and Local Network mobile testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Permissive for local development and mobile network access
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API v1 Routers
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(tasks.router, prefix=settings.API_V1_STR)

@app.get("/health", tags=["Health"])
def health_check():
    """Top-level health check endpoint"""
    return {
        "status": "ok",
        "app": settings.PROJECT_NAME,
        "version": settings.VERSION
    }

@app.get(f"{settings.API_V1_STR}/health", tags=["Health"])
def api_v1_health(db: Session = Depends(get_db)):
    """API v1 Health check with database connectivity verification"""
    db_status = "connected"
    try:
        db.execute(text("SELECT 1"))
    except Exception as e:
        db_status = f"unhealthy: {e}"

    return {
        "status": "healthy",
        "service": "Flowstate Core",
        "version": settings.VERSION,
        "database": db_status
    }
