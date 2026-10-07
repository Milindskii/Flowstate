"""The backend half of the shared task-state contract (see shared/task_state_vectors.json)."""
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from app.services import task_state
from app.services.task_state import day_boundary, derive_task_state

SPEC = json.loads((Path(__file__).resolve().parents[2] / "shared" / "task_state_vectors.json").read_text(encoding="utf-8"))
TZ = ZoneInfo("Asia/Kolkata")


def _dt(s):
    return None if s is None else datetime.fromisoformat(s).replace(tzinfo=TZ)


def test_constants_match_the_shared_contract():
    assert task_state.MISSED_GRACE_MINUTES == SPEC["missed_grace_minutes"]
    assert task_state.BEDTIME_AFTER_MIDNIGHT_BELOW_HOURS == SPEC["bedtime_after_midnight_below_hours"]


@pytest.mark.parametrize("case", SPEC["cases"], ids=[c["name"] for c in SPEC["cases"]])
def test_derive_task_state_matches_vector(case):
    start, end, now = _dt(case["start"]), _dt(case["end"]), _dt(case["now"])
    boundary = day_boundary((start or now).date(), TZ, case["bedtime"])
    got = derive_task_state(completed=case["completed"], cancelled=case["cancelled"], active=case["active"],
                            start=start, end=end, now=now, day_boundary=boundary,
                            commitment=case.get("commitment", False))
    assert got == case["expected"]


# ── every backend consumer of "slot ended" agrees with the shared vectors ──────────────────────────────

from datetime import timezone  # noqa: E402

from app.api.routes.today import _actionable_now  # noqa: E402
from app.models.task import Task, TaskStatus  # noqa: E402
from app.services.calendar_service import CalendarService  # noqa: E402

_SLOTTED = [c for c in SPEC["cases"] if c["start"] and not (c["completed"] or c["cancelled"])]


def _row(case):
    start = _dt(case["start"]).astimezone(timezone.utc)
    end = _dt(case["end"]).astimezone(timezone.utc)
    return Task(id="t", user_id="u", title="x", estimated_minutes=60, scheduled_start=start, scheduled_end=end,
                status=TaskStatus.in_progress if case["active"] else TaskStatus.todo,
                is_commitment=case.get("commitment", False))


@pytest.mark.parametrize("case", _SLOTTED, ids=[c["name"] for c in _SLOTTED])
def test_slot_missed_agrees_with_the_shared_vectors(case):
    """CalendarService._slot_missed (Replan history) must flag exactly the vectors that are missed or failed."""
    now = _dt(case["now"]).astimezone(timezone.utc)
    assert CalendarService._slot_missed(_row(case), now) == (case["expected"] in ("missed", "failed"))


@pytest.mark.parametrize("case", _SLOTTED, ids=[c["name"] for c in _SLOTTED])
def test_today_never_offers_a_missed_or_failed_task(case):
    """/today's "do this now" candidates must exclude exactly the vectors that are missed or failed."""
    now = _dt(case["now"]).astimezone(timezone.utc)
    offered = bool(_actionable_now([_row(case)], now))
    assert offered == (case["expected"] not in ("missed", "failed", "commitment"))
