import os
import hashlib
import hmac

ITERATIONS = 600000

def hash_password(password: str) -> str:
    """Derives a PBKDF2-HMAC-SHA256 hash with cryptographic salt."""
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS)
    return f"{salt.hex()}${key.hex()}"

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verifies a password against the stored salt and hash in constant time."""
    try:
        salt_hex, key_hex = hashed_password.split("$")
        salt = bytes.fromhex(salt_hex)
        expected_key = bytes.fromhex(key_hex)
        key = hashlib.pbkdf2_hmac("sha256", plain_password.encode("utf-8"), salt, ITERATIONS)
        return hmac.compare_digest(key, expected_key)
    except Exception:
        return False
