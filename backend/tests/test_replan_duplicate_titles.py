"""Replan with the same task name on two days: "today's gym" and "tomorrow's gym" are different tasks.

Manual report: Gym today + Gym tomorrow, "move today's gym to tomorrow" moved the wrong one. Cause: Replan only sees
the day on screen and ignored the day the user named, so with Calendar on tomorrow it moved tomorrow's Gym.
Rule now: a message that names a day other than the one on screen changes nothing and says where to ask. The task a
message names is never guessed across days.
"""
from datetime import date

import pytest

from tests.plan_helpers import IST, client, make_user
from tests.test_apply_replan_semantics import at, get, replan, seed

TODAY, TOMORROW, FRIDAY = "2026-10-05", "2026-10-06", "2026-10-09"  # the clock is Monday 5 Oct 09:00


def moved_ids(diff):
    if not diff.get("apply_request"):
        return []
    return [u["task_id"] for u in diff["apply_request"]["task_updates"]]


def cancelled_ids(diff):
    if not diff.get("apply_request"):
        return []
    return list(diff["apply_request"]["cancelled_task_ids"])


async def two_gyms():
    uid, h = make_user()
    return uid, h, seed(uid, "Gym", at(17), 60), seed(uid, "Gym", at(17, day=6), 60)


def assert_untouched(diff, *task_ids):
    assert moved_ids(diff) == [] and cancelled_ids(diff) == [], diff["apply_request"]
    assert diff["conflicts"], "the user is told why nothing changed"
    for task_id in task_ids:
        assert get(task_id).scheduled_start is not None


# ── the day named is the day on screen: that day's task moves ────────────────────────────────────────────────
@pytest.mark.asyncio
@pytest.mark.parametrize("message", [
    "move today's gym to tomorrow",
    "move todays gym to tomorrow",
    "push today's gym to tomorrow",
    "move the gym today to tomorrow",
    "move gym to tomorrow",
])
async def test_todays_gym_moves_when_today_is_on_screen(message):
    _, h, today_gym, tomorrow_gym = await two_gyms()
    async with client() as ac:
        diff = await replan(ac, h, message, day=TODAY)
    assert moved_ids(diff) == [today_gym]
    assert get(tomorrow_gym).scheduled_start.astimezone(IST).date() == date(2026, 10, 6)


@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["move tomorrow's gym to friday", "move tomorrows gym to friday", "move the gym tomorrow to friday"])
async def test_tomorrows_gym_moves_when_tomorrow_is_on_screen(message):
    _, h, today_gym, tomorrow_gym = await two_gyms()
    async with client() as ac:
        diff = await replan(ac, h, message, day=TOMORROW)
    assert moved_ids(diff) == [tomorrow_gym]
    assert get(today_gym).scheduled_start.astimezone(IST).date() == date(2026, 10, 5)


# ── the day named is NOT the day on screen: never the other day's task ────────────────────────────────────────
@pytest.mark.asyncio
@pytest.mark.parametrize("message", [
    "move today's gym to tomorrow",
    "move todays gym to tomorrow",
    "push today's gym to tomorrow",
    "move the gym today to tomorrow",
    "skip today's gym",
    "cancel today's gym",
])
async def test_todays_gym_named_while_tomorrow_is_on_screen_changes_nothing(message):
    _, h, today_gym, tomorrow_gym = await two_gyms()
    async with client() as ac:
        diff = await replan(ac, h, message, day=TOMORROW)
    assert_untouched(diff, today_gym, tomorrow_gym)
    assert "today" in " ".join(diff["conflicts"]).lower(), diff["conflicts"]


@pytest.mark.asyncio
@pytest.mark.parametrize("message", [
    "move tomorrow's gym to friday",
    "move the gym tomorrow to friday",
    "skip tomorrow's gym",
    "cancel tomorrow's gym",
])
async def test_tomorrows_gym_named_while_today_is_on_screen_changes_nothing(message):
    _, h, today_gym, tomorrow_gym = await two_gyms()
    async with client() as ac:
        diff = await replan(ac, h, message, day=TODAY)
    assert_untouched(diff, today_gym, tomorrow_gym)
    assert "tomorrow" in " ".join(diff["conflicts"]).lower(), diff["conflicts"]


@pytest.mark.asyncio
@pytest.mark.parametrize("message,named", [
    ("move friday's gym to monday", "friday"),
    ("move the gym on friday to monday", "friday"),
    ("move gym on 9 oct to monday", "friday"),
    ("move gym on oct 9 to monday", "friday"),
    ("move gym on 2026-10-09 to monday", "friday"),
])
async def test_a_specific_day_that_is_not_on_screen_changes_nothing(message, named):
    uid, h, today_gym, tomorrow_gym = await two_gyms()
    friday_gym = seed(uid, "Gym", at(17, day=9), 60)
    async with client() as ac:
        diff = await replan(ac, h, message, day=TODAY)
    assert_untouched(diff, today_gym, tomorrow_gym, friday_gym)
    assert named in " ".join(diff["conflicts"]).lower(), diff["conflicts"]


# ── destinations are not sources, and plain messages are unchanged ───────────────────────────────────────────
@pytest.mark.asyncio
@pytest.mark.parametrize("message", ["move gym to friday", "push gym to tomorrow", "defer gym", "skip gym", "move gym to monday"])
async def test_a_destination_day_is_not_mistaken_for_the_source(message):
    _, h, today_gym, tomorrow_gym = await two_gyms()
    async with client() as ac:
        diff = await replan(ac, h, message, day=TODAY)
    assert moved_ids(diff) == [today_gym]


@pytest.mark.asyncio
async def test_two_gyms_on_the_same_day_are_still_asked_about_not_guessed():
    uid, h = make_user()
    first, second = seed(uid, "Gym", at(10), 60), seed(uid, "Gym", at(17), 60)
    async with client() as ac:
        diff = await replan(ac, h, "move gym to tomorrow", day=TODAY)
    assert moved_ids(diff) == []
    assert diff.get("clarification"), "ambiguity is surfaced as clarification options"
    clar = diff["clarification"]
    assert len(clar["options"]) == 2
    labels = [o["label"] for o in clar["options"]]
    assert any("10:00 AM" in l for l in labels)
    assert any("5:00 PM" in l for l in labels)
    # Choosing the first option acts on that exact task, not both
    async with client() as ac:
        diff2 = await replan(ac, h, clar["options"][0]["message"], day=TODAY)
    assert moved_ids(diff2) == [first]
    assert second not in moved_ids(diff2)
