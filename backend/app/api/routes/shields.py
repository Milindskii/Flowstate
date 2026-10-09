"""The Shield wallet and the ways to earn Shields beyond the free refill (see services/shield_rewards.py).

No route here accepts a balance, a cost or a reward amount from the app: the wallet is read-only, an ad pays only from
Google's signed callback, and a pack pays only after Google Play confirms the purchase.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from ...core import economy_config as econ
from ...core.security import get_current_user
from ...db.session import get_db
from ...models.user import User
from ...services import shield_ledger, shield_rewards
from ...services.ai_economy_service import AIEconomyService
from ...services.flow_service import FlowService

router = APIRouter(prefix="/shields", tags=["Shields"])
_flow = FlowService()


class ShieldCosts(BaseModel):
    build_my_day: int
    replan: int
    streak_restore: int


class AdOffer(BaseModel):
    enabled: bool
    ad_unit_id: Optional[str] = None
    ads_per_reward: int
    shields_per_reward: int
    progress: int
    ads_today: int
    daily_limit: int
    daily_remaining: int


class PackOffer(BaseModel):
    enabled: bool
    store: str
    product_id: str
    price_inr: int
    price_display: str
    units: int
    account_ref: str


class ShieldTransaction(BaseModel):
    kind: str
    shields: int
    at: Optional[datetime] = None


class ShieldWallet(BaseModel):
    balance: int
    maximum: int
    next_refill_at: Optional[datetime] = None
    server_now: datetime
    costs: ShieldCosts
    ads: AdOffer
    pack: PackOffer
    history: List[ShieldTransaction] = Field(default_factory=list)


class AdSessionResponse(BaseModel):
    session_id: str
    ssv_user_id: str
    ad_unit_id: str
    expires_at: datetime


class AdSessionStatus(BaseModel):
    session_id: str
    status: str            # pending | verified | over_limit | expired
    shields_granted: int
    wallet: ShieldWallet


class PackVerifyRequest(BaseModel):
    purchase_token: str = Field(..., min_length=1, max_length=4096)
    product_id: str = Field(..., min_length=1, max_length=200)


class PackVerifyResponse(BaseModel):
    granted: int
    already_processed: bool
    units: int
    wallet: ShieldWallet


def _refused(err: shield_rewards.RewardError) -> JSONResponse:
    return JSONResponse(status_code=err.http_status, content={"detail": err.message, "failure_code": err.code})


def _wallet(db: Session, user: User, with_history: bool = False) -> ShieldWallet:
    profile = AIEconomyService.get_or_create_profile(db, user.id)
    status = shield_ledger.sync_refill(db, user.id, profile=profile)
    return ShieldWallet(
        balance=status.balance, maximum=status.maximum, next_refill_at=status.next_refill_at,
        server_now=status.server_now,
        costs=ShieldCosts(build_my_day=econ.SHIELD_COST_BUILD_MY_DAY, replan=econ.SHIELD_COST_REPLAN,
                          streak_restore=econ.SHIELD_COST_STREAK_RESTORE),
        ads=AdOffer(**shield_rewards.ad_offer(db, user.id, profile)),
        pack=PackOffer(**shield_rewards.pack_offer(user.id)),
        history=[ShieldTransaction(**r) for r in shield_rewards.history(db, user.id)] if with_history else [],
    )


@router.get("", response_model=ShieldWallet)
def get_wallet(history: bool = False, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """The server-authoritative Shield balance, every price, and the earn offers (ads, pack)."""
    return _wallet(db, current_user, with_history=history)


@router.post("/ads/sessions", response_model=AdSessionResponse, responses={503: {}, 409: {}, 429: {}})
def start_ad_session(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Register one rewarded ad before it is shown. Grants nothing: only Google's verified callback can."""
    AIEconomyService.get_or_create_profile(db, current_user.id)
    try:
        return shield_rewards.create_ad_session(db, current_user.id)
    except shield_rewards.RewardError as err:
        return _refused(err)


@router.get("/ads/sessions/{session_id}", response_model=AdSessionStatus)
def get_ad_session(session_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Poll after the ad closes: `verified` once Google confirmed the reward (and the wallet shows the result)."""
    try:
        state = shield_rewards.ad_session_status(db, current_user.id, session_id)
    except shield_rewards.RewardError as err:
        return _refused(err)
    return AdSessionStatus(**state, wallet=_wallet(db, current_user))


@router.get("/ads/ssv", include_in_schema=False)
def admob_ssv_callback(request: Request, db: Session = Depends(get_db)) -> Dict[str, Any]:
    """AdMob server-side verification callback (GET, called by Google, not by the app). Signed by Google; the raw
    query string is verified before anything is read from it."""
    try:
        return shield_rewards.handle_ssv_callback(db, request.url.query)
    except shield_rewards.RewardError as err:
        return _refused(err)


@router.post("/purchases/verify", response_model=PackVerifyResponse)
def verify_pack(body: PackVerifyRequest, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Verify a Google Play Shield-pack purchase server-side and grant it exactly once."""
    AIEconomyService.get_or_create_profile(db, current_user.id)
    try:
        result = shield_rewards.verify_pack_purchase(db, current_user.id, purchase_token=body.purchase_token,
                                                      product_id=body.product_id)
    except shield_rewards.RewardError as err:
        return _refused(err)
    return PackVerifyResponse(**result, wallet=_wallet(db, current_user))
