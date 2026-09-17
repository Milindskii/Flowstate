# Flowstate FastAPI Backend

Production-ready backend for Flowstate, an AI-powered, non-medical personal productivity app.

---

## Architecture Overview

```
Flutter App (Client)
     ↓ (HTTP / REST)
FastAPI Routes (app/api/routes/)
     ↓
Services Layer (app/services/)
     ↓
Core Engines & AI Service (app/engines/ & app/services/ai_service.py)
     ↓
Repositories & Database (app/repositories/ & app/db/)
     ↓
PostgreSQL (Supabase) / SQLite (Local Dev)
```

---

## Prerequisites

- Python 3.10+ (tested on Python 3.12)
- Pip

---

## Quickstart

### 1. Setup Virtual Environment

```bash
cd backend
python -m venv venv
.\venv\Scripts\activate   # On Windows
source venv/bin/activate  # On Linux/macOS
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Run the Development Server

```bash
uvicorn app.main:app --reload --port 8000 --host 0.0.0.0
```

Interactive API documentation will be available at:
- **Swagger UI**: `http://localhost:8000/docs`
- **ReDoc**: `http://localhost:8000/redoc`
- **Health Check**: `http://localhost:8000/health`

---

## Environment Variables (`.env`)

Create a `.env` file in the `backend/` directory:

```ini
PROJECT_NAME=Flowstate
API_V1_STR=/api/v1
DATABASE_URL=sqlite:///./flowstate.db  # Or postgresql://user:pass@host:5432/flowstate
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-or-service-key
SUPABASE_JWT_SECRET=your-supabase-jwt-secret
```

---

## Testing

Run tests with pytest:

```bash
pytest -v
```
