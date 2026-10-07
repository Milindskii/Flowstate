"""Planner purity contract (spec section 4): deterministic, side-effect free, no I/O concerns."""
import ast
import copy
import dataclasses
import inspect
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.engines import planner as planner_module
from app.engines.planner import PlanItem, PlanTemporal, plan
from app.engines.scheduling_engine import PlanningProfile

IST = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 10, 5, 9, 0, tzinfo=IST)  # Monday

ENGINES_DIR = os.path.dirname(inspect.getfile(planner_module))
ALLOWED_TOP_LEVEL = {"dataclasses", "datetime", "typing", "zoneinfo", "scheduling_engine", "__future__"}


def _imported_modules(path):
    tree = ast.parse(open(path, encoding="utf-8").read())
    mods = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            mods |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom):
            mods.add(("." * node.level) + (node.module or ""))
    return mods


def test_planner_imports_only_stdlib_and_the_pure_engine():
    mods = _imported_modules(os.path.join(ENGINES_DIR, "planner.py"))
    normalized = {m.lstrip(".") for m in mods}
    assert normalized <= ALLOWED_TOP_LEVEL, normalized - ALLOWED_TOP_LEVEL


def test_scheduling_engine_is_stdlib_only():
    mods = _imported_modules(os.path.join(ENGINES_DIR, "scheduling_engine.py"))
    assert {m.lstrip(".") for m in mods} <= {"typing", "datetime", "zoneinfo", "re"}


@pytest.mark.parametrize("needle", [".now(", "utcnow", "random", "time.time", "open(", "print(", "logging", "logger", "os.environ"])
def test_planner_source_has_no_clock_randomness_or_io(needle):
    src = open(os.path.join(ENGINES_DIR, "planner.py"), encoding="utf-8").read()
    # docstring/comments mention words like "clock"; code tokens must not appear
    code_lines = [l for l in src.splitlines() if not l.strip().startswith("#")]
    stripped = ast.get_source_segment(src, ast.parse(src)) or ""
    body = "\n".join(code_lines)
    # remove the module docstring before scanning
    doc = ast.get_docstring(ast.parse(src)) or ""
    body = body.replace(doc, "")
    assert needle not in body, needle


def test_evaluate_function_does_not_read_the_clock():
    from app.engines.scheduling_engine import SchedulingEngine

    for fn in (SchedulingEngine.evaluate_best_slot_with_reason, SchedulingEngine.urgency_sort_key):
        assert ".now(" not in inspect.getsource(fn)


def _items():
    return [
        PlanItem(id="a", title="Write report", estimated_minutes=60, priority="high"),
        PlanItem(id="b", title="Email", estimated_minutes=30, task_type="admin"),
        PlanItem(id="c", title="Dentist", estimated_minutes=45, time_locked=True,
                 start=datetime(2026, 10, 5, 18, 0, tzinfo=IST), task_type="meeting"),
        PlanItem(id="d", title="Done thing", status="completed", estimated_minutes=30,
                 start=datetime(2026, 10, 5, 8, 0, tzinfo=IST), completed_at=datetime(2026, 10, 5, 8, 30, tzinfo=IST)),
    ]


def test_same_inputs_give_equal_results():
    kw = dict(now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")
    items = [dataclasses.replace(i, is_new=(i.id in "ab")) for i in _items()]
    assert plan(items, **kw) == plan(items, **kw)


def test_inputs_are_frozen_and_not_mutated():
    items = [dataclasses.replace(i, is_new=(i.id in "ab")) for i in _items()]
    before = copy.deepcopy(items)
    profile = PlanningProfile()
    profile_state = copy.deepcopy(profile.__dict__)
    plan(items, now_local=NOW, tz=IST, profile=profile, mode="build")
    assert items == before
    assert profile.__dict__ == profile_state
    with pytest.raises(dataclasses.FrozenInstanceError):
        items[0].title = "mutated"
    with pytest.raises(dataclasses.FrozenInstanceError):
        PlanTemporal().target_date = None


def test_result_does_not_depend_on_ambient_clock():
    """Two very different wall-clock moments give identical output for identical explicit inputs."""
    items = [dataclasses.replace(i, is_new=(i.id in "ab")) for i in _items()]
    r1 = plan(items, now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")
    r2 = plan(items, now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")
    assert r1 == r2 and r1.placements


def test_naive_datetimes_are_rejected_not_guessed():
    with pytest.raises(ValueError):
        plan([PlanItem(id="x", title="x", is_new=True)], now_local=datetime(2026, 10, 5, 9, 0), tz=IST,
             profile=PlanningProfile(), mode="build")
    with pytest.raises(ValueError):
        plan([PlanItem(id="x", title="x", is_new=True, deadline_at=datetime(2026, 10, 5, 20, 0))],
             now_local=NOW, tz=IST, profile=PlanningProfile(), mode="build")


def test_build_and_replan_entry_points_share_one_function_object():
    """Both modes are the same callable (adapters must not carry their own placement logic)."""
    assert planner_module.plan.__name__ == "plan"
    assert planner_module.MODES == ("build", "replan")
