"""The day Trophy: the rule table, driven through the real endpoints (complete a task by the API, read the day, claim).

Rule (unchanged): a day earns it when it is today or earlier, at least one non-commitment task was completed, and no
non-commitment task is still open on it. Skipped-and-gone does not block; skipped-but-still-open and missed do.
"""
import pytest

from tests.plan_helpers import client, make_user
from tests.test_apply_replan_semantics import at, seed
from tests.test_missed_state import D, day, now_at

DAY = "2026-10-05"


async def complete(ac, h, task_id):
    r = await ac.post(f"/api/v1/tasks/{task_id}/complete", headers=h, json={})
    assert r.status_code == 200, r.text


async def claim(ac, h, d=DAY):
    return await ac.post("/api/v1/flow/day-complete/claim", headers=h, json={"date": d, "timezone": "Asia/Kolkata"})


@pytest.mark.asyncio
async def test_all_tasks_completed_through_the_api_earns_the_trophy():
    uid, h = make_user()
    a, b = seed(uid, "A", at(9), 30, planned_date=D), seed(uid, "B", at(10), 30, planned_date=D)
    async with client() as ac:
        await complete(ac, h, a)
        assert (await day(ac, h, now_at(12)))["day_complete"]["eligible"] is False, "B is still open"
        await complete(ac, h, b)
        assert (await day(ac, h, now_at(12)))["day_complete"]["eligible"] is True


@pytest.mark.asyncio
async def test_completed_plus_a_task_still_open_after_a_skip_blocks_it():
    uid, h = make_user()
    a, b = seed(uid, "A", at(9), 30, planned_date=D), seed(uid, "B", at(10), 30, planned_date=D)
    async with client() as ac:
        await complete(ac, h, a)
        skip = await ac.post(f"/api/v1/today/skip/{b}", headers=h, json={"timezone": "Asia/Kolkata"},
                             params={"current_local_time": now_at(9, 30).isoformat()})
        assert skip.status_code == 200, skip.text
        body = await day(ac, h, now_at(9, 40))
    moved_away = [t for t in body["timeline"] if t.get("task_id") == b]
    # product rule: a skipped task that lands later TODAY is still open work; one that leaves the day does not block
    assert body["day_complete"]["eligible"] is (not moved_away), body["day_complete"]


@pytest.mark.asyncio
async def test_a_day_with_nothing_completed_never_earns_it():
    uid, h = make_user()
    seed(uid, "A", at(9), 30, planned_date=D)
    async with client() as ac:
        assert (await day(ac, h, now_at(12)))["day_complete"]["eligible"] is False


@pytest.mark.asyncio
async def test_an_empty_day_never_earns_it():
    _, h = make_user()
    async with client() as ac:
        assert (await day(ac, h, now_at(12)))["day_complete"]["eligible"] is False


@pytest.mark.asyncio
async def test_a_future_day_never_earns_it_even_when_all_its_tasks_are_done():
    uid, h = make_user()
    t = seed(uid, "Tomorrow task", at(9, day=6), 30, planned_date=D.replace(day=6))
    async with client() as ac:
        await complete(ac, h, t)
        body = await day(ac, h, now_at(12), d="2026-10-06")
    assert body["day_complete"]["eligible"] is False


@pytest.mark.asyncio
async def test_repeated_reads_and_claims_are_stable_and_pay_once():
    uid, h = make_user()
    a = seed(uid, "A", at(9), 30, planned_date=D)
    async with client() as ac:
        await complete(ac, h, a)
        reads = [(await day(ac, h, now_at(12)))["day_complete"] for _ in range(3)]
        first, second, third = await claim(ac, h), await claim(ac, h), await claim(ac, h)
        after = await day(ac, h, now_at(12))
    assert all(r["eligible"] for r in reads) and all(r == reads[0] for r in reads)
    assert [first.json()["xp_awarded"], second.json()["xp_awarded"], third.json()["xp_awarded"]] == [25, 0, 0]
    assert after["day_complete"]["claimed"] is True and after["day_complete"]["eligible"] is True


@pytest.mark.asyncio
async def test_a_claimed_day_stays_claimed_when_a_task_is_added_later():
    uid, h = make_user()
    a = seed(uid, "A", at(9), 30, planned_date=D)
    async with client() as ac:
        await complete(ac, h, a)
        assert (await claim(ac, h)).status_code == 200
        seed(uid, "Late addition", at(20), 30, planned_date=D)
        body = await day(ac, h, now_at(12))
    assert body["day_complete"]["claimed"] is True, "the XP already paid is never taken back"
