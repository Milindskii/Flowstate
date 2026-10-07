"""Replan notes are typed (`issues`) so the app can tell a true clash from a capacity miss, a protected block or
an ambiguous instruction, and no internal code ever reaches the user-facing text."""
import pytest

from tests.plan_helpers import client, make_user
from tests.test_apply_replan_semantics import at, replan, seed
from tests.test_replan_compound_and_fixed_blocks import OUT_S, TODAY
from tests.test_replan_running_late_context import MSG, NOW, _seed_day


def kinds(diff):
    return [i["kind"] for i in diff["issues"]]


@pytest.mark.asyncio
async def test_issues_mirror_conflicts_and_carry_a_kind():
    uid, h = make_user()
    seed(uid, "Essay", at(16, 0), 60, planned_date=TODAY)
    async with client() as ac:
        diff = await replan(ac, h, "cancel the unicorn task", now=NOW)
    assert [i["message"] for i in diff["issues"]] == diff["conflicts"]
    assert kinds(diff) == ["not_found"]


@pytest.mark.asyncio
async def test_leave_commitment_untouched_is_protected_not_a_conflict():
    uid, h = make_user()
    seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True)
    async with client() as ac:
        diff = await replan(ac, h, "keep going out as is", now=NOW)
    assert "conflict" not in kinds(diff)
    assert not diff["cancelled_tasks"]


@pytest.mark.asyncio
async def test_cancelling_a_named_commitment_is_proposed_not_refused():
    """The user naming their own commitment is an explicit request: it is proposed (and applied only on confirm)."""
    uid, h = make_user()
    seed(uid, "Going out", OUT_S, 120, planned_date=TODAY, time_locked=True, is_commitment=True)
    async with client() as ac:
        diff = await replan(ac, h, "cancel going out", now=NOW)
    assert [c["title"] for c in diff["cancelled_tasks"]] == ["Going out"]
    assert "protected" not in kinds(diff)


@pytest.mark.asyncio
async def test_satisfied_clause_is_not_reported_as_unacted():
    uid, h = make_user()
    _seed_day(uid)
    async with client() as ac:
        diff = await replan(ac, h, MSG, now=NOW)
    assert "unparsed" not in kinds(diff), diff["issues"]
    assert not any("didn't act" in i["message"] for i in diff["issues"])


@pytest.mark.asyncio
async def test_past_day_has_no_internal_code_prefix():
    uid, h = make_user()
    async with client() as ac:
        diff = await replan(ac, h, "move gym later", now=NOW, day="2026-10-01")
    assert kinds(diff) == ["past"]
    assert "date_in_past" not in diff["explanation"] and "date_in_past" not in diff["conflicts"][0]
