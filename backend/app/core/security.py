from typing import Optional
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from sqlalchemy.orm import Session
from .config import settings
from ..db.session import get_db
from ..models.user import User
from ..models.user_preferences import UserPreferences

import httpx
from jose import jwt, jwk, JWTError

ALGORITHM = "HS256"
security_scheme = HTTPBearer(auto_error=False)

_JWKS_KEYS_CACHE = {}

def fetch_supabase_jwks() -> dict:
    global _JWKS_KEYS_CACHE
    if not settings.SUPABASE_JWKS_URL:
        return {}
    try:
        res = httpx.get(settings.SUPABASE_JWKS_URL, timeout=5.0)
        if res.status_code == 200:
            data = res.json()
            for key in data.get("keys", []):
                kid = key.get("kid")
                if kid:
                    _JWKS_KEYS_CACHE[kid] = key
    except Exception:
        pass
    return _JWKS_KEYS_CACHE

def verify_security_environment():
    """
    Fail-closed security check.
    Refuses application boot or request if DEV_BYPASS_AUTH is active in production.
    """
    env_clean = settings.ENVIRONMENT.strip().lower()
    if env_clean == "production" and settings.DEV_BYPASS_AUTH:
        raise RuntimeError(
            "CRITICAL SECURITY VIOLATION: DEV_BYPASS_AUTH is enabled while ENVIRONMENT='production'! "
            "Execution refused to protect user data."
        )

ALLOWED_ALGORITHMS = ["RS256", "ES256", "HS256"]

def decode_access_token(token: str) -> Optional[dict]:
    """
    Decodes and verifies a JWT token issued by Supabase Auth (via live JWKS)
    or the test suite (via symmetric secret).
    Enforces strict algorithm whitelisting to prevent alg:none and algorithm confusion attacks.
    """
    try:
        # First check unverified header to see if it's a Supabase JWKS-signed token
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        alg = header.get("alg", ALGORITHM)

        # Reject any unsupported algorithms (such as 'none')
        if alg not in ALLOWED_ALGORITHMS:
            return None

        if kid:
            if kid not in _JWKS_KEYS_CACHE:
                fetch_supabase_jwks()

            key_dict = _JWKS_KEYS_CACHE.get(kid)
            if key_dict:
                public_key = jwk.construct(key_dict)
                payload = jwt.decode(
                    token,
                    public_key,
                    algorithms=[alg],
                    options={"verify_aud": False, "verify_exp": True}
                )
                return payload

        # Fallback to symmetric secret (for tests or legacy HS256 tokens)
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=[ALGORITHM],
            options={"verify_aud": False, "verify_exp": True}
        )
        return payload
    except JWTError:
        return None

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Utility for minting valid test tokens or internal tokens"""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(days=7))
    to_encode.update({"exp": expire})
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
