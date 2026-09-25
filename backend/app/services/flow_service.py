import json
from datetime import datetime, timezone, timedelta
from typing import Tuple, Optional, List
import zoneinfo
from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from ..core.economy_config import (
    COMPANION_XP_PER_FOCUS_MINUTE,
    FLOW_REWARD_FOCUS_SESSION,
    FLOW_REWARD_PRIORITY_TASK,
    FLOW_REWARD_FEEDBACK,
    FLOW_REWARD_WEEKLY_CHALLENGE,
    MAX_PRIORITY_REWARDS_PER_DAY,
    MIN_QUALIFYING_FOCUS_MINUTES,
    MIN_QUALIFYING_FOCUS_MINUTES_TEST,
    MAX_FOCUS_MINUTES,
    SHIELD_EARN_DAYS,
    MAX_FREE_SHIELDS,
    INITIAL_SHIELDS,
    MAX_XP_PER_DAY,
    MIN_TASK_DURATION_FOR_PRIORITY_BONUS,
    get_level_for_xp,
    check_evolution_ready,
    get_next_stage,
    COMPANION_CATALOG,
    DAILY_QUESTS_TEMPLATES,
    ACHIEVEMENTS_CATALOG,
)
from ..models.user import User
from ..models.task import Task
from ..models.user_preferences import UserPreferences
from ..models.flow_progression import (
    FlowCompanion,
    FlowProfile,
    FlowFocusSession,
    FlowChallenge,
    FlowEconomicEvent,
    FlowDailyQuest,
    FlowAchievement,
    FlowInventoryItem,
    FlowWeeklyProgress,
    utcnow,
)
from ..schemas.flow import (
    FlowOverviewResponse,
    FlowCompanionResponse,
    FlowProfileResponse,
    FlowChallengeResponse,
    FlowDailyQuestResponse,
    FlowAchievementResponse,
    ClaimQuestResponse,
    LeagueCohortResponse,
    PersonalProgressResponse,
    StartSessionResponse,
    CompleteSessionResponse,
    AbandonSessionResponse,
    EvolveResponse,
    ClaimChallengeResponse,
    ShopItemResponse,
    FlowWeeklyProgressResponse,
    PurchaseCompanionResponse,
    UseShieldResponse,
)

def _make_aware(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt

class FlowService:
    def _get_user_timezone(self, db: Session, user_id: str) -> zoneinfo.ZoneInfo:
        prefs = db.query(UserPreferences).filter(UserPreferences.user_id == user_id).first()
        tz_name = prefs.timezone if prefs and prefs.timezone else "Asia/Kolkata"
        try:
            return zoneinfo.ZoneInfo(tz_name)
        except Exception:
            return zoneinfo.ZoneInfo("Asia/Kolkata")

    def _get_user_today_str(self, user_tz: zoneinfo.ZoneInfo) -> str:
        return datetime.now(user_tz).strftime("%Y-%m-%d")

    def _get_current_week_identifier(self, user_tz: zoneinfo.ZoneInfo) -> str:
        now = datetime.now(user_tz)
        return now.strftime("%Y-W%W")

    def get_or_create_flow_profile(
        self, db: Session, user: User
    ) -> Tuple[FlowProfile, FlowCompanion, FlowChallenge]:
        user_tz = self._get_user_timezone(db, user.id)
        current_week = self._get_current_week_identifier(user_tz)

        profile = db.query(FlowProfile).filter(FlowProfile.user_id == user.id).first()
        if not profile:
            profile = FlowProfile(
                user_id=user.id,
                flow_balance=0,
                lifetime_flow=0,
                current_streak=0,
                longest_streak=0,
                shield_progress_days=0,
                shields_available=INITIAL_SHIELDS, # Initial 2 shields for streak protection and AI economy
                shields_used_count=0,
                weekly_flow_points=0,
                current_week_identifier=current_week,
                league_tier="Bronze",
                is_pro=False,
            )
            db.add(profile)
            db.flush()
        else:
            # Check weekly reset
            if profile.current_week_identifier != current_week:
                profile.weekly_flow_points = 0
                profile.current_week_identifier = current_week
                db.flush()

        companion = (
            db.query(FlowCompanion)
            .filter(FlowCompanion.user_id == user.id, FlowCompanion.is_active == True)
            .first()
        )
        if not companion:
            companion = FlowCompanion(
                user_id=user.id,
                species="fox",
                name="Noya",
                level=1,
                stage="Baby",
                companion_xp=0,
                xp_to_next_level=60,
                is_evolution_ready=False,
                is_active=True,
            )
            db.add(companion)
            db.flush()

        challenge = (
            db.query(FlowChallenge)
            .filter(
                FlowChallenge.user_id == user.id,
                FlowChallenge.week_identifier == current_week,
            )
            .first()
        )
        if not challenge:
            challenge = FlowChallenge(
                user_id=user.id,
                week_identifier=current_week,
                title="Complete 5 priority tasks",
                target_count=5,
                current_count=0,
                reward_flow=FLOW_REWARD_WEEKLY_CHALLENGE,
                is_completed=False,
                is_claimed=False,
                challenge_type="priority_tasks",
            )
            db.add(challenge)
            db.flush()

        db.commit()
        db.refresh(profile)
        db.refresh(companion)
        db.refresh(challenge)
        return profile, companion, challenge

    def get_or_create_daily_quests(self, db: Session, user: User, today_str: str) -> List[FlowDailyQuest]:
        quests = (
            db.query(FlowDailyQuest)
            .filter(
                FlowDailyQuest.user_id == user.id,
                FlowDailyQuest.quest_date == today_str,
            )
            .all()
        )
        if len(quests) < len(DAILY_QUESTS_TEMPLATES):
            existing_keys = {q.quest_key for q in quests}
            for tmpl in DAILY_QUESTS_TEMPLATES:
                if tmpl["key"] not in existing_keys:
                    q = FlowDailyQuest(
                        user_id=user.id,
                        quest_date=today_str,
                        quest_key=tmpl["key"],
                        title=tmpl["title"],
                        description=tmpl["description"],
                        target_count=tmpl["target_count"],
                        current_count=0,
                        reward_flow=tmpl["reward_flow"],
                        is_completed=False,
                        is_claimed=False,
                    )
                    db.add(q)
            db.commit()
            quests = (
                db.query(FlowDailyQuest)
                .filter(
                    FlowDailyQuest.user_id == user.id,
                    FlowDailyQuest.quest_date == today_str,
                )
                .all()
            )
        return quests

    def get_or_create_achievements(self, db: Session, user: User) -> List[FlowAchievement]:
        achievements = (
            db.query(FlowAchievement)
            .filter(FlowAchievement.user_id == user.id)
            .all()
        )
        if len(achievements) < len(ACHIEVEMENTS_CATALOG):
            existing_keys = {a.achievement_key for a in achievements}
            for cat in ACHIEVEMENTS_CATALOG:
                if cat["key"] not in existing_keys:
                    a = FlowAchievement(
                        user_id=user.id,
                        achievement_key=cat["key"],
                        title=cat["title"],
                        description=cat["description"],
                        icon=cat["icon"],
                        reward_flow=cat["reward_flow"],
                        is_unlocked=False,
                    )
                    db.add(a)
            db.commit()
            achievements = (
                db.query(FlowAchievement)
                .filter(FlowAchievement.user_id == user.id)
                .all()
            )
        return achievements

    def _update_daily_quest_progress(
        self, db: Session, user_id: str, today_str: str, quest_key: str, increment: int = 1
    ):
        quest = (
            db.query(FlowDailyQuest)
            .filter(
                FlowDailyQuest.user_id == user_id,
                FlowDailyQuest.quest_date == today_str,
                FlowDailyQuest.quest_key == quest_key,
            )
            .first()
        )
        if quest and not quest.is_completed:
            quest.current_count = min(quest.current_count + increment, quest.target_count)
            if quest.current_count >= quest.target_count:
                quest.is_completed = True
            db.flush()

    def _get_or_create_weekly_progress(
        self,
        db: Session,
        user_id: str,
        week_identifier: str,
    ) -> FlowWeeklyProgress:
        """
        Upserts the weekly progress record for (user, week).
        On first creation, calculates an adaptive session/minute target based on
        the prior 4 completed weeks, clamped between sensible bounds.
        """
        wp = (
            db.query(FlowWeeklyProgress)
            .filter(
                FlowWeeklyProgress.user_id == user_id,
                FlowWeeklyProgress.week_identifier == week_identifier,
            )
            .first()
        )
        if wp:
            return wp

        # Adaptive target: look at prior 4 weeks' session counts
        prior_weeks = (
            db.query(FlowWeeklyProgress)
            .filter(
                FlowWeeklyProgress.user_id == user_id,
                FlowWeeklyProgress.week_identifier != week_identifier,
            )
            .order_by(FlowWeeklyProgress.created_at.desc())
            .limit(4)
            .all()
        )
        if prior_weeks:
            avg_sessions = sum(w.sessions_completed for w in prior_weeks) / len(prior_weeks)
            avg_minutes = sum(w.focus_minutes_logged for w in prior_weeks) / len(prior_weeks)
            # Target = prior avg + 10%, clamped [2, 7] sessions, [30, 210] minutes
            adaptive_sessions = max(2, min(7, round(avg_sessions * 1.1) or 3))
            adaptive_minutes = max(30, min(210, round(avg_minutes * 1.1) or 60))
        else:
            # Brand-new user defaults
            adaptive_sessions = 3
            adaptive_minutes = 60

        wp = FlowWeeklyProgress(
            user_id=user_id,
            week_identifier=week_identifier,
            sessions_completed=0,
            focus_minutes_logged=0,
            priority_tasks_completed=0,
            feedback_given=0,
            flow_points_earned=0,
            adaptive_session_target=adaptive_sessions,
            adaptive_minutes_target=adaptive_minutes,
            weekly_goal_hit=False,
        )
        db.add(wp)
        db.flush()
        return wp

    def _evaluate_achievements(
        self,
        db: Session,
        user: User,
        profile: FlowProfile,
        duration_minutes: int,
    ):
        achievements = self.get_or_create_achievements(db, user)
        ach_map = {a.achievement_key: a for a in achievements}

        completed_sessions = (
            db.query(FlowFocusSession)
            .filter(
                FlowFocusSession.user_id == user.id,
                FlowFocusSession.status == "completed",
            )
            .all()
        )
        total_sessions = len(completed_sessions)
        total_mins = sum((s.duration_minutes or 0) for s in completed_sessions)

        def unlock(key: str):
            ach = ach_map.get(key)
            if ach and not ach.is_unlocked:
                ach.is_unlocked = True
                ach.unlocked_at = utcnow()
                try:
                    event = FlowEconomicEvent(
                        user_id=user.id,
                        idempotency_key=f"ach_{key}_{user.id}",
                        event_type="achievement_unlocked",
                        reference_id=key,
                        flow_awarded=ach.reward_flow,
                        xp_awarded=0,
                        metadata_json=json.dumps({"achievement": key, "title": ach.title}),
                    )
                    db.add(event)
                    profile.flow_balance += ach.reward_flow
                    profile.lifetime_flow += ach.reward_flow
                except Exception:
                    pass

        if total_sessions >= 1:
            unlock("first_spark")
        if total_sessions >= 10:
            unlock("decathlon")
        if total_sessions >= 25:
            unlock("quarter_century")
        if total_sessions >= 100:
            unlock("centurion")
        if total_mins >= 600:
            unlock("ten_hour_club")
        if duration_minutes >= 60:
            unlock("deep_diver")
        if profile.current_streak >= 3:
            unlock("in_the_groove")
        if profile.current_streak >= 7:
            unlock("weekly_anchor")
        if profile.current_streak >= 30:
            unlock("habit_master")

        db.flush()

    def get_overview(self, db: Session, user: User) -> FlowOverviewResponse:
        profile, companion, challenge = self.get_or_create_flow_profile(db, user)
        user_tz = self._get_user_timezone(db, user.id)
        today_str = self._get_user_today_str(user_tz)

        # Ensure daily quests and achievements exist
        daily_quests = self.get_or_create_daily_quests(db, user, today_str)
        achievements = self.get_or_create_achievements(db, user)

        # Check for any active focus session
        active_session = (
            db.query(FlowFocusSession)
            .filter(
                FlowFocusSession.user_id == user.id,
                FlowFocusSession.status == "started",
            )
            .order_by(FlowFocusSession.created_at.desc())
            .first()
        )
        active_session_id = None
        if active_session:
            # Check if not timed out
            elapsed = (utcnow() - _make_aware(active_session.server_start_at)).total_seconds()
            if elapsed <= MAX_FOCUS_MINUTES * 60:
                active_session_id = active_session.id
            else:
                active_session.status = "abandoned"
                db.commit()

        # League representation: strictly no fake real users
        league = LeagueCohortResponse(
            tier=profile.league_tier,
            weekly_flow_points=profile.weekly_flow_points,
            rank=1,
            participants_count=1,
            is_mock=False,
            status_message="Focus on your rhythm. Cohort leagues open when participant quorum is reached.",
        )

        # Real personal progress calculation from user events
        completed_sessions = (
            db.query(FlowFocusSession)
            .filter(
                FlowFocusSession.user_id == user.id,
                FlowFocusSession.status == "completed",
            )
            .all()
        )
        total_sessions = len(completed_sessions)
        total_focus_mins = sum((s.duration_minutes or 0) for s in completed_sessions)
        longest_session = max(((s.duration_minutes or 0) for s in completed_sessions), default=0)

        # Daily focus totals grouped by calendar date in user's timezone
        daily_focus_totals: dict[str, int] = {}
        for s in completed_sessions:
            if s.created_at and s.duration_minutes:
                local_dt = _make_aware(s.created_at).astimezone(user_tz)
                day_key = local_dt.strftime("%Y-%m-%d")
                daily_focus_totals[day_key] = daily_focus_totals.get(day_key, 0) + (s.duration_minutes or 0)
        best_focus_day_mins = max(daily_focus_totals.values(), default=0)

        now_tz = datetime.now(user_tz)
        week_start = (now_tz - timedelta(days=now_tz.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
        weekly_sessions = [
            s for s in completed_sessions
            if _make_aware(s.created_at) >= week_start.astimezone(timezone.utc)
        ]
        weekly_focus_mins = sum((s.duration_minutes or 0) for s in weekly_sessions)

        # Rhythm / consistency calculation strictly from actual user data
        if total_sessions == 0 and profile.current_streak == 0:
            consistency_label = "Building"
            rhythm_msg = "Start your first flow to build your rhythm with Noya. 🦊"
        elif profile.current_streak >= 5:
            consistency_label = "In Flow"
            rhythm_msg = "You are locked in. Flow momentum is peaking. 🦊"
        elif profile.current_streak >= 2 or len(weekly_sessions) >= 3:
            consistency_label = "Steady"
            rhythm_msg = "You usually focus best around this time. Noya noticed. 🦊"
        elif total_sessions > 0:
            consistency_label = "Calibrating"
            rhythm_msg = "Noya is tuning into your peak focus rhythm. 🦊"
        else:
            consistency_label = "Building"
            rhythm_msg = "Start your first flow to build your rhythm with Noya. 🦊"

        personal_progress = PersonalProgressResponse(
            personal_best_focus_minutes=longest_session,
            weekly_focus_sessions=len(weekly_sessions),
            weekly_focus_minutes=weekly_focus_mins,
            total_focus_minutes=total_focus_mins,
            total_sessions_completed=total_sessions,
            best_focus_day_minutes=best_focus_day_mins,
            consistency_score=consistency_label,
            rhythm_acknowledgement=rhythm_msg,
        )

        notification = None
        if profile.last_shield_used_date:
            if profile.last_shield_used_date == today_str:
                notification = "Your Flow Shield protected your streak today."

        # Weekly progress for current week
        current_week = self._get_current_week_identifier(user_tz)
        wp_record = (
            db.query(FlowWeeklyProgress)
            .filter(
                FlowWeeklyProgress.user_id == user.id,
                FlowWeeklyProgress.week_identifier == current_week,
            )
            .first()
        )
        weekly_progress_resp = None
        if wp_record:
            weekly_progress_resp = FlowWeeklyProgressResponse(
                week_identifier=wp_record.week_identifier,
                sessions_completed=wp_record.sessions_completed,
                focus_minutes_logged=wp_record.focus_minutes_logged,
                priority_tasks_completed=wp_record.priority_tasks_completed,
                feedback_given=wp_record.feedback_given,
                flow_points_earned=wp_record.flow_points_earned,
                adaptive_session_target=wp_record.adaptive_session_target,
                adaptive_minutes_target=wp_record.adaptive_minutes_target,
                weekly_goal_hit=wp_record.weekly_goal_hit,
            )
        else:
            # First-time user: return default targets with zero progress
            weekly_progress_resp = FlowWeeklyProgressResponse(
                week_identifier=current_week,
                adaptive_session_target=3,
                adaptive_minutes_target=60,
            )

        return FlowOverviewResponse(
            companion=FlowCompanionResponse.model_validate(companion),
            profile=FlowProfileResponse.model_validate(profile),
            active_challenge=FlowChallengeResponse.model_validate(challenge) if challenge else None,
            daily_quests=[FlowDailyQuestResponse.model_validate(q) for q in daily_quests],
            achievements=[FlowAchievementResponse.model_validate(a) for a in achievements],
            league=league,
            personal_progress=personal_progress,
            weekly_progress=weekly_progress_resp,
            active_session_id=active_session_id,
            notification=notification,
        )

    def start_focus_session(
        self, db: Session, user: User, task_id: Optional[str] = None
    ) -> StartSessionResponse:
        # Check active session
        active = (
            db.query(FlowFocusSession)
            .filter(
                FlowFocusSession.user_id == user.id,
                FlowFocusSession.status == "started",
            )
            .order_by(FlowFocusSession.created_at.desc())
            .first()
        )
        if active:
            elapsed_mins = (utcnow() - _make_aware(active.server_start_at)).total_seconds() / 60
            if elapsed_mins < MAX_FOCUS_MINUTES:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="A focus session is already in progress. Complete or abandon it before starting a new one.",
                )
            else:
                active.status = "abandoned"
                db.flush()

        session = FlowFocusSession(
            user_id=user.id,
            task_id=task_id,
            server_start_at=utcnow(),
            status="started",
        )
        db.add(session)
        db.commit()
        db.refresh(session)
        return StartSessionResponse(
            session_id=session.id,
            server_start_at=session.server_start_at,
            status=session.status,
        )

    def complete_focus_session(
        self,
        db: Session,
        user: User,
        session_id: str,
        task_completed: bool = True,
        feeling_score: Optional[int] = None,
        idempotency_key: Optional[str] = None,
        test_mode: bool = False,
    ) -> CompleteSessionResponse:
        # Semantic idempotency: check if already rewarded
        existing_event = (
            db.query(FlowEconomicEvent)
            .filter(
                FlowEconomicEvent.user_id == user.id,
                FlowEconomicEvent.event_type == "focus_session",
                FlowEconomicEvent.reference_id == session_id,
            )
            .first()
        )
        if existing_event:
            # Return previously computed response safely
            profile, companion, _ = self.get_or_create_flow_profile(db, user)
            return CompleteSessionResponse(
                session_id=session_id,
                duration_minutes=existing_event.xp_awarded // COMPANION_XP_PER_FOCUS_MINUTE or 1,
                xp_awarded=existing_event.xp_awarded,
                flow_awarded=existing_event.flow_awarded,
                new_level=companion.level,
                leveled_up=False,
                evolution_ready=companion.is_evolution_ready,
                new_stage=companion.stage,
                current_streak=profile.current_streak,
                streak_incremented=False,
                shield_awarded=False,
                shield_used=False,
                notification="Session already processed (idempotent result).",
                companion=FlowCompanionResponse.model_validate(companion),
                profile=FlowProfileResponse.model_validate(profile),
            )

        session = (
            db.query(FlowFocusSession)
            .filter(FlowFocusSession.id == session_id, FlowFocusSession.user_id == user.id)
            .first()
        )
        if not session:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Focus session not found or does not belong to user.",
            )

        if session.status == "completed":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Session has already been marked completed.",
            )
        if session.status == "abandoned":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot complete an abandoned session.",
            )

        now = utcnow()
        elapsed_seconds = max(0.0, (now - _make_aware(session.server_start_at)).total_seconds())
        if test_mode:
            duration_minutes = max(1, int(elapsed_seconds // 60))
        else:
            duration_minutes = int(elapsed_seconds // 60)

        min_allowed = MIN_QUALIFYING_FOCUS_MINUTES_TEST if test_mode else MIN_QUALIFYING_FOCUS_MINUTES
        if duration_minutes < min_allowed:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Focus session duration ({duration_minutes} min) is below the minimum qualifying duration ({min_allowed} min).",
            )

        if duration_minutes > MAX_FOCUS_MINUTES:
            duration_minutes = MAX_FOCUS_MINUTES

        session.status = "completed"
        session.server_completed_at = now
        session.duration_minutes = duration_minutes

        profile, companion, challenge = self.get_or_create_flow_profile(db, user)

        # Rewards calculation with Daily Focus XP Cap (MAX_XP_PER_DAY = 300)
        base_xp = duration_minutes * COMPANION_XP_PER_FOCUS_MINUTE
        today_start_utc = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        today_xp_sum = (
            db.query(func.coalesce(func.sum(FlowEconomicEvent.xp_awarded), 0))
            .filter(
                FlowEconomicEvent.user_id == user.id,
                FlowEconomicEvent.event_type == "focus_session",
                FlowEconomicEvent.created_at >= today_start_utc,
            )
            .scalar()
        ) or 0
        remaining_daily_xp = max(0, MAX_XP_PER_DAY - today_xp_sum)
        xp_earned = min(base_xp, remaining_daily_xp)
        flow_earned = FLOW_REWARD_FOCUS_SESSION

        # Priority task check & daily cap with anti-farming complexity guard
        user_tz = self._get_user_timezone(db, user.id)
        today_str = self._get_user_today_str(user_tz)

        is_priority_task = False
        if session.task_id and task_completed:
            task = db.query(Task).filter(Task.id == session.task_id, Task.user_id == user.id).first()
            task_est = getattr(task, "estimated_minutes", 0) or 0
            is_prio = getattr(task, "is_priority", False) or str(getattr(task, "priority", "")).lower().endswith(("high", "urgent"))
            is_substantive = duration_minutes >= MIN_TASK_DURATION_FOR_PRIORITY_BONUS or task_est >= MIN_TASK_DURATION_FOR_PRIORITY_BONUS or test_mode
            if task and is_prio and is_substantive:
                is_priority_task = True
                # Check priority reward cap for today
                today_priority_rewards = (
                    db.query(FlowEconomicEvent)
                    .filter(
                        FlowEconomicEvent.user_id == user.id,
                        FlowEconomicEvent.event_type == "priority_task",
                        FlowEconomicEvent.created_at >= today_start_utc,
                    )
                    .count()
                )
                if today_priority_rewards < MAX_PRIORITY_REWARDS_PER_DAY:
                    flow_earned += FLOW_REWARD_PRIORITY_TASK
                    # Record priority task event
                    try:
                        p_event = FlowEconomicEvent(
                            user_id=user.id,
                            idempotency_key=f"priority-{task.id}-{now.timestamp()}",
                            event_type="priority_task",
                            reference_id=task.id,
                            flow_awarded=FLOW_REWARD_PRIORITY_TASK,
                            xp_awarded=0,
                        )
                        db.add(p_event)
                        db.flush()
                    except IntegrityError:
                        db.rollback()

        # Honest feedback reward
        if feeling_score is not None and duration_minutes >= min_allowed:
            flow_earned += FLOW_REWARD_FEEDBACK

        # Companion XP & Progression
        companion.companion_xp += xp_earned
        old_level = companion.level
        new_level, xp_into_level, xp_needed = get_level_for_xp(companion.companion_xp)
        leveled_up = new_level > old_level
        companion.level = new_level
        companion.xp_to_next_level = xp_needed
        evolution_ready = check_evolution_ready(new_level, companion.stage)
        companion.is_evolution_ready = evolution_ready
        companion.last_progress_at = now

        # Update profile
        profile.flow_balance += flow_earned
        profile.lifetime_flow += flow_earned
        profile.weekly_flow_points += flow_earned

        # Streak & Shield logic (Timezone aware, user-confirmed shield consumption)
        streak_incremented = False
        shield_awarded = False
        shield_used = False
        notification = None

        if profile.last_qualifying_date == today_str:
            # Already qualified today
            pass
        else:
            streak_incremented = True
            if profile.last_qualifying_date is None:
                # First qualifying day
                profile.current_streak = 1
                profile.longest_streak = 1
                profile.streak_start_date = today_str
                profile.last_qualifying_date = today_str
                profile.shield_progress_days = 1
            else:
                last_dt = datetime.strptime(profile.last_qualifying_date, "%Y-%m-%d").date()
                today_dt = datetime.strptime(today_str, "%Y-%m-%d").date()
                days_diff = (today_dt - last_dt).days

                if days_diff == 1:
                    # Consecutive day!
                    profile.current_streak += 1
                    if profile.current_streak > profile.longest_streak:
                        profile.longest_streak = profile.current_streak
                    profile.last_qualifying_date = today_str

                    if profile.last_shield_used_date == today_str:
                        shield_used = True
                        notification = "Your Flow Shield protected your streak."

                    profile.shield_progress_days += 1
                    if profile.shield_progress_days >= SHIELD_EARN_DAYS:
                        if profile.shields_available < MAX_FREE_SHIELDS:
                            profile.shields_available += 1
                            shield_awarded = True
                        profile.shield_progress_days = 0
                elif days_diff > 1:
                    # Missed a day! Check if user confirmed shield usage
                    if profile.last_shield_used_date == today_str:
                        profile.current_streak += 1
                        if profile.current_streak > profile.longest_streak:
                            profile.longest_streak = profile.current_streak
                        profile.last_qualifying_date = today_str
                        notification = "Your Flow Shield protected your streak."
                        shield_used = True
                    else:
                        # Streak resets cleanly with zero guilt; shields preserved in inventory
                        profile.current_streak = 1
                        profile.streak_start_date = today_str
                        profile.last_qualifying_date = today_str
                        profile.shield_progress_days = 1

        # Advance challenge
        if challenge and not challenge.is_completed:
            if challenge.challenge_type == "priority_tasks" and is_priority_task:
                challenge.current_count += 1
            elif challenge.challenge_type == "focus_minutes":
                challenge.current_count += duration_minutes
            if challenge.current_count >= challenge.target_count:
                challenge.is_completed = True

        # Advance daily quests
        self.get_or_create_daily_quests(db, user, today_str)
        self._update_daily_quest_progress(db, user.id, today_str, "complete_1_session", 1)
        if task_completed:
            self._update_daily_quest_progress(db, user.id, today_str, "finish_2_tasks", 1)
        if feeling_score is not None:
            self._update_daily_quest_progress(db, user.id, today_str, "give_feedback", 1)

        # Evaluate and unlock any new achievements
        self._evaluate_achievements(db, user, profile, duration_minutes)

        # ── Weekly Grind Progress (atomic update) ─────────────────────────────
        current_week = self._get_current_week_identifier(user_tz)
        weekly_progress = self._get_or_create_weekly_progress(db, user.id, current_week)
        weekly_progress.sessions_completed += 1
        weekly_progress.focus_minutes_logged += duration_minutes
        weekly_progress.flow_points_earned += flow_earned
        if is_priority_task:
            weekly_progress.priority_tasks_completed += 1
        if feeling_score is not None:
            weekly_progress.feedback_given += 1
        # Check if adaptive weekly goal just hit
        if (not weekly_progress.weekly_goal_hit and
                weekly_progress.sessions_completed >= weekly_progress.adaptive_session_target):
            weekly_progress.weekly_goal_hit = True
            weekly_progress.goal_hit_at = now
        db.flush()
        # ─────────────────────────────────────────────────────────────────────

        event_key = idempotency_key or f"session-{session.id}-{now.timestamp()}"
        econ_event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=event_key,
            event_type="focus_session",
            reference_id=session.id,
            flow_awarded=flow_earned,
            xp_awarded=xp_earned,
            metadata_json=json.dumps({
                "duration_minutes": duration_minutes,
                "task_id": session.task_id,
                "feeling_score": feeling_score,
                "is_priority": is_priority_task,
            }),
        )
        db.add(econ_event)

        try:
            db.commit()
            db.refresh(companion)
            db.refresh(profile)
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Transaction conflict: this session reward was already recorded.",
            )

        return CompleteSessionResponse(
            session_id=session.id,
            duration_minutes=duration_minutes,
            xp_awarded=xp_earned,
            flow_awarded=flow_earned,
            new_level=companion.level,
            leveled_up=leveled_up,
            evolution_ready=companion.is_evolution_ready,
            new_stage=companion.stage,
            current_streak=profile.current_streak,
            streak_incremented=streak_incremented,
            shield_awarded=shield_awarded,
            shield_used=shield_used,
            notification=notification,
            companion=FlowCompanionResponse.model_validate(companion),
            profile=FlowProfileResponse.model_validate(profile),
        )

    def abandon_focus_session(
        self, db: Session, user: User, session_id: str
    ) -> AbandonSessionResponse:
        session = (
            db.query(FlowFocusSession)
            .filter(FlowFocusSession.id == session_id, FlowFocusSession.user_id == user.id)
            .first()
        )
        if not session:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Focus session not found.",
            )
        if session.status != "started":
            return AbandonSessionResponse(
                session_id=session.id,
                status=session.status,
                companion_status="idle",
                message="Session was already ended.",
            )

        session.status = "abandoned"
        session.server_completed_at = utcnow()
        db.commit()

        return AbandonSessionResponse(
            session_id=session.id,
            status="abandoned",
            companion_status="tired",
            message="Session abandoned. Noya is resting. Protect your progress tomorrow.",
        )

    def evolve_companion(self, db: Session, user: User) -> EvolveResponse:
        profile, companion, _ = self.get_or_create_flow_profile(db, user)
        if not companion.is_evolution_ready:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Companion has not reached the required level milestone to evolve.",
            )

        target_stage = get_next_stage(companion.stage)

        # Semantic uniqueness on evolution
        event_ref = f"{companion.id}_{target_stage}"
        econ_event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=f"evolve-{event_ref}-{utcnow().timestamp()}",
            event_type="evolution",
            reference_id=event_ref,
            flow_awarded=0,
            xp_awarded=0,
            metadata_json=json.dumps({"from_stage": companion.stage, "to_stage": target_stage}),
        )
        db.add(econ_event)

        companion.stage = target_stage
        companion.is_evolution_ready = False
        companion.last_progress_at = utcnow()

        try:
            db.commit()
            db.refresh(companion)
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Evolution to this stage was already recorded.",
            )

        return EvolveResponse(
            success=True,
            new_stage=companion.stage,
            companion=FlowCompanionResponse.model_validate(companion),
        )

    def claim_challenge(self, db: Session, user: User, challenge_id: str) -> ClaimChallengeResponse:
        challenge = (
            db.query(FlowChallenge)
            .filter(FlowChallenge.id == challenge_id, FlowChallenge.user_id == user.id)
            .first()
        )
        if not challenge:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Challenge not found.")
        if not challenge.is_completed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Challenge is not completed yet.")
        if challenge.is_claimed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Challenge reward already claimed.")

        profile, _, _ = self.get_or_create_flow_profile(db, user)

        econ_event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=f"challenge-{challenge.id}-{utcnow().timestamp()}",
            event_type="challenge_claim",
            reference_id=challenge.id,
            flow_awarded=challenge.reward_flow,
            xp_awarded=0,
        )
        db.add(econ_event)

        challenge.is_claimed = True
        profile.flow_balance += challenge.reward_flow
        profile.lifetime_flow += challenge.reward_flow

        try:
            db.commit()
            db.refresh(profile)
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Challenge already claimed.")

        return ClaimChallengeResponse(
            challenge_id=challenge.id,
            flow_awarded=challenge.reward_flow,
            new_balance=profile.flow_balance,
        )

    def claim_daily_quest(self, db: Session, user: User, quest_id: str) -> ClaimQuestResponse:
        quest = (
            db.query(FlowDailyQuest)
            .filter(FlowDailyQuest.id == quest_id, FlowDailyQuest.user_id == user.id)
            .first()
        )
        if not quest:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Daily quest not found.")
        if not quest.is_completed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Daily quest is not completed yet.")
        if quest.is_claimed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Daily quest reward already claimed.")

        profile, _, _ = self.get_or_create_flow_profile(db, user)

        econ_event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=f"dailyquest-{quest.id}-{utcnow().timestamp()}",
            event_type="daily_quest_claim",
            reference_id=quest.id,
            flow_awarded=quest.reward_flow,
            xp_awarded=0,
        )
        db.add(econ_event)

        quest.is_claimed = True
        profile.flow_balance += quest.reward_flow
        profile.lifetime_flow += quest.reward_flow

        try:
            db.commit()
            db.refresh(profile)
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Daily quest already claimed.")

        return ClaimQuestResponse(
            quest_id=quest.id,
            flow_awarded=quest.reward_flow,
            new_balance=profile.flow_balance,
        )

    def select_companion(
        self, db: Session, user: User, species: str, name: Optional[str] = None
    ) -> FlowCompanion:
        valid_species = {c["species"]: c["name"] for c in COMPANION_CATALOG}
        if species not in valid_species:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid companion species: {species}. Available: {list(valid_species.keys())}",
            )

        # Fox (Noya) is always owned; others require inventory record
        if species != "fox":
            owned = (
                db.query(FlowInventoryItem)
                .filter(
                    FlowInventoryItem.user_id == user.id,
                    FlowInventoryItem.item_type == "companion",
                    FlowInventoryItem.item_key == species,
                )
                .first()
            )
            if not owned:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"{species.capitalize()} has not been unlocked. Purchase from the Flow Shop first.",
                )

        companion = (
            db.query(FlowCompanion)
            .filter(FlowCompanion.user_id == user.id, FlowCompanion.is_active == True)
            .first()
        )
        if not companion:
            _, companion, _ = self.get_or_create_flow_profile(db, user)

        companion.species = species
        companion.name = name if name else valid_species[species]
        db.commit()
        db.refresh(companion)
        return companion

    def purchase_companion(
        self, db: Session, user: User, species: str
    ) -> PurchaseCompanionResponse:
        """Purchase a companion from the Flow Shop using Flow Points."""
        # Validate species
        catalog_item = next((c for c in COMPANION_CATALOG if c["species"] == species), None)
        if not catalog_item:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Companion '{species}' not found in catalog.",
            )

        # Fox is always free / already owned
        if species == "fox":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Noya (fox) is your default companion and is always available.",
            )

        # Double-purchase guard
        already_owned = (
            db.query(FlowInventoryItem)
            .filter(
                FlowInventoryItem.user_id == user.id,
                FlowInventoryItem.item_type == "companion",
                FlowInventoryItem.item_key == species,
            )
            .first()
        )
        if already_owned:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"{catalog_item['name']} is already in your companion roster.",
            )

        cost = catalog_item["flow_cost"]
        profile, _, _ = self.get_or_create_flow_profile(db, user)

        if profile.flow_balance < cost:
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail=f"Insufficient Flow Points. You need {cost} Flow but have {profile.flow_balance}.",
            )

        # Deduct balance
        profile.flow_balance -= cost

        # Write inventory row
        inventory_item = FlowInventoryItem(
            user_id=user.id,
            item_type="companion",
            item_key=species,
            flow_spent=cost,
        )
        db.add(inventory_item)

        # Economic event audit trail
        econ_event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=f"shop-companion-{species}-{user.id}",
            event_type="shop_purchase",
            reference_id=f"companion:{species}",
            flow_awarded=-cost,  # negative = spent
            xp_awarded=0,
            metadata_json=json.dumps({"species": species, "name": catalog_item["name"], "cost": cost}),
        )
        db.add(econ_event)

        try:
            db.commit()
            db.refresh(profile)
        except IntegrityError:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Purchase transaction conflict. Please try again.",
            )

        return PurchaseCompanionResponse(
            species=species,
            name=catalog_item["name"],
            flow_spent=cost,
            new_balance=profile.flow_balance,
            message=f"{catalog_item['name']} has joined your companion roster! 🎉",
        )

    def get_shop_catalog(self, db: Optional[Session] = None, user_id: Optional[str] = None) -> List[ShopItemResponse]:
        """Returns companion catalog enriched with real ownership from FlowInventoryItem."""
        if db is None or user_id is None:
            return [ShopItemResponse(**item) for item in COMPANION_CATALOG]

        # Get all companion inventory for this user
        owned_species = set(
            r.item_key
            for r in db.query(FlowInventoryItem)
            .filter(
                FlowInventoryItem.user_id == user_id,
                FlowInventoryItem.item_type == "companion",
            )
            .all()
        )
        # Fox always owned
        owned_species.add("fox")

        result = []
        for item in COMPANION_CATALOG:
            is_owned = item["species"] in owned_species
            result.append(ShopItemResponse(
                **{**item, "is_owned": is_owned, "is_unlocked": is_owned},
            ))
        return result

    def use_streak_shield(self, db: Session, user: User) -> UseShieldResponse:
        """
        User-confirmed shield consumption:
        Protects or restores a streak when the user chooses to use an available shield.
        """
        profile, _, _ = self.get_or_create_flow_profile(db, user)
        if profile.shields_available <= 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No Flow Shields available to consume.",
            )

        user_tz = self._get_user_timezone(db, user.id)
        today_str = self._get_user_today_str(user_tz)

        if profile.last_shield_used_date == today_str:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Flow Shield already active for today.",
            )

        profile.shields_available -= 1
        profile.shields_used_count += 1
        profile.last_shield_used_date = today_str

        # Protect streak: if user missed yesterday, keep streak chain alive
        yesterday_str = (datetime.now(user_tz) - timedelta(days=1)).strftime("%Y-%m-%d")
        profile.last_qualifying_date = yesterday_str

        event = FlowEconomicEvent(
            user_id=user.id,
            idempotency_key=f"shield_use_{user.id}_{today_str}_{profile.shields_used_count}",
            event_type="shield_used",
            reference_id=f"shield_{profile.shields_used_count}",
            flow_awarded=0,
            xp_awarded=0,
            metadata_json=json.dumps({"action": "user_confirmed_shield_use", "date": today_str}),
        )
        db.add(event)
        db.commit()
        db.refresh(profile)

        return UseShieldResponse(
            success=True,
            message="Flow Shield activated. Your streak is protected.",
            shields_available=profile.shields_available,
            current_streak=profile.current_streak,
        )

