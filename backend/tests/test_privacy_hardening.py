"""Signed unsubscribe links, retired client-trusting purchase endpoints, and PII-free logs."""
import logging

import pytest

from app.api.routes import auth as auth_routes
from app.db.session import SessionLocal
from app.models.user import User

from .plan_helpers import client, make_user


def _marketing_enabled(uid: str) -> bool:
    db = SessionLocal()
    try:
        return bool(db.query(User).filter(User.id == uid).first().marketing_emails_enabled)
    finally:
        db.close()


def _enable_marketing(uid: str):
    db = SessionLocal()
    try:
        db.query(User).filter(User.id == uid).update({"marketing_emails_enabled": True})
        db.commit()
    finally:
        db.close()


@pytest.mark.asyncio
async def test_unsubscribe_by_bare_email_no_longer_works():
    uid, _ = make_user()
    _enable_marketing(uid)
    async with client() as ac:
        res = await ac.get(f"/api/v1/auth/unsubscribe?email={uid}@flowstate.local")
    assert res.status_code == 400
    assert _marketing_enabled(uid) is True


@pytest.mark.asyncio
async def test_signed_unsubscribe_token_works_and_does_not_echo_email():
    uid, _ = make_user()
    _enable_marketing(uid)
    token = auth_routes.make_unsubscribe_token(f"{uid}@flowstate.local")
    async with client() as ac:
        res = await ac.get(f"/api/v1/auth/unsubscribe?token={token}")
        assert res.status_code == 200
        assert uid not in res.text
        assert "@" not in res.text
        assert (await ac.post(f"/api/v1/auth/unsubscribe?token={token}")).status_code == 200
    assert _marketing_enabled(uid) is False


@pytest.mark.asyncio
async def test_tampered_unsubscribe_token_rejected():
    uid, _ = make_user()
    _enable_marketing(uid)
    token = auth_routes.make_unsubscribe_token(f"{uid}@flowstate.local")
    forged = token[:-4] + ("AAAA" if not token.endswith("AAAA") else "BBBB")
    other = auth_routes.make_unsubscribe_token("someone-else@flowstate.local").split(".")[0] + "." + token.split(".")[1]
    async with client() as ac:
        for bad in (forged, other, "garbage", ""):
            assert (await ac.get(f"/api/v1/auth/unsubscribe?token={bad}")).status_code == 400
    assert _marketing_enabled(uid) is True


@pytest.mark.asyncio
@pytest.mark.parametrize("path,body", [
    ("/api/v1/subscription/verify", {"purchase_token": "x" * 40, "product_id": "flowstate_pro_monthly"}),
    ("/api/v1/subscription/streak-recover", {"purchase_token": "x" * 40, "cost_inr": 0}),
])
async def test_client_driven_purchase_endpoints_are_retired(path, body):
    _, headers = make_user()
    async with client() as ac:
        res = await ac.post(path, headers=headers, json=body)
        assert res.status_code == 410
        assert (await ac.get("/api/v1/ai/status", headers=headers)).json()["is_pro"] is False


def test_streak_recovery_schema_has_no_client_price():
    from app.schemas.ai import StreakRecoveryRequest

    assert "cost_inr" not in StreakRecoveryRequest.model_fields


@pytest.mark.asyncio
async def test_web_deletion_logs_do_not_contain_the_email(caplog):
    caplog.set_level(logging.DEBUG)
    async with client() as ac:
        await ac.post("/delete-account", data={"email": "private.person@example.com"})
    assert "private.person@example.com" not in caplog.text
