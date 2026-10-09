"""Build My Day quality pass (spec docs/superpowers/specs/2026-10-03-build-my-day-quality-design.md).

Gemini is stubbed at the transport seam (`AIService._gemini_generate`) with fixture JSON, so the real
prompt -> mapper -> dependency -> planner -> confirm -> DB path runs. The client clock is pinned.
"""
from datetime import datetime, timedelta

from app.db.session import SessionLocal
from app.models.task import Task
from app.repositories.task_repository import TaskRepository
from tests.plan_helpers import IST, make_user

NOW = datetime(2026, 10, 3, 9, 0, tzinfo=IST)  # Saturday 09:00 IST


# ── Task 1: persistence foundation ───────────────────────────────────────────

def test_quality_columns_round_trip():
    uid, _ = make_user(prefix="bmdq")
    ps = NOW + timedelta(hours=2)
    db = SessionLocal()
    try:
        t = TaskRepository.create(db, Task(
            user_id=uid, title="Write essay", estimated_minutes=60, planned_date=NOW.date(),
            focus_level="high", deadline_kind="soft", priority_source="explicit",
            duration_source="inferred", focus_source="explicit", depends_on=["x"],
            preferred_start=ps, preferred_window_start=ps - timedelta(minutes=45),
            preferred_window_end=ps + timedelta(minutes=45),
        ))
        tid = t.id
    finally:
        db.close()
    db = SessionLocal()
    try:
        r = db.get(Task, tid)
        assert (r.focus_level, r.deadline_kind) == ("high", "soft")
        assert (r.priority_source, r.duration_source, r.focus_source) == ("explicit", "inferred", "explicit")
        assert r.depends_on == ["x"]
        assert r.preferred_start == ps
        assert r.preferred_window_start == ps - timedelta(minutes=45)
        assert r.preferred_window_end == ps + timedelta(minutes=45)
    finally:
        db.close()


# ── Task 2: Gemini seam, prompt and mapper ───────────────────────────────────
import json as _json
from pathlib import Path

import pytest

pytestmark = pytest.mark.usefixtures("one_free_plan")  # these exercise the free-allowance mechanism

from app.services import ai_service as _ais
from app.services.ai_service import AIService, GeminiFailure

FIX = Path(__file__).parent / "fixtures" / "gemini_bmd"


def _gemini_returns(monkeypatch, *payloads):
    """Stub the transport seam; each call returns the next payload (dict -> JSON text, str as is)."""
    seq = list(payloads)
    calls = []

    def fake(cls, prompt, api_key, *, request_id, temperature=0.1):
        calls.append(prompt)
        p = seq.pop(0) if len(seq) > 1 else seq[0]
        if isinstance(p, Exception):
            raise p
        return p if isinstance(p, str) else _json.dumps(p)

    monkeypatch.setattr(AIService, "_gemini_generate", classmethod(fake))
    monkeypatch.setattr(_ais.settings, "GEMINI_API_KEY", "test-key")
    return calls


def _messy():
    return _json.loads((FIX / "messy.json").read_text())


def _extract(monkeypatch, payload, now=NOW):
    _gemini_returns(monkeypatch, payload)
    cands, *_ = AIService.extract_structured_plan_with_gemini("dump", user_timezone_str="Asia/Kolkata", now_local=now)
    return {c.title: c for c in cands}


def _one(task: dict) -> dict:
    return {"tasks": [{"ref": "t1", "depends_on": [], **task}], "ambiguities": [], "planning_context": {}}


def test_messy_dump_splits_into_separate_tasks(monkeypatch):
    by = _extract(monkeypatch, _messy())
    assert set(by) == {"Finish DBMS assignment", "Send assignment to professor", "Dentist appointment", "Call mom", "Gym session"}


def test_explicit_time_is_locked(monkeypatch):
    c = _extract(monkeypatch, _messy())["Dentist appointment"]
    assert c.scheduled_start == datetime(2026, 10, 4, 16, 0, tzinfo=IST)
    assert c.field_provenance["scheduled_time"].source == "explicit"


def test_explicit_duration_preserved(monkeypatch):
    c = _extract(monkeypatch, _messy())["Finish DBMS assignment"]
    assert c.estimated_minutes == 120 and c.duration_source == "explicit"


def test_explicit_priority_preserved(monkeypatch):
    by = _extract(monkeypatch, _messy())
    assert by["Finish DBMS assignment"].priority.value == "urgent"
    assert by["Finish DBMS assignment"].priority_source == "explicit"
    assert (by["Gym session"].priority.value, by["Gym session"].priority_source) == ("low", "explicit")


def test_missing_priority_is_inferred_not_unspecified(monkeypatch):
    tomorrow = (NOW + timedelta(days=1)).date().isoformat()
    c = _extract(monkeypatch, _one({"title": "Pay rent", "type": "admin", "priority": None,
                                    "deadline": tomorrow, "deadline_time": "18:00"}))["Pay rent"]
    assert c.priority.value == "high" and c.priority_source == "inferred"
    assert "priority_unspecified" not in c.ambiguities and "priority" not in c.missing_fields
    assert c.field_provenance["priority"].source == "inferred"


def test_explicit_focus_preserved(monkeypatch):
    c = _extract(monkeypatch, _messy())["Finish DBMS assignment"]
    assert (c.focus_level, c.focus_source) == ("high", "explicit")


def test_focus_inferred_from_type(monkeypatch):
    by = _extract(monkeypatch, _messy())
    assert (by["Gym session"].focus_level, by["Gym session"].focus_source) == ("low", "inferred")


def test_before_tuesday_is_end_of_monday(monkeypatch):
    c = _extract(monkeypatch, _messy())["Finish DBMS assignment"]
    assert c.deadline_at == datetime(2026, 10, 6, 0, 0, tzinfo=IST)
    assert c.deadline_kind == "hard"


def test_before_same_weekday_rolls_to_next_week(monkeypatch):
    # Saturday NOW; Gemini resolved "before Saturday" to today -> must be next Saturday 00:00.
    c = _extract(monkeypatch, _one({"title": "Book tickets", "type": "admin", "deadline": NOW.date().isoformat(),
                                    "deadline_time": None, "deadline_phrase": "before"}))["Book tickets"]
    assert c.deadline_at == datetime(2026, 10, 10, 0, 0, tzinfo=IST)


def test_by_friday_is_friday_2359(monkeypatch):
    c = _extract(monkeypatch, _messy())["Call mom"]
    assert c.deadline_at == datetime(2026, 10, 9, 23, 59, tzinfo=IST)
    assert c.deadline_kind == "soft"


def test_explicit_preferred_window_is_carried_top_level(monkeypatch):
    c = _extract(monkeypatch, _messy())["Gym session"]
    assert c.preferred_window_start == datetime(2026, 10, 3, 8, 0, tzinfo=IST)
    assert c.preferred_window_end == datetime(2026, 10, 3, 12, 0, tzinfo=IST)


def test_deterministic_parser_before_weekday_matches():
    c = AIService._parse_single_clause("submit report before tuesday", NOW, IST)
    assert c.deadline_at == datetime(2026, 10, 6, 0, 0, tzinfo=IST)
    c2 = AIService._parse_single_clause("submit report by tuesday", NOW, IST)
    assert c2.deadline_at == datetime(2026, 10, 6, 23, 59, tzinfo=IST)


def test_malformed_gemini_raises_malformed(monkeypatch):
    _gemini_returns(monkeypatch, "not json")
    with pytest.raises(GeminiFailure) as ei:
        AIService.extract_structured_plan_with_gemini("dump", user_timezone_str="Asia/Kolkata", now_local=NOW)
    assert ei.value.code == "malformed"


def test_transport_failure_raises_gemini_error(monkeypatch):
    _gemini_returns(monkeypatch, GeminiFailure("gemini_error", "timeout"))
    with pytest.raises(GeminiFailure) as ei:
        AIService.extract_structured_plan_with_gemini("dump", user_timezone_str="Asia/Kolkata", now_local=NOW)
    assert ei.value.code == "gemini_error"


def test_empty_gemini_raises_empty(monkeypatch):
    _gemini_returns(monkeypatch, {"tasks": [], "ambiguities": []})
    with pytest.raises(GeminiFailure) as ei:
        AIService.extract_structured_plan_with_gemini("dump", user_timezone_str="Asia/Kolkata", now_local=NOW)
    assert ei.value.code == "empty"


# ── Task 3: dependency resolution ────────────────────────────────────────────
from app.services.candidate_dependencies import prune_dangling, resolve_dependencies
from tests.plan_helpers import cand


def _codes(c):
    return [i["code"] for i in c.validation_issues]


def test_after_that_creates_dependency(monkeypatch):
    by = _extract(monkeypatch, _messy())
    assert by["Send assignment to professor"].depends_on == [by["Finish DBMS assignment"].candidate_id]
    assert by["Finish DBMS assignment"].depends_on == []


def test_unknown_dependency_dropped():
    a = cand("A", depends_on=["t9"])
    resolve_dependencies([a], {"t1": a.candidate_id})
    assert a.depends_on == [] and _codes(a) == ["unknown_dependency"]


def test_self_dependency_dropped():
    a = cand("A", depends_on=["t1"])
    resolve_dependencies([a], {"t1": a.candidate_id})
    assert a.depends_on == [] and _codes(a) == ["unknown_dependency"]


def test_dependency_cycle_broken():
    a, b, c = cand("A", depends_on=["t3"]), cand("B", depends_on=["t1"]), cand("C", depends_on=["t2"])
    resolve_dependencies([a, b, c], {"t1": a.candidate_id, "t2": b.candidate_id, "t3": c.candidate_id})
    assert a.depends_on == b.depends_on == c.depends_on == []
    assert all("dependency_cycle" in _codes(x) for x in (a, b, c))


def test_dependency_outside_cycle_survives():
    a, b, c = cand("A"), cand("B", depends_on=["t1"]), cand("C", depends_on=["t2"])
    resolve_dependencies([a, b, c], {"t1": a.candidate_id, "t2": b.candidate_id, "t3": c.candidate_id})
    assert b.depends_on == [a.candidate_id] and c.depends_on == [b.candidate_id]


def test_dependency_on_dropped_candidate_is_removed():
    a = cand("A")
    b = cand("B", depends_on=[a.candidate_id])
    prune_dangling([b])  # A was dropped/split away by segmentation
    assert b.depends_on == [] and _codes(b) == ["unknown_dependency"]


# ── Task 4: planner consumes the contract ────────────────────────────────────
from app.engines.scheduling_engine import PlanningProfile
from app.services import planning_service


def _schedule(cands, now=NOW):
    planning_service.schedule_candidates(cands, None, [], profile=PlanningProfile(), tz=IST,
                                         tz_name="Asia/Kolkata", now_local=now)
    return cands


def test_dependency_successor_starts_after_predecessor():
    a = cand("Write draft", 60)
    b = cand("Send draft", 15, depends_on=[a.candidate_id])
    _schedule([b, a])
    assert b.recommended_slot_start >= a.recommended_slot_end


def test_unschedulable_task_has_real_reason():
    c = cand("Huge project", 480, deadline_at=NOW + timedelta(hours=2), deadline_kind="hard")
    _schedule([c])
    assert c.unscheduled_reason == "deadline_infeasible"
    assert c.recommended_slot_start is None and c.scheduled_start is None


def test_successor_of_unschedulable_is_dependency_unschedulable():
    a = cand("Huge project", 480, deadline_at=NOW + timedelta(hours=2), deadline_kind="hard")
    b = cand("Submit project", 15, depends_on=[a.candidate_id])
    _schedule([a, b])
    assert b.unscheduled_reason == "dependency_unschedulable"
    assert b.recommended_slot_start is None


def test_hard_deadline_never_exceeded():
    c = cand("Report", 60, deadline_at=NOW + timedelta(hours=3), deadline_kind="hard")
    _schedule([c])
    assert c.recommended_slot_end <= c.deadline_at


def test_soft_deadline_exceeded_only_when_necessary():
    roomy = cand("Call mom", 30, deadline_at=NOW + timedelta(hours=4), deadline_kind="soft")
    _schedule([roomy])
    assert roomy.recommended_slot_end <= roomy.deadline_at
    assert not (roomy.scheduling_reasons or {}).get("soft_deadline_exceeded")

    tight = cand("Long read", 240, deadline_at=NOW + timedelta(hours=1), deadline_kind="soft")
    _schedule([tight])
    assert tight.unscheduled_reason is None and tight.recommended_slot_start is not None
    assert tight.recommended_slot_end > tight.deadline_at
    assert tight.scheduling_reasons["soft_deadline_exceeded"] is True


def test_high_focus_prefers_peak():
    early = NOW.replace(hour=6)
    prof = PlanningProfile()
    hi = cand("Tax forms", 60, task_type="admin", focus_level="high")
    _schedule([hi], now=early)
    h = hi.recommended_slot_start.astimezone(IST)
    assert prof.preferred_peak_start <= h.hour + h.minute / 60 < prof.preferred_peak_end


# ── Task 5: confirm persists the full contract (spec §10 coverage matrix) ────
import uuid as _uuid

from tests.plan_helpers import client, post_plan

CONTRACT = ("planned_date", "estimated_minutes", "priority", "priority_source", "duration_source", "focus_level",
            "focus_source", "deadline_at", "deadline_kind", "time_locked", "preferred_start",
            "preferred_window_start", "preferred_window_end")


def _batch_item(t: dict) -> dict:
    """What Flutter's confirm sends for one preview candidate."""
    keys = ("title", "task_type", "priority", "estimated_minutes", "deadline_at", "time_locked", "planned_date",
            "candidate_id", "depends_on", "focus_level", "deadline_kind", "priority_source", "duration_source",
            "focus_source", "preferred_start", "preferred_window_start", "preferred_window_end")
    item = {k: t.get(k) for k in keys}
    item["client_ref"] = t["candidate_id"]
    item["scheduled_start"] = t.get("recommended_slot_start") or t.get("scheduled_start")
    item["scheduled_end"] = t.get("recommended_slot_end") or t.get("scheduled_end")
    return item


def _dt(v):
    return datetime.fromisoformat(v) if isinstance(v, str) else v


def _same(a, b):
    if a is None or b is None:
        return a == b
    if isinstance(a, str) and "T" in a:
        return _dt(a) == _dt(b)
    return a == b


async def _plan_and_confirm(monkeypatch, payload, now=NOW, tz="Asia/Kolkata", user_tz="Asia/Kolkata"):
    _gemini_returns(monkeypatch, payload)
    _, h = make_user(tz=user_tz, prefix="bmdq")
    async with client() as ac:
        r = await post_plan(ac, h, now, tz=tz)
        assert r.status_code == 200, r.text
        preview = r.json()["tasks"]
        body = {"tasks": [_batch_item(t) for t in preview], "plan_id": _uuid.uuid4().hex,
                "timezone": tz, "current_local_time": now.isoformat()}
        c = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h, json=body)
        assert c.status_code == 201, c.text
        created = c.json()["tasks"]
        listed = (await ac.get("/api/v1/tasks?limit=100", headers=h)).json()["items"]
    return preview, created, {t["id"]: t for t in listed}


@pytest.mark.asyncio
async def test_confirm_round_trip_preserves_contract(monkeypatch):
    preview, created, by_id = await _plan_and_confirm(monkeypatch, _messy())
    cand_to_task = {p["candidate_id"]: c["id"] for p, c in zip(preview, created)}
    for p, c in zip(preview, created):
        db_row = by_id[c["id"]]
        for f in CONTRACT:
            assert _same(p[f], db_row[f]), (p["title"], f, p[f], db_row[f])
        slot = p["recommended_slot_start"] or p["scheduled_start"]
        assert _same(slot, db_row["scheduled_start"]), (p["title"], slot, db_row["scheduled_start"])
        assert db_row["depends_on"] in (None, []) if not p["depends_on"] else \
            db_row["depends_on"] == [cand_to_task[d] for d in p["depends_on"]]
    send = next(t for t in by_id.values() if t["title"] == "Send assignment to professor")
    dbms = next(t for t in by_id.values() if t["title"] == "Finish DBMS assignment")
    assert send["depends_on"] == [dbms["id"]]
    assert _dt(send["scheduled_start"]) >= _dt(dbms["scheduled_end"])


@pytest.mark.asyncio
async def test_inferred_preferred_window_not_persisted(monkeypatch):
    # "around 6 PM" is explicit; a type-default window would be inferred. Here no window was stated at all.
    _, _, by_id = await _plan_and_confirm(monkeypatch, _one({"title": "Laundry", "type": "admin", "estimated_minutes": 30}))
    row = next(iter(by_id.values()))
    assert row["preferred_start"] is None and row["preferred_window_start"] is None and row["preferred_window_end"] is None


@pytest.mark.asyncio
async def test_soft_deadline_item_past_deadline_is_accepted_on_confirm(monkeypatch):
    _, h = make_user(prefix="bmdq")
    start = NOW + timedelta(hours=2)
    item = {"title": "Long read", "estimated_minutes": 120, "deadline_at": (NOW + timedelta(hours=1)).isoformat(),
            "deadline_kind": "soft", "scheduled_start": start.isoformat(),
            "scheduled_end": (start + timedelta(minutes=120)).isoformat(), "client_ref": "c1", "candidate_id": "c1"}
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h,
                          json={"tasks": [item], "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
    assert r.status_code == 201, r.text
    assert r.json()["tasks"][0]["deadline_kind"] == "soft"


@pytest.mark.asyncio
async def test_hard_deadline_item_past_deadline_is_rejected_on_confirm(monkeypatch):
    _, h = make_user(prefix="bmdq")
    start = NOW + timedelta(hours=2)
    item = {"title": "Long read", "estimated_minutes": 120, "deadline_at": (NOW + timedelta(hours=1)).isoformat(),
            "deadline_kind": "hard", "scheduled_start": start.isoformat(),
            "scheduled_end": (start + timedelta(minutes=120)).isoformat(), "client_ref": "c1"}
    async with client() as ac:
        r = await ac.post("/api/v1/tasks/batch-create-and-schedule", headers=h,
                          json={"tasks": [item], "timezone": "Asia/Kolkata", "current_local_time": NOW.isoformat()})
    assert r.status_code == 422


@pytest.mark.asyncio
async def test_request_timezone_wins_for_planned_date(monkeypatch):
    early_ist = datetime(2026, 10, 4, 4, 30, tzinfo=IST)  # = 2026-10-03 23:00 UTC
    preview, created, _ = await _plan_and_confirm(
        monkeypatch, _one({"title": "Read book", "type": "study", "estimated_minutes": 30}),
        now=early_ist, user_tz="UTC")
    assert preview[0]["planned_date"] == "2026-10-04"
    assert created[0]["planned_date"] == "2026-10-04"


def test_successor_follows_predecessor_onto_later_day():
    a = cand("Thesis chapter", 120, deadline_at=datetime(2026, 10, 6, 0, 0, tzinfo=IST), deadline_kind="hard",
             temporal=None)
    b = cand("Email chapter", 15, depends_on=[a.candidate_id])
    late = NOW.replace(hour=22, minute=30)  # no room left today: A lands on a later day
    _schedule([a, b], now=late)
    assert a.recommended_slot_start is not None
    assert b.unscheduled_reason is None, b.validation_issues
    assert b.recommended_slot_start >= a.recommended_slot_end


def test_kept_predecessor_bounds_successor_at_confirm():
    from app.engines.planner import PlanItem, plan
    mon = datetime(2026, 10, 5, 9, 30, tzinfo=IST)
    a = PlanItem(id="item-0", title="A", estimated_minutes=120, start=mon, end=mon + timedelta(minutes=120))
    b = PlanItem(id="item-1", title="B", estimated_minutes=15, depends_on=("item-0",))
    res = plan([a, b], now_local=NOW, tz=IST, profile=PlanningProfile(), mode="replan", scope_date=None)
    placed = {p.item_id: p for p in res.placements}
    assert placed["item-1"].start >= placed["item-0"].end


# ── Task 6: route — attempts, single charge, failure codes ───────────────────
from app.models.ai_usage import AIPlanningAttempt, AIUsageRecord


def _attempts(uid):
    db = SessionLocal()
    try:
        return db.query(AIPlanningAttempt).filter_by(user_id=uid).order_by(AIPlanningAttempt.created_at).all()
    finally:
        db.close()


def _free_used(uid):
    db = SessionLocal()
    try:
        u = db.query(AIUsageRecord).filter_by(user_id=uid).first()
        return u.free_uses_consumed if u else 0
    finally:
        db.close()


async def _post(ac, h, key=None, **extra):
    body = {"raw_text": "messy dump", "idempotency_key": key or _uuid.uuid4().hex,
            "current_local_time": NOW.isoformat(), "timezone": "Asia/Kolkata", **extra}
    return await ac.post("/api/v1/ai/plan", headers=h, json=body)


@pytest.mark.asyncio
async def test_gemini_failure_not_charged_and_recorded(monkeypatch):
    _gemini_returns(monkeypatch, GeminiFailure("gemini_error", "timeout"))
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    assert r.status_code == 502
    assert r.json()["failure_code"] == "gemini_error"
    assert _free_used(uid) == 0
    [a] = _attempts(uid)
    assert (a.status, a.failure_code) == ("failed", "gemini_error")


@pytest.mark.asyncio
async def test_malformed_gemini_not_charged_code_malformed(monkeypatch):
    _gemini_returns(monkeypatch, "not json")
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    assert r.status_code == 502 and r.json()["failure_code"] == "malformed"
    assert _free_used(uid) == 0 and _attempts(uid)[0].failure_code == "malformed"


@pytest.mark.asyncio
async def test_empty_gemini_not_charged_code_empty(monkeypatch):
    _gemini_returns(monkeypatch, {"tasks": []})
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    assert r.status_code == 422 and r.json()["failure_code"] == "empty"
    assert _free_used(uid) == 0


@pytest.mark.asyncio
async def test_scheduling_failure_not_charged_code_scheduling_failed(monkeypatch):
    _gemini_returns(monkeypatch, _messy())
    monkeypatch.setattr(planning_service, "schedule_candidates", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    body = r.json()
    assert body["failure_code"] == "scheduling_failed" and body["scheduling_error"]
    assert not body["free_consumed"] and _free_used(uid) == 0
    assert _attempts(uid)[0].failure_code == "scheduling_failed"


@pytest.mark.asyncio
async def test_nothing_schedulable_is_a_scheduling_failure(monkeypatch):
    _gemini_returns(monkeypatch, _one({"title": "Huge", "type": "admin", "estimated_minutes": 480,
                                       "deadline": NOW.date().isoformat(), "deadline_time": "10:00"}))
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    body = r.json()
    assert body["failure_code"] == "scheduling_failed"
    assert body["tasks"][0]["unscheduled_reason"] == "deadline_infeasible"
    assert _free_used(uid) == 0


@pytest.mark.asyncio
async def test_quota_exhausted_records_code(monkeypatch):
    _gemini_returns(monkeypatch, _messy())
    uid, h = make_user(prefix="bmdq")
    db = SessionLocal()
    try:
        db.add(AIUsageRecord(user_id=uid, free_uses_total=1, free_uses_consumed=1))
        db.commit()
    finally:
        db.close()
    async with client() as ac:
        r = await _post(ac, h)
    assert r.status_code == 402 and r.json()["failure_code"] == "quota_exhausted"
    assert _attempts(uid)[0].failure_code == "quota_exhausted"


@pytest.mark.asyncio
async def test_retry_same_request_charges_once(monkeypatch):
    calls = _gemini_returns(monkeypatch, GeminiFailure("gemini_error", "timeout"))
    uid, h = make_user(prefix="bmdq")
    key = _uuid.uuid4().hex
    async with client() as ac:
        r1 = await _post(ac, h, key)
        assert r1.status_code == 502
        _gemini_returns(monkeypatch, _messy())
        r2 = await _post(ac, h, key)
        assert r2.status_code == 200 and r2.json()["free_consumed"] is True
        r3 = await _post(ac, h, key)
    assert r3.status_code == 200
    assert [t["candidate_id"] for t in r3.json()["tasks"]] == [t["candidate_id"] for t in r2.json()["tasks"]]
    attempts = _attempts(uid)
    assert [a.status for a in attempts] == ["failed", "succeeded"]
    assert len({a.attempt_id for a in attempts}) == 2 and {a.request_id for a in attempts} == {key}
    assert _free_used(uid) == 1


@pytest.mark.asyncio
async def test_privacy_declined_report_endpoint():
    uid, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await ac.post("/api/v1/ai/planning-attempts", headers=h,
                          json={"request_id": "req-1", "failure_code": "privacy_declined"})
    assert r.status_code == 204
    [a] = _attempts(uid)
    assert (a.request_id, a.status, a.failure_code) == ("req-1", "failed", "privacy_declined")
    assert _free_used(uid) == 0


@pytest.mark.asyncio
async def test_route_never_uses_local_parser(monkeypatch):
    _gemini_returns(monkeypatch, GeminiFailure("gemini_error", "down"))
    monkeypatch.setattr(AIService, "parse_task_dump", classmethod(lambda *a, **k: pytest.fail("local parser used")))
    _, h = make_user(prefix="bmdq")
    async with client() as ac:
        r = await _post(ac, h)
    assert r.status_code == 502
