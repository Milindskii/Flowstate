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

ALGORITHM = "HS256"
security_scheme = HTTPBearer(auto_error=False)

def decode_access_token(token: str) -> Optional[dict]:
    """
    Decodes and verifies a JWT token issued by Supabase Auth (or test suite).
    """
    try:
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=[ALGORITHM],
            options={"verify_aud": False}
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

    return user
