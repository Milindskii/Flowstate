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
MIN_QUALIFYING_FOCUS_MINUTES: int = 5  # Server requires min 5 mins of focus for rewards
MIN_QUALIFYING_FOCUS_MINUTES_TEST: int = 1  # For test runs
MAX_FOCUS_MINUTES: int = 180  # Max 3 hours per session to prevent runaway timers

# Anti-Farming & Daily Caps
MAX_XP_PER_DAY: int = 300  # Cap at 5 hours equivalent daily focus XP
MIN_TASK_DURATION_FOR_PRIORITY_BONUS: int = 10  # Task estimate or focus duration must be >= 10 mins

# Flow Shield Limits (100% Free - Earned via 7-day streaks, zero microtransactions)
SHIELD_EARN_DAYS: int = 7
MAX_FREE_SHIELDS: int = 3
INITIAL_SHIELDS: int = 2

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

def get_level_for_xp(xp: int) -> Tuple[int, int, int]:
    """
    Given total cumulative XP, returns:
    (current_level, xp_into_current_level, xp_needed_for_next_level)
    """
    if xp < 0:
        xp = 0
    level = 1
    while True:
        next_xp = get_cumulative_xp_for_level(level + 1)
        if xp < next_xp:
            current_level_base = get_cumulative_xp_for_level(level)
            xp_into_level = xp - current_level_base
            xp_needed = next_xp - current_level_base
            return level, xp_into_level, xp_needed
        level += 1
        if level >= 100:  # Safety ceiling
            current_level_base = get_cumulative_xp_for_level(level)
            return level, xp - current_level_base, 1000

# Stages
STAGE_BABY = "Baby"
STAGE_YOUNG = "Young"
STAGE_EXPLORER = "Explorer"
STAGE_ADULT = "Adult"
STAGE_EVOLVED = "Evolved"

def get_stage_for_level(level: int) -> str:
    if level < 5:
        return STAGE_BABY
    elif level < 10:
        return STAGE_YOUNG
    elif level < 20:
        return STAGE_EXPLORER
    elif level < 35:
        return STAGE_ADULT
    else:
        return STAGE_EVOLVED

def check_evolution_ready(level: int, current_stage: str) -> bool:
    """Checks if companion has reached the level threshold for next stage evolution."""
    target_stage = get_stage_for_level(level)
    stages = [STAGE_BABY, STAGE_YOUNG, STAGE_EXPLORER, STAGE_ADULT, STAGE_EVOLVED]
    current_idx = stages.index(current_stage) if current_stage in stages else 0
    target_idx = stages.index(target_stage) if target_stage in stages else 0
    return target_idx > current_idx

def get_next_stage(current_stage: str) -> str:
    stages = [STAGE_BABY, STAGE_YOUNG, STAGE_EXPLORER, STAGE_ADULT, STAGE_EVOLVED]
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
