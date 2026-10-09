"""
Flowstate Progression Economy Configuration.
Central, authoritative source of truth for:
- Companion XP rules
- Flow Points currency rewards & daily frequency caps
- Focus session time bounds
- Level progression curve and stages
- Flow Shield thresholds and inventory caps
- Companion species catalog
"""
import os
from typing import Tuple, Dict, Any, List

# Focus time & XP conversion
COMPANION_XP_PER_FOCUS_MINUTE: int = 1

# Flow Points Rewards
FLOW_REWARD_FOCUS_SESSION: int = 15
FLOW_REWARD_PRIORITY_TASK: int = 20
FLOW_REWARD_FEEDBACK: int = 5
FLOW_REWARD_DAILY_PLAN: int = 25
FLOW_REWARD_PERSONAL_BEST: int = 30
FLOW_REWARD_WEEKLY_CHALLENGE: int = 100

# Anti-Farming & Frequency Caps
MAX_PRIORITY_REWARDS_PER_DAY: int = 3
MIN_TASKS_FOR_DAILY_PLAN: int = 3
MIN_QUALIFYING_FOCUS_MINUTES: int = 1  # Server requires min 1 min of focus for rewards
MIN_QUALIFYING_FOCUS_MINUTES_TEST: int = 1  # For test runs
MAX_FOCUS_MINUTES: int = 180  # Max 3 hours per session to prevent runaway timers

# Anti-Farming & Daily Caps
MAX_XP_PER_DAY: int = 300  # Cap at 5 hours equivalent daily focus XP
MIN_TASK_DURATION_FOR_PRIORITY_BONUS: int = 10  # Task estimate or focus duration must be >= 10 mins

# Flow Shield Limits (100% Free - Earned via 7-day streaks, zero microtransactions)
SHIELD_EARN_DAYS: int = 7
MAX_FREE_SHIELDS: int = 3
INITIAL_SHIELDS: int = 2
# Free refill: while the balance is below MAX_FREE_SHIELDS the account earns one Shield every SHIELD_REFILL_DAYS days.
# The clock is the server's (FlowProfile.shield_refill_at); the device clock never takes part.
SHIELD_REFILL_DAYS: int = 3

# One simple mental model: "Shields pay for Noya's AI planning". There is no separate free trial plan; a new account
# starts with INITIAL_SHIELDS (granted once, recorded in the ledger as ONBOARDING_SHIELDS_EVENT) and each Build My
# Day plan costs SHIELD_COST_BUILD_MY_DAY of them.
FREE_BMD_PLANS: int = 0
ONBOARDING_SHIELDS_EVENT: str = "onboarding_initial_shields"
ONBOARDING_WELCOME_SEEN_EVENT: str = "onboarding_shield_welcome_seen"

# Shields one Build My Day plan costs a free-tier user.
# Server-authoritative (ai_gateway charges exactly this many in one conditional UPDATE); /ai/status reports it
# so the app never hard-codes the price.
SHIELD_COST_BUILD_MY_DAY: int = 1
# Shields one AI Replan costs when the deterministic rules cannot read the request. Rules-only replan costs 0 Shields.
SHIELD_COST_REPLAN: int = 1
# Shields restoring a broken streak costs (POST /flow/streak/restore). The app shows it before the user confirms and
# sends it back as `expected_cost`; the server charges only this value and refuses a stale one.
SHIELD_COST_STREAK_RESTORE: int = 1

# --- Earning Shields beyond the free refill (see services/shield_rewards.py) ------------------------------------------
# Rewarded ads: every ADS_PER_SHIELD_REWARD ads that Google's server-side verification (SSV) confirms add
# SHIELDS_PER_AD_REWARD Shields (capped at MAX_FREE_SHIELDS, like every free grant). At most ADS_DAILY_LIMIT verified
# ads count per account per UTC day; further callbacks are recorded and pay nothing. Values are overridable from the
# environment (Settings.SHIELD_ADS_*), so the "five ads" offer can change without a release.
ADS_PER_SHIELD_REWARD: int = 5
SHIELDS_PER_AD_REWARD: int = 1
ADS_DAILY_LIMIT: int = 10
AD_SESSION_TTL_MINUTES: int = 60   # an ad session that Google has not confirmed by then can no longer pay

# Paid Shield pack (Google Play Billing, consumable). Granted only after the server verifies the purchase token with the
# Google Play Developer API; paid Shields are NOT capped at MAX_FREE_SHIELDS (the user paid for them).
SHIELD_PACK_PRODUCT_ID: str = "flowstate_shield_pack_20"
SHIELD_PACK_PRICE_INR: int = 20
SHIELD_PACK_UNITS: int = 5        # product decision: confirm before launch (Play Console price must say the same)

# Build My Day input limit. ONE value, server-authoritative: /ai/status reports it, the app counter shows it, and
# /ai/plan enforces it before any Shield is reserved or any model is called. PROVISIONAL until
# the paced benchmark (backend/scripts/bmd_limit_benchmark.py, docs/superpowers/plans/bmd-limit-benchmark-run2.md):
# 150 words was clean, 250-350 had tail-latency risk, 450 timed out. 200 sits under the observed knee with headroom.
# Words are what the user sees; the character cap is the backstop for text without spaces (CJK, one giant token).
BMD_MAX_INPUT_WORDS: int = int(os.getenv("BMD_MAX_INPUT_WORDS", "200"))  # env-overridable; /ai/status tells the app
BMD_MAX_INPUT_CHARS: int = BMD_MAX_INPUT_WORDS * 8


def input_limit_for(*, is_pro: bool = False) -> int:
    """Words one Build My Day dump may hold. Basic and Pro share a limit for now; a Pro tier changes only this."""
    return BMD_MAX_INPUT_WORDS

# Flowstate Pro pricing. The ONLY place the price lives: /subscription/plans serves it, the app displays what it
# gets (its offline fallback mirrors these numbers in lib/models/pricing_config.dart). Entitlement is never derived
# from this file or from anything the client says; it comes from the server-verified subscription record.
PRO_MONTHLY_PRICE_INR: int = 89
PRO_YEARLY_PRICE_INR: int = 999
PRO_PRICING_DAYS_PER_MONTH: int = 30   # the monthly daily figure is the monthly price spread over a 30-day month
PRO_PRICING_DAYS_PER_YEAR: int = 365   # the yearly daily figure is the yearly price spread over 365 days


def _daily_display(price_inr: int, days: int) -> str:
    from decimal import Decimal, ROUND_HALF_UP
    daily = (Decimal(price_inr) / Decimal(days)).quantize(Decimal("0.01"), ROUND_HALF_UP)
    return f"₹{daily}/day"


def pro_daily_price_display() -> str:
    """"₹2.97/day": monthly price / 30, rounded half-up to the paisa. Always shown WITH the monthly billing line."""
    return _daily_display(PRO_MONTHLY_PRICE_INR, PRO_PRICING_DAYS_PER_MONTH)


def pro_billing_disclosure() -> str:
    return f"₹{PRO_MONTHLY_PRICE_INR} billed monthly"


def pro_yearly_daily_price_display() -> str:
    """"₹2.74/day": yearly price / 365, rounded half-up. Always shown WITH the yearly billing line."""
    return _daily_display(PRO_YEARLY_PRICE_INR, PRO_PRICING_DAYS_PER_YEAR)


def pro_yearly_billing_disclosure() -> str:
    return f"₹{PRO_YEARLY_PRICE_INR} billed yearly"


# Level Progression Table (Deterministic XP thresholds)
# Level 1: 0, Level 2: 60, Level 3: 150, Level 4: 270, Level 5: 420 (Young evolution)
LEVEL_THRESHOLDS: List[int] = [
    0,      # Level 1
    60,     # Level 2
    150,    # Level 3
    270,    # Level 4
    420,    # Level 5 (Young)
    600,    # Level 6
    810,    # Level 7
    1050,   # Level 8
    1320,   # Level 9
    1620,   # Level 10 (Explorer)
    1950,   # Level 11
    2310,   # Level 12
    2700,   # Level 13
    3120,   # Level 14
    3570,   # Level 15
    4050,   # Level 16
    4560,   # Level 17
    5100,   # Level 18
    5670,   # Level 19
    6270,   # Level 20 (Adult)
]

def get_cumulative_xp_for_level(level: int) -> int:
    """Returns total XP required to reach the given level."""
    if level <= 1:
        return 0
    if level <= len(LEVEL_THRESHOLDS):
        return LEVEL_THRESHOLDS[level - 1]
    # For levels beyond table, compute scaling increment
    last = LEVEL_THRESHOLDS[-1]
    for lvl in range(len(LEVEL_THRESHOLDS) + 1, level + 1):
        step = 600 + (lvl - len(LEVEL_THRESHOLDS)) * 30
        last += step
    return last

MAX_LEVEL: int = 100  # Level 1 is Baby Noya, level 100 is Super Noya. XP past the cap is kept but never levels further.


def get_level_for_xp(xp: int) -> Tuple[int, int, int]:
    """
    Given total cumulative XP, returns:
    (current_level, xp_into_current_level, xp_needed_for_next_level)

    At MAX_LEVEL there is no next level: xp_needed_for_next_level is 0 (the app shows a full bar).
    """
    if xp < 0:
        xp = 0
    level = 1
    while level < MAX_LEVEL:
        next_xp = get_cumulative_xp_for_level(level + 1)
        if xp < next_xp:
            current_level_base = get_cumulative_xp_for_level(level)
            return level, xp - current_level_base, next_xp - current_level_base
        level += 1
    return MAX_LEVEL, xp - get_cumulative_xp_for_level(MAX_LEVEL), 0

# Stages
STAGE_BABY = "Baby"
STAGE_YOUNG = "Young"
STAGE_EXPLORER = "Explorer"
STAGE_ADULT = "Adult"
STAGE_EVOLVED = "Evolved"
STAGE_SUPER = "Super"  # level 100: Super Noya
STAGES = ["Baby", "Young", "Explorer", "Adult", "Evolved", "Super"]

def get_stage_for_level(level: int) -> str:
    if level < 5:
        return STAGE_BABY
    elif level < 10:
        return STAGE_YOUNG
    elif level < 20:
        return STAGE_EXPLORER
    elif level < 35:
        return STAGE_ADULT
    elif level < MAX_LEVEL:
        return STAGE_EVOLVED
    else:
        return STAGE_SUPER

def check_evolution_ready(level: int, current_stage: str) -> bool:
    """Checks if companion has reached the level threshold for next stage evolution."""
    target_stage = get_stage_for_level(level)
    stages = STAGES
    current_idx = stages.index(current_stage) if current_stage in stages else 0
    target_idx = stages.index(target_stage) if target_stage in stages else 0
    return target_idx > current_idx

def get_next_stage(current_stage: str) -> str:
    stages = STAGES
    current_idx = stages.index(current_stage) if current_stage in stages else 0
    if current_idx < len(stages) - 1:
        return stages[current_idx + 1]
    return current_stage

# Companion Catalog with rich detail & personality profiles
COMPANION_CATALOG: List[Dict[str, Any]] = [
    {
        "species": "fox",
        "name": "Noya",
        "title": "The Swift Sprinter",
        "motto": "Light on your feet, sharp in your mind.",
        "description": "Curious, agile, and razor-sharp. Noya thrives during high-energy focus windows and quick sprint bursts.",
        "personality": "Alert, curious, encouraging, and playful. Noya nudges you gently when you drift and celebrates small wins.",
        "perk": "Sprint Mastery (+15% focus clarity during 25m Pomodoro sprints)",
        "accent_color": "#F97316",
        "emoji": "🦊",
        "evolution_line": ["Kit Noya", "Swift Noya", "Nomad Noya", "Astral Fox", "Celestial Kitsune"],
        "is_owned": True,
        "is_unlocked": True,
        "flow_cost": 0,
    },
    {
        "species": "otter",
        "name": "Ludo",
        "title": "The Flow Navigator",
        "motto": "Smooth waters run deep. Drift with the current, not the chaos.",
        "description": "Playful, resilient, and fluid. Ludo washes away anxiety and keeps your focus rhythm smooth over long blocks.",
        "personality": "Grounded, adaptable, cheerful, and smooth. Keeps momentum steady and turns challenging tasks into enjoyable play.",
        "perk": "Deep Current (Maintains steady momentum through 45–60m continuous sessions)",
        "accent_color": "#06B6D4",
        "emoji": "🦦",
        "evolution_line": ["Pup Ludo", "River Ludo", "Wave Ludo", "Torrent Otter", "Tide Sovereign"],
        "is_owned": False,
        "is_unlocked": False,
        "flow_cost": 250,
    },
    {
        "species": "owl",
        "name": "Aria",
        "title": "The Deep Scholar",
        "motto": "Silence cuts through distraction. Insight arrives in stillness.",
        "description": "Calm, observant, and wise. Aria masters late-night or early-morning uninterrupted deep work and intricate problem solving.",
        "personality": "Serene, observant, dignified, and perceptive. Helps you eliminate ambient noise and spot breakthroughs.",
        "perk": "Night Owl & Insight (Peak clarity during complex problem-solving and quiet study)",
        "accent_color": "#8B5CF6",
        "emoji": "🦉",
        "evolution_line": ["Owlet Aria", "Fledgling Aria", "Nightwing Aria", "Archon Owl", "Celestial Seraph"],
        "is_owned": False,
        "is_unlocked": False,
        "flow_cost": 350,
    },
    {
        "species": "capybara",
        "name": "Boba",
        "title": "The Zen Anchor",
        "motto": "Nothing is an emergency. Stay centered and steady.",
        "description": "Unshakeable serenity and warmth. Boba is the ultimate antidote to deadline panic and high-friction backlogs.",
        "personality": "Peaceful, warm, unbothered, and steadfast. Balances heavy workloads with emotional calm.",
        "perk": "Stress Immunity (Eliminates overwhelm when tackling high-priority backlogs)",
        "accent_color": "#10B981",
        "emoji": "🐾",
        "evolution_line": ["Bean Boba", "Warm Spring Boba", "Grove Boba", "Elder Capy", "Nirvana Sovereign"],
        "is_owned": False,
        "is_unlocked": False,
        "flow_cost": 500,
    },
]

ACHIEVEMENTS_CATALOG: List[Dict[str, Any]] = [
    {
        "key": "first_spark",
        "title": "First Spark",
        "description": "Complete your very first focus session with Noya.",
        "icon": "bolt",
        "reward_flow": 25,
    },
    {
        "key": "in_the_groove",
        "title": "In the Groove",
        "description": "Maintain a 3-day focus streak.",
        "icon": "local_fire_department",
        "reward_flow": 30,
    },
    {
        "key": "weekly_anchor",
        "title": "Weekly Anchor",
        "description": "Reach a 7-day focus streak without breaking rhythm.",
        "icon": "shield",
        "reward_flow": 50,
    },
    {
        "key": "habit_master",
        "title": "Habit Master",
        "description": "Achieve an unshakeable 30-day focus streak.",
        "icon": "military_tech",
        "reward_flow": 150,
    },
    {
        "key": "decathlon",
        "title": "Decathlon",
        "description": "Complete 10 focused work sessions.",
        "icon": "timer",
        "reward_flow": 40,
    },
    {
        "key": "quarter_century",
        "title": "Quarter Century",
        "description": "Complete 25 focused work sessions.",
        "icon": "stars",
        "reward_flow": 75,
    },
    {
        "key": "centurion",
        "title": "Centurion",
        "description": "Complete 100 focused work sessions.",
        "icon": "workspace_premium",
        "reward_flow": 200,
    },
    {
        "key": "ten_hour_club",
        "title": "Ten Hour Club",
        "description": "Log 10 hours (600 minutes) of deep focused work.",
        "icon": "hourglass_bottom",
        "reward_flow": 60,
    },
    {
        "key": "deep_diver",
        "title": "Deep Diver",
        "description": "Complete a single marathon focus session of 60+ minutes.",
        "icon": "scuba_diving",
        "reward_flow": 50,
    },
    {
        "key": "rhythm_sync",
        "title": "Rhythm Sync",
        "description": "Complete a focus session during your peak focus window.",
        "icon": "light_mode",
        "reward_flow": 30,
    },
    {
        "key": "night_scholar",
        "title": "Night Scholar",
        "description": "Complete a focus session in an evening or quiet window.",
        "icon": "nights_stay",
        "reward_flow": 30,
    },
    {
        "key": "personal_best",
        "title": "Personal Best",
        "description": "Surpass your previous record for longest focus session.",
        "icon": "emoji_events",
        "reward_flow": 50,
    },
]

DAILY_QUESTS_TEMPLATES: List[Dict[str, Any]] = [
    {
        "key": "complete_1_session",
        "title": "Deep Focus",
        "description": "Complete 1 focus session today",
        "target_count": 1,
        "reward_flow": 15,
    },
    {
        "key": "finish_2_tasks",
        "title": "Planned Execution",
        "description": "Finish 2 planned tasks",
        "target_count": 2,
        "reward_flow": 20,
    },
    {
        "key": "give_feedback",
        "title": "Rhythm Calibration",
        "description": "Record session feeling feedback",
        "target_count": 1,
        "reward_flow": 10,
    },
]

# Weekly quests (reset every ISO week, Monday start, in the user's own timezone). The first is the legacy "weekly
# challenge" and stays the app's `active_challenge`.
WEEKLY_QUESTS_TEMPLATES: List[Dict[str, Any]] = [
    {"type": "priority_tasks", "title": "Complete 5 priority tasks", "target_count": 5, "reward_flow": FLOW_REWARD_WEEKLY_CHALLENGE,
     "reward_shields": 1},
    {"type": "focus_sessions", "title": "Finish 4 focus sessions", "target_count": 4, "reward_flow": 60},
    {"type": "focus_minutes", "title": "Focus for 120 minutes", "target_count": 120, "reward_flow": 80},
]

# Every task of a day done: the trophy at the end of the day path (once per user per local date)
DAY_COMPLETE_XP: int = 25


def weekly_quest_reward_shields(challenge_type: str) -> int:
    """Shields the weekly quest of this type pays on claim (server-owned; 0 for a quest that pays none)."""
    for t in WEEKLY_QUESTS_TEMPLATES:
        if t["type"] == challenge_type:
            return int(t.get("reward_shields", 0))
    return 0
