"""Replan M5: a task whose slot passed is MISSED automatically (derived, never persisted), stays at its original
slot on the Calendar, is never the "do this now" task, and Redo/Replan keep the missed fact in task_deviations."""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal
from app.models.task_deviation import TaskDeviation
from app.services.task_state import derive_task_state
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import apply, at, get, replan, seed

D = date(2026, 10, 5)


def now_at(h, m=0, day=5):
    return at(h, m, day)


async def day(ac, h, now, d="2026-10-05"):
    r = await ac.get("/api/v1/calendar/day", headers=h, params={
        "date": d, "timezone": "Asia/Kolkata", "current_local_time": now.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()


def deviations(uid):
    db = SessionLocal()
    try:
        return db.query(TaskDeviation).filter(TaskDeviation.user_id == uid).all()
    finally:
        db.close()


# ── pure rule ────────────────────────────────────────────────────────────────
def test_state_is_normal_before_the_slot_and_missed_after_it():
    start, end, boundary = at(18), at(19), at(23)
    kw = dict(completed=False, cancelled=False, active=False, start=start, end=end, day_boundary=boundary)
    assert derive_task_state(now=at(17), **kw) == "scheduled"
    assert derive_task_state(now=at(18, 30), **kw) == "scheduled"  # inside its slot, not started: still its time
    assert derive_task_state(now=at(19, 1), **kw) == "missed"


def test_state_becomes_failed_only_after_the_sleep_boundary():
    kw = dict(completed=False, cancelled=False, active=False, start=at(18), end=at(19), day_boundary=at(23))
    assert derive_task_state(now=at(22, 59), **kw) == "missed"
    assert derive_task_state(now=at(23, 1), **kw) == "failed"


def test_completed_active_and_unslotted_are_never_missed():
    base = dict(start=at(10), end=at(11), day_boundary=at(23), now=at(15), cancelled=False)
    assert derive_task_state(completed=True, active=False, **base) == "completed"
    assert derive_task_state(completed=False, active=True, **base) == "active"
    assert derive_task_state(completed=False, active=False, **{**base, "start": None, "end": None}) == "unscheduled"


# ── calendar day: automatic, no click, original position kept ───────────────
@pytest.mark.asyncio
async def test_calendar_shows_missed_automatically_at_the_original_slot():
    uid, h = make_user()
    seed(uid, "A", at(10), 60, planned_date=D)
    c = seed(uid, "C", at(18), 60, planned_date=D)
    async with client() as ac:
        before = await day(ac, h, now_at(17))
        after = await day(ac, h, now_at(19, 30))
        later = await day(ac, h, now_at(19, 30))  # reopen/reload: same answer
    by = lambda d: {i["title"]: i for i in d["timeline"]}
    assert by(before)["C"]["state"] == "scheduled" and not by(before)["C"]["is_missed"]
    assert by(after)["C"]["state"] == "missed" and by(after)["C"]["is_missed"]
    assert by(after)["C"]["time"] == "6:00" and by(after)["C"]["period"] == "PM"
    assert [i["title"] for i in after["timeline"]] == ["A", "C"]  # chronological, C not moved to the top
    assert by(later)["C"]["state"] == "missed"
    assert get(c).scheduled_start == at(18).astimezone(timezone.utc)  # nothing was rewritten
    assert deviations(uid) == []  # rendering never writes history


@pytest.mark.asyncio
async def test_missed_becomes_failed_after_bedtime_and_on_a_past_day():
    uid, h = make_user()
    seed(uid, "C", at(18), 60, planned_date=D)
    async with client() as ac:
        late = await day(ac, h, now_at(23, 30))
        next_day = await day(ac, h, now_at(9, 0, day=6))
    assert late["timeline"][0]["state"] == "failed" and not late["timeline"][0]["is_missed"]
    assert next_day["timeline"][0]["state"] == "failed"


# ── Today: the missed task never dominates "do this now" (the endpoint uses the real clock) ──
def _today_task(uid, title, start_offset_min, minutes=60, **kw):
    real = datetime.now(timezone.utc)
    start = real + timedelta(minutes=start_offset_min)
    local_day = real.astimezone(IST).date()
    return seed(uid, title, start, minutes, planned_date=local_day, **kw)


async def _today(ac, h):
    r = await ac.get("/api/v1/today", headers=h, params={"timezone": "Asia/Kolkata"})
    assert r.status_code == 200, r.text
    return r.json()


@pytest.mark.asyncio
async def test_today_does_not_recommend_a_missed_task_and_keeps_chronological_timeline():
    uid, h = make_user()
    missed = _today_task(uid, "Gym", -180, priority="urgent")
    nxt = _today_task(uid, "Essay", 5)
    async with client() as ac:
        body = await _today(ac, h)
    rec = body["current_recommendation"]
    assert rec is not None and rec["task"]["id"] == nxt and rec["task"]["id"] != missed
    states = {i["title"]: i["state"] for i in body["upcoming_timeline"]}
    assert states.get("Gym") in ("missed", "failed")  # still visible, with its state (clock may be past bedtime)
    titles = [i["title"] for i in body["upcoming_timeline"]]
    assert titles.index("Gym") < titles.index("Essay")  # history stays in time order


@pytest.mark.asyncio
async def test_today_offers_the_next_upcoming_task_not_a_future_one_early_and_never_a_missed_one():
    uid, h = make_user()
    _today_task(uid, "Gym", -180)
    later = _today_task(uid, "Report", 120)
    async with client() as ac:
        body = await _today(ac, h)
    assert body["current_recommendation"]["task"]["id"] == later  # only the next slot, not the missed one


# ── Redo / Replan keep the missed occurrence ────────────────────────────────
@pytest.mark.asyncio
async def test_replan_of_a_missed_task_keeps_one_missed_deviation_at_the_original_slot():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(8), 60, planned_date=D)
    now = now_at(15)
    async with client() as ac:
        diff = await replan(ac, h, "I missed gym", now=now)
        assert not diff["conflicts"], diff["conflicts"]
        req = diff["apply_request"]
        assert (await apply(ac, h, req, now=now)).status_code == 200
        await apply(ac, h, req, now=now)  # replayed apply: no duplicate
        view = await day(ac, h, now)
    devs = deviations(uid)
    assert len(devs) == 1 and devs[0].kind == "missed"
    assert devs[0].original_start == at(8).astimezone(timezone.utc).replace(tzinfo=None) or \
        devs[0].original_start.astimezone(timezone.utc) == at(8).astimezone(timezone.utc)
    row = get(gym)
    assert row.scheduled_start is not None and row.scheduled_start.astimezone(at(8).tzinfo) >= now  # new future slot
    ghosts = [i for i in view["deviations"] if i["deviation"] == "missed"]
    assert len(ghosts) == 1 and ghosts[0]["time"] == "8:00" and ghosts[0]["is_missed"]
    assert row.status.value == "todo"


@pytest.mark.asyncio
async def test_explicit_skip_is_deferred_not_missed():
    uid, h = make_user()
    seed(uid, "Gym", at(18), 60, planned_date=D)
    async with client() as ac:
        diff = await replan(ac, h, "skip gym today", now=now_at(9))
        await apply(ac, h, diff["apply_request"], now=now_at(9))
    assert [d.kind for d in deviations(uid)] == ["skipped"]


@pytest.mark.asyncio
async def test_skipping_from_today_does_not_re_slot_to_now_or_pin():
    uid, h = make_user()
    a = _today_task(uid, "A", 5)
    _today_task(uid, "B", 90)
    async with client() as ac:
        today = await _today(ac, h)
        rec = today["current_recommendation"]["task"]["id"]
        assert rec == a
        r = await ac.post("/api/v1/today/override", headers=h, json={
            "decision_id": today["decision_id"], "reason": "skip", "chosen_task_id": rec,
            "timezone": "Asia/Kolkata"})
        assert r.status_code == 200, r.text
        after = await _today(ac, h)
    skipped = get(rec)
    soon = datetime.now(timezone.utc) + timedelta(minutes=2)
    # the override path did not drag the skipped task to "now"; it moved to a later window and kept its old slot as history
    assert skipped.scheduled_start is not None and skipped.scheduled_start.astimezone(timezone.utc) > soon
    assert [d.kind for d in deviations(uid)] == ["skipped"]
    assert after["current_recommendation"]["task"]["id"] != rec


@pytest.mark.asyncio
async def test_redo_the_missed_task_without_naming_it_and_ambiguity():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(8), 60, planned_date=D)
    now = now_at(15)
    async with client() as ac:
        diff = await replan(ac, h, "redo the missed task", now=now)
        assert not diff["conflicts"], diff["conflicts"]
        assert (await apply(ac, h, diff["apply_request"], now=now)).status_code == 200
    assert get(gym).scheduled_start.astimezone(IST) >= now
    assert [d.kind for d in deviations(uid)] == ["missed"]

    uid2, h2 = make_user()
    seed(uid2, "Gym", at(8), 60, planned_date=D)
    seed(uid2, "Essay", at(9), 60, planned_date=D)
    async with client() as ac:
        amb = await replan(ac, h2, "redo the missed task", now=now)
    assert any("More than one" in c for c in amb["conflicts"])  # asks which one; moves nothing


@pytest.mark.asyncio
async def test_replan_and_redo_keep_the_order_chronological():
    uid, h = make_user()
    gym = seed(uid, "Gym", at(8), 60, planned_date=D)
    seed(uid, "Essay", at(17), 60, planned_date=D)
    now = now_at(15)
    async with client() as ac:
        diff = await replan(ac, h, "I missed gym", now=now)
        await apply(ac, h, diff["apply_request"], now=now)
        view = await day(ac, h, now)
    starts = [i["start_time"] for i in view["timeline"]]
    assert starts == sorted(starts)
    assert get(gym).scheduled_start.astimezone(IST) >= now


@pytest.mark.asyncio
async def test_do_it_now_on_a_missed_task_keeps_one_missed_deviation():
    uid, h = make_user()
    gym = _today_task(uid, "Gym", -180)
    _today_task(uid, "Essay", 5)
    async with client() as ac:
        today = await _today(ac, h)
        for _ in range(2):  # a double tap / replay must not duplicate history
            r = await ac.post("/api/v1/today/override", headers=h, json={
                "decision_id": today["decision_id"], "chosen_task_id": gym, "timezone": "Asia/Kolkata"})
            assert r.status_code == 200, r.text
    devs = deviations(uid)
    assert [d.kind for d in devs] == ["missed"]
    assert get(gym).scheduled_start.astimezone(timezone.utc) > datetime.now(timezone.utc) - timedelta(minutes=5)
