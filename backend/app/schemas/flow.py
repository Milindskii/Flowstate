from typing import Optional, List
from datetime import datetime, timezone
from pydantic import BaseModel, Field, ConfigDict
from ..core.economy_config import MAX_FREE_SHIELDS

class FlowWeeklyProgressResponse(BaseModel):
    week_identifier: str
    sessions_completed: int = 0
    focus_minutes_logged: int = 0
    priority_tasks_completed: int = 0
    feedback_given: int = 0
    flow_points_earned: int = 0
    adaptive_session_target: int = 3
    adaptive_minutes_target: int = 60
    weekly_goal_hit: bool = False

class PurchaseCompanionResponse(BaseModel):
    species: str
    name: str
    flow_spent: int
    new_balance: int
    message: str

class FlowCompanionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    species: str
    name: str
    level: int
    stage: str
    companion_xp: int
    xp_to_next_level: int
    is_evolution_ready: bool
    is_active: bool
    cosmetic_state: str

class FlowProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: str
    flow_balance: int
    lifetime_flow: int
    current_streak: int
    longest_streak: int
    streak_start_date: Optional[str] = None
    last_qualifying_date: Optional[str] = None
    shield_progress_days: int
    shields_available: int
    shields_used_count: int
    last_shield_used_date: Optional[str] = None
    # Free-refill clock (server instants). The app counts down to `shield_refill_at` from `server_now`; it never
    # decides eligibility itself.
    shield_refill_at: Optional[datetime] = None
    shield_max: int = MAX_FREE_SHIELDS
    # True once today's streak Shield was activated (the server's local day): the app shows it as active and offers no
    # second activation; the server refuses one anyway.
    shield_active_today: bool = False
    server_now: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    weekly_flow_points: int
    current_week_identifier: Optional[str] = None
    league_tier: str
    is_pro: bool

class FlowChallengeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    week_identifier: str
    title: str
    target_count: int
    current_count: int
    reward_flow: int
    reward_shields: int = 0
    is_completed: bool
    is_claimed: bool
    challenge_type: str

class FlowDailyQuestResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    quest_date: str
    quest_key: str
    title: str
    description: str
    target_count: int
    current_count: int
    reward_flow: int
    is_completed: bool
    is_claimed: bool

class FlowAchievementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    achievement_key: str
    title: str
    description: str
    icon: str
    reward_flow: int
    is_unlocked: bool
    unlocked_at: Optional[datetime] = None

class PersonalProgressResponse(BaseModel):
    personal_best_focus_minutes: int = 0
    weekly_focus_sessions: int = 0
    weekly_focus_minutes: int = 0
    total_focus_minutes: int = 0
    total_sessions_completed: int = 0
    best_focus_day_minutes: int = 0
    consistency_score: str = "Building"
    rhythm_acknowledgement: str = "Start your first flow to build your rhythm with Noya. 🦊"

class LeagueCohortResponse(BaseModel):
    tier: str
    weekly_flow_points: int
    rank: int = 1
    participants_count: int = 1
    is_mock: bool = False
    status_message: str

class StreakRecoveryStatus(BaseModel):
    """Whether the account's streak can be restored right now, decided by the server on its own clock."""
    eligible: bool = False
    expired: bool = False            # True when the 7-hour recovery window has expired
    streak: int = 0                  # the streak that would be restored
    missed_days: int = 0
    cost: int = 1                    # Shields the restore costs (server-owned; send it back as expected_cost)
    shields_available: int = 0
    can_afford: bool = False
    reason: Optional[str] = None     # why not eligible: no_streak | not_broken | already_used_today | expired
    deadline_at: Optional[datetime] = None
    seconds_remaining: int = 0       # countdown in seconds during the 7-hour recovery window
    ads_required: int = 5            # Option B: verified ads required to restore
    ads_progress: int = 0            # Option B: verified ads watched so far
    can_restore_with_ads: bool = False


class StreakRestoreRequest(BaseModel):
    idempotency_key: str = Field(..., min_length=8, max_length=100)
    expected_cost: int = Field(1, ge=0, le=100)
    restore_method: str = Field("shield", description="shield or ads")


class StreakRestoreResponse(BaseModel):
    restored: bool
    replayed: bool = False           # the same idempotency key was already applied; nothing was charged again
    current_streak: int
    shields_spent: int
    shields_available: int
    message: str


class FlowOverviewResponse(BaseModel):
    companion: FlowCompanionResponse
    profile: FlowProfileResponse
    streak_recovery: Optional[StreakRecoveryStatus] = None
    active_challenge: Optional[FlowChallengeResponse] = None
    weekly_quests: List[FlowChallengeResponse] = []
    daily_quests: List[FlowDailyQuestResponse] = []
    achievements: List[FlowAchievementResponse] = []
    league: LeagueCohortResponse
    personal_progress: PersonalProgressResponse
    weekly_progress: Optional[FlowWeeklyProgressResponse] = None
    active_session_id: Optional[str] = None
    notification: Optional[str] = None

class ClaimQuestResponse(BaseModel):
    quest_id: str
    flow_awarded: int
    new_balance: int

class StartSessionRequest(BaseModel):
    task_id: Optional[str] = None

class StartSessionResponse(BaseModel):
    session_id: str
    server_start_at: datetime
    status: str

class CompleteSessionRequest(BaseModel):
    task_completed: bool = True
    feeling_score: Optional[int] = None
    idempotency_key: Optional[str] = None

class CompleteSessionResponse(BaseModel):
    session_id: str
    duration_minutes: int
    xp_awarded: int
    flow_awarded: int
    new_level: int
    leveled_up: bool
    evolution_ready: bool
    new_stage: Optional[str] = None
    current_streak: int
    streak_incremented: bool
    shield_awarded: bool
    shield_used: bool
    notification: Optional[str] = None
    companion: FlowCompanionResponse
    profile: FlowProfileResponse

class AbandonSessionResponse(BaseModel):
    session_id: str
    status: str
    companion_status: str
    message: str

class EvolveResponse(BaseModel):
    success: bool
    new_stage: str
    companion: FlowCompanionResponse

class ClaimChallengeResponse(BaseModel):
    challenge_id: str
    flow_awarded: int
    new_balance: int
    shields_awarded: int = 0
    shields_available: Optional[int] = None

class SelectCompanionRequest(BaseModel):
    species: str
    name: Optional[str] = None

class ShopItemResponse(BaseModel):
    species: str
    name: str
    title: Optional[str] = None
    motto: Optional[str] = None
    description: str
    personality: Optional[str] = None
    perk: Optional[str] = None
    accent_color: Optional[str] = None
    emoji: Optional[str] = None
    evolution_line: Optional[List[str]] = None
    is_owned: bool = True
    is_unlocked: bool = True
    flow_cost: int = 0

class UseShieldResponse(BaseModel):
    success: bool
    message: str
    shields_available: int
    current_streak: int
    shield_active_today: bool = True


class DayCompleteClaimRequest(BaseModel):
    date: str  # user-local YYYY-MM-DD
    timezone: Optional[str] = None


class DayCompleteClaimResponse(BaseModel):
    date: str
    claimed: bool
    already_claimed: bool = False
    xp_awarded: int = 0
    companion_xp: int = 0
    level: int = 1
    leveled_up: bool = False
