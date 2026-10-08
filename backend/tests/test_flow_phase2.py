"""Flow hub + Noya progression (Phase 2): resets, XP, levels, stages, idempotency, restart.

The progression rules read one clock (flow_service._now); tests replace it to cross day and week boundaries.
"""
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException
from httpx import ASGITransport, AsyncClient

from app.core import economy_config as eco
from app.db.session import SessionLocal
from app.main import app
from app.models.flow_progression import (FlowChallenge, FlowCompanion, FlowDailyQuest, FlowEconomicEvent,
                                         FlowFocusSession, FlowProfile)
from app.models.task import Task
from app.models.user import User
from app.models.user_preferences import UserPreferences
from app.services import flow_service as fs
from tests.test_flow_progression import make_auth_header, unique_user

IST = ZoneInfo("Asia/Kolkata")
svc = fs.FlowService()


def mk_user(tz="Asia/Kolkata"):
    uid = unique_user("p2")
    with SessionLocal() as db:
        db.add(User(id=uid, email=f"{uid}@flowstate.local", name="t"))
        db.add(UserPreferences(user_id=uid, timezone=tz))
        db.commit()
    return uid


def set_clock(monkeypatch, local_dt: datetime):
    monkeypatch.setattr(fs, "_now", lambda: local_dt.astimezone(timezone.utc))


def load(db, uid):
    return db.query(User).filter(User.id == uid).first()


def make_task(uid, priority="high", minutes=30):
    with SessionLocal() as db:
        t = Task(id=f"t-{uuid.uuid4().hex[:8]}", user_id=uid, title="Priority thing", estimated_minutes=minutes,
                 priority=priority, status="todo")
        db.add(t)
        db.commit()
        return t.id


def finish_session(db, user, minutes=10, task_id=None, **kw):
    """Start a session, age it by `minutes`, complete it."""
    s = svc.start_focus_session(db, user, task_id)
    row = db.query(FlowFocusSession).filter(FlowFocusSession.id == s.session_id).one()
    row.server_start_at = datetime.now(timezone.utc) - timedelta(minutes=minutes, seconds=5)
    db.commit()
    return svc.complete_focus_session(db, user, s.session_id, test_mode=True, **kw)


# ── level table, cap and stages ──────────────────────────────────────────────

def test_level_boundaries():
    assert eco.get_level_for_xp(0)[0] == 1
    assert eco.get_level_for_xp(59)[0] == 1
    assert eco.get_level_for_xp(60)[0] == 2
    assert eco.get_level_for_xp(60)[1:] == (0, 90)           # 0 into level 2, 90 to level 3
    levels = [eco.get_level_for_xp(eco.get_cumulative_xp_for_level(n))[0] for n in range(1, 101)]
    assert levels == list(range(1, 101))                      # every level is reachable, strictly increasing
    assert eco.get_level_for_xp(-5)[0] == 1


def test_level_100_is_super_noya_and_caps():
    need = eco.get_cumulative_xp_for_level(100)
    assert eco.get_level_for_xp(need - 1)[0] == 99
    assert eco.get_level_for_xp(need) == (100, 0, 0)
    assert eco.get_level_for_xp(need * 10)[0] == 100          # XP past the cap never levels further
    assert eco.get_level_for_xp(need * 10)[2] == 0
    assert eco.get_stage_for_level(1) == "Baby"
    assert eco.get_stage_for_level(99) == "Evolved"
    assert eco.get_stage_for_level(100) == "Super"
    assert eco.check_evolution_ready(100, "Evolved") is True
    assert eco.check_evolution_ready(100, "Super") is False
    assert eco.get_next_stage("Evolved") == "Super" and eco.get_next_stage("Super") == "Super"


def test_stage_ladder_is_monotonic():
    order = {s: i for i, s in enumerate(eco.STAGES)}
    prev = 0
    for lvl in range(1, 101):
        cur = order[eco.get_stage_for_level(lvl)]
        assert cur >= prev
        prev = cur


# ── clock helpers: local day / ISO week ──────────────────────────────────────

def test_week_identifier_is_iso_and_never_splits_new_year(monkeypatch):
    tz = IST
    ids = {}
    for d in (datetime(2026, 12, 28, 9, tzinfo=IST), datetime(2026, 12, 31, 23, 59, tzinfo=IST),
              datetime(2027, 1, 1, 0, 1, tzinfo=IST), datetime(2027, 1, 3, 20, tzinfo=IST),
              datetime(2027, 1, 4, 0, 1, tzinfo=IST)):
        set_clock(monkeypatch, d)
        ids[d] = svc._get_current_week_identifier(tz)
    vals = list(ids.values())
    assert vals[0] == vals[1] == vals[2] == vals[3] == "2026-W53"   # Mon Dec 28 .. Sun Jan 3 is ONE week
    assert vals[4] == "2027-W01"                                    # resets exactly on Monday


def test_daily_caps_reset_at_the_users_midnight_not_utc(monkeypatch):
    set_clock(monkeypatch, datetime(2026, 10, 8, 1, 30, tzinfo=IST))      # 20:00 UTC on Oct 7
    start = svc._local_day_start_utc(IST)
    assert start == datetime(2026, 10, 7, 18, 30, tzinfo=timezone.utc)    # IST midnight, not UTC midnight
    assert svc._get_user_today_str(IST) == "2026-10-08"


# ── daily / weekly reset ─────────────────────────────────────────────────────

def test_daily_reset_creates_fresh_quests_and_keeps_history(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        set_clock(monkeypatch, datetime(2026, 10, 5, 22, 0, tzinfo=IST))
        day1 = svc.get_overview(db, user)
        assert len(day1.daily_quests) == 3 and {q.quest_date for q in day1.daily_quests} == {"2026-10-05"}
        svc._update_daily_quest_progress(db, uid, "2026-10-05", "complete_1_session", 1)
        db.commit()
        set_clock(monkeypatch, datetime(2026, 10, 6, 0, 5, tzinfo=IST))   # five minutes past local midnight
        day2 = svc.get_overview(db, user)
        assert {q.quest_date for q in day2.daily_quests} == {"2026-10-06"}
        assert all(q.current_count == 0 and not q.is_completed and not q.is_claimed for q in day2.daily_quests)
        old = db.query(FlowDailyQuest).filter(FlowDailyQuest.user_id == uid, FlowDailyQuest.quest_date == "2026-10-05")
        assert old.count() == 3
        assert next(q for q in old if q.quest_key == "complete_1_session").is_completed   # yesterday's progress kept


def test_weekly_reset_gives_new_quests_and_resets_weekly_points(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        set_clock(monkeypatch, datetime(2026, 10, 7, 12, 0, tzinfo=IST))     # Wednesday
        ov = svc.get_overview(db, user)
        assert [q.challenge_type for q in ov.weekly_quests] == ["priority_tasks", "focus_sessions", "focus_minutes"]
        assert ov.active_challenge.challenge_type == "priority_tasks"
        wk1 = ov.profile.current_week_identifier
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        profile.weekly_flow_points = 55
        db.commit()
        svc._advance_weekly_quests(db, user, wk1, sessions=4, minutes=130)
        db.commit()
        set_clock(monkeypatch, datetime(2026, 10, 12, 0, 1, tzinfo=IST))     # next Monday
        ov2 = svc.get_overview(db, user)
        assert ov2.profile.current_week_identifier != wk1
        assert ov2.profile.weekly_flow_points == 0
        assert all(q.current_count == 0 and not q.is_completed for q in ov2.weekly_quests)
        assert db.query(FlowChallenge).filter(FlowChallenge.user_id == uid).count() == 6   # last week kept as history


def test_weekly_quests_advance_from_sessions_and_minutes(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        set_clock(monkeypatch, datetime.now(IST))
        for _ in range(2):
            finish_session(db, user, minutes=60)
        ov = svc.get_overview(db, user)
        by = {q.challenge_type: q for q in ov.weekly_quests}
        assert by["focus_sessions"].current_count == 2
        assert by["focus_minutes"].current_count >= 120 and by["focus_minutes"].is_completed


# ── XP accumulation, duplicates, idempotency ─────────────────────────────────

def test_xp_accumulates_and_levels_up(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        a = finish_session(db, user, minutes=40)
        assert a.xp_awarded == 40 and a.new_level == 1 and not a.leveled_up
        b = finish_session(db, user, minutes=30)
        assert b.companion.companion_xp == 70 and b.new_level == 2 and b.leveled_up
        assert b.companion.xp_to_next_level == 90


def test_completing_a_session_twice_rewards_once():
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        first = finish_session(db, user, minutes=10)
        again = svc.complete_focus_session(db, user, first.session_id, test_mode=True)
        assert again.xp_awarded == first.xp_awarded
        comp = db.query(FlowCompanion).filter(FlowCompanion.user_id == uid).one()
        assert comp.companion_xp == first.xp_awarded
        events = db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                    FlowEconomicEvent.event_type == "focus_session").count()
        assert events == 1


def test_task_completion_counts_once_even_if_reported_twice():
    uid = mk_user()
    tid = make_task(uid)
    with SessionLocal() as db:
        user = load(db, uid)
        task = db.query(Task).filter(Task.id == tid).one()
        svc.on_task_completed(db, uid, task)
        svc.on_task_completed(db, uid, task)          # reopened + completed again / duplicate callback
        ov = svc.get_overview(db, user)
        assert next(q for q in ov.daily_quests if q.quest_key == "finish_2_tasks").current_count == 1
        assert ov.active_challenge.current_count == 1
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        assert profile.flow_balance == eco.FLOW_REWARD_PRIORITY_TASK     # paid once


def test_focus_session_then_task_completion_does_not_double_count_priority():
    uid = mk_user()
    tid = make_task(uid)
    with SessionLocal() as db:
        user = load(db, uid)
        finish_session(db, user, minutes=15, task_id=tid, task_completed=True)
        task = db.query(Task).filter(Task.id == tid).one()
        svc.on_task_completed(db, uid, task)
        ov = svc.get_overview(db, user)
        assert ov.active_challenge.current_count == 1                      # one task, one count
        assert ov.weekly_progress.priority_tasks_completed == 1
        paid = db.query(FlowEconomicEvent).filter(FlowEconomicEvent.user_id == uid,
                                                  FlowEconomicEvent.event_type == "priority_task").count()
        assert paid == 1


def test_claims_pay_once():
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        ov = svc.get_overview(db, user)
        q = ov.daily_quests[0]
        svc._update_daily_quest_progress(db, uid, ov.daily_quests[0].quest_date, q.quest_key, q.target_count)
        db.commit()
        r1 = svc.claim_daily_quest(db, user, q.id)
        with pytest.raises(HTTPException) as e:
            svc.claim_daily_quest(db, user, q.id)
        assert e.value.status_code == 400
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        assert profile.flow_balance == r1.flow_awarded
        wq = ov.weekly_quests[1]
        svc._advance_weekly_quests(db, user, ov.profile.current_week_identifier, sessions=10)
        db.commit()
        svc.claim_challenge(db, user, wq.id)
        with pytest.raises(HTTPException):
            svc.claim_challenge(db, user, wq.id)
        db.refresh(profile)
        assert profile.flow_balance == r1.flow_awarded + wq.reward_flow


def test_seventh_streak_day_awards_one_shield_once(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        base = datetime(2026, 10, 1, 12, 0, tzinfo=IST)
        awarded = []
        for day in range(7):
            set_clock(monkeypatch, base + timedelta(days=day))
            r = finish_session(db, user, minutes=5)
            awarded.append(r.shield_awarded)
        assert awarded == [False] * 6 + [True]
        profile = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        assert profile.shields_available == eco.INITIAL_SHIELDS + 1 and profile.current_streak == 7
        again = finish_session(db, user, minutes=5)                       # same day, second session
        assert again.shield_awarded is False and again.streak_incremented is False


def test_shields_never_exceed_cap(monkeypatch):
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        svc.get_overview(db, user)
        p = db.query(FlowProfile).filter(FlowProfile.user_id == uid).one()
        p.shields_available = eco.MAX_FREE_SHIELDS
        p.shield_progress_days = eco.SHIELD_EARN_DAYS - 1
        p.current_streak = 6
        p.last_qualifying_date = "2026-10-06"
        db.commit()
        set_clock(monkeypatch, datetime(2026, 10, 7, 12, 0, tzinfo=IST))
        r = finish_session(db, user, minutes=5)
        assert r.shield_awarded is False
        db.refresh(p)
        assert p.shields_available == eco.MAX_FREE_SHIELDS


# ── level 100 + evolution ────────────────────────────────────────────────────

def test_reaching_level_100_unlocks_super_stage_once():
    uid = mk_user()
    with SessionLocal() as db:
        user = load(db, uid)
        svc.get_overview(db, user)
        comp = db.query(FlowCompanion).filter(FlowCompanion.user_id == uid).one()
        comp.companion_xp = eco.get_cumulative_xp_for_level(100) - 5
        comp.level, comp.stage = 99, "Evolved"
        db.commit()
        r = finish_session(db, user, minutes=10)
        assert r.new_level == 100 and r.leveled_up and r.evolution_ready is True
        assert r.companion.xp_to_next_level == 0
        ev = svc.evolve_companion(db, user)
        assert ev.new_stage == "Super"
        with pytest.raises(HTTPException) as e:
            svc.evolve_companion(db, user)                    # nothing past Super Noya
        assert e.value.status_code == 400
        more = finish_session(db, user, minutes=10)           # XP keeps being recorded, level stays 100
        assert more.new_level == 100 and more.leveled_up is False and more.evolution_ready is False


# ── restart: everything is server state ──────────────────────────────────────

@pytest.mark.asyncio
async def test_progress_survives_app_restart():
    uid = mk_user()
    headers = make_auth_header(uid)
    with SessionLocal() as db:
        user = load(db, uid)
        finish_session(db, user, minutes=25)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        a = (await ac.get("/api/v1/flow", headers=headers)).json()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:   # a fresh client
        b = (await ac.get("/api/v1/flow", headers=headers)).json()
    assert a["companion"]["companion_xp"] == b["companion"]["companion_xp"] == 25
    assert b["profile"]["current_streak"] == 1
    assert len(b["weekly_quests"]) == 3 and len(b["daily_quests"]) == 3
    assert [q["challenge_type"] for q in b["weekly_quests"]] == ["priority_tasks", "focus_sessions", "focus_minutes"]
