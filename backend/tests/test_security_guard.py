"""Auth fails closed, tokens are fully validated, and the per-IP limiter has no spoofable bypass."""
import base64
import json
import logging
import uuid
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from httpx import ASGITransport, AsyncClient
from jose import jwt
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route

from app.core import security
from app.main import app
from app.core.config import Settings, settings
from app.core.rate_limit import RateLimitMiddleware

DEFAULT_SECRET = "flowstate-local-dev-secret-replace-in-production"


def _b64(obj: dict) -> str:
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def _token(secret=None, **claims) -> str:
    payload = {
        "sub": "u1",
        "aud": "authenticated",
        "iss": f"{settings.SUPABASE_URL}/auth/v1",
        "exp": datetime.now(timezone.utc) + timedelta(hours=1),
    }
    payload.update(claims)
    payload = {k: v for k, v in payload.items() if v is not None}
    return jwt.encode(payload, secret or settings.SUPABASE_JWT_SECRET, algorithm="HS256")


# ---- fail-closed environment ------------------------------------------------------------------

def test_environment_defaults_to_production_when_unset(monkeypatch):
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    assert Settings(_env_file=None).ENVIRONMENT == "production"


@pytest.mark.parametrize("env", ["production", "staging", "", "prod", "anything-else"])
def test_default_dev_secret_refused_outside_development(monkeypatch, env):
    monkeypatch.setattr(settings, "ENVIRONMENT", env)
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    with pytest.raises(RuntimeError):
        security.verify_security_environment()


@pytest.mark.parametrize("env", ["production", "staging", "unknown"])
def test_dev_bypass_refused_outside_development(monkeypatch, env):
    monkeypatch.setattr(settings, "ENVIRONMENT", env)
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", "a-real-secret-value-0123456789abcdef")
    monkeypatch.setattr(settings, "DEV_BYPASS_AUTH", True)
    with pytest.raises(RuntimeError):
        security.verify_security_environment()


def test_development_environment_is_allowed(monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    security.verify_security_environment()


# ---- token validation -------------------------------------------------------------------------

def test_valid_token_accepted():
    assert security.decode_access_token(_token())["sub"] == "u1"


def test_forged_token_signed_with_default_secret_rejected(monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", "a-real-secret-value-0123456789abcdef")
    assert security.decode_access_token(_token(secret=DEFAULT_SECRET)) is None


def test_wrong_audience_rejected():
    assert security.decode_access_token(_token(aud="something-else")) is None


def test_missing_audience_rejected():
    assert security.decode_access_token(_token(aud=None)) is None


def test_wrong_issuer_rejected():
    assert security.decode_access_token(_token(iss="https://evil.example/auth/v1")) is None


def test_expired_token_rejected():
    assert security.decode_access_token(_token(exp=datetime.now(timezone.utc) - timedelta(seconds=5))) is None


def test_asymmetric_alg_with_unknown_kid_never_falls_back_to_hs256():
    header = _b64({"alg": "RS256", "kid": "does-not-exist", "typ": "JWT"})
    body = _b64({"sub": "u1", "aud": "authenticated", "iss": f"{settings.SUPABASE_URL}/auth/v1", "exp": 9999999999})
    assert security.decode_access_token(f"{header}.{body}.c2ln") is None


def test_alg_none_rejected():
    header = _b64({"alg": "none", "typ": "JWT"})
    body = _b64({"sub": "u1", "aud": "authenticated", "exp": 9999999999})
    assert security.decode_access_token(f"{header}.{body}.") is None


def test_unknown_kids_cannot_force_repeated_jwks_fetches(monkeypatch):
    calls = []

    def fake_get(*a, **k):
        calls.append(1)
        raise httpx.ConnectError("down")

    monkeypatch.setattr(security.httpx, "get", fake_get)
    monkeypatch.setattr(security, "_LAST_JWKS_FETCH", 0.0)
    for i in range(10):
        header = _b64({"alg": "RS256", "kid": f"k{i}", "typ": "JWT"})
        security.decode_access_token(f"{header}.e30.c2ln")
    assert len(calls) <= 1


# ---- rate limiter -----------------------------------------------------------------------------

def _limited_app(**kwargs):
    async def ok(request):
        return PlainTextResponse("ok")

    app = Starlette(routes=[Route("/x", ok)])
    app.add_middleware(RateLimitMiddleware, **kwargs)
    return app


async def _hit(app, n, client=("203.0.113.9", 5000), headers=None, base="http://test"):
    out = []
    async with AsyncClient(transport=ASGITransport(app=app, client=client), base_url=base) as ac:
        for _ in range(n):
            out.append((await ac.get("/x", headers=headers or {})).status_code)
    return out


@pytest.mark.asyncio
async def test_host_header_named_test_does_not_bypass_limit():
    codes = await _hit(_limited_app(max_requests_per_minute=2), 4, base="http://test")
    assert codes == [200, 200, 429, 429]


@pytest.mark.asyncio
async def test_spoofed_forwarded_for_ignored_from_untrusted_client():
    app = _limited_app(max_requests_per_minute=2)
    out = []
    async with AsyncClient(transport=ASGITransport(app=app, client=("203.0.113.9", 1)), base_url="http://x") as ac:
        for i in range(4):
            out.append((await ac.get("/x", headers={"X-Forwarded-For": f"198.51.100.{i}"})).status_code)
    assert out == [200, 200, 429, 429]


@pytest.mark.asyncio
async def test_forwarded_for_honoured_only_from_trusted_proxy():
    app = _limited_app(max_requests_per_minute=1, trusted_proxies=["10.0.0.0/8"])
    out = []
    async with AsyncClient(transport=ASGITransport(app=app, client=("10.0.0.5", 1)), base_url="http://x") as ac:
        out.append((await ac.get("/x", headers={"X-Forwarded-For": "198.51.100.1"})).status_code)
        out.append((await ac.get("/x", headers={"X-Forwarded-For": "198.51.100.2"})).status_code)  # different user
        out.append((await ac.get("/x", headers={"X-Forwarded-For": "198.51.100.1"})).status_code)  # same user again
    assert out == [200, 200, 429]


@pytest.mark.asyncio
async def test_health_is_never_limited():
    async def ok(request):
        return PlainTextResponse("ok")

    app = Starlette(routes=[Route("/health", ok)])
    app.add_middleware(RateLimitMiddleware, max_requests_per_minute=1)
    async with AsyncClient(transport=ASGITransport(app=app, client=("203.0.113.9", 1)), base_url="http://x") as ac:
        assert [(await ac.get("/health")).status_code for _ in range(3)] == [200, 200, 200]


@pytest.mark.asyncio
async def test_limiter_memory_is_bounded():
    mw = RateLimitMiddleware(Starlette(), max_requests_per_minute=5, max_tracked_clients=50)
    for i in range(500):
        mw._record(f"ip-{i}", now=1000.0 + i * 0.001)
    assert len(mw.request_history) <= 50


# ---- the public dev secret can never authenticate against a non-local database ----------------------------------
REMOTE_DB = "postgresql+psycopg://u:p@aws-0-example.pooler.supabase.com:5432/postgres"
REAL_SECRET = "a-real-secret-value-0123456789abcdef"


def _forged(secret=DEFAULT_SECRET, sub="forged-user"):
    return jwt.encode(
        {"sub": sub, "aud": "authenticated", "iss": f"{settings.SUPABASE_URL}/auth/v1",
         "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, secret, algorithm="HS256")


def test_dev_secret_token_is_rejected_when_the_database_is_remote_even_in_development(monkeypatch, caplog):
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    monkeypatch.setattr(settings, "DATABASE_URL", REMOTE_DB)
    with caplog.at_level(logging.WARNING):
        assert security.decode_access_token(_forged()) is None
    assert "jwt_rejected" in caplog.text and "hs256_disabled" in caplog.text


@pytest.mark.parametrize("db_url", [
    "sqlite:///./x.db",
    "postgresql+psycopg://u@127.0.0.1:5432/flowstate_test",
    "postgresql+psycopg://u@localhost:5432/flowstate_test",
])
def test_dev_secret_token_still_works_for_local_development_and_tests(monkeypatch, db_url):
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    monkeypatch.setattr(settings, "DATABASE_URL", db_url)
    assert security.decode_access_token(_forged())["sub"] == "forged-user"


def test_a_real_hs256_secret_is_honoured_against_a_remote_database(monkeypatch):
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", REAL_SECRET)
    monkeypatch.setattr(settings, "DATABASE_URL", REMOTE_DB)
    assert security.decode_access_token(_forged(REAL_SECRET))["sub"] == "forged-user"
    assert security.decode_access_token(_forged(DEFAULT_SECRET)) is None, "the public secret is never valid then"


def test_dev_secret_is_never_valid_outside_development_even_on_a_local_database(monkeypatch):
    monkeypatch.setattr(settings, "ENVIRONMENT", "staging")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    monkeypatch.setattr(settings, "DATABASE_URL", "sqlite:///./x.db")
    assert security.decode_access_token(_forged()) is None


@pytest.mark.asyncio
async def test_forged_login_against_a_remote_database_is_401_and_creates_no_user(monkeypatch):
    from app.db.session import SessionLocal
    from app.models.user import User

    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    monkeypatch.setattr(settings, "SUPABASE_JWT_SECRET", DEFAULT_SECRET)
    monkeypatch.setattr(settings, "DATABASE_URL", REMOTE_DB)
    ghost = f"forged-{uuid.uuid4().hex[:8]}"
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        for path in ("/api/v1/today", "/api/v1/auth/me", "/api/v1/ai/status"):
            res = await ac.get(path, headers={"Authorization": f"Bearer {_forged(sub=ghost)}"})
            assert res.status_code == 401, (path, res.status_code)
    with SessionLocal() as db:
        assert db.query(User).filter(User.id == ghost).first() is None, "a rejected login must not provision a user"
