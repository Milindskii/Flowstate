"""Shields earned outside the free refill: rewarded ads (AdMob SSV) and the paid pack (Google Play Billing).

Nothing here trusts the app:
  * an ad pays only when Google's SIGNED server-side verification callback names one of our pending ad sessions; a
    dismissed or unverified ad never produces a callback, so it never pays. Each AdMob transaction pays at most once
    (unique), each session at most once (pending -> verified, compare-and-set), and at most the daily limit counts;
  * a pack pays only after the Google Play Developer API confirms the purchase token is purchased, unconsumed and was
    bought by THIS account (obfuscatedExternalAccountId); a token pays at most once (unique) and is then consumed.

Grants go through shield_ledger (free ad Shields are capped at MAX_FREE_SHIELDS, paid ones are not) and leave an audit
row in flow_economic_events in the same transaction.
"""
import base64
import hashlib
import json
import logging
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, List, Optional
from urllib.parse import parse_qsl

import httpx
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..core import economy_config as econ
from ..core.config import settings
from ..models.flow_progression import FlowEconomicEvent, FlowProfile
from ..models.shield_reward import ShieldAdSession, ShieldPurchase
from . import shield_ledger

logger = logging.getLogger("flowstate")


class RewardError(Exception):
    """A refusal the API turns into an HTTP error. `code` is machine-readable; `message` is safe to show."""

    def __init__(self, http_status: int, code: str, message: str):
        super().__init__(message)
        self.http_status = http_status
        self.code = code
        self.message = message


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# ---- configuration (env overrides economy_config) --------------------------------------------------------------------

def ads_per_reward() -> int:
    return max(1, settings.SHIELD_ADS_PER_REWARD or econ.ADS_PER_SHIELD_REWARD)


def ads_daily_limit() -> int:
    return max(1, settings.SHIELD_ADS_DAILY_LIMIT or econ.ADS_DAILY_LIMIT)


def ads_configured() -> bool:
    return bool(settings.SHIELD_ADS_ENABLED and settings.ADMOB_REWARDED_AD_UNIT_ID)


def pack_configured() -> bool:
    return bool(settings.SHIELD_PACK_ENABLED and settings.GOOGLE_PLAY_PACKAGE_NAME
                and settings.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE)


def account_ref(user_id: str) -> str:
    """The opaque id the app passes to Google Play as obfuscatedAccountId (64 hex chars, no personal data). The server
    requires it on every purchase it verifies, so a token bought by one account cannot pay another."""
    return hashlib.sha256(f"flowstate-account:{user_id}".encode("utf-8")).hexdigest()


# ---- wallet (what every Shield surface shows) ------------------------------------------------------------------------

def _day_start(now: datetime) -> datetime:
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _ads_today(db: Session, user_id: str, now: datetime) -> int:
    return int(db.execute(
        select(func.count()).select_from(ShieldAdSession).where(
            ShieldAdSession.user_id == user_id, ShieldAdSession.status == "verified",
            ShieldAdSession.verified_at >= _day_start(now))
    ).scalar_one())


def ad_offer(db: Session, user_id: str, profile: Optional[FlowProfile] = None, now: Optional[datetime] = None) -> Dict[str, Any]:
    now = now or _utcnow()
    if profile is None:
        profile = db.execute(select(FlowProfile).where(FlowProfile.user_id == user_id)).scalar_one_or_none()
    needed = ads_per_reward()
    today = _ads_today(db, user_id, now)
    limit = ads_daily_limit()
    return {
        "enabled": ads_configured(),
        "ad_unit_id": settings.ADMOB_REWARDED_AD_UNIT_ID or None,
        "ads_per_reward": needed,
        "shields_per_reward": econ.SHIELDS_PER_AD_REWARD,
        "progress": min(needed, int(getattr(profile, "ad_reward_progress", 0) or 0)),
        "ads_today": today,
        "daily_limit": limit,
        "daily_remaining": max(0, limit - today),
    }


def pack_offer(user_id: str) -> Dict[str, Any]:
    return {
        "enabled": pack_configured(),
        "store": "google_play",
        "product_id": econ.SHIELD_PACK_PRODUCT_ID,
        "price_inr": econ.SHIELD_PACK_PRICE_INR,
        "price_display": f"₹{econ.SHIELD_PACK_PRICE_INR}",
        "units": econ.SHIELD_PACK_UNITS,
        "account_ref": account_ref(user_id),
    }


def history(db: Session, user_id: str, limit: int = 30) -> List[Dict[str, Any]]:
    """The account's Shield transactions, newest first: grants and streak spends from the economic ledger, AI charges
    and refunds from the AI request log. Read-only."""
    from ..models.ai_usage import AIRequest

    kinds = {
        econ.ONBOARDING_SHIELDS_EVENT: "welcome", "shield_refill": "free_refill", "shield_streak_award": "streak_reward",
        "challenge_claim": "quest_reward", "shield_ad_reward": "ad_reward", "shield_purchase": "purchase",
        "shield_used": "streak_shield", "streak_restore": "streak_restore",
    }
    rows: List[Dict[str, Any]] = []
    for ev in db.execute(
        select(FlowEconomicEvent).where(FlowEconomicEvent.user_id == user_id,
                                        FlowEconomicEvent.event_type.in_(tuple(kinds)))
        .order_by(FlowEconomicEvent.created_at.desc()).limit(limit)
    ).scalars():
        try:
            meta = json.loads(ev.metadata_json or "{}")
        except ValueError:
            meta = {}
        delta = meta.get("shields")
        if delta is None:
            delta = {"shield_refill": 1, "shield_streak_award": 1, "shield_used": -1}.get(ev.event_type, 0)
        if ev.event_type == "challenge_claim" and not meta.get("shields"):
            continue  # a quest that paid Flow points only
        rows.append({"kind": kinds[ev.event_type], "shields": int(delta), "at": ev.created_at})
    for req in db.execute(
        select(AIRequest).where(AIRequest.user_id == user_id, AIRequest.charge_source == "shield")
        .order_by(AIRequest.created_at.desc()).limit(limit)
    ).scalars():
        units = int(req.charge_units or 1)
        label = "replan" if req.kind == "replan" else "build_my_day"
        if req.status == "succeeded":
            rows.append({"kind": label, "shields": -units, "at": req.created_at})
        elif req.status in ("failed", "expired"):
            rows.append({"kind": f"{label}_refunded", "shields": 0, "at": req.created_at})
        else:
            rows.append({"kind": f"{label}_reserved", "shields": -units, "at": req.created_at})

    def _key(r):
        at = r["at"]
        return at.replace(tzinfo=timezone.utc) if at is not None and at.tzinfo is None else (at or datetime.min.replace(tzinfo=timezone.utc))
    rows.sort(key=_key, reverse=True)
    return rows[:limit]


# ---- rewarded ads -----------------------------------------------------------------------------------------------------

def create_ad_session(db: Session, user_id: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    """Start one rewarded-ad showing. The returned id goes to AdMob as the SSV custom_data (and the account id as the
    SSV user_id); nothing is granted here."""
    now = now or _utcnow()
    if not ads_configured():
        raise RewardError(503, "ads_unavailable", "Rewarded ads aren't available yet. No Shields were changed.")
    profile = db.execute(select(FlowProfile).where(FlowProfile.user_id == user_id)).scalar_one_or_none()
    if profile is None:
        raise RewardError(404, "no_profile", "Open Flowstate once before watching an ad.")
    if profile.shields_available >= econ.MAX_FREE_SHIELDS:
        raise RewardError(409, "shields_full", "You already hold the most free Shields you can.")
    if _ads_today(db, user_id, now) >= ads_daily_limit():
        raise RewardError(429, "ad_daily_limit", "That's all the ads for today. Come back tomorrow.")
    session = ShieldAdSession(user_id=user_id, status="pending", shields_granted=0, created_at=now)
    db.add(session)
    db.commit()
    return {"session_id": session.id, "ssv_user_id": user_id, "ad_unit_id": settings.ADMOB_REWARDED_AD_UNIT_ID,
            "expires_at": now + timedelta(minutes=econ.AD_SESSION_TTL_MINUTES)}


def ad_session_status(db: Session, user_id: str, session_id: str) -> Dict[str, Any]:
    session = db.execute(select(ShieldAdSession).where(ShieldAdSession.id == session_id,
                                                       ShieldAdSession.user_id == user_id)).scalar_one_or_none()
    if session is None:
        raise RewardError(404, "unknown_session", "That ad session doesn't exist.")
    status = session.status
    if status == "pending" and _aware(session.created_at) + timedelta(minutes=econ.AD_SESSION_TTL_MINUTES) < _utcnow():
        status = "expired"
    return {"session_id": session.id, "status": status, "shields_granted": session.shields_granted}


def _aware(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


# Google's SSV public keys, cached. Tests replace `_fetch_ssv_keys`.
_KEYS_LOCK = threading.Lock()
_KEYS_CACHE: Dict[str, Any] = {"at": 0.0, "keys": {}}
_KEYS_TTL_SECONDS = 24 * 3600


def _fetch_ssv_keys() -> Dict[str, str]:
    resp = httpx.get(settings.ADMOB_SSV_KEYS_URL, timeout=10.0)
    resp.raise_for_status()
    return {str(k["keyId"]): k["pem"] for k in resp.json().get("keys", [])}


def _ssv_key(key_id: str) -> Optional[str]:
    with _KEYS_LOCK:
        fresh = time.monotonic() - _KEYS_CACHE["at"] < _KEYS_TTL_SECONDS
        if not fresh or key_id not in _KEYS_CACHE["keys"]:
            try:
                _KEYS_CACHE["keys"] = _fetch_ssv_keys()
                _KEYS_CACHE["at"] = time.monotonic()
            except Exception as exc:  # network: the callback is refused and Google retries it later
                logger.warning("shield_rewards.ssv_keys_unavailable %s", type(exc).__name__)
                return None
        return _KEYS_CACHE["keys"].get(key_id)


def reset_ssv_key_cache() -> None:
    with _KEYS_LOCK:
        _KEYS_CACHE["at"] = 0.0
        _KEYS_CACHE["keys"] = {}


def _b64url(data: str) -> bytes:
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))


def verify_ssv_signature(raw_query: str) -> Dict[str, str]:
    """Check AdMob's ECDSA signature over the raw query string. Google appends `signature` and `key_id` as the last two
    parameters and signs everything before `&signature=`. Returns the parsed parameters; raises RewardError."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    marker = raw_query.find("&signature=")
    if marker <= 0:
        raise RewardError(400, "ssv_unsigned", "Missing signature.")
    message = raw_query[:marker].encode("utf-8")
    params = dict(parse_qsl(raw_query, keep_blank_values=True))
    signature, key_id = params.get("signature"), params.get("key_id")
    if not signature or not key_id:
        raise RewardError(400, "ssv_unsigned", "Missing signature.")
    pem = _ssv_key(key_id)
    if pem is None:
        raise RewardError(503, "ssv_key_unknown", "Verification key unavailable.")
    try:
        public_key = serialization.load_pem_public_key(pem.encode("utf-8"))
        public_key.verify(_b64url(signature), message, ec.ECDSA(hashes.SHA256()))
    except (InvalidSignature, ValueError, TypeError):
        raise RewardError(400, "ssv_bad_signature", "Invalid signature.")
    return params


def handle_ssv_callback(db: Session, raw_query: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    """AdMob's server-side verification callback. Verifies the signature, then pays the ad session it names at most
    once. Returns the outcome (always 200 to Google once the signature is valid, so it stops retrying)."""
    now = now or _utcnow()
    params = verify_ssv_signature(raw_query)
    session_id = params.get("custom_data") or ""
    ssv_user = params.get("user_id") or ""
    txn = params.get("transaction_id") or ""
    if not txn:
        raise RewardError(400, "ssv_no_transaction", "Missing transaction id.")
    if settings.ADMOB_SSV_AD_UNIT and params.get("ad_unit") != settings.ADMOB_SSV_AD_UNIT:
        logger.warning("shield_rewards.ssv_wrong_ad_unit ad_unit=%s", params.get("ad_unit"))
        return {"outcome": "ignored_ad_unit"}

    if db.execute(select(ShieldAdSession.id).where(ShieldAdSession.transaction_id == txn)).first():
        return {"outcome": "duplicate"}  # Google retried, or a replayed callback: already handled
    session = db.execute(select(ShieldAdSession).where(ShieldAdSession.id == session_id)).scalar_one_or_none()
    if session is None or session.user_id != ssv_user:
        logger.warning("shield_rewards.ssv_unknown_session session=%s", session_id[:40])
        return {"outcome": "unknown_session"}
    if session.status != "pending":
        return {"outcome": "duplicate"}
    if _aware(session.created_at) + timedelta(minutes=econ.AD_SESSION_TTL_MINUTES) < now:
        return {"outcome": "expired"}

    user_id = session.user_id
    over_limit = _ads_today(db, user_id, now) >= ads_daily_limit()
    new_status = "over_limit" if over_limit else "verified"
    claimed = db.execute(
        update(ShieldAdSession).where(ShieldAdSession.id == session.id, ShieldAdSession.status == "pending")
        .values(status=new_status, transaction_id=txn, verified_at=now)
    ).rowcount == 1
    if not claimed:
        db.rollback()
        return {"outcome": "duplicate"}

    granted = 0
    if not over_limit:
        needed = ads_per_reward()
        db.execute(update(FlowProfile).where(FlowProfile.user_id == user_id)
                   .values(ad_reward_progress=FlowProfile.ad_reward_progress + 1))
        # Turn a full set of verified ads into Shields only while there is room under the free cap; otherwise the
        # progress is kept for later. One compare-and-set: two callbacks finishing the same set cannot both pay.
        took = db.execute(
            update(FlowProfile)
            .where(FlowProfile.user_id == user_id, FlowProfile.ad_reward_progress >= needed,
                   FlowProfile.shields_available < econ.MAX_FREE_SHIELDS)
            .values(ad_reward_progress=FlowProfile.ad_reward_progress - needed)
        ).rowcount == 1
        if took:
            granted = shield_ledger.grant_capped(db, user_id, econ.SHIELDS_PER_AD_REWARD)
            db.execute(update(ShieldAdSession).where(ShieldAdSession.id == session.id)
                       .values(shields_granted=granted))
            db.add(FlowEconomicEvent(
                user_id=user_id, idempotency_key=f"shield_ad_reward-{session.id}", event_type="shield_ad_reward",
                reference_id=session.id, flow_awarded=0, xp_awarded=0,
                metadata_json=json.dumps({"shields": granted, "ads": needed, "transaction_id": txn})))
    try:
        db.commit()
    except IntegrityError:  # the same transaction id raced in on another worker
        db.rollback()
        return {"outcome": "duplicate"}
    logger.info("shield_rewards.ad_verified user=%s session=%s status=%s granted=%s", user_id, session.id, new_status, granted)
    return {"outcome": new_status, "shields_granted": granted}


# ---- paid Shield pack (Google Play Billing) --------------------------------------------------------------------------

@dataclass
class PlayPurchase:
    purchase_state: Optional[int]          # 0 purchased, 1 cancelled, 2 pending
    consumption_state: Optional[int]       # 0 not consumed, 1 consumed
    order_id: Optional[str]
    account_ref: Optional[str]             # obfuscatedExternalAccountId
    purchase_type: Optional[int]           # 0 test (license tester), 1 promo, 2 rewarded; absent for a real purchase


class GooglePlayVerifier:
    """Google Play Developer API (androidpublisher v3) with a service account. Tests substitute `verifier`."""

    SCOPE = "https://www.googleapis.com/auth/androidpublisher"
    BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"

    def __init__(self):
        self._token: Optional[str] = None
        self._token_exp = 0.0
        self._lock = threading.Lock()

    def _access_token(self) -> str:
        from jose import jwt

        with self._lock:
            if self._token and time.time() < self._token_exp - 60:
                return self._token
            with open(settings.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE, encoding="utf-8") as fh:
                sa = json.load(fh)
            now = int(time.time())
            assertion = jwt.encode(
                {"iss": sa["client_email"], "scope": self.SCOPE, "aud": sa["token_uri"], "iat": now, "exp": now + 3600},
                sa["private_key"], algorithm="RS256")
            resp = httpx.post(sa["token_uri"], timeout=10.0, data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion})
            resp.raise_for_status()
            body = resp.json()
            self._token = body["access_token"]
            self._token_exp = time.time() + int(body.get("expires_in", 3600))
            return self._token

    def _url(self, product_id: str, token: str) -> str:
        return f"{self.BASE}/{settings.GOOGLE_PLAY_PACKAGE_NAME}/purchases/products/{product_id}/tokens/{token}"

    def get(self, product_id: str, token: str) -> Optional[PlayPurchase]:
        resp = httpx.get(self._url(product_id, token), timeout=10.0,
                         headers={"Authorization": f"Bearer {self._access_token()}"})
        if resp.status_code in (400, 404, 410):
            return None  # Google does not know this token for this product
        resp.raise_for_status()
        b = resp.json()
        return PlayPurchase(purchase_state=b.get("purchaseState"), consumption_state=b.get("consumptionState"),
                            order_id=b.get("orderId"), account_ref=b.get("obfuscatedExternalAccountId"),
                            purchase_type=b.get("purchaseType"))

    def consume(self, product_id: str, token: str) -> bool:
        resp = httpx.post(self._url(product_id, token) + ":consume", timeout=10.0,
                          headers={"Authorization": f"Bearer {self._access_token()}"})
        return resp.status_code in (200, 204)


verifier: Any = GooglePlayVerifier()


def _consume(db: Session, purchase: ShieldPurchase) -> bool:
    try:
        ok = bool(verifier.consume(purchase.product_id, purchase.purchase_token))
    except Exception as exc:
        logger.warning("shield_rewards.consume_failed purchase=%s %s", purchase.id, type(exc).__name__)
        ok = False
    if ok:
        db.execute(update(ShieldPurchase).where(ShieldPurchase.id == purchase.id, ShieldPurchase.status == "granted")
                   .values(status="consumed", consumed_at=_utcnow()))
        db.commit()
    return ok


def verify_pack_purchase(db: Session, user_id: str, *, purchase_token: str, product_id: str) -> Dict[str, Any]:
    """Verify a Shield-pack purchase with Google Play and grant its Shields exactly once."""
    token = (purchase_token or "").strip()
    if product_id != econ.SHIELD_PACK_PRODUCT_ID:
        raise RewardError(400, "unknown_product", "That isn't a Flowstate Shield pack.")
    if len(token) < 10 or len(token) > 4096:
        raise RewardError(400, "invalid_token", "That purchase could not be verified. No Shields were granted.")

    existing = db.execute(select(ShieldPurchase).where(ShieldPurchase.purchase_token == token)).scalar_one_or_none()
    if existing is not None:
        if existing.user_id != user_id:
            raise RewardError(409, "purchase_other_account", "This purchase belongs to another account.")
        if existing.status == "granted":
            _consume(db, existing)  # finish what an earlier call could not
        return {"granted": 0, "already_processed": True, "units": existing.units}

    if not pack_configured():
        raise RewardError(503, "billing_unavailable",
                          "Purchases can't be verified right now. You were not charged Shields and none were granted.")
    try:
        found = verifier.get(product_id, token)
    except Exception as exc:
        logger.warning("shield_rewards.play_verify_unavailable %s", type(exc).__name__)
        raise RewardError(503, "billing_unavailable",
                          "Google Play couldn't confirm the purchase yet. Try again in a moment; nothing was lost.")
    if found is None:
        raise RewardError(402, "purchase_not_found", "Google Play doesn't recognise that purchase. No Shields were granted.")
    if found.purchase_state == 2:
        raise RewardError(409, "purchase_pending", "Your payment is still pending. Shields arrive once it completes.")
    if found.purchase_state != 0:
        raise RewardError(402, "purchase_not_completed", "That purchase was cancelled. No Shields were granted.")
    if found.account_ref != account_ref(user_id):
        raise RewardError(403, "purchase_other_account", "This purchase was made from another account.")
    if found.consumption_state == 1:
        raise RewardError(409, "purchase_already_used", "This purchase was already used.")

    units = econ.SHIELD_PACK_UNITS
    purchase = ShieldPurchase(user_id=user_id, product_id=product_id, purchase_token=token, order_id=found.order_id,
                              units=units, status="granted")
    db.add(purchase)
    try:
        db.flush()  # the unique token is claimed before any Shield moves
        granted = shield_ledger.grant_paid(db, user_id, units)
        db.add(FlowEconomicEvent(
            user_id=user_id, idempotency_key=f"shield_purchase-{purchase.id}", event_type="shield_purchase",
            reference_id=purchase.id, flow_awarded=0, xp_awarded=0,
            metadata_json=json.dumps({"shields": granted, "product_id": product_id, "order_id": found.order_id,
                                      "test_purchase": found.purchase_type == 0})))
        db.commit()
    except IntegrityError:  # the same token raced in from a second tap or device
        db.rollback()
        return {"granted": 0, "already_processed": True, "units": units}
    logger.info("shield_rewards.pack_granted user=%s purchase=%s units=%s", user_id, purchase.id, granted)
    _consume(db, purchase)
    return {"granted": granted, "already_processed": False, "units": units}
