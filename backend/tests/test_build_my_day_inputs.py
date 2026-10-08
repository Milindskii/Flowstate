"""Build My Day across realistic inputs (spec section 12). Contract invariants are asserted,
never exact slots, so the tests do not depend on the wall clock."""
from datetime import datetime, timedelta

import pytest

from app.schemas.task import (
    AvailabilityContext,
    FixedEventContext,
    PlanningContext,
    TaskDependencyContext,
)
from tests.plan_helpers import (
    IST,
    cand,
    client,
    fixed_cand,
    make_user,
    post_plan,
    stub_deterministic_extraction,
    stub_extraction,
)


def _dt(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))


def real_now():
    return datetime.now(IST).replace(second=0, microsecond=0)


def assert_contract(body, now):
    """C4/C5/C6 on a /ai/plan response."""
    assert body["scheduling_error"] is None, body
    spans = []
    for t in body["tasks"]:
        if not t["recommended_slot_start"]:
            continue
        s, e = _dt(t["recommended_slot_start"]), _dt(t["recommended_slot_end"])
        assert s >= now - timedelta(seconds=60), (t["title"], s, now)
        assert e > s
        if t["deadline_at"]:
            assert e <= _dt(t["deadline_at"]), (t["title"], e, t["deadline_at"])
        spans.append((t["title"], s, e, t["time_locked"]))
    for i, a in enumerate(spans):
        for b in spans[i + 1:]:
            if a[3] and b[3]:
                continue  # two user-fixed times may overlap; reported in `conflicts`
            assert not (a[1] < b[2] and a[2] > b[1]), f"overlap: {a[0]} / {b[0]}"
    return spans


TEXTS = {
    "simple": "finish the DSA assignment",
    "messy": "ugh so much to do. need to finish the DSA assignment, then gym, also email prof and call mom at 7pm",
    "paragraph": "gym, groceries, email and laundry",
    "explicit_time": "dentist at 6 PM",
    "explicit_duration": "write the report for 2 hours",
    "deadline": "submit the assignment by friday 5pm",
    "time_and_deadline": "study DSA tomorrow at 9 AM and submit the lab report by friday",
    "fixed_plus_flexible": "team meeting at 3 PM, write the report and go to the gym",
    "conflicting": "call mom at 7 PM and gym at 7 PM",
    "duplicate_like": "gym, gym",
}


@pytest.mark.asyncio
@pytest.mark.parametrize("name", sorted(TEXTS))
async def test_deterministic_inputs_honour_the_contract(monkeypatch, name):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    now = real_now()
    async with client() as ac:
        r = await post_plan(ac, h, now, text=TEXTS[name])
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["tasks"], f"{name}: no tasks extracted"
    assert_contract(body, now)
    # an explicit user clock time is never silently moved
    for t in body["tasks"]:
        if t["time_locked"]:
            assert t["scheduled_start"] and _dt(t["recommended_slot_start"]) == _dt(t["scheduled_start"])
    # nothing silently disappears: every extracted task is either slotted or explains why not
    for t in body["tasks"]:
        assert t["recommended_slot_start"] or t["unscheduled_reason"], t["title"]


@pytest.mark.asyncio
async def test_explicit_time_input_is_locked_and_exact(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    now = datetime.now(IST).replace(hour=5, minute=0, second=0, microsecond=0)  # 5 AM: 6 PM is future
    async with client() as ac:
        r = await post_plan(ac, h, now, text="dentist at 6 PM")
    t = r.json()["tasks"][0]
    assert t["time_locked"] is True
    assert _dt(t["recommended_slot_start"]).astimezone(IST).hour == 18


@pytest.mark.asyncio
async def test_bare_hour_is_preference_not_lock(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    now = real_now().replace(hour=5, minute=0)
    async with client() as ac:
        r = await post_plan(ac, h, now, text="gym around 6 PM")
    t = r.json()["tasks"][0]
    assert t["time_locked"] is False


@pytest.mark.asyncio
async def test_explicit_duration_is_used(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, real_now().replace(hour=7, minute=30), text=TEXTS["explicit_duration"])
    t = r.json()["tasks"][0]
    assert t["estimated_minutes"] == 120
    assert (_dt(t["recommended_slot_end"]) - _dt(t["recommended_slot_start"])) == timedelta(minutes=120)


@pytest.mark.asyncio
async def test_conflicting_explicit_times_are_both_kept_and_reported(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    now = real_now().replace(hour=5, minute=0)
    async with client() as ac:
        r = await post_plan(ac, h, now, text=TEXTS["conflicting"])
    body = r.json()
    locked = [t for t in body["tasks"] if t["time_locked"]]
    assert len(locked) == 2
    assert _dt(locked[0]["recommended_slot_start"]) == _dt(locked[1]["recommended_slot_start"])
    assert any(c["code"] == "locked_overlap" for c in body["conflicts"])


@pytest.mark.asyncio
async def test_optional_low_priority_task_yields_to_deadline_work_late_in_the_day(monkeypatch):
    now = datetime(2026, 10, 5, 20, 0, tzinfo=IST)
    dl = datetime(2026, 10, 5, 23, 15, tzinfo=IST)
    stub_extraction(monkeypatch, [
        cand("Optional: tidy desk", 60, priority="low"),
        cand("Urgent report", 60, priority="urgent", deadline_at=dl),
        cand("Pay bills", 45, priority="high", deadline_at=dl),
    ])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, now)
    body = r.json()
    by = {t["title"]: t for t in body["tasks"]}
    assert_contract(body, now)
    # the two deadline tasks take the remaining evening; the optional task (no deadline) does not displace them
    for title in ("Urgent report", "Pay bills"):
        assert by[title]["recommended_slot_date"] == "2026-10-05", title
        assert _dt(by[title]["recommended_slot_end"]) <= dl
    # and nothing is silently lost: the optional one is slotted (probably tomorrow) or explains why not
    opt = by["Optional: tidy desk"]
    assert opt["recommended_slot_start"] or opt["unscheduled_reason"]


@pytest.mark.asyncio
async def test_date_boundary_late_night_rolls_to_tomorrow(monkeypatch):
    now = datetime(2026, 10, 5, 23, 50, tzinfo=IST)
    stub_extraction(monkeypatch, [cand("Write report", 60), cand("Email", 30)])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, now)
    body = r.json()
    assert_contract(body, now)
    for t in body["tasks"]:
        assert t["recommended_slot_date"] == "2026-10-06"
        assert 7 <= _dt(t["recommended_slot_start"]).astimezone(IST).hour < 23


@pytest.mark.asyncio
async def test_empty_and_invalid_input(monkeypatch):
    stub_deterministic_extraction(monkeypatch)
    _, h = make_user()
    async with client() as ac:
        r1 = await ac.post("/api/v1/ai/plan", headers=h, json={"raw_text": ""})
        r2 = await ac.post("/api/v1/ai/plan", headers=h, json={})
        r3 = await ac.post("/api/v1/ai/plan", headers=h, json={"raw_text": "x " * 1000})  # over the word limit
    assert r1.status_code == 422 and r2.status_code == 422 and r3.status_code == 422


@pytest.mark.asyncio
async def test_planning_context_fixed_event_dependency_and_availability(monkeypatch):
    now = datetime(2026, 10, 5, 8, 0, tzinfo=IST)
    ctx = PlanningContext(
        fixed_events=[FixedEventContext(title="Client call", start_time="10:00", end_time="11:00")],
        availability_windows=[AvailabilityContext(label="office", start_time="09:30", end_time="17:30")],
        task_dependencies=[TaskDependencyContext(predecessor="draft", successor="submit")],
    )
    stub_extraction(monkeypatch, [cand("Submit proposal", 30), cand("Draft proposal", 60)], planning_context=ctx)
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, now)
    body = r.json()
    assert_contract(body, now)
    by = {t["title"]: t for t in body["tasks"]}
    d_s, d_e = _dt(by["Draft proposal"]["recommended_slot_start"]), _dt(by["Draft proposal"]["recommended_slot_end"])
    s_s = _dt(by["Submit proposal"]["recommended_slot_start"])
    assert s_s >= d_e, "dependency: submit after draft"
    for t in by.values():  # office-hours window bounds every task
        s, e = _dt(t["recommended_slot_start"]).astimezone(IST), _dt(t["recommended_slot_end"]).astimezone(IST)
        assert s.hour * 60 + s.minute >= 9 * 60 + 30 and e.hour * 60 + e.minute <= 17 * 60 + 30
        # client call 10:00-11:00 is hard busy time
        assert not (s < datetime(2026, 10, 5, 11, 0, tzinfo=IST) and e > datetime(2026, 10, 5, 10, 0, tzinfo=IST))


@pytest.mark.asyncio
async def test_hallucinated_inferred_time_does_not_lock(monkeypatch):
    c = fixed_cand("Maybe call bank", datetime(2026, 10, 5, 15, 0, tzinfo=IST), 30)
    c.temporal.provenance["fixed_start"].source = "inferred"
    c.field_provenance["scheduled_time"].source = "inferred"
    stub_extraction(monkeypatch, [c])
    _, h = make_user()
    async with client() as ac:
        r = await post_plan(ac, h, datetime(2026, 10, 5, 9, 0, tzinfo=IST))
    assert r.json()["tasks"][0]["time_locked"] is False
