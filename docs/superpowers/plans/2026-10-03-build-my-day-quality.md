# Build My Day Quality Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Build My Day carry every user-stated fact (tasks, dates, durations, priority, focus, deadlines, dependencies, preferred windows) losslessly from Gemini to Supabase to the Flutter Plan Result, with honest failure handling.

**Architecture:** Fix at the source. The Gemini prompt and mapper emit a complete candidate contract with stable `candidate_id`s. The shared planner (`engines/planner.py`) consumes it. Confirm persists it (migration 009). Flutter renders backend slots as they are and never silently falls back.

**Tech Stack:** FastAPI + SQLAlchemy + Alembic (Supabase PG17), httpx → Gemini, pytest; Flutter/Dart, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-03-build-my-day-quality-design.md` (rev 2)

## Global Constraints

- Scope: Build My Day only. No Replan, Insights, Auth, Calendar UI, or visual redesign.
- **Never commit** (user rule). Working tree has unrelated uncommitted work; touch only files listed per task.
- Never weaken or delete existing tests. Run targeted tests per task; run the full backend suite once at the end (Task 9).
- Backend tests: `backend/venv/Scripts/python -m pytest -q <file>` from `backend/`. Flutter: `flutter test <file>`.
- "Charge" = Flowstate internal credit accounting (`ai_usage_records` free uses / Flow Shields), never Gemini billing.
- `planned_date` is always set and is the ownership source of truth; `created_at`/`completed_at` never change ownership.
- Explicit user values (time, duration, priority, focus, deadline, preferred window) are never overwritten by defaults or inference.
- Preferred-window columns are written only when provenance is `explicit`.
- Enum strings, exact: `priority_source|duration_source|focus_source ∈ {"explicit","inferred"}`; `focus_level ∈ {"low","medium","high"}`; `deadline_kind ∈ {"hard","soft"}`; failure codes `gemini_error, malformed, empty, scheduling_failed, quota_exhausted, privacy_declined`; unscheduled reasons add `dependency_unschedulable`.

## Review Focus

1. Gemini `depends_on` points at a task that `validate_and_segment_candidates` later splits or drops. Expect the dependency to be rewritten to a surviving id or dropped with `unknown_dependency`, never left dangling. *(Task 3 test `test_dependency_on_dropped_candidate_is_removed`)*
2. "before Saturday" typed on a Saturday. Expect the *next* Saturday 00:00, never a deadline already in the past. *(Task 2 test `test_before_same_weekday_rolls_to_next_week`)*
3. User edits time, duration or priority in the preview before confirming. Expect that field's source to become `explicit` and an edited time to become `time_locked`. *(Task 7 test `edited field becomes explicit in batch payload`)*
4. Request timezone differs from the stored user preference (traveling). Expect the request tz to win for `planned_date` and slots. *(Task 5 test `test_request_timezone_wins_for_planned_date`)*
5. Retry with AI after a Gemini timeout, using the same request id. Expect two attempt rows, exactly one charge, and a cached replay on a third call. *(Task 6 test `test_retry_same_request_charges_once`)*

---

### Task 1: Persistence foundation (migration 009, models, schemas)

**Files:**
- Create: `backend/alembic/versions/009_build_my_day_quality.py` (down_revision = 008's revision id)
- Modify: `backend/app/models/task.py`, `backend/app/models/ai_usage.py`, `backend/app/models/__init__.py`, `backend/app/schemas/task.py`
- Test: `backend/tests/test_build_my_day_quality.py` (new; shared by Tasks 1–6)

**Interfaces — Produces:**
- `Task` columns: `focus_level, deadline_kind, priority_source, duration_source, focus_source` (`String(16)`, nullable); `depends_on` (`JSON`, nullable, list[str] of task ids); `preferred_start, preferred_window_start, preferred_window_end` (`UTCDateTime`, nullable).
- `AIPlanningAttempt` (`__tablename__="ai_planning_attempts"`): `attempt_id String PK`, `request_id String index`, `user_id FK users.id cascade`, `status String` (`succeeded|failed`), `failure_code String nullable`, `failure_reason Text nullable`, `latency_ms Integer nullable`, `created_at UTCDateTime`.
- Migration also runs `ALTER TABLE ai_planning_attempts ENABLE ROW LEVEL SECURITY` on Postgres only (follow 007's dialect guard).
- Schemas: add the same 9 task fields as Optional to `TaskCreate`, `TaskResponse`, `BatchTaskItem`. `TaskCandidateResponse` adds `candidate_id: str = Field(default_factory=lambda: "c_" + uuid4().hex[:12])` and `depends_on: List[str] = []`, where the ids are candidate ids. `BatchTaskItem.depends_on` holds candidate ids (`client_ref` / `candidate_id` of sibling items); add `candidate_id: Optional[str]`.
- `TaskUpdate._NULLABLE` adds the 9 new fields.

- [ ] **Step 1: Write failing test** `test_quality_columns_round_trip`: create a Task through `TaskRepository` with every new field set (`focus_level="high"`, `deadline_kind="soft"`, `priority_source="explicit"`, `duration_source="inferred"`, `focus_source="explicit"`, `depends_on=["x"]`, three preferred datetimes). Re-query it in a new session and assert each value is equal, with aware datetimes.
- [ ] **Step 2: Run** `pytest tests/test_build_my_day_quality.py -k round_trip`. Expected: FAIL (unknown attribute).
- [ ] **Step 3: Implement** the model, migration and schema changes above.
- [ ] **Step 4: Run** the same test and `pytest tests/test_date_invariant.py tests/test_build_my_day_integrity.py`. Expected: all PASS. Also run `alembic heads`: a single head, `009`.

### Task 2: Gemini seam, prompt and mapper (sources, focus, deadlines, "before <weekday>")

**Files:**
- Modify: `backend/app/services/ai_service.py` (prompt ~l.93-248, `_map_gemini_tasks_to_candidates` ~l.1492, `_parse_single_clause` deadline block ~l.940-990, Gemini call ~l.1220)
- Test: `backend/tests/test_build_my_day_quality.py`, fixtures `backend/tests/fixtures/gemini_bmd/*.json`

**Interfaces — Produces:**
- `AIService._gemini_generate(cls, prompt: str, api_key: str, *, request_id: str) -> str`: the only place that makes the httpx call; returns the raw model text and raises on transport errors. Tests stub this.
- Prompt JSON per task adds: `"ref": "t1"`, `"depends_on": ["t1"]`, `"focus_level"`, `"focus_source"`, `"duration_source"`, `"deadline_kind": "hard"|"soft"|null`, `"deadline_phrase": "before"|"by"|"due"|null`. Replace the "priority=null when unspecified" rule with: infer the priority and set `priority_source="inferred"`. Add examples: "after that"/"then" → `depends_on` the previous ref; "before Tuesday" → `deadline_phrase:"before"`, `deadline: <Tue date>`, `deadline_time: null`; "ideally by Friday" → `deadline_kind:"soft"`.
- `infer_priority(deadline_at: Optional[datetime], text: str, now_local: datetime) -> TaskPriority`: hard deadline on today or tomorrow → `high`; text matches `optional|if (i have )?time|not urgent` → `low`; otherwise `medium`.
- `infer_focus(task_type: TaskType) -> str`: `deep_work, study` → `high`; `admin, physical` → `low`; else `medium`.
- `resolve_deadline(date_, time_hhmm, phrase, tz) -> datetime`: `phrase == "before"` with no time → `date_ 00:00`; a time present → that time; otherwise `23:59`. Weekday resolution always picks the next occurrence after today.
- Mapper sets `candidate_id`, the three `*_source` fields, `focus_level`, `deadline_kind` (default `hard` when a deadline exists), and returns `ref_map: Dict[str, str]` (ref → candidate_id) plus raw `depends_on` refs for Task 3. Preferred windows keep the existing provenance. Only `explicit` ones are persisted later.
- The deterministic parser uses the same `resolve_deadline` and `infer_*` helpers.

- [ ] **Step 1: Write failing tests.** Stub `_gemini_generate` to return fixture JSON, pin `now_local = 2026-10-03 09:00 Asia/Kolkata` (a Saturday), and call `extract_structured_plan_with_gemini`:
  - `test_messy_dump_splits_into_separate_tasks`: fixture with 5 refs → 5 candidates, titles as given, none merged, no extras.
  - `test_explicit_time_is_locked`: "dentist at 4pm" → `scheduled_start == 16:00 local` and fixed provenance.
  - `test_explicit_duration_preserved`: 90 min with `duration_source="explicit"` → `estimated_minutes == 90` and `duration_source == "explicit"`.
  - `test_explicit_priority_preserved` and `test_missing_priority_is_inferred_not_unspecified`: Gemini null priority with a deadline tomorrow → `priority == "high"`, `priority_source == "inferred"`, and `"priority_unspecified" not in ambiguities`.
  - `test_explicit_focus_preserved` / `test_focus_inferred_from_type`.
  - `test_before_tuesday_is_end_of_monday`: `deadline_at == 2026-10-06 00:00+05:30`, `deadline_kind == "hard"`.
  - `test_before_same_weekday_rolls_to_next_week`: "before Saturday" → `2026-10-10 00:00+05:30`.
  - `test_by_friday_is_friday_2359`.
  - `test_deterministic_parser_before_weekday_matches`: `_parse_single_clause("submit report before tuesday", ...)` gives the same `deadline_at`.
  - `test_malformed_gemini_raises_malformed`: the stub returns `"not json"` twice → raises `GeminiFailure(code="malformed")`. Define `GeminiFailure(Exception)` with `.code` and `.reason` in `ai_service.py`. Transport errors → `code="gemini_error"`.
- [ ] **Step 2: Run** `pytest tests/test_build_my_day_quality.py -k "messy or explicit or priority or focus or before or by_friday or malformed"`. Expected: FAIL.
- [ ] **Step 3: Implement** the seam, prompt, helpers and mapper above.
- [ ] **Step 4: Run** the same tests, plus `tests/test_conservative_fallback.py tests/test_temporal_constraints.py tests/test_temporal_scheduling.py`. Expected: PASS. If an existing test asserted `priority_unspecified` for Gemini output, it encodes the old contract the user rejected. Report it before editing, and never delete it.

### Task 3: Dependency resolution and validation

**Files:**
- Create: `backend/app/services/candidate_dependencies.py`
- Modify: `backend/app/services/ai_service.py` (call it after mapping and again after `validate_and_segment_candidates`)
- Test: `backend/tests/test_build_my_day_quality.py`

**Interfaces — Produces:**
- `resolve_dependencies(candidates: List[TaskCandidateResponse], raw_refs: Dict[str, List[str]], ref_map: Dict[str, str]) -> None`: mutates `c.depends_on` to candidate ids. `raw_refs` maps a candidate_id to the Gemini refs it depends on. Unknown ref or self-reference → dropped, with `validation_issues.append({"code":"unknown_dependency","field":"depends_on","message":...})`. Cycles found by DFS → every edge in the cycle dropped, with `{"code":"dependency_cycle",...}` on each member.
- `prune_dangling(candidates) -> None`: drops `depends_on` ids that no longer exist in the list (after segmentation) and adds `unknown_dependency`.

- [ ] **Step 1: Write failing tests:** `test_after_that_creates_dependency` (t2 depends on t1 → `c2.depends_on == [c1.candidate_id]`), `test_unknown_dependency_dropped`, `test_self_dependency_dropped`, `test_dependency_cycle_broken`, `test_dependency_on_dropped_candidate_is_removed`.
- [ ] **Step 2: Run** with `-k dependency`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.

### Task 4: Planner and planning_service consume the contract

**Files:**
- Modify: `backend/app/engines/planner.py` (`PlanItem` l.55, unplaced reasons, placement loop ~l.320-420), `backend/app/services/planning_service.py` (`candidates_to_plan_items` l.169, `apply_result_to_candidates` l.251)
- Test: `backend/tests/test_build_my_day_quality.py`

**Interfaces — Produces:**
- `PlanItem` adds `focus_level: str = "medium"` and `deadline_kind: str = "hard"`.
- Planner, hard deadline: unchanged (never ends after `deadline_at`).
- Planner, soft deadline: first try the placement with `deadline_at` as an upper bound. If that fails, retry without it, and set `Placement.secondary_reasons += ("soft_deadline_exceeded",)`.
- Focus: wherever the planner or `PlanningProfile` gives peak-hour preference to `task_type == "deep_work"` (grep `"deep_work"` in `planner.py` and `scheduling_engine.py`), also apply it when `focus_level == "high"`. Do not change the scoring for other items.
- Dependency: if a predecessor ends up in `unplaced`, the successor is unplaced with reason `dependency_unschedulable` (message names the predecessor). The successor's earliest start is ≥ the predecessor's end. This already holds; keep it.
- `candidates_to_plan_items`: `ids = [c.candidate_id ...]`; `depends_on = tuple(c.depends_on)` merged with the existing title-based `ctx.task_dependencies` pairs; pass `focus_level` and `deadline_kind`.
- `apply_result_to_candidates`: on `soft_deadline_exceeded`, set `scheduling_reasons["soft_deadline_exceeded"] = True` and append an explanation sentence. Unplaced → `unscheduled_reason`, and slots stay None (never placeholder slots).

- [ ] **Step 1: Write failing tests** (call `planning_service.schedule_candidates` directly with built candidates and a fixed profile):
  - `test_dependency_successor_starts_after_predecessor`
  - `test_unschedulable_task_has_real_reason`: 480-min task, hard deadline in 2 h → `unscheduled_reason == "deadline_infeasible"` and `scheduled_start is None`.
  - `test_successor_of_unschedulable_is_dependency_unschedulable`
  - `test_hard_deadline_never_exceeded`
  - `test_soft_deadline_exceeded_only_when_necessary`: one case with room (ends ≤ deadline, flag absent) and one without room (placed after, flag True).
  - `test_high_focus_prefers_peak`: admin task with `focus_level="high"` lands inside the profile's peak window when free.
- [ ] **Step 2: Run** with `-k "dependency_successor or unschedul or deadline or focus_prefers"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** these, plus `pytest tests/ -k planner` and `tests/test_build_my_day_integrity.py`. Expected: PASS.

### Task 5: Confirm persists the full contract

**Files:**
- Modify: `backend/app/services/plan_confirm_service.py` (`_validate_items` l.41, `batch_create` l.75-180), `backend/app/repositories/task_repository.py` if create omits the new fields
- Test: `backend/tests/test_build_my_day_quality.py`

**Interfaces — Consumes:** Task 1 schema fields; Task 4 `PlanItem` fields.
**Produces:**
- `_validate_items` applies `deadline_before_end` only when `deadline_kind != "soft"`.
- `batch_create` builds `PlanItem(id=item.candidate_id or client_ref or f"req-{i}", depends_on=tuple(item.depends_on), focus_level, deadline_kind, temporal=PlanTemporal(preferred_* from item))`.
- After creating rows, it translates `depends_on` candidate ids to the new task ids and saves them. Ids not in this batch are dropped.
- Every new field is persisted. Preferred windows are saved only if the item carries them, because Flutter sends them only when explicit.
- `planned_date` is the slot's local day, else `item.planned_date`, else today in the request tz.

- [ ] **Step 1: Write failing tests:**
  - `test_confirm_round_trip_preserves_contract`: POST `/ai/plan` (stubbed Gemini fixture with every field) → build the batch from the response like Flutter does → POST batch confirm → GET `/tasks`. Assert per task that `planned_date`, slot, `estimated_minutes`, `priority`, `priority_source`, `duration_source`, `focus_level`, `focus_source`, `deadline_at`, `deadline_kind`, `time_locked`, explicit preferred window, and `depends_on` (as real task ids) all equal the preview. This test is the contract matrix (spec §10).
  - `test_inferred_preferred_window_not_persisted`
  - `test_soft_deadline_item_past_deadline_is_accepted_on_confirm`
  - `test_request_timezone_wins_for_planned_date`: user pref UTC, request `Asia/Kolkata` at 23:30 local → `planned_date` is the Kolkata day.
- [ ] **Step 2: Run** with `-k "confirm or preferred_window or soft_deadline_item or request_timezone"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** these, plus `tests/test_tasks.py tests/test_date_invariant.py`. Expected: PASS.

### Task 6: Route — attempts, single charge, failure codes, diagnostics endpoint

**Files:**
- Modify: `backend/app/api/routes/ai.py` (`generate_ai_plan` l.55-196), `backend/app/services/ai_economy_service.py`, `backend/app/schemas/ai.py`
- Test: `backend/tests/test_build_my_day_quality.py`

**Interfaces — Produces:**
- `AIEconomyService.record_attempt(db, *, user_id: str, request_id: str, status: str, failure_code: Optional[str], failure_reason: Optional[str], latency_ms: Optional[int]) -> str`: returns the `attempt_id` (`uuid4().hex`).
- Route flow: compute `request_id = request.idempotency_key or uuid4().hex`. A completed cache hit returns the replay (no Gemini call, no charge, no attempt row). On authorize failure (402/403 quota) → record `quota_exhausted`, then re-raise with `detail={"failure_code":"quota_exhausted","message":...}`.
- Each Gemini call → one attempt row. A `GeminiFailure` gets its code; an empty result → `empty` (422); a scheduling exception, or zero scheduled tasks when every task is unplaced for `no_capacity`, → `scheduling_failed`, which is never charged. All error `detail`s are `{"failure_code", "message"}`.
- `finalize_usage` runs only on success and marks the request `completed`.
- Remove any backend substitution of the local parser in this route (`parse_task_dump` is not called here; assert this in a test).
- `POST /ai/planning-attempts` with body `PlanningAttemptReport(request_id: str, failure_code: Literal["privacy_declined","gemini_error"], failure_reason: Optional[str] = None)` → 204. Records an attempt and never charges.

- [ ] **Step 1: Write failing tests:**
  - `test_gemini_failure_not_charged_and_recorded` (code `gemini_error`, usage unchanged, one failed attempt row)
  - `test_malformed_gemini_not_charged_code_malformed`
  - `test_scheduling_failure_not_charged_code_scheduling_failed`
  - `test_quota_exhausted_records_code`
  - `test_retry_same_request_charges_once` (fail, then success, then replay → attempts == 2, `free_uses_consumed == 1`, third response identical)
  - `test_privacy_declined_report_endpoint`
  - `test_route_never_uses_local_parser` (monkeypatch `AIService.parse_task_dump` to raise; a Gemini failure still returns 502)
- [ ] **Step 2: Run** with `-k "charged or quota or retry_same or privacy or local_parser"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** these, plus `tests/test_build_my_day_integrity.py` and `pytest tests/ -k "ai_economy or ai_plan"`. Expected: PASS.

### Task 7: Flutter model and service contract

**Files:**
- Modify: `lib/models/ai_plan_models.dart` (`ExtractedTaskItem` l.5, `fromJson` l.72, `toJson` l.166, `toTaskItem`), `lib/services/ai_plan_service.dart` (`generatePlan` l.42), and the batch-confirm payload builder (grep `client_ref` in `lib/`)
- Test: `test/build_my_day_quality_test.dart` (new)

**Interfaces — Produces:**
- `ExtractedTaskItem` gains `candidateId`, `prioritySource`, `durationSource`, `focusLevel`, `focusSource`, `deadlineKind`, `List<String> dependsOn`, `preferredStart`, `preferredWindowStart`, `preferredWindowEnd`. Preferred fields are kept only when `field_provenance` marks them `explicit`.
- The batch payload sends these plus `candidate_id`. Any field the user edits in the preview sets its `*Source` to `'explicit'`; an edited time sets `time_locked: true`.
- `AIPlanService.generatePlan({required String rawText, required String requestId, bool consumeShield})` throws `AIPlanFailure(code, message)` parsed from `detail.failure_code`. Network or timeout → `code: 'gemini_error'`.
- `AIPlanService.reportFailure(String requestId, String code, [String? reason])` → POST `/ai/planning-attempts`. Errors are swallowed; diagnostics must not block the UI.

- [ ] **Step 1: Write failing tests:**
  - `fromJson/toJson round-trips all new fields`
  - `inferred preferred window is not sent`
  - `edited field becomes explicit in batch payload`
  - `generatePlan maps failure_code to AIPlanFailure` (fake `ApiService`)
- [ ] **Step 2: Run** `flutter test test/build_my_day_quality_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it, plus `flutter test test/build_my_day_wire_fields_test.dart`. Expected: PASS.

### Task 8: Flutter Plan Result — no silent fallback, no client re-schedule, honest labels

**Files:**
- Modify: `lib/screens/brain_dump_sheet.dart` (l.185-310 AI path, l.950-1100 rendering), `lib/screens/ai_plan_preview_sheet.dart` (l.340-375)
- Test: `test/build_my_day_quality_test.dart`

**Interfaces — Consumes:** Task 7 `AIPlanFailure`, `reportFailure`, `generatePlan(requestId:)`.
**Produces:**
- A `_requestId` is created once per submission and reused by Retry.
- When `requiresAiEnrichment` is true, these cases call `_showAiFailure(code, message)` instead of `_proceedLocalParsing`: privacy declined (also `reportFailure(..., 'privacy_declined')`), shield declined or no shields (`quota_exhausted`), `AIPlanFailure`, empty tasks, or a non-null `scheduling_error`.
- `_showAiFailure` keeps the editor text. It shows `"AI planning failed: <message>"` and two buttons with exact labels **Retry with AI** and **Use basic planner**.
- Basic planner → `_proceedLocalParsing(text, 'Basic plan (not AI)')`. It never calls `generatePlan`, `getUsageStatus` or any charging path.
- AI success: `_planCandidates = result.tasks.map(toTaskItem)` with backend slots as-is. The client `SchedulingEngine` is not called on the AI path.
- Labels: explicit → `'High priority'`; inferred → `'Suggested: High'`. Remove the string `'Priority not specified'` from both screens. `focusLevel == 'high'` shows a `'High focus'` chip (existing chip style, no new design).

- [ ] **Step 1: Write failing widget tests:**
  - `AI failure keeps dump and shows Retry with AI + Use basic planner`
  - `Use basic planner labels plan "Basic plan (not AI)" and makes no AI call` (fake service counts calls)
  - `Retry with AI reuses the same requestId`
  - `AI plan slots are rendered unchanged` (fake result slot 14:00 → preview shows 14:00)
  - `explicit vs inferred priority labels; no "Priority not specified"`
  - `high focus chip`
- [ ] **Step 2: Run** `flutter test test/build_my_day_quality_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** it, plus `flutter test test/build_my_day_conservative_fallback_test.dart test/build_my_day_wire_fields_test.dart` and the brain-dump tests (`flutter test test/ --name "brain dump"`). Expected: PASS. Pre-existing `pumpAndSettle` timeouts that are unrelated to these files are reported, not "fixed".

### Task 9: Live verification (real Gemini + Supabase) and final gate

**Files:** scratchpad script only, `<scratchpad>/bmd_live_verify.py`. No repo files.

- [ ] **Step 1:** `alembic upgrade head` against Supabase (`backend/.env`). Expected: head `009`; `alembic check` reports no drift.
- [ ] **Step 2:** Start the backend. Use the script to POST `/ai/plan` with this messy dump: *"urgent: finish DBMS assignment before tuesday, about 2 hours, needs deep focus. after that send it to the prof. dentist at 4pm tomorrow. ideally call mom by friday evening. gym sometime in the morning, optional"* with tz `Asia/Kolkata` and the real `current_local_time`.
  - Assert in the logs that the real Gemini path was taken (`path=` / attempt row `succeeded`).
  - Assert 5 tasks; `before tuesday` → Tue 00:00; 120 min explicit; urgent explicit; focus high explicit; "send to prof" depends on the assignment; dentist locked at 16:00; the call-mom deadline is soft; gym priority low with a preferred morning window.
- [ ] **Step 3:** Confirm the batch, record the task ids, and dump every contract field.
- [ ] **Step 4:** Restart the backend, GET the tasks, and diff field by field against Step 3. Expected: an empty diff, and exactly one charge for the request.
- [ ] **Step 5:** Run the full backend suite once: `pytest -q`. Expected: ≥ 1196 pass plus the new tests, 0 new failures. Then run `flutter test` once and compare against the 487-pass baseline.
- [ ] **Step 6:** Report to the user: root causes (spec §1), files changed, flow before/after, targeted tests, Supabase evidence (diff output), and remaining issues. Update memory `build-my-day-replan-status.md`.
