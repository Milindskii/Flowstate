"""Auto-skip: open stops between two done stops. A done + C done + B open -> B; A, D done -> B and C. Kept in place."""
from datetime import datetime, time, timedelta, timezone

import pytest

from app.models.task import TaskStatus
from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import get, seed
from tests.test_missed_state import deviations


def _local_today_at(h):
    """A slot TOMORROW (local): its time has not passed whenever the test runs, so the stops are upcoming, not missed."""
    day = datetime.now(timezone.utc).astimezone(IST).date() + timedelta(days=1)
    return datetime.combine(day, time(h), tzinfo=IST)


def _utc(dt):
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


@pytest.mark.asyncio
async def test_a_done_b_open_c_done_auto_skips_b_in_place():
    uid, h = make_user()
    day = _local_today_at(0).date()
    a = seed(uid, "A", _local_today_at(9), 30, planned_date=day)
    b = seed(uid, "B", _local_today_at(10), 30, planned_date=day)
    c = seed(uid, "C", _local_today_at(11), 30, planned_date=day)
    d = seed(uid, "D", _local_today_at(12), 30, planned_date=day)
    meeting = seed(uid, "Meeting", _local_today_at(10) + timedelta(minutes=30), 15, planned_date=day, is_commitment=True)
    b_start, b_end = get(b).scheduled_start, get(b).scheduled_end
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert deviations(uid) == []  # nothing is closed in yet
        r = await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "completed"
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": day.isoformat(), "timezone": "Asia/Kolkata"})).json()

    devs = deviations(uid)
    assert [(dv.task_id, dv.kind) for dv in devs] == [(b, "auto_skipped")]  # its own state, not an explicit "skipped"
    assert _utc(devs[0].original_start) == _utc(b_start)
    # B stays exactly where it was planned: not moved, not done
    assert get(b).status == TaskStatus.todo
    assert _utc(get(b).scheduled_start) == _utc(b_start) and _utc(get(b).scheduled_end) == _utc(b_end)
    assert get(b).planned_date == day
    assert get(d).status == TaskStatus.todo                 # after C, with nothing done after it: untouched
    assert get(meeting).status == TaskStatus.todo           # commitments are never stops here
    ghosts = [i for i in view["deviations"] if i["task_id"] == b]
    assert len(ghosts) == 1 and ghosts[0]["deviation"] == "auto_skipped" and ghosts[0]["is_skipped"] is True
    assert ghosts[0]["tag_text"] == "AUTO-SKIPPED"


@pytest.mark.asyncio
async def test_a_done_b_c_open_d_done_auto_skips_b_and_c_in_place():
    uid, h = make_user()
    day = _local_today_at(0).date()
    a = seed(uid, "A", _local_today_at(9), 30, planned_date=day)
    b = seed(uid, "B", _local_today_at(10), 30, planned_date=day)
    c = seed(uid, "C", _local_today_at(11), 30, planned_date=day)
    d = seed(uid, "D", _local_today_at(12), 30, planned_date=day)
    e = seed(uid, "E", _local_today_at(13), 30, planned_date=day)
    b_start, c_start = get(b).scheduled_start, get(c).scheduled_start
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert (await ac.post(f"/api/v1/tasks/{d}/complete", headers=h, json={})).status_code == 200
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": day.isoformat(), "timezone": "Asia/Kolkata"})).json()
    assert sorted((dv.task_id, dv.kind) for dv in deviations(uid)) == sorted([(b, "auto_skipped"), (c, "auto_skipped")])
    for tid, start in ((b, b_start), (c, c_start)):  # both stay at their own slots, open
        assert get(tid).status == TaskStatus.todo and _utc(get(tid).scheduled_start) == _utc(start)
    assert get(e).status == TaskStatus.todo  # after D, nothing done after it: not closed in
    assert {i["task_id"] for i in view["deviations"] if i["deviation"] == "auto_skipped"} == {b, c}


@pytest.mark.asyncio
async def test_a_longer_run_is_auto_skipped_and_un_completing_restores_the_whole_run():
    uid, h = make_user()
    day = _local_today_at(0).date()
    ids = [seed(uid, n, _local_today_at(9 + k), 30, planned_date=day) for k, n in enumerate("ABCDE")]
    a, b, c, d, e = ids
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert (await ac.post(f"/api/v1/tasks/{e}/complete", headers=h, json={})).status_code == 200
        assert sorted(dv.task_id for dv in deviations(uid)) == sorted([b, c, d])
        assert (await ac.patch(f"/api/v1/tasks/{e}", headers=h, json={"status": "todo"})).status_code == 200
    assert deviations(uid) == []  # nothing closes them in any more: B, C and D are Open again


@pytest.mark.asyncio
async def test_completing_a_after_c_also_closes_in_b():
    """The rule is about the state, not the order of the taps: C done first, then A, still leaves B in the middle."""
    uid, h = make_user()
    day = _local_today_at(0).date()
    a = seed(uid, "A", _local_today_at(9), 30, planned_date=day)
    b = seed(uid, "B", _local_today_at(10), 30, planned_date=day)
    c = seed(uid, "C", _local_today_at(11), 30, planned_date=day)
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})).status_code == 200
        assert deviations(uid) == []  # B is first-but-one with nothing done before it yet
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
    assert [(dv.task_id, dv.kind) for dv in deviations(uid)] == [(b, "auto_skipped")]


@pytest.mark.asyncio
async def test_first_stop_is_never_in_the_middle():
    uid, h = make_user()
    day = _local_today_at(0).date()
    a = seed(uid, "A", _local_today_at(9), 30, planned_date=day)
    b = seed(uid, "B", _local_today_at(10), 30, planned_date=day)
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{b}/complete", headers=h, json={})).status_code == 200
    assert deviations(uid) == []
    assert get(a).status == TaskStatus.todo


@pytest.mark.asyncio
async def test_in_progress_and_other_day_tasks_are_not_bypassed():
    uid, h = make_user()
    day = _local_today_at(0).date()
    yesterday = seed(uid, "Yesterday", _local_today_at(8) - timedelta(days=1), 30,
                     planned_date=day - timedelta(days=1))
    a = seed(uid, "A", _local_today_at(8), 30, planned_date=day)
    working = seed(uid, "Working", _local_today_at(9), 30, planned_date=day, status=TaskStatus.in_progress)
    c = seed(uid, "C", _local_today_at(11), 30, planned_date=day)
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert (await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})).status_code == 200
    assert deviations(uid) == []
    assert get(working).status == TaskStatus.in_progress
    assert get(yesterday).status == TaskStatus.todo


@pytest.mark.asyncio
async def test_a_slot_that_already_ended_stays_missed_and_is_not_auto_skipped():
    uid, h = make_user()
    yesterday = datetime.now(timezone.utc).astimezone(IST).date() - timedelta(days=1)
    a = seed(uid, "A", datetime.combine(yesterday, time(8), tzinfo=IST), 30, planned_date=yesterday)
    ended = seed(uid, "Ended", datetime.combine(yesterday, time(9), tzinfo=IST), 30, planned_date=yesterday)
    c = seed(uid, "C", datetime.combine(yesterday, time(11), tzinfo=IST), 30, planned_date=yesterday)
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert (await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})).status_code == 200
    assert deviations(uid) == []  # missed is derived from the clock; no auto-skip is recorded over it
    assert get(ended).status == TaskStatus.todo


@pytest.mark.asyncio
async def test_un_completing_c_restores_auto_skipped_b_to_open():
    uid, h = make_user()
    day = _local_today_at(0).date()
    a = seed(uid, "A", _local_today_at(9), 30, planned_date=day)
    b = seed(uid, "B", _local_today_at(10), 30, planned_date=day)
    c = seed(uid, "C", _local_today_at(11), 30, planned_date=day)
    b_start = get(b).scheduled_start
    async with client() as ac:
        assert (await ac.post(f"/api/v1/tasks/{a}/complete", headers=h, json={})).status_code == 200
        assert (await ac.post(f"/api/v1/tasks/{c}/complete", headers=h, json={})).status_code == 200
        assert [(dv.task_id, dv.kind) for dv in deviations(uid)] == [(b, "auto_skipped")]
        r = await ac.patch(f"/api/v1/tasks/{c}", headers=h, json={"status": "todo"})
        assert r.status_code == 200, r.text
        view = (await ac.get("/api/v1/calendar/day", headers=h, params={
            "date": day.isoformat(), "timezone": "Asia/Kolkata"})).json()
    assert deviations(uid) == []  # B is Open again
    assert get(b).status == TaskStatus.todo and _utc(get(b).scheduled_start) == _utc(b_start)
    assert not [i for i in view["deviations"] if i["task_id"] == b]
    assert get(a).status == TaskStatus.completed  # nothing else changes
