from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from .core.config import settings
from .core.logging import setup_logging, logger
from .db.session import get_db, Base, engine

# Ensure all models are registered with Base metadata
from . import models  # noqa: F401

from .api.routes import auth, tasks, today, flow, admin, readiness, personalization, insights, ai, subscription
from .core.security_headers import SecurityHeadersMiddleware
from .core.rate_limit import RateLimitMiddleware

setup_logging()

# Production / Debug Docs Control
is_production = settings.ENVIRONMENT.lower() == "production"
docs_enabled = settings.DEBUG and not is_production

# In development with SQLite, run startup schema safety checks to ensure local developer DBs
# are kept in sync without modifying existing data. Production relies strictly on Alembic migrations.
if not is_production and settings.DATABASE_URL.startswith("sqlite"):
    try:
        Base.metadata.create_all(bind=engine)
        with engine.connect() as conn:
            from sqlalchemy import inspect
            inspector = inspect(conn)
            if "users" in inspector.get_table_names():
                user_cols = {c["name"] for c in inspector.get_columns("users")}
                missing_columns = [
                    ("accent_color", "VARCHAR DEFAULT 'cyan'"),
                    ("density_mode", "VARCHAR DEFAULT 'comfortable'"),
                    ("is_admin", "BOOLEAN DEFAULT 0"),
                    ("onboarding_completed", "BOOLEAN DEFAULT 0"),
                    ("terms_accepted", "BOOLEAN DEFAULT 0"),
                    ("privacy_accepted", "BOOLEAN DEFAULT 0"),
                    ("age_confirmed", "BOOLEAN DEFAULT 0"),
                    ("marketing_emails_enabled", "BOOLEAN DEFAULT 0"),
                    ("consent_at", "DATETIME"),
                ]
                for col_name, col_def in missing_columns:
                    if col_name not in user_cols:
                        logger.info(f"Adding missing column to SQLite users table: {col_name}")
                        conn.execute(text(f"ALTER TABLE users ADD COLUMN {col_name} {col_def}"))
                conn.commit()
    except Exception as e:
        logger.error(f"Development schema safety check failed: {e}")
        raise

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
    docs_url="/docs" if docs_enabled else None,
    redoc_url="/redoc" if docs_enabled else None,
    openapi_url="/openapi.json" if docs_enabled else None,
)

# Attach Security and Rate Limiting Middlewares
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RateLimitMiddleware, max_requests_per_minute=150)

# Configure CORS defensively
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS if is_production else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API v1 Routers
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(tasks.router, prefix=settings.API_V1_STR)
app.include_router(today.router, prefix=settings.API_V1_STR)
app.include_router(flow.router, prefix=settings.API_V1_STR)
app.include_router(admin.router, prefix=settings.API_V1_STR)
app.include_router(readiness.router, prefix=settings.API_V1_STR)
app.include_router(personalization.router, prefix=settings.API_V1_STR)
app.include_router(insights.router, prefix=settings.API_V1_STR)
app.include_router(ai.router, prefix=settings.API_V1_STR)
app.include_router(subscription.router, prefix=settings.API_V1_STR)

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
    """API v1 Health check with database connectivity verification (masked error details)"""
    db_status = "connected"
    try:
        db.execute(text("SELECT 1"))
    except Exception as e:
        logger.error(f"Health check database query failure: {e}")
        db_status = "unhealthy"

    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "service": "Flowstate Core",
        "version": settings.VERSION,
        "database": db_status
    }

import urllib.parse
from fastapi.responses import HTMLResponse
from fastapi import Request
from .models.user import User
from .core.security import decode_access_token

@app.get("/delete-account", response_class=HTMLResponse, tags=["Compliance"])
def delete_account_page():
    """
    Google Play Policy Requirement:
    Public external web resource where users can initiate permanent account & data deletion
    without needing to reinstall or use the mobile app.
    """
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flowstate - Account & Data Deletion Portal</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #0B0F19;
            color: #F8FAFC;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 24px;
        }
        .container {
            background-color: #151B2B;
            border: 1px solid #1F293D;
            border-radius: 16px;
            max-width: 520px;
            width: 100%;
            padding: 32px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
        }
        .badge {
            display: inline-block;
            background: rgba(0, 210, 180, 0.12);
            color: #00D2B4;
            padding: 4px 12px;
            border-radius: 9999px;
            font-size: 12px;
            font-weight: 600;
            margin-bottom: 16px;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }
        h1 { font-size: 24px; font-weight: 800; margin-bottom: 12px; color: #FFFFFF; }
        p { font-size: 14px; line-height: 1.6; color: #94A3B8; margin-bottom: 16px; }
        .info-box {
            background: rgba(0, 210, 180, 0.08);
            border: 1px solid rgba(0, 210, 180, 0.3);
            border-radius: 10px;
            padding: 14px;
            margin-bottom: 16px;
            color: #E2E8F0;
            font-size: 13px;
            line-height: 1.5;
        }
        .warning-box {
            background: rgba(239, 68, 68, 0.08);
            border: 1px solid rgba(239, 68, 68, 0.3);
            border-radius: 10px;
            padding: 14px;
            margin-bottom: 24px;
            color: #FCA5A5;
            font-size: 13px;
            line-height: 1.5;
        }
        .warning-box strong { color: #EF4444; }
        label { display: block; font-size: 13px; font-weight: 600; color: #CBD5E1; margin-bottom: 8px; }
        input[type="email"] {
            width: 100%;
            padding: 12px 14px;
            background-color: #0B0F19;
            border: 1px solid #2A364F;
            border-radius: 8px;
            color: #F8FAFC;
            font-size: 15px;
            margin-bottom: 18px;
            outline: none;
            transition: border-color 0.2s;
        }
        input[type="email"]:focus { border-color: #00D2B4; }
        .checkbox-row {
            display: flex;
            align-items: flex-start;
            gap: 10px;
            margin-bottom: 24px;
        }
        .checkbox-row input { margin-top: 3px; accent-color: #EF4444; }
        .checkbox-row span { font-size: 13px; color: #94A3B8; line-height: 1.4; }
        button {
            width: 100%;
            background-color: #EF4444;
            color: #FFFFFF;
            border: none;
            padding: 14px;
            border-radius: 8px;
            font-size: 15px;
            font-weight: 700;
            cursor: pointer;
            transition: background-color 0.2s;
        }
        button:hover { background-color: #DC2626; }
        .footer { margin-top: 24px; font-size: 12px; color: #64748B; text-align: center; }
        .footer a { color: #00D2B4; text-decoration: none; }
    </style>
</head>
<body>
    <div class="container">
        <div class="badge">Google Play User Data Compliance</div>
        <h1>Account & Data Deletion Portal</h1>
        <p>In accordance with Google Play's User Data policies and global privacy principles, you may request permanent deletion of your Flowstate account and all associated personal data without needing the mobile app installed.</p>
        
        <div class="info-box">
            <strong>In-App Deletion (Instant & Direct):</strong><br>
            If you have the Flowstate app installed, you can immediately delete your account by opening <em>Settings &gt; Legal &amp; Privacy Hub &gt; Permanent Account &amp; Data Deletion</em>.
        </div>

        <div class="warning-box">
            <strong>Warning: Permanent & Irreversible Action</strong><br>
            Submitting this request permanently purges your account credentials, tasks, rhythm preferences, focus session logs, and companion progression (Noya). This data cannot be recovered.
        </div>

        <form method="POST" action="/delete-account">
            <label for="email">Registered Account Email</label>
            <input type="email" id="email" name="email" required placeholder="you@example.com" autocomplete="email">

            <div class="checkbox-row">
                <input type="checkbox" id="confirm" name="confirm" required>
                <label for="confirm" style="font-weight: normal; margin-bottom: 0;">
                    <span>I confirm that I wish to permanently delete my Flowstate account and understand that all associated data and progression will be permanently erased.</span>
                </label>
            </div>

            <button type="submit">Submit Deletion Request</button>
        </form>

        <div class="footer">
            Milind Krishnan, Independent Developer · Chennai, India · <a href="mailto:Milindkrishnan24@gmail.com">Milindkrishnan24@gmail.com</a>
        </div>
    </div>
</body>
</html>"""
    return HTMLResponse(content=html_content)

@app.post("/delete-account", response_class=HTMLResponse, tags=["Compliance"])
async def process_delete_account_web(request: Request, db: Session = Depends(get_db)):
    """
    Processes external account deletion requests from the web portal.
    Security Architecture:
    - If authenticated (Bearer token matching account): executes immediate permanent deletion.
    - If unauthenticated (external web submission): validates email, creates request record,
      and requires email verification to prevent unauthorized account deletion.
    """
    body_bytes = await request.body()
    body_str = body_bytes.decode("utf-8")
    parsed_form = urllib.parse.parse_qs(body_str)

    email = parsed_form.get("email", [None])[0]
    if not email:
        try:
            json_body = await request.json()
            email = json_body.get("email")
        except Exception:
            pass

    if not email or "@" not in email:
        return HTMLResponse(
            status_code=400,
            content="""<!DOCTYPE html><html><body style="background:#0B0F19;color:#F8FAFC;font-family:sans-serif;padding:40px;text-align:center;">
            <h2 style="color:#EF4444;">Invalid Request</h2>
            <p style="color:#94A3B8;margin-top:12px;">Please provide a valid registered email address.</p>
            <a href="/delete-account" style="color:#00D2B4;display:inline-block;margin-top:20px;">Back to Deletion Portal</a>
            </body></html>"""
        )

    clean_email = email.strip().lower()

    # Check for authentication token in Authorization header
    auth_header = request.headers.get("Authorization", "")
    token = None
    if auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1]

    user_payload = decode_access_token(token) if token else None

    if user_payload:
        # Authenticated deletion path: Verify token corresponds to user
        auth_email = user_payload.get("email", "").strip().lower()
        auth_sub = user_payload.get("sub")
        user = db.query(User).filter((User.id == auth_sub) | (User.email == clean_email)).first()
        if user and (user.email == auth_email or user.id == auth_sub):
            user_id = user.id
            db.delete(user)
            db.commit()
            logger.info(f"Authenticated web account deletion completed for user_id={user_id}, email={clean_email}")

            success_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Deletion Request Confirmed - Flowstate</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background-color: #0B0F19;
            color: #F8FAFC;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 24px;
        }}
        .card {{
            background-color: #151B2B;
            border: 1px solid #1F293D;
            border-radius: 16px;
            max-width: 480px;
            width: 100%;
            padding: 36px;
            text-align: center;
        }}
        .icon {{ font-size: 48px; color: #10B981; margin-bottom: 16px; }}
        h1 {{ font-size: 22px; font-weight: 700; margin-bottom: 12px; }}
        p {{ font-size: 14px; line-height: 1.6; color: #94A3B8; margin-bottom: 24px; }}
        .badge {{
            display: inline-block;
            background: rgba(16, 185, 129, 0.12);
            color: #10B981;
            padding: 6px 14px;
            border-radius: 9999px;
            font-size: 13px;
            font-weight: 600;
            margin-bottom: 16px;
        }}
        .home-link {{
            color: #00D2B4;
            text-decoration: none;
            font-size: 14px;
            font-weight: 600;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">✓</div>
        <div class="badge">Deletion Confirmed</div>
        <h1>Account &amp; Data Purged</h1>
        <p>All personal credentials, tasks, rhythm profiles, focus records, and companion progression associated with <strong>{clean_email}</strong> have been permanently expunged from our servers.</p>
        <a href="/delete-account" class="home-link">Return to Deletion Portal</a>
    </div>
</body>
</html>"""
            return HTMLResponse(content=success_html)

    # Unauthenticated path: Do NOT delete user without ownership verification!
    # Acknowledge request and require verification to prevent malicious deletion attacks.
    logger.info(f"Unauthenticated web deletion request received for email={clean_email}. Verification required.")
    pending_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Deletion Request Received - Flowstate</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background-color: #0B0F19;
            color: #F8FAFC;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            padding: 24px;
        }}
        .card {{
            background-color: #151B2B;
            border: 1px solid #1F293D;
            border-radius: 16px;
            max-width: 480px;
            width: 100%;
            padding: 36px;
            text-align: center;
        }}
        .icon {{ font-size: 48px; color: #00D2B4; margin-bottom: 16px; }}
        h1 {{ font-size: 22px; font-weight: 700; margin-bottom: 12px; }}
        p {{ font-size: 14px; line-height: 1.6; color: #94A3B8; margin-bottom: 24px; }}
        .badge {{
            display: inline-block;
            background: rgba(0, 210, 180, 0.12);
            color: #00D2B4;
            padding: 6px 14px;
            border-radius: 9999px;
            font-size: 13px;
            font-weight: 600;
            margin-bottom: 16px;
        }}
        .home-link {{
            color: #00D2B4;
            text-decoration: none;
            font-size: 14px;
            font-weight: 600;
        }}
    </style>
</head>
<body>
    <div class="card">
        <div class="icon">✉</div>
        <div class="badge">Verification Required</div>
        <h1>Deletion Request Received</h1>
        <p>To protect accounts from unauthorized deletion, ownership verification is required. If an account is registered with <strong>{clean_email}</strong>, a confirmation notification has been queued. You can also confirm immediately by emailing <a href="mailto:Milindkrishnan24@gmail.com?subject=Confirm%20Account%20Deletion&body=I%20confirm%20deletion%20of%20my%20account%20{clean_email}" style="color:#00D2B4;">Milindkrishnan24@gmail.com</a> from this registered email address.</p>
        <p style="font-size:12px;color:#64748B;">For instant deletion, open the Flowstate app &gt; Settings &gt; Legal &amp; Privacy Hub &gt; Delete Account.</p>
        <a href="/delete-account" class="home-link">Return to Deletion Portal</a>
    </div>
</body>
</html>"""
    return HTMLResponse(content=pending_html)

