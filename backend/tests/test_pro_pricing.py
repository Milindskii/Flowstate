"""Phase 4: Pro at ₹89/month, shown as ₹2.97/day with the monthly billing disclosed; entitlement stays server-owned."""
import pytest
from httpx import ASGITransport, AsyncClient

from app.core import economy_config as eco
from app.main import app
from tests.plan_helpers import make_user


def test_price_is_defined_once_and_the_daily_figure_is_exact():
    assert eco.PRO_MONTHLY_PRICE_INR == 89
    assert eco.pro_daily_price_display() == "₹2.97/day"       # 89 / 30 = 2.9666... -> 2.97
    assert eco.pro_billing_disclosure() == "₹89 billed monthly"


def test_daily_rounding_is_half_up_not_truncated(monkeypatch):
    monkeypatch.setattr(eco, "PRO_MONTHLY_PRICE_INR", 90)
    assert eco.pro_daily_price_display() == "₹3.00/day"
    monkeypatch.setattr(eco, "PRO_MONTHLY_PRICE_INR", 100)
    assert eco.pro_daily_price_display() == "₹3.33/day"


@pytest.mark.asyncio
async def test_plans_endpoint_serves_the_centralized_price():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        r = await ac.get("/api/v1/subscription/plans")
    assert r.status_code == 200
    plans = r.json()
    assert [p["plan_id"] for p in plans] == ["flowstate_pro_monthly"]      # no yearly price was ever set
    p = plans[0]
    assert p["monthly_price_inr"] == 89 and p["price_display"] == "₹89 / month"
    assert p["daily_price_display"] == "₹2.97/day"
    assert p["billing_disclosure"] == "₹89 billed monthly"                 # never the daily figure alone
    assert p["purchasable"] is False                                       # billing is not live: the app must not imply it
    assert "₹—" not in str(p) and "coming_soon" not in str(p)


@pytest.mark.asyncio
async def test_a_client_can_never_grant_itself_pro():
    uid, h = make_user()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        for path, body in (
            ("/api/v1/subscription/verify", {"purchase_token": "x" * 40, "product_id": "flowstate_pro_monthly"}),
            ("/api/v1/subscription/streak-recover", {"purchase_token": "x" * 40}),
        ):
            r = await ac.post(path, headers=h, json=body)
            assert r.status_code == 410
        st = await ac.get("/api/v1/subscription/status", headers=h)
        assert st.json()["is_pro"] is False
        ai = await ac.get("/api/v1/ai/status", headers=h)
        assert ai.json()["is_pro"] is False and ai.json()["subscription_tier"] == "free"
