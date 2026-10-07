"""Backend end-to-end scenarios A-D (spec section 12.1).

Real FastAPI app, real (temp) database, real planner. The only stub is the Gemini extractor.
The clock is injected: via ``current_local_time`` where the API accepts it, and by freezing
``datetime.now`` inside the two modules behind GET /today for the Today-vs-Calendar comparison.
"Restart" is emulated by disposing the SQLAlchemy engine and discarding every session, so the
next request can only see what was persisted.
"""
from datetime import date, datetime, timedelta, timezone

import pytest

from app.db.session import SessionLocal, engine
from app.models.task import Task, TaskStatus
from tests.plan_helpers import IST, LA, cand, client, fixed_cand, make_user, post_plan, stub_extraction

NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)  # Monday 09:00 IST


def at(h, m=0, day=5, tz=IST):
    return datetime(2026, 10, day, h, m, tzinfo=tz)


def _dt(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))


@pytest.fixture
def frozen_clock(monkeypatch):
    """Freeze datetime.now() in the modules that read the wall clock behind GET /today."""
    import app.api.routes.today as today_mod
    import app.services.task_service as task_service_mod

    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return NOW if tz is None else NOW.astimezone(tz)

    monkeypatch.setattr(today_mod, "datetime", Frozen)
    monkeypatch.setattr(task_service_mod, "datetime", Frozen)
    return NOW


def restart():
    """Discard every pooled connection: only persisted state survives."""
    engine.dispose()


async def calendar_day(ac, h, d="2026-10-05", now=NOW):
    r = await ac.get("/api/v1/calendar/day", headers=h, params={"date": d, "timezone": "Asia/Kolkata", "current_local_time": now.isoformat()})
    assert r.status_code == 200, r.text
    return r.json()


def sig_calendar(day):
    return sorted((i["task_id"], _dt(i["start_time"]), i["duration_minutes"], i["is_fixed"]) for i in day["timeline"] if not i["is_completed"])


def db_tasks(uid):
    db = SessionLocal()
    try:
        return db.query(Task).filter(Task.user_id == uid).all()
    finally:
        db.close()


def assert_no_overlap(slots):
    slots = sorted(slots)
    for (s1, e1), (s2, e2) in zip(slots, slots[1:]):
        assert e1 <= s2, f"overlap {s1}-{e1} / {s2}-{e2}"


# ═════════════════════════════════════════════════════════════════════════════
@pytest.mark.asyncio
async def test_E2E_A_messy_brain_dump_to_today_and_calendar_and_restart(monkeypatch, frozen_clock):
    uid, h = make_user()
    stub_extraction(monkeypatch, [
        cand("Finish DSA assignment", 90, priority="high"),
        cand("Gym", 60, task_type="physical"),
        cand("Email prof", 15, task_type="admin"),
        fixed_cand("Call mom", at(19), 30),
    ])
    async with client() as ac:
        # 1. Build My Day (preview)
        plan = (await post_plan(ac, h, NOW, text="messy dump")).json()
        assert plan["scheduling_error"] is None and plan["timezone_used"] == "Asia/Kolkata"
        tasks = plan["tasks"]
        assert all(t["recommended_slot_start"] for t in tasks)
        # 2. user edits one flexible task's time -> becomes a locked, explicit time
        gym = next(t for t in tasks if t["title"] == "Gym")
        gym_new = at(17, 30)
        # 3. confirm
        items = []
        for i, t in enumerate(tasks):
            start = gym_new if t["title"] == "Gym" else _dt(t["recommended_slot_start"])
            items.append({
                "title": t["title"], "estimated_minutes": t["estimated_minutes"], "priority": t["priority"],
                "task_type": t["task_type"], "scheduled_start": start.isoformat(),
                "scheduled_end": (start + timedelta(minutes=t["estimated_minutes"])).isoformat(),
                "time_locked": bool(t["time_locked"] or t["title"] == "Gym"), "client_ref": f"tmp-{i}",
            })
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json={
            "tasks": items, "plan_id": "e2e-a", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
        assert r.status_code == 201, r.text
        confirmed = r.json()
        assert confirmed["created_count"] == 4 and not confirmed["adjustments"]

        # 4. Today and Calendar agree with each other and with the DB
        cal = await calendar_day(ac, h)
        today = (await ac.get("/api/v1/today", headers=h)).json()
        today_times = sorted((i["title"], i["time"], i["period"]) for i in today["upcoming_timeline"])
        cal_times = sorted((i["title"], i["time"], i["period"]) for i in cal["timeline"] if not i["is_completed"])
        assert today_times == cal_times and len(cal_times) == 4

        by_title = {i["title"]: i for i in cal["timeline"]}
        assert by_title["Call mom"]["is_fixed"] is True and by_title["Gym"]["is_fixed"] is True
        assert by_title["Finish DSA assignment"]["is_fixed"] is False
        assert by_title["Gym"]["time"] == "5:30" and by_title["Gym"]["period"] == "PM"
        assert_no_overlap([(_dt(i["start_time"]), _dt(i["end_time"])) for i in cal["timeline"]])

        rows = {t.title: t for t in db_tasks(uid)}
        assert rows["Gym"].time_locked and rows["Call mom"].time_locked and not rows["Email prof"].time_locked
        before = sig_calendar(cal)

    # 5. restart: only persisted state remains
    restart()
    async with client() as ac:
        cal2 = await calendar_day(ac, h)
        today2 = (await ac.get("/api/v1/today", headers=h)).json()
        assert sig_calendar(cal2) == before
        assert sorted((i["title"], i["time"], i["period"]) for i in today2["upcoming_timeline"]) == cal_times
        # 6. confirming the same plan again (double tap after restart) creates nothing
        again = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json={
            "tasks": items, "plan_id": "e2e-a", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
        assert again.json()["idempotent_replay"] is True
    assert len(db_tasks(uid)) == 4


# ═════════════════════════════════════════════════════════════════════════════
@pytest.mark.asyncio
async def test_E2E_B_realistic_day_complete_start_urgent_replan_apply(frozen_clock):
    uid, h = make_user()
    db = SessionLocal()

    def add(title, start, minutes, **kw):
        t = Task(user_id=uid, title=title, estimated_minutes=minutes, scheduled_start=start.astimezone(timezone.utc),
                 scheduled_end=(start + timedelta(minutes=minutes)).astimezone(timezone.utc), **kw)
        db.add(t)
        db.commit()
        return str(t.id)

    standup = add("Standup", at(9, 0), 30, time_locked=True)              # fixed event
    dentist = add("Dentist", at(18, 0), 45, time_locked=True)              # fixed event
    report = add("Write report", at(10, 0), 60, deadline_at=at(17, 0).astimezone(timezone.utc))
    study = add("Study DSA", at(11, 30), 90)
    email = add("Email batch", at(14, 0), 30)
    gym = add("Gym", at(16, 0), 60)
    db.close()

    fixed_before = {t.title: (t.scheduled_start, t.scheduled_end) for t in db_tasks(uid) if t.title in ("Standup", "Dentist")}

    async with client() as ac:
        # complete one, start another (via the real endpoints)
        r = await ac.post(f"/api/v1/tasks/{standup}/complete", headers=h, json={"completed_at": at(9, 30).astimezone(timezone.utc).isoformat()})
        assert r.status_code == 200
        r = await ac.post(f"/api/v1/tasks/{report}/start", headers=h)
        assert r.status_code == 200
        db = SessionLocal()   # the start endpoint stamps the real wall clock; align it with the frozen test clock
        db.query(Task).filter(Task.id == report).update({"started_at": at(10, 0).astimezone(timezone.utc)})
        db.commit()
        db.close()

        now = at(10, 45)  # report has been running 45 of its 60 minutes
        r = await ac.post("/api/v1/ai/replan", headers=h, json={
            "selected_date": "2026-10-05", "user_message": "urgent client fix needs 2 hours at 3 PM",
            "current_local_time": now.isoformat(), "timezone": "Asia/Kolkata"})
        assert r.status_code == 200, r.text
        diff = r.json()["plan_diff"]

        protected = {p["title"] for p in diff["skipped_immutable"]}
        assert {"Standup", "Write report"} <= protected
        assert "Dentist" not in {m["title"] for m in diff["moved_tasks"]}
        # urgent 3-5 PM collides with Email (14:00-14:30)? no; with Gym 16:00-17:00 -> Gym must be displaced
        new_titles = {n["title"] for n in diff["newly_scheduled_tasks"]}
        assert any("client fix" in t.lower() for t in new_titles), new_titles

        applied = await ac.post("/api/v1/calendar/apply-replan", headers=h, json={
            **diff["apply_request"], "current_local_time": now.isoformat(), "timezone": "Asia/Kolkata"})
        assert applied.status_code == 200, applied.text
        res = applied.json()

        # database == apply response == calendar == today
        rows = {t.title: t for t in db_tasks(uid)}
        for pt in res["persisted_tasks"]:
            r_ = next(t for t in rows.values() if str(t.id) == pt["id"])
            assert _dt(pt["scheduled_start"]) == r_.scheduled_start if pt["scheduled_start"] else r_.scheduled_start is None
        # completed + in-progress preserved
        assert rows["Standup"].status == TaskStatus.completed and rows["Standup"].scheduled_start == at(9, 0)
        assert rows["Write report"].status == TaskStatus.in_progress and rows["Write report"].scheduled_start == at(10, 0)
        # fixed events untouched
        for name, (s, e) in fixed_before.items():
            assert (rows[name].scheduled_start, rows[name].scheduled_end) == (s, e), name
        # deadline respected
        assert rows["Write report"].scheduled_end <= at(17)
        # urgent exists exactly once, exactly at 3 PM (explicit "at" lock), locked
        urgent = [t for t in rows.values() if "client fix" in t.title.lower()]
        assert len(urgent) == 1 and urgent[0].time_locked and urgent[0].scheduled_start == at(15) and urgent[0].priority.value == "urgent"
        # nothing duplicated or lost
        assert len(db_tasks(uid)) == 7

        cal = await calendar_day(ac, h, now=now)
        open_slots = [(_dt(i["start_time"]), _dt(i["end_time"])) for i in cal["timeline"]]
        # no overlaps among everything shown (completed, in-progress, fixed, flexible)
        assert_no_overlap(open_slots)
        # every flexible, not-yet-started task is in the future
        for t in rows.values():
            if t.status == TaskStatus.todo and not t.time_locked and t.scheduled_start:
                assert t.scheduled_start >= now, t.title
        # Today shows the same non-completed times as the calendar
        today = (await ac.get("/api/v1/today", headers=h)).json()
        assert sorted((i["title"], i["time"], i["period"]) for i in today["upcoming_timeline"]) == \
            sorted((i["title"], i["time"], i["period"]) for i in cal["timeline"] if not i["is_completed"])

    restart()
    async with client() as ac:
        cal2 = await calendar_day(ac, h, now=now)
    assert sig_calendar(cal2) == sig_calendar(cal)


# ═════════════════════════════════════════════════════════════════════════════
@pytest.mark.asyncio
async def test_E2E_C_user_isolation_across_plan_replan_and_logout_login(monkeypatch, frozen_clock):
    ua, ha = make_user(prefix="alice")
    ub, hb = make_user(prefix="bob")
    stub_extraction(monkeypatch, [cand("Alice secret thesis", 60), fixed_cand("Alice dentist", at(18), 45)])
    async with client() as ac:
        plan = (await post_plan(ac, ha, NOW, text="alice")).json()
        items = [{"title": t["title"], "estimated_minutes": t["estimated_minutes"],
                  "scheduled_start": t["recommended_slot_start"], "time_locked": t["time_locked"]} for t in plan["tasks"]]
        await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=ha, json={
            "tasks": items, "plan_id": "alice-plan", "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
        cal_a = await calendar_day(ac, ha)
        replan_a = (await ac.post("/api/v1/ai/replan", headers=ha, json={
            "selected_date": "2026-10-05", "user_message": "urgent thing needs 30 minutes",
            "current_local_time": NOW.isoformat(), "timezone": "Asia/Kolkata"})).json()["plan_diff"]

        # --- "logout" A, "login" B: B sees nothing of A ---
        cal_b = await calendar_day(ac, hb)
        today_b = (await ac.get("/api/v1/today", headers=hb)).json()
        tasks_b = (await ac.get("/api/v1/tasks", headers=hb)).json()
        assert cal_b["timeline"] == [] and today_b["upcoming_timeline"] == [] and tasks_b["total"] == 0
        diff_b = (await ac.post("/api/v1/ai/replan", headers=hb, json={
            "selected_date": "2026-10-05", "user_message": "urgent thing at 6 PM needs 45 minutes",
            "current_local_time": NOW.isoformat(), "timezone": "Asia/Kolkata"})).json()["plan_diff"]
        assert diff_b["conflicts"] == [], "Alice's 6 PM dentist must be invisible to Bob"
        assert diff_b["moved_tasks"] == [] and diff_b["unchanged_tasks"] == []

        # B tries to apply A's plan payload against A's task ids: nothing changes
        hostile = {**replan_a["apply_request"], "plan_id": "bob-hostile", "current_local_time": NOW.isoformat()}
        r = await ac.post("/api/v1/calendar/apply-replan", headers=hb, json=hostile)
        assert r.status_code == 200
        assert r.json()["updated_count"] == 0 and r.json()["cancelled_count"] == 0
        assert all(s["reason"] == "not_found" for s in r.json()["skipped"])
        # new_tasks in a payload are created for the AUTHENTICATED user only (Bob's own row), never for Alice
        assert r.json()["created_count"] == len(replan_a["apply_request"]["new_tasks"])

        # --- A "logs back in": state identical ---
        restart()
        cal_a2 = await calendar_day(ac, ha)
    assert sig_calendar(cal_a2) == sig_calendar(cal_a)
    assert len(db_tasks(ua)) == 2, "Alice's data is exactly what she created"
    assert all(t.user_id == ub for t in db_tasks(ub)) and len(db_tasks(ub)) == len(replan_a["apply_request"]["new_tasks"])


# ═════════════════════════════════════════════════════════════════════════════
@pytest.mark.asyncio
@pytest.mark.parametrize("tzname,tz,now_local", [
    ("Asia/Kolkata", IST, datetime(2026, 10, 5, 23, 40, tzinfo=IST)),
    ("Asia/Kolkata", IST, datetime(2026, 10, 6, 0, 10, tzinfo=IST)),
    ("America/Los_Angeles", LA, datetime(2026, 11, 1, 0, 20, tzinfo=LA)),   # US DST ends 01:00-02:00 that night
    ("America/Los_Angeles", LA, datetime(2026, 11, 1, 23, 50, tzinfo=LA)),
])
async def test_E2E_D_time_and_date_boundaries(monkeypatch, tzname, tz, now_local):
    uid, h = make_user(tz=tzname)
    stub_extraction(monkeypatch, [cand("Write report", 60), cand("Email", 30)])
    async with client() as ac:
        r = await post_plan(ac, h, now_local, tz=tzname)
        body = r.json()
        assert r.status_code == 200 and body["scheduling_error"] is None and body["timezone_used"] == tzname
        slots = []
        for t in body["tasks"]:
            s, e = _dt(t["recommended_slot_start"]), _dt(t["recommended_slot_end"])
            assert s >= now_local, "never in the past"
            local = s.astimezone(tz)
            assert 6 <= local.hour < 23, f"outside waking hours: {local}"
            assert t["recommended_slot_date"] == local.date().isoformat()
            slots.append((s, e))
        assert_no_overlap(slots)
        # replan on the boundary day never places anything before 'now' or off the requested day
        rp = await ac.post("/api/v1/ai/replan", headers=h, json={
            "selected_date": now_local.date().isoformat(), "user_message": "urgent thing needs 30 minutes",
            "current_local_time": now_local.isoformat(), "timezone": tzname})
        assert rp.status_code == 200, rp.text
        diff = rp.json()["plan_diff"]
        for n in diff["newly_scheduled_tasks"]:
            assert _dt(n["new_start"]) >= now_local
        for u in diff["unscheduled_tasks"]:
            if u["suggestion_start"]:
                assert _dt(u["suggestion_start"]).astimezone(tz).date() > now_local.date() or _dt(u["suggestion_start"]) >= now_local
