"""Shared invariant fixtures (spec section 9). The same JSON is run against the Dart engine by
test/scheduling_contract_fixtures_test.dart; the backend planner is the reference implementation."""
import json
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.engines.planner import PlanItem, check_invariants, plan
from app.engines.scheduling_engine import PlanningProfile

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "scheduling_contract_cases.json")
DATA = json.load(open(FIXTURE, encoding="utf-8"))
TZ = ZoneInfo(DATA["tz"])


def _dt(s):
    return datetime.fromisoformat(s).replace(tzinfo=TZ)


def _items(case):
    out = []
    for t in case["tasks"]:
        locked = bool(t.get("locked"))
        start = _dt(t["start"]) if t.get("start") else None
        out.append(PlanItem(
            id=t["id"], title=t["title"], estimated_minutes=t["minutes"], priority=t.get("priority", "medium"),
            task_type=t.get("type", "deep_work"), start=start,
            end=(start + timedelta(minutes=t["minutes"])) if start else None, time_locked=locked,
            deadline_at=_dt(t["deadline"]) if t.get("deadline") else None, is_new=True))
    return out


@pytest.mark.parametrize("case", DATA["cases"], ids=[c["name"] for c in DATA["cases"]])
def test_planner_satisfies_contract_invariants(case):
    now = _dt(case["now"])
    items = _items(case)
    res = plan(items, now_local=now, tz=TZ, profile=PlanningProfile(), mode="build")
    assert check_invariants(items, res, now_local=now, tz=TZ) == []

    spans = [(p.item_id, p.start, p.end) for p in res.placements] + \
            [(i.item_id, i.start, i.end) for i in res.immutable if i.start and i.end]
    for a in range(len(spans)):
        for b in range(a + 1, len(spans)):
            assert not (spans[a][1] < spans[b][2] and spans[a][2] > spans[b][1]), (case["name"], spans[a][0], spans[b][0])

    for it in items:
        if it.time_locked:
            im = next(i for i in res.immutable if i.item_id == it.id)
            assert im.start == it.start, "user-fixed time moved"
    for p in res.placements:
        assert p.start >= now
        dl = next(i.deadline_at for i in items if i.id == p.item_id)
        assert dl is None or p.end <= dl
    accounted = {p.item_id for p in res.placements} | {i.item_id for i in res.immutable} | {u.item_id for u in res.unscheduled}
    assert accounted == {i.id for i in items}, "a task was silently lost"
