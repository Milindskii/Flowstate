"""Earning Shields beyond the free refill: rewarded ads (AdMob SSV) and the paid pack (Google Play).

Ads: only a callback carrying Google's valid signature over the exact query string pays; it must name a pending ad
session of the same account; each transaction and each session pays at most once (replays, retries, races); five
verified ads (configurable) make one Shield; a daily limit holds; the free cap holds; a dismissed ad (no callback) pays
nothing; ads are refused while unconfigured.

Pack: refused while unconfigured; Google must confirm purchased + unconsumed + bought by THIS account; a token pays
once (replays, a second device, races); paid Shields are not capped; a failed consume is retried on the next call.
"""
import asyncio
import base64
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.core import economy_config as econ
from app.core.config import settings
from app.db.session import SessionLocal
from app.models.flow_progression import FlowEconomicEvent, FlowProfile
from app.models.shield_reward import ShieldAdSession, ShieldPurchase
from app.services import shield_rewards
from app.services.shield_rewards import PlayPurchase, account_ref
from tests.plan_helpers import client, make_user

KEY = ec.generate_private_key(ec.SECP256R1())
OTHER_KEY = ec.generate_private_key(ec.SECP256R1())
KEY_ID = "1234567890"
PEM = KEY.public_key().public_bytes(serialization.Encoding.PEM,
                                    serialization.PublicFormat.SubjectPublicKeyInfo).decode()


@pytest.fixture(autouse=True)
def _configured(monkeypatch):
    monkeypatch.setattr(settings, "SHIELD_ADS_ENABLED", True)
    monkeypatch.setattr(settings, "ADMOB_REWARDED_AD_UNIT_ID", "ca-app-pub-3940256099942544/5224354917")
    monkeypatch.setattr(settings, "ADMOB_SSV_AD_UNIT", "5224354917")
    monkeypatch.setattr(settings, "SHIELD_PACK_ENABLED", True)
    monkeypatch.setattr(settings, "GOOGLE_PLAY_PACKAGE_NAME", "com.flowstate.app")
    monkeypatch.setattr(settings, "GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "unused-in-tests.json")
    monkeypatch.setattr(shield_rewards, "_fetch_ssv_keys", lambda: {KEY_ID: PEM})
    shield_rewards.reset_ssv_key_cache()
    yield
    shield_rewards.reset_ssv_key_cache()


def _signed_query(*, custom_data, user_id, txn, ad_unit="5224354917", key=KEY, key_id=KEY_ID, tamper=None):
    content = (f"ad_network=5450213213286189855&ad_unit={ad_unit}&custom_data={quote(custom_data)}"
               f"&reward_amount=1&reward_item=Shield&timestamp=1760000000000&transaction_id={txn}"
               f"&user_id={quote(user_id)}")
    sig = key.sign(content.encode(), ec.ECDSA(hashes.SHA256()))
    if tamper:
        content = tamper(content)
    return f"{content}&signature={base64.urlsafe_b64encode(sig).decode().rstrip('=')}&key_id={key_id}"


def _set(uid, **values):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        for k, v in values.items():
            setattr(p, k, v)
        db.commit()


def _profile(uid):
    with SessionLocal() as db:
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        return p.shields_available, p.ad_reward_progress


def _events(uid, kind):
    with SessionLocal() as db:
        return db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                  FlowEconomicEvent.event_type == kind).count()


async def _user(ac, shields=0):
    uid, h = make_user()
    await ac.get("/api/v1/shields", headers=h)
    _set(uid, shields_available=shields, shield_refill_at=None)
    return uid, h


async def _watch(ac, uid, h, n=1, txn_prefix=None):
    """Start n ad sessions and deliver Google's signed callback for each. Returns the callback responses."""
    out = []
    for i in range(n):
        sess = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()
        txn = f"{txn_prefix or uid}-{i}-{sess['session_id'][:6]}"
        out.append(await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(
            custom_data=sess["session_id"], user_id=sess["ssv_user_id"], txn=txn)))
    return out


# ---- wallet ----------------------------------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_wallet_is_read_only_and_reports_costs_and_offers():
    async with client() as ac:
        uid, h = await _user(ac, shields=1)
        w = (await ac.get("/api/v1/shields?history=true", headers=h)).json()
    assert w["balance"] == 1 and w["maximum"] == econ.MAX_FREE_SHIELDS
    assert w["costs"] == {"build_my_day": econ.SHIELD_COST_BUILD_MY_DAY, "replan": econ.SHIELD_COST_REPLAN,
                          "streak_restore": econ.SHIELD_COST_STREAK_RESTORE}
    assert w["ads"]["enabled"] and w["ads"]["ads_per_reward"] == econ.ADS_PER_SHIELD_REWARD
    assert w["pack"]["price_inr"] == 20 and w["pack"]["account_ref"] == account_ref(uid)
    assert any(t["kind"] == "welcome" for t in w["history"])


# ---- rewarded ads ----------------------------------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_five_verified_ads_make_one_shield_and_progress_persists():
    async with client() as ac:
        uid, h = await _user(ac)
        await _watch(ac, uid, h, n=4)
        assert _profile(uid) == (0, 4)
        mid = (await ac.get("/api/v1/shields", headers=h)).json()["ads"]
        assert mid["progress"] == 4 and mid["ads_today"] == 4
        last = await _watch(ac, uid, h, n=1, txn_prefix="fifth")
    assert last[0].json() == {"outcome": "verified", "shields_granted": 1}
    assert _profile(uid) == (1, 0)
    assert _events(uid, "shield_ad_reward") == 1


@pytest.mark.asyncio
async def test_offer_size_is_configurable(monkeypatch):
    monkeypatch.setattr(settings, "SHIELD_ADS_PER_REWARD", 2)
    async with client() as ac:
        uid, h = await _user(ac)
        await _watch(ac, uid, h, n=2)
    assert _profile(uid) == (1, 0)


@pytest.mark.asyncio
async def test_a_dismissed_or_unverified_ad_pays_nothing():
    async with client() as ac:
        uid, h = await _user(ac)
        sess = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()
        status = (await ac.get(f"/api/v1/shields/ads/sessions/{sess['session_id']}", headers=h)).json()
    assert status["status"] == "pending" and status["shields_granted"] == 0
    assert _profile(uid) == (0, 0)


@pytest.mark.asyncio
async def test_forged_tampered_or_unsigned_callbacks_are_refused():
    async with client() as ac:
        uid, h = await _user(ac)
        sid = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        forged = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn="t1",
                                                                         key=OTHER_KEY))
        tampered = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(
            custom_data=sid, user_id=uid, txn="t2", tamper=lambda c: c.replace("reward_amount=1", "reward_amount=99")))
        unsigned = await ac.get(f"/api/v1/shields/ads/ssv?custom_data={sid}&user_id={uid}&transaction_id=t3")
        unknown_key = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn="t4",
                                                                              key_id="999"))
    assert forged.status_code == 400 and tampered.status_code == 400 and unsigned.status_code == 400
    assert unknown_key.status_code == 503
    assert _profile(uid) == (0, 0)


@pytest.mark.asyncio
async def test_a_replayed_callback_or_reused_transaction_pays_once():
    async with client() as ac:
        uid, h = await _user(ac)
        sid = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        q = _signed_query(custom_data=sid, user_id=uid, txn="same-txn")
        results = [await ac.get("/api/v1/shields/ads/ssv?" + q) for _ in range(3)]
        sid2 = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        reuse = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid2, user_id=uid, txn="same-txn"))
    assert [r.json()["outcome"] for r in results] == ["verified", "duplicate", "duplicate"]
    assert reuse.json()["outcome"] == "duplicate"
    assert _profile(uid) == (0, 1)


@pytest.mark.asyncio
async def test_concurrent_callbacks_for_one_session_count_once():
    async with client() as ac:
        uid, h = await _user(ac)
        sid = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        res = await asyncio.gather(*[
            ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn=f"race-{i}"))
            for i in range(6)])
    assert sum(1 for r in res if r.json().get("outcome") == "verified") == 1
    assert _profile(uid) == (0, 1)


@pytest.mark.asyncio
async def test_a_session_cannot_pay_another_account_or_a_wrong_ad_unit():
    async with client() as ac:
        uid, h = await _user(ac)
        other, _ = make_user()
        sid = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        stolen = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=other, txn="x1"))
        wrong_unit = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn="x2",
                                                                             ad_unit="111"))
    assert stolen.json()["outcome"] == "unknown_session"
    assert wrong_unit.json()["outcome"] == "ignored_ad_unit"
    assert _profile(uid) == (0, 0)


@pytest.mark.asyncio
async def test_expired_sessions_pay_nothing():
    async with client() as ac:
        uid, h = await _user(ac)
        sid = (await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"]
        with SessionLocal() as db:
            s = db.get(ShieldAdSession, sid)
            s.created_at = datetime.now(timezone.utc) - timedelta(minutes=econ.AD_SESSION_TTL_MINUTES + 1)
            db.commit()
        res = await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn="late"))
    assert res.json()["outcome"] == "expired"
    assert _profile(uid) == (0, 0)


@pytest.mark.asyncio
async def test_the_daily_limit_is_enforced_by_the_server(monkeypatch):
    monkeypatch.setattr(settings, "SHIELD_ADS_DAILY_LIMIT", 3)
    monkeypatch.setattr(settings, "SHIELD_ADS_PER_REWARD", 10)
    async with client() as ac:
        uid, h = await _user(ac)
        pending = [(await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"] for _ in range(4)]
        outcomes = [(await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(
            custom_data=sid, user_id=uid, txn=f"d{i}"))).json()["outcome"] for i, sid in enumerate(pending)]
        refused = await ac.post("/api/v1/shields/ads/sessions", headers=h)
    assert outcomes == ["verified", "verified", "verified", "over_limit"]
    assert refused.status_code == 429
    assert _profile(uid) == (0, 3)


@pytest.mark.asyncio
async def test_ads_never_pass_the_free_cap_and_full_wallets_get_no_ad():
    async with client() as ac:
        uid, h = await _user(ac, shields=econ.MAX_FREE_SHIELDS)
        assert (await ac.post("/api/v1/shields/ads/sessions", headers=h)).status_code == 409
        _set(uid, shields_available=econ.MAX_FREE_SHIELDS - 1)
        sessions = [(await ac.post("/api/v1/shields/ads/sessions", headers=h)).json()["session_id"] for _ in range(5)]
        _set(uid, shields_available=econ.MAX_FREE_SHIELDS)  # filled up meanwhile (e.g. the free refill)
        for i, sid in enumerate(sessions):
            await ac.get("/api/v1/shields/ads/ssv?" + _signed_query(custom_data=sid, user_id=uid, txn=f"cap{i}"))
    assert _profile(uid) == (econ.MAX_FREE_SHIELDS, 5), "progress is kept, never paid past the cap"


@pytest.mark.asyncio
async def test_ads_are_refused_while_not_configured(monkeypatch):
    monkeypatch.setattr(settings, "SHIELD_ADS_ENABLED", False)
    async with client() as ac:
        uid, h = await _user(ac)
        res = await ac.post("/api/v1/shields/ads/sessions", headers=h)
        wallet = (await ac.get("/api/v1/shields", headers=h)).json()
    assert res.status_code == 503 and res.json()["failure_code"] == "ads_unavailable"
    assert wallet["ads"]["enabled"] is False


# ---- paid pack -------------------------------------------------------------------------------------------------------

class FakePlay:
    def __init__(self, purchases=None, consume_ok=True):
        self.purchases = purchases or {}
        self.consume_ok = consume_ok
        self.consumed = []
        self.gets = 0

    def get(self, product_id, token):
        self.gets += 1
        return self.purchases.get(token)

    def consume(self, product_id, token):
        if self.consume_ok:
            self.consumed.append(token)
        return self.consume_ok


def _bought(uid, state=0, consumed=0):
    return PlayPurchase(purchase_state=state, consumption_state=consumed, order_id="GPA.1",
                        account_ref=account_ref(uid), purchase_type=None)


def _verify(ac, h, token, product=econ.SHIELD_PACK_PRODUCT_ID):
    return ac.post("/api/v1/shields/purchases/verify", headers=h, json={"purchase_token": token, "product_id": product})


@pytest.mark.asyncio
async def test_a_verified_purchase_grants_the_pack_once_uncapped_and_is_consumed(monkeypatch):
    async with client() as ac:
        uid, h = await _user(ac, shields=econ.MAX_FREE_SHIELDS)
        play = FakePlay({"tok-good-123": _bought(uid)})
        monkeypatch.setattr(shield_rewards, "verifier", play)
        first = await _verify(ac, h, "tok-good-123")
        again = await _verify(ac, h, "tok-good-123")
    assert first.status_code == 200, first.text
    assert first.json()["granted"] == econ.SHIELD_PACK_UNITS
    assert first.json()["wallet"]["balance"] == econ.MAX_FREE_SHIELDS + econ.SHIELD_PACK_UNITS
    assert again.json()["granted"] == 0 and again.json()["already_processed"] is True
    assert play.consumed == ["tok-good-123"]
    assert _profile(uid)[0] == econ.MAX_FREE_SHIELDS + econ.SHIELD_PACK_UNITS
    assert _events(uid, "shield_purchase") == 1


@pytest.mark.asyncio
async def test_concurrent_verifications_of_one_token_grant_once(monkeypatch):
    async with client() as ac:
        uid, h = await _user(ac)
        monkeypatch.setattr(shield_rewards, "verifier", FakePlay({"tok-race-123": _bought(uid)}))
        res = await asyncio.gather(*[_verify(ac, h, "tok-race-123") for _ in range(5)])
    assert all(r.status_code == 200 for r in res)
    assert sum(r.json()["granted"] for r in res) == econ.SHIELD_PACK_UNITS
    assert _profile(uid)[0] == econ.SHIELD_PACK_UNITS


@pytest.mark.asyncio
async def test_unverified_cancelled_pending_consumed_or_foreign_purchases_grant_nothing(monkeypatch):
    async with client() as ac:
        uid, h = await _user(ac)
        other, h_other = await _user(ac)
        play = FakePlay({
            "tok-cancelled-1": _bought(uid, state=1),
            "tok-pending-12": _bought(uid, state=2),
            "tok-consumed-1": _bought(uid, consumed=1),
            "tok-for-other": _bought(other),
        })
        monkeypatch.setattr(shield_rewards, "verifier", play)
        codes = {
            "unknown": (await _verify(ac, h, "tok-not-known")).status_code,
            "cancelled": (await _verify(ac, h, "tok-cancelled-1")).status_code,
            "pending": (await _verify(ac, h, "tok-pending-12")).status_code,
            "consumed": (await _verify(ac, h, "tok-consumed-1")).status_code,
            "foreign": (await _verify(ac, h, "tok-for-other")).status_code,
            "wrong_product": (await _verify(ac, h, "tok-for-other", product="flowstate_pro_monthly")).status_code,
            "short": (await _verify(ac, h, "abc")).status_code,
        }
        ok_other = await _verify(ac, h_other, "tok-for-other")
        stolen = await _verify(ac, h, "tok-for-other")
    assert codes == {"unknown": 402, "cancelled": 402, "pending": 409, "consumed": 409, "foreign": 403,
                     "wrong_product": 400, "short": 400}
    assert ok_other.json()["granted"] == econ.SHIELD_PACK_UNITS
    assert stolen.status_code == 409, "a token already granted to one account never pays another"
    assert _profile(uid)[0] == 0


@pytest.mark.asyncio
async def test_unconfigured_billing_or_google_outage_grants_nothing(monkeypatch):
    async with client() as ac:
        uid, h = await _user(ac)
        monkeypatch.setattr(settings, "SHIELD_PACK_ENABLED", False)
        off = await _verify(ac, h, "tok-anything-1")
        monkeypatch.setattr(settings, "SHIELD_PACK_ENABLED", True)

        class Down(FakePlay):
            def get(self, product_id, token):
                raise RuntimeError("google down")
        monkeypatch.setattr(shield_rewards, "verifier", Down())
        down = await _verify(ac, h, "tok-anything-1")
    assert off.status_code == 503 and off.json()["failure_code"] == "billing_unavailable"
    assert down.status_code == 503
    assert _profile(uid)[0] == 0


@pytest.mark.asyncio
async def test_a_failed_consume_is_retried_without_granting_again(monkeypatch):
    async with client() as ac:
        uid, h = await _user(ac)
        play = FakePlay({"tok-consume-1": _bought(uid)}, consume_ok=False)
        monkeypatch.setattr(shield_rewards, "verifier", play)
        first = await _verify(ac, h, "tok-consume-1")
        play.consume_ok = True
        retry = await _verify(ac, h, "tok-consume-1")
    assert first.json()["granted"] == econ.SHIELD_PACK_UNITS and retry.json()["granted"] == 0
    assert play.consumed == ["tok-consume-1"]
    with SessionLocal() as db:
        assert db.query(ShieldPurchase).filter(ShieldPurchase.user_id == uid).one().status == "consumed"
    assert _profile(uid)[0] == econ.SHIELD_PACK_UNITS


def test_no_route_accepts_a_balance_cost_or_reward_from_the_app():
    from app.main import app
    for path, ops in app.openapi()["paths"].items():
        if "shield" not in path and "streak" not in path:
            continue
        for op in ops.values():
            schema = op.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema", {})
            ref = schema.get("$ref", "").rsplit("/", 1)[-1]
            props = app.openapi()["components"]["schemas"].get(ref, {}).get("properties", {}) if ref else {}
            assert not set(props) & {"shields_available", "balance", "units", "granted", "reward_amount", "cost"}, path
