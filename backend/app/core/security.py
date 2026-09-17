from typing import Optional
from jose import jwt, JWTError
from .config import settings

ALGORITHM = "HS256"

def decode_access_token(token: str) -> Optional[dict]:
    """
    Decodes and verifies a JWT token.
    Compatible with Supabase access tokens.
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
