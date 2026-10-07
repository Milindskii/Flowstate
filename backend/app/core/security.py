from typing import Optional
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .config import settings
from ..db.session import get_db
from ..models.user import User
from ..models.user_preferences import UserPreferences

import time

import httpx
from sqlalchemy.engine import make_url
from .logging import logger
from jose import jwt, jwk, JWTError

ALGORITHM = "HS256"
DEFAULT_DEV_SECRET = "flowstate-local-dev-secret-replace-in-production"
DEV_ENVIRONMENTS = {"development", "test"}
TOKEN_AUDIENCE = "authenticated"
JWKS_MIN_REFETCH_SECONDS = 60.0
security_scheme = HTTPBearer(auto_error=False)

_JWKS_KEYS_CACHE = {}
_LAST_JWKS_FETCH = 0.0


def _issuer() -> str:
    return f"{settings.SUPABASE_URL.rstrip('/')}/auth/v1"


def fetch_supabase_jwks() -> dict:
    """Refresh the JWKS cache, at most once per JWKS_MIN_REFETCH_SECONDS (random `kid`s can't force fetches)."""
    global _LAST_JWKS_FETCH
    if not settings.SUPABASE_JWKS_URL:
        return _JWKS_KEYS_CACHE
    now = time.monotonic()
    if _LAST_JWKS_FETCH and now - _LAST_JWKS_FETCH < JWKS_MIN_REFETCH_SECONDS:
        return _JWKS_KEYS_CACHE
    _LAST_JWKS_FETCH = now
    try:
        res = httpx.get(settings.SUPABASE_JWKS_URL, timeout=5.0)
        if res.status_code == 200:
            for key in res.json().get("keys", []):
                kid = key.get("kid")
                if kid:
                    _JWKS_KEYS_CACHE[kid] = key
    except Exception:
        pass
    return _JWKS_KEYS_CACHE


def verify_security_environment():
    """
    Fail-closed security check. Anything other than an explicit development/test environment is treated as
    production: the dev bypass and the public development JWT secret are refused.
    """
    env_clean = settings.ENVIRONMENT.strip().lower()
    if env_clean in DEV_ENVIRONMENTS:
        return
    if settings.DEV_BYPASS_AUTH:
        raise RuntimeError(
            f"CRITICAL SECURITY VIOLATION: DEV_BYPASS_AUTH is enabled while ENVIRONMENT='{env_clean}'! "
            "Execution refused to protect user data."
        )
    if settings.SUPABASE_JWT_SECRET == DEFAULT_DEV_SECRET:
        raise RuntimeError(
            f"CRITICAL SECURITY VIOLATION: the development Supabase JWT secret is configured while ENVIRONMENT='{env_clean}'."
        )

ALLOWED_ALGORITHMS = ["RS256", "ES256", "HS256"]
LOCAL_DB_HOSTS = {"", "localhost", "127.0.0.1", "::1"}


def _database_is_local() -> bool:
    """SQLite, or PostgreSQL on this machine. Anything else (e.g. the Supabase pooler) holds real accounts."""
    try:
        url = make_url(settings.DATABASE_URL)
    except Exception:
        return False
    return url.get_backend_name() == "sqlite" or (url.host or "") in LOCAL_DB_HOSTS


def _hs256_allowed() -> bool:
    """The shared-secret path is for a real project secret, or for local dev/tests only.

    The development secret is public (it is in the repository), so a token signed with it proves nothing. It is
    honoured only in an explicit development/test environment AND against a local database; against any remote
    database the HS256 path is closed and only asymmetric (JWKS) tokens authenticate."""
    if settings.SUPABASE_JWT_SECRET != DEFAULT_DEV_SECRET:
        return True
    return settings.ENVIRONMENT.strip().lower() in DEV_ENVIRONMENTS and _database_is_local()

def _jwt_rejection_reason(exc: Exception) -> str:
    text = str(exc).lower()
    for needle, reason in (("audience", "audience"), ("issuer", "issuer"), ("expired", "expired"),
                           ("signature", "signature"), ("subject", "subject"), ("not enough segments", "malformed")):
        if needle in text:
            return reason
    return type(exc).__name__.lower()


def decode_access_token(token: str) -> Optional[dict]:
    """
    Decodes and verifies a Supabase Auth JWT: signature, expiry, audience and issuer.
    Asymmetric tokens are verified only against the Supabase JWKS; the symmetric secret is used only for
    HS256 tokens, so an unknown `kid` can never downgrade verification.
    """
    try:
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        alg = header.get("alg", ALGORITHM)

        # Reject any unsupported algorithms (such as 'none')
        if alg not in ALLOWED_ALGORITHMS:
            return None

        options = {"verify_aud": True, "verify_exp": True, "verify_iss": True,
                   "require_aud": True, "require_exp": True, "require_iss": True, "require_sub": True}
        common = {"audience": TOKEN_AUDIENCE, "issuer": _issuer(), "options": options}

        if alg != "HS256":
            if not kid:
                return None
            if kid not in _JWKS_KEYS_CACHE:
                fetch_supabase_jwks()
            key_dict = _JWKS_KEYS_CACHE.get(kid)
            if not key_dict:
                return None
            return jwt.decode(token, jwk.construct(key_dict), algorithms=[alg], **common)

        if not _hs256_allowed():
            logger.warning("jwt_rejected reason=hs256_disabled")
            return None
        return jwt.decode(token, settings.SUPABASE_JWT_SECRET, algorithms=[ALGORITHM], **common)
    except JWTError as e:
        # Diagnosable without leaking anything: only the failure class, never the token or its claims.
        logger.warning("jwt_rejected reason=%s", _jwt_rejection_reason(e))
        return None

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Utility for minting valid test tokens or internal tokens"""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(days=7))
    to_encode.update({"exp": expire})
    to_encode.setdefault("aud", TOKEN_AUDIENCE)
    to_encode.setdefault("iss", _issuer())
    return jwt.encode(to_encode, settings.SUPABASE_JWT_SECRET, algorithm=ALGORITHM)

def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme),
    db: Session = Depends(get_db)
) -> User:
    """
    FastAPI dependency that extracts and validates the Supabase Auth JWT.
    Lazily provisions the local User record upon first verified request.
    """
    verify_security_environment()

    # Local development bypass: ONLY allowed when DEV_BYPASS_AUTH is explicitly set in non-production
    if settings.DEV_BYPASS_AUTH and (not credentials or not credentials.credentials):
        user_id = "dev-user-local"
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            user = User(
                id=user_id,
                email="dev@flowstate.local",
                name="Local Developer",
            )
            db.add(user)
            db.flush()
            prefs = UserPreferences(user_id=user_id)
            db.add(prefs)
            db.commit()
            db.refresh(user)
        return user

    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id: Optional[str] = payload.get("sub")
    email: Optional[str] = payload.get("email", f"{user_id}@flowstate.local")

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing user identity subject (sub)",
        )

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        # First-time access: provision user profile and default preferences
        name = payload.get("user_metadata", {}).get("name") or (email.split("@")[0] if email else "Friend")
        user = User(
            id=user_id,
            email=email or f"{user_id}@flowstate.local",
            name=name,
            avatar_url=payload.get("user_metadata", {}).get("avatar_url"),
        )
        db.add(user)
        db.flush()

        prefs = UserPreferences(user_id=user_id)
        db.add(prefs)
        db.commit()
        db.refresh(user)

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is deactivated",
        )

    return user

def get_current_user_allow_deactivated(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_scheme),
    db: Session = Depends(get_db)
) -> User:
    """Dependency that authenticates the user even if currently deactivated (e.g. for reactivation)."""
    verify_security_environment()

    if settings.DEV_BYPASS_AUTH and (not credentials or not credentials.credentials):
        user_id = "dev-user-local"
        user = db.query(User).filter(User.id == user_id).first()
        return user

    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials
    payload = decode_access_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id: Optional[str] = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing user identity subject (sub)",
        )

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Dependency that enforces administrative permissions."""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrative privileges required",
        )
    return current_user
