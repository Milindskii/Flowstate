# Build My Day & Replan Reliability — Implementation Specification

Status: **REVISION 2 — decisions D1–D10 applied; awaiting approval of this final version. No product code has been changed; nothing has been committed.**
Chosen direction: Approach B (a `time_locked` flag plus one shared planning function; smallest change that achieves correctness).
Date: 2026-10-02

### Revision log
- **Rev 1:** initial spec.
- **Rev 2 (this version):** applies the approved decisions. Changes: (a) D2 backfill tightened to a single high-confidence predicate, default unlocked, inspectable report, predicate tests (§3, §11, §12); (b) D4 resolved from repository evidence — **production `tasks` bootstrap is NOT determinable from the repo; implementation is split into a dev/test track that can proceed and a production-migration track that is blocked on specific facts** (§11.1, §15); migration 006 is now **ALTER-only and fails loudly** rather than skipping silently; (c) D6 past-explicit-time error format and engine change (§2 C5, §4, §7); (d) D7 explicit in-progress tests (§2 C2, §12); (e) D8 lock sources restricted to explicit user input / existing product semantics (§3); (f) D3 dependency handling (§5, §10.2); (g) D10 no commit; (h) **new §16: complete traceability matrix, findings 1–19 → root cause → fix → migration → test**.

---

## 0. Evidence base and corrections to the audit report

### 0.1 Reconciling the count
The audit report listed **12 numbered findings**. The phrase "eight" referred to the number of *failing reproduction probes*, not root causes. That wording was misleading. Accurate accounting:

| # | Finding | How established | Probe (scratch, not in repo) |
|---|---------|-----------------|------------------------------|
| 1 | Timezone: `/ai/plan` ignores client tz (`user_timezone` vs `timezone`), defaults to `"UTC"` and overrides the preference; Replan sends non-IANA `timeZoneName` → silent UTC | Reproduced | `H1` (slot `…T09:30:00Z`) |
| 2 | Every persisted `scheduled_start` is an immutable anchor; Calendar tags all tasks FIXED; Replan cannot move them | Reproduced | `H6` (`tag_text=FIXED, is_fixed=True`) |
| 3 | Anchored tasks are never checked for overlap / past / deadline | Reproduced | `H anchors` (15:00 and 15:10 overlap) |
| 4 | `latest_end` overwritten by loop variable in `evaluate_best_slot_for_task` | Reproduced | `H2` (bound 12:00, placed 14:00–14:45) |
| 5 | Replan apply fails 422 for any new task (`source:'quick_add'` invalid) and drops `urgent` priority | Reproduced (422) / code reading (priority) | `H3` |
| 6 | "Move X to tomorrow" diff item has no new time → apply update carries no start → no-op counted as updated | Code reading (Dart `toApplyRequest`; backend never emits an after-slot for moved-date tasks). **Not yet reproduced** (Dart tests blocked) | — |
| 7 | Replan working set ≠ day-view working set → task can show as "new" and be re-created by apply (duplicate); in-progress/unscheduled tasks omitted from replan | Code reading. **Not yet reproduced** — will be reproduced as the first failing test of M3 | — |
| 8 | No idempotency/atomicity: apply double-submit duplicates; `batch-create-and-schedule` ignores `idempotency_key` and commits per task; `confirmCandidates` swallows per-task failures | Reproduced (backend halves) / code reading (Flutter half) | `H5`, `H9` |
| 9 | `PATCH` cannot clear `scheduled_start` (repository skips `None`) | Reproduced | `H10` |
| 10 | `rescheduleTask` sends `deadline_at = target-day midnight` (inverts "not before") and cannot clear the old start | Code reading (Dart). Backend half proven by #9 | — |
| 11 | Dates lost after preview: `_addAndSchedule` rebuilds start as *today* + displayed time | Code reading (Dart) | — |
| 12 | Silent failure paths: `/ai/plan` scheduling `except Exception` (`ai.py:288`), `TaskService.updateTask` returns local copy on error, apply skips missing/completed tasks while counting | Code reading | — |

Probe result summary: 8 probes failed for the stated reasons (covering findings 1, 2, 3, 4, 5, 8×2, 9). 1 placeholder probe was empty. Findings 6, 7, 10, 11, 12 are **code-reading findings** and will each get a failing test before their fix (§12).

### 0.2 Additional findings discovered while writing this spec
| # | Finding | Evidence |
|---|---------|----------|
| 13 | **Alembic has no migration for the `tasks` table** (nor for `users`, `user_preferences`, `task_performance`, `ai_usage_records`, `ai_planning_requests`, `recommendation_decisions`, `recommendation_outcomes`). Migration 001 *assumes* `users` already exists (`inspector.get_columns('users')`). `create_all` runs only for non-production SQLite (`main.py:24-26`). **The repository does not show how a production schema is bootstrapped — see §11.1.** | `alembic/versions` (001–005), `app/main.py`, §11.1 evidence table |
| 14 | **SQLite drops tzinfo without converting** (aware 15:00 IST is stored as naive 15:00). `ai.py:134` reads naive as user-tz; `calendar_service._to_user_tz` reads naive as UTC. Two readers, two answers. | probe `tzprobe.py` |
| 15 | `generate_schedule` re-runs on every `GET /calendar/day` and `GET /today`, so the displayed times for flexible tasks depend on *when you ask* (drift). | `calendar_service.py:197`, `today.py:396` |
| 16 | Build My Day candidate order is the AI's order, not "locked first"; a flexible candidate can occupy a later explicit-time candidate's slot, which then gets no slot (`None`). | `ai.py:246-263` vs `generate_schedule` anchors-first |
| 17 | Slot cursor is rounded to 15 min only when `minute % 15 != 0`; seconds/microseconds survive when already aligned. | `scheduling_engine.py:586-592` |
| 18 | The no-feasible-slot fallback can place past bedtime (`max_busy_end + 10min`, unbounded). | `scheduling_engine.py:675-686` |
| 19 | Test suite writes to the configured dev DB via `SessionLocal()` (no isolated test DB). Evidence: `backend/flowstate.db` currently holds 1,611 task rows (992 manual `todo`, 361 manual `completed`, 148 archived, 89 cancelled, 21 `ai_parsed` `todo`, 1 `ai_parsed` `completed`) — overwhelmingly test artefacts. | `tests/test_calendar_replan.py:33-46`; read-only query of `backend/flowstate.db` |

Findings 13–19 are folded into the design below (§3, §5, §10, §11, §12).

---

## 1. Goals / non-goals

**Goals:** a single scheduling contract obeyed by Build My Day and Replan; correct, consistent timezone/date handling; atomic, idempotent writes; Today and Calendar render what is persisted; every invariant proven by tests.

**Non-goals (this change):**
- Removing the Flutter scheduler (kept; §9).
- Redesigning AI extraction/prompting or the AI economy (charging logic untouched).
- Un-completing a task from the UI (`toggleTaskCompletion` toggle-off is local-only today). Noted as a separate known issue; not in scope unless approved.
- Google Calendar sync stubs (`checkConnectionStatus`, etc.).

---

## 2. Shared scheduling contract

Terminology: *user-locked* = `time_locked = true`. *Flexible* = `time_locked = false` and status `todo`/`postponed`. All instants are timezone-aware; "day" means the user's local day in their IANA zone (§5).

| ID | Invariant | Enforced by |
|----|-----------|-------------|
| C1 | **Completed tasks are immutable.** Never moved, re-timed, re-statused, or deleted by planning/replan/apply. Their `[started_at or scheduled_start, completed_at]` interval is busy time. | `planner.partition()`; `apply` rejects with `skipped[reason=completed]` |
| C2 | **In-progress tasks are preserved (D7).** Never moved or cancelled by Replan. Busy until **the later of its planned end and the current time**: `start = started_at ?? scheduled_start ?? now`; `planned_end = start + estimated_minutes`; `busy = [start, max(planned_end, now)]`. An overrun therefore consumes time up to *now*; later tasks are placed at or after `max(planned_end, now)` (plus buffer). Only the user (cancel/complete endpoints) changes them. | `planner.partition()`, `apply`; tests T-C2-a…h (§12) |
| C3 | **Only `time_locked=true` times are immovable.** Scheduler-generated times (`time_locked=false`) are movable by Replan. | `planner` |
| C4 | **No overlaps.** Final placements never intersect any busy interval (completed, in-progress, locked, other placements). Buffers are soft: tried first (10–15 min), relaxed to 0 only when infeasible with them. Two *user-locked* tasks that overlap are the user's choice: both stay, and a `conflicts[]` entry is returned. | `planner` + `validate_final()` |
| C5 | **No scheduling into the past.** New/moved placements start ≥ `now` (rounded up to the 15-min grid, seconds zeroed). A flexible task whose slot is in the past and not started is *missed* → eligible for Replan re-placement. **A past explicit (user-locked) time is never silently moved (D6):** the engine returns "no slot" with reason `explicit_time_in_past` (it no longer falls through to a flexible slot); preview flags the candidate with `validation_issues[{code:"explicit_time_in_past"}]` and suggests no replacement; confirm/apply reject with the structured 422 in §7.1. "Past" means `start < now − 60 s` (tolerates client clock skew). | `planner`, `evaluate_best_slot_for_task`, `confirm`/`apply` validation |
| C6 | **Hard deadlines.** `end ≤ deadline_at` always. If impossible → task is *unscheduled* with `reason=deadline_infeasible`; never placed after the deadline; fallback never bypasses it. An imminent deadline (≤14 h) may overrun bedtime by ≤90 min (existing rule, kept). | `evaluate_best_slot_for_task` (fixed) |
| C7 | **`latest_end` / `earliest_start` / `target_date` are hard bounds** (the shadowed-variable bug, finding 4, is fixed). Preferred windows remain soft. | engine fix + tests |
| C8 | **Explicit outranks inferred.** Priority order for any time conflict: user-locked time > explicit constraints (target date, bounds, deadline) > AI-inferred > scheduler scoring. Scheduler never changes explicit fields; it only reports conflicts. | `planner` ordering |
| C9 | **No silent task loss (conservation).** Every input task id appears in exactly one of: `placements`, `immutable` (completed/in-progress/locked), `unscheduled` (with reason), `cancelled` (only when the user's op asked). The planner asserts this before returning. | `planner.assert_conserved()` |
| C10 | **No silent duplication.** Planner/apply never create a task for an id that exists; creates happen only for items explicitly flagged `new`, deduplicated per `(user_id, plan_id)`. | `apply`, `plan_applications` |
| C11 | **Replan scope.** Replan only re-places *movable* tasks whose slot is ≥ now on the target date, plus missed flexible tasks of that date and tasks named by the user's op. Other dates are untouched. Stability: a flexible task keeps its slot unless it is invalid (past/conflict/violates a bound) or displaced by an urgent/locked item; displacement order = lowest priority, then no-deadline first. Replan on a past date returns an empty diff and `conflicts=["date_in_past"]`. | `planner(mode=replan)` |
| C12 | **User scoping.** Every read/write filters on the authenticated `user_id`; `plan_applications` PK includes `user_id`; cross-user ids return 404 (existing behaviour); apply of another user's task id → `skipped[reason=not_found]`, never mutated. | repositories + tests |
| C13 | **Deterministic render.** Persisted `scheduled_start/end` are rendered as stored by Today/Calendar; the engine is not re-run on read for tasks that already have a slot (finding 15). | §8 |
| C14 | **One timezone, one clock.** §5. |

---

## 3. What `time_locked` means

`tasks.time_locked BOOLEAN NOT NULL DEFAULT FALSE`.

**Definition:** the user (or an authoritative external source) explicitly chose this start time and Flowstate must not move it. It is *not* "has a `scheduled_start`".

**D8 rule: a task becomes `time_locked` only if the time was explicitly fixed by the user's own input, or by existing product semantics that already treat it as fixed. Scheduler output is never locked.**

**Lock sources (exhaustive — anything not listed is NOT locked):**
| # | Source | Condition |
|---|--------|-----------|
| L1 | Brain-dump text | The extracted start time has provenance `explicit` (user wrote a clock time, e.g. "dentist **at 6 PM**"; deterministic parser `temporal.fixed_start` / `flexibility == "fixed"`). Gemini-extracted times lock only if the candidate's `field_provenance.scheduled_start.source` is `explicit`; `inferred`/`default` do not. |
| L2 | Fixed events in `planning_context.fixed_events` | Only when `start_time` is present **and** the same time appears in the user's text (checked in M0 by reading the extraction mapper `_map_gemini_planning_context`; if provenance cannot be established, the event is persisted **unlocked** and the preview shows a "Lock this time" toggle — never auto-locked). |
| L3 | User edits | The user sets/changes a clock time in the preview editor, edit-task sheet or reschedule sheet *with a time* (client sends `time_locked: true`). |
| L4 | Replan op wording | Existing product semantics: "…**at** 6" ⇒ fixed (`constraint_type="fixed_start"`, `calendar_service.py:409`). "around / before / by" ⇒ **not** locked (preferred start / bound). |
| L5 | External source | `source in (calendar, imported)` — only via the backfill predicate (§11.2) and any future importer. (No producer of these sources exists in the backend or Flutter code today; verified by grep.) |

**Never locked:** `recommended_slot_*`, any Replan/planner placement, "around X" (`preferred_start`), `preferred_window_*`, `relative_after/before`, availability windows, deadlines, and a `scheduled_start` that merely exists.

**Clearing:** `PATCH {time_locked:false}` or `PATCH {scheduled_start:null}` (clears both). Moving a locked task via the edit sheet keeps it locked at the new time.

**Backfill for existing rows (D2): default unlocked; strict single predicate** — rows are locked only when `source IN ('calendar','imported')`, `scheduled_start IS NOT NULL`, and status is open. Nothing is inferred from a `scheduled_start` alone, from `task_type`, or from titles. Exact SQL, report tooling and tests: §11.2–§11.4. Consequence accepted: pre-existing AI-parsed appointments (e.g. "Dentist 6 PM") remain **unlocked** after migration; Replan is a dry-run the user confirms, apply re-validates, and the user can lock them via the edit sheet. The report's *review list* (§11.3) lets you see which unlocked rows look like appointments.

**Second additive column — `planned_date DATE NULL`** (user-local date): "intended for this day, time not chosen". Replaces the current abuse of `deadline_at = midnight` for "do it on day D" (finding 10). Used for date-only reschedules and "move to tomorrow" with no feasible slot.

---

## 4. One authoritative scheduling path

New module **`backend/app/engines/planner.py`** (pure, no DB, no FastAPI). Existing `SchedulingEngine.evaluate_best_slot_for_task` (scoring, cognitive windows, personalization) is **reused unchanged in behaviour** except for the fixes listed; `generate_schedule` becomes a thin caller of the planner so Today/Calendar previews share it.

```python
@dataclass
class PlanItem:           # input; built from Task rows or AI candidates
    id: str; title: str; status: str            # todo|in_progress|completed|postponed
    estimated_minutes: int; priority: str; task_type: str; difficulty: str
    start: datetime|None; end: datetime|None    # persisted slot (aware)
    time_locked: bool; deadline_at: datetime|None
    temporal: TemporalConstraints|None; planned_date: date|None
    started_at: datetime|None; completed_at: datetime|None
    is_new: bool = False

@dataclass
class PlanResult:
    placements: list[Placement]      # flexible, with reason codes + whether moved
    immutable: list[PlanItem]        # completed / in_progress / locked (echoed, unchanged)
    unscheduled: list[Unplaced]      # id, reason (deadline_infeasible|no_capacity|bound_infeasible|date_unavailable), suggestion?
    conflicts: list[str]             # locked-vs-locked overlap, explicit-time-in-past, ...
    timezone_used: str

def plan(items, *, now_local, tz, profile, mode: Literal["build","replan"],
         extra_busy=(), ops_context=None) -> PlanResult
```

**Purity contract (final clarification, binding):** `planner.py` is deterministic and side-effect free. It imports no SQLAlchemy, FastAPI, repository, service, settings, or Flutter-facing module; it performs no I/O, no logging of user data, no `datetime.now()`, no randomness, and mutates none of its inputs (inputs are frozen dataclasses / copied). Every input — items, `now_local`, `tz`, `profile`, `extra_busy`, `mode`, op-derived constraints — is passed explicitly, and the same inputs always yield an equal `PlanResult`. Database access, persistence, authentication, timezone resolution and API/schema mapping live **outside** it. Build My Day (`/ai/plan`) and Replan (`generate_replan`) both call the one `plan()` function with a `mode` argument; their adapters only (a) build `PlanItem`s from rows/candidates and (b) map `PlanResult` to the response schema — **no placement, ordering, bounds or conflict logic may exist in an adapter**. Enforced by `test_planner_purity.py` (AST import check, frozen-input check, determinism check, no-clock check) and a test that both endpoints invoke the same `plan` object (monkeypatch spy).

**Algorithm (both modes):**
1. Normalize every datetime to aware, in `tz`.
2. Partition (C1–C3): completed → busy; in_progress → busy (C2); locked → anchors (validated: overlap among locked ⇒ `conflicts`, never moved; locked in the past are kept, not re-placed).
3. `extra_busy` (AI `planning_context` fixed events/travel/protected periods) added as busy.
4. **Keep-if-valid pass** (replan only, C11): flexible task with a persisted slot ≥ now, no conflict, bounds satisfied → stays (placed first, so churn is minimal).
5. Remaining flexible tasks (new, missed, displaced, op-targeted) ordered by existing urgency rank (overdue → due today → high/urgent → rest), then placed with `evaluate_best_slot_for_task` against all busy; each placement adds slot + soft buffer to busy. Explicit-time items are always processed before flexible ones (fixes #16).
6. Infeasible → `unscheduled` with reason (never invented slot; fallback respects bedtime and all hard bounds — fixes #18). Retry once with zero buffers before declaring `no_capacity`.
7. `assert_conserved()` (C9) and `validate_final()` (C4–C7) — a violation is a server bug → 500 + log in dev/test, covered by property tests.

**Callers:**
| Caller | Change |
|--------|--------|
| `POST /ai/plan` (`ai.py:106-289`) | Replace the per-candidate loop with `plan(mode="build")`. Existing tasks (todo/in_progress/completed-today) go in as immutable/busy; candidates as `is_new`. `planning_context` → `extra_busy`, bounds, dependency ordering (kept). The bare `except Exception` becomes: log + return candidates with `scheduling_error: "<code>"` in the response (never silent). |
| `CalendarService.generate_replan` | Replace the `TempTask` + `generate_schedule` block with `plan(mode="replan")`. Ops (§8) only *mutate input items / add constraints*; they no longer do date arithmetic on slots. |
| `CalendarService.get_day_schedule`, `today.py` | Render persisted slots as-is; tasks with no slot get an **unpersisted suggested** placement from `plan(mode="build")` marked `is_suggested=true`. |
| `generate_schedule` | Kept as a compatibility wrapper (existing tests keep passing) delegating to `plan()`. |

**Engine fixes (inside `scheduling_engine.py`):**
- #4: rename the user bound (`user_latest_end`) vs. day-limit (`day_limit`).
- #3/#2: anchors validated; "anchor" now means `time_locked` only.
- D6: the "past fixed start falls through to a flexible slot" branch (`scheduling_engine.py:519-522`) is replaced by `return None` with reason `explicit_time_in_past` (callers surface it; no silent move).
- #17: zero seconds/microseconds on cursor.
- #18: fallback bounded by bedtime and hard bounds.

---

## 5. Timezone handling (end-to-end)

**Single representation:** IANA name (`Asia/Kolkata`). Instants on the wire and in storage are UTC (`…Z`) or carry an explicit offset; **never** naive; **never** abbreviations (`IST`).

**Resolution (one backend helper `resolve_timezone(request_tz, prefs_tz) -> (ZoneInfo, name)` in `app/core/timezone.py`):**
1. `request_tz` if it is a valid IANA key;
2. else `user_preferences.timezone` if valid;
3. else `"UTC"` and log a warning.
An invalid-but-present request tz (e.g. `"IST"` from an old client) falls back to the preference (step 2), **not** UTC. Every response that depends on tz returns `timezone_used`.

**Per layer:**
| Layer | Change |
|-------|--------|
| Flutter | Obtain device IANA name via `flutter_timezone` (**D3 approved**; the exact version and call signature are taken from current package docs at M6 — the API differs between major versions — and `flutter pub get` must be run by you since `flutter` is blocked here). Send as `timezone` on `/ai/plan`, `/calendar/replan`, `/calendar/day`, `/tasks/batch-create…`. Replace `DateTime.now().timeZoneName` (`app_state_provider.dart:888`) and `user_timezone` (`ai_plan_service.dart:64`). Onboarding stops hardcoding `Asia/Kolkata` (`onboarding_flow_screen.dart:272`) and stores the device zone; on launch/login, if device zone ≠ stored preference, PUT it. Serialize instants with `toUtc().toIso8601String()`; send `current_local_time` with offset. |
| API schemas | `AIPlanRequest.timezone` accepts alias `user_timezone` (back-compat). Add optional `current_local_time` to `AIPlanRequest` (determinism; mirrors `ReplanRequest`). Add `timezone_used` to `AIPlanResponse`, `PlanDiff`, `DayScheduleResponse`. |
| Scheduler | Receives `tz` from the single helper; no module reads `datetime.now()` itself (clock injected via `now_local`). |
| DB | New `UTCDateTime` `TypeDecorator` (impl `DateTime(timezone=True)`) on `Task.deadline_at/scheduled_start/scheduled_end/started_at/completed_at`: bind → convert aware to UTC (naive treated as UTC); result → aware UTC. Eliminates finding 14. No schema change; Postgres behaviour unchanged. Legacy SQLite rows hold naive digits written from UTC clients → interpreted as UTC (documented; rows written by Python tests with non-UTC aware values are test artefacts only). |
| Serialization | Pydantic emits aware datetimes; Flutter parses with `DateTime.parse(...).toLocal()` only for display. |

**Verification:** `test_timezone_contract.py` (§12) asserts each hop; manual checklist asserts on device.

---

## 6. Date preservation: brain dump → Replan

Rule: **a placed task carries one full aware instant (`scheduledStart`) from extraction to the DB; nothing reconstructs a date from a display string.**

| Stage | Contract |
|-------|----------|
| Brain dump | Raw text + IANA tz + `current_local_time`. |
| AI extraction / deterministic parse | Dates resolved server-side in user tz into `temporal.target_date` (date) / `temporal.fixed_start` (aware instant). |
| Planner | Returns `recommended_slot_start/end` as aware UTC instants **plus** `recommended_slot_date` (user-local `YYYY-MM-DD`) for display/grouping. |
| Preview (Flutter) | `ExtractedTaskItem.toTaskItem()` keeps `scheduledStart = explicit ?? recommendedSlotStart` as `DateTime`, and sets `timeLocked = explicit != null`. The local engine **must not override** a task that already has a server slot (§9). |
| Editing | Date picker + time picker both write into `scheduledStart` (existing `parsed_plan_confirm_sheet` behaviour); editing time sets `timeLocked=true`; editing date only → keeps time-of-day, `timeLocked` unchanged; clearing time → `scheduledStart=null, plannedDate=date`. |
| Confirmation | `_addAndSchedule` (`brain_dump_sheet.dart:455-492`) deletes the "rebuild from `sched.time` + today" branch (finding 11); it uses `task.scheduledStart` or, for local-fallback items, `ScheduleItem.startTime` (full `DateTime`). If neither exists the task is sent unscheduled with `plannedDate`. |
| Persistence | `POST /tasks/batch-create-and-schedule` (§7) stores UTC instants + `time_locked` + `planned_date`. |
| Today / Calendar | Render stored instants converted to the user's tz; the day bucket = user-local date of `scheduled_start`, else `planned_date`, else (existing deadline rules). |
| Replan | Ops resolve to concrete local dates server-side (`tomorrow` → `YYYY-MM-DD`; weekday → next occurrence strictly after today); the diff carries `new_date` as ISO date **and** an after-slot instant. |

---

## 7. Plan My Day (Build My Day confirm) apply semantics

Endpoint (existing path kept): `POST /api/v1/tasks/batch-create-and-schedule`.

**Request additions:** `plan_id` (required for new clients; falls back to existing `idempotency_key`), `timezone`, per-item `time_locked`, `planned_date`, `client_ref` (local temp id, echoed back so Flutter can swap temp → persisted ids).

**Semantics:**
- **Atomic:** one transaction; repository gets non-committing `add()`/`flush()` variants; a single `commit()`. Any failure → rollback, nothing persisted.
- **Idempotent per `plan_id`:** new table `plan_applications(user_id, plan_id, kind, response_json, created_at, PRIMARY KEY (user_id, plan_id))`. Replay returns the stored response with HTTP 200 and `idempotent_replay: true`. Concurrent duplicates are serialized by the existing per-user lock and by the PK (`IntegrityError` → return stored response).
- **Server-side validation (per item, HTTP 422, all-or-nothing, nothing persisted):** title 1–255; duration 5–480; aware datetimes; `scheduled_end > scheduled_start` (derived from duration when absent); `deadline_at ≥ scheduled_end` if both; **explicit (locked) start not in the past** (`explicit_time_in_past`, D6); user-locked vs existing locked overlap → allowed with `conflicts[]` (C4).

#### 7.1 Structured validation error (D6) — consumed by Flutter
```json
HTTP 422
{ "detail": {
    "code": "validation_failed",
    "errors": [
      { "index": 2, "client_ref": "task-1727…-2", "field": "scheduled_start",
        "code": "explicit_time_in_past",
        "message": "“Dentist” is set for 6:00 PM, which has already passed. Choose a new time.",
        "title": "Dentist", "requested_start": "2026-10-02T12:30:00Z" } ] } }
```
`message` is user-facing, in the user's local time/format, and safe to render verbatim. Flutter behaviour: keep the preview open, mark the item(s) by `client_ref`, show the message inline, and open the time picker for the first failing item; Confirm stays disabled for that item until a future time is chosen (or the user clears the time, making it flexible). Same `code`/shape is used by Replan apply as `start_in_past` (field `task_updates[i].scheduled_start`). Other codes: `invalid_duration`, `deadline_before_end`, `missing_timezone`.
- **Stale-slot re-validation:** for each *flexible* item the server checks the proposed slot against current DB state (completed, in-progress, locked, already-persisted flexible, and earlier items in this batch). Valid → persisted as proposed. Invalid (state changed since preview) → server re-places that item via `plan()` and reports `adjustments[{client_ref, from, to, reason}]`; infeasible → persisted **unscheduled** (`scheduled_start=null`, `planned_date` set) and listed in `unscheduled[]`. Never dropped.
- **Dedupe:** exact `(title, scheduled_start, duration)` already present as an open task of this user → not re-created, reported in `deduplicated[]` (guards double-tap before `plan_id` exists on old clients).
- **Failure behavior in Flutter:** on 4xx/5xx/network error the preview stays open, the error is shown inline with a Retry that re-sends the **same `plan_id`**; local `_tasks` are **not** mutated until the server confirms (replaces optimistic insert + swallowed errors in `confirmCandidates`). On success, local tasks are replaced by the returned persisted rows, then `refreshTodayData` + `loadCalendarDay`.
- **Fixed events:** items from `planning_context.fixed_events` are persisted as `task_type=meeting, time_locked=true` tasks (deduped against a candidate of the same time/title). *To verify in M0 step 1: how the Flutter client currently treats `planning_context.fixed_events` (not yet audited).*

`POST /ai/plan` remains a **preview**: no task writes; economy charging unchanged.

---

## 8. Replan semantics

Dry run: `POST /ai/replan` and `/calendar/replan` (alias, kept). Apply: `POST /calendar/apply-replan`.

### 8.1 Dry run
1. Working set = **all open tasks of the user that are relevant to the target date** using the *same query as the day view* (fixes #7), plus completed tasks of that date as immutable.
2. Ops (parser unchanged in behaviour; resolution moves server-side):
   | Op | Effect on planner input |
   |----|-------------------------|
   | `delay_remaining_schedule(n)` | Movable tasks get `earliest_start = max(now, current_start)+n`; re-placed by planner (not raw offset arithmetic, so no new overlaps). Locked, in-progress, completed untouched. Replaces keyword guard (`dentist/doctor/meeting`) with `time_locked`. |
   | `cancel_task(q)` | Matches **only open flexible or locked** tasks by title; ambiguous (>1 match) ⇒ conflict `ambiguous_task` and no cancel; completed/in-progress never matched. |
   | `move_task_date(q, date)` | Resolve date; set `temporal.target_date`; planner places on that date; infeasible ⇒ `planned_date=date`, unscheduled with suggestion. Diff item carries `new_date` **and** `new_start`. |
   | `shift_task_preference`, `add_constraint` | Soft/hard constraints as today (window = soft; after-dinner = hard bound). |
   | `add_task` (urgent) | New `is_new` item. With explicit time → `time_locked=true`; collides with a *locked* item ⇒ conflict, task placed in nearest feasible slot, locked item untouched; collides with a *flexible* item ⇒ the flexible item is **displaced**. |
3. Planner runs in `replan` mode (C11). Result is classified into: `unchanged`, `moved` (old→new instant), `newly_scheduled` (only `is_new`), `cancelled`, `unscheduled`, `skipped_immutable` (informational: completed/in-progress/locked tasks that were considered).
4. **Insufficient remaining time:** lowest-displacement-cost tasks go to `unscheduled`; if no deadline blocks it, the diff includes a *proposed* roll-over (`planned_date=tomorrow` + slot) shown to the user as a distinct section; if a deadline blocks it, it stays `unscheduled(reason=deadline_infeasible)` + conflict message. Nothing is hidden.
5. Response: `PlanDiff` (existing fields kept) + new fields `plan_id`, `timezone_used`, `skipped_immutable`, per-task `expected_updated_at` (optimistic-concurrency token), `new_start/new_end` instants on every moved/new item.

### 8.2 Apply
Request: `plan_id`, `selected_date`, `task_updates[{task_id, scheduled_start, scheduled_end, planned_date, expected_updated_at}]`, `new_tasks[…]` (valid `source`, priority/type preserved from the diff), `cancelled_task_ids[]`. **Built from the diff by one function** (`PlanDiff.toApplyRequest`) that now reads `new_start/new_end` directly — no title matching, no `firstWhere(..., orElse: first)` guessing (finding 6).

Server behaviour (single transaction, idempotent per `(user_id, plan_id)` via `plan_applications`):
| Case | Behaviour |
|------|-----------|
| Task not found / other user's | `skipped[reason=not_found]`; not counted as updated |
| Completed | `skipped[reason=completed]` (C1) |
| In-progress | `skipped[reason=in_progress]` for moves/cancels (C2) |
| Cancelled/archived | `skipped[reason=terminal]` |
| `time_locked` task in `task_updates` | `skipped[reason=locked]` (Replan never emits these; protects against stale/hostile payloads) |
| `expected_updated_at` mismatch | Whole apply → **409** `stale_plan` listing changed task ids; nothing persisted; Flutter re-runs the dry run |
| Update start in the past | rejected (C5) → 422 `start_in_past`, all-or-nothing |
| Result violates overlap/deadline/`latest_end` vs *current DB state + this payload* | 422 `invariant_violation` with details (planner `validate_final` re-run server-side) |
| New task | created once per `(plan_id, index)`; `time_locked` per §3; urgent priority preserved |
| Cancel | open non-in-progress tasks only → `status=cancelled` |
| Success response | `{success, updated[], created[], cancelled[], skipped[], persisted_tasks[]}` — the persisted rows, so Flutter updates local state from truth; counts derive from the lists |
| Replay | stored response, `idempotent_replay: true` |

**Unchanged tasks:** never written (no `updated_at` churn).
**"Tomorrow" moves:** persisted as concrete `scheduled_start/end` (if a slot was found) or `planned_date` + null slot; `time_locked` unchanged.

---

## 9. The Flutter scheduler (kept, not removed)

- **Backend is authoritative** for any task that carries a server slot. Flutter's `enrichTasksWithOptimalSlots` / `generateOptimizedSchedule` are changed to **skip tasks that already have `scheduledStart` or `recommendedSlotStart` from the server** (guarded by the new `timeLocked`/`slotSource` fields) and are otherwise left as-is for the offline/local-fallback path (`_proceedLocalParsing`, demo mode, `_recalculateSchedule` when backend data isn't fresh).
- `brain_dump_sheet.dart:213-220` still calls the local engine for the AI path **only to render the preview timeline**, never to alter slots.
- **Equivalence proof before any removal:** a shared fixture file `backend/tests/fixtures/scheduling_contract_cases.json` (inputs + *invariant* expectations: no overlap, not past, locked unchanged, deadline/`latest_end` respected, conservation — not exact slots). Backend tests run it against `planner`; a Dart test `test/scheduling_contract_fixtures_test.dart` runs the same file against the Dart engine. Divergences are logged as an issue list; the Dart engine is **not** deleted in this change. Removal would be a separate spec after the user runs the Dart suite and the divergence list is empty.
- Offline path writes tasks with `scheduledStart` only if the user typed a time (`timeLocked=true`); otherwise unscheduled with `plannedDate`, so the server can place them later (prevents the local guess from becoming a permanent anchor).

---

## 10. Exact change list

### 10.1 Backend
| File | Change |
|------|--------|
| `app/models/task.py` | add `time_locked` (Boolean, default False, server_default false), `planned_date` (Date, null); apply `UTCDateTime` to datetime columns |
| `app/db/types.py` (new) | `UTCDateTime` TypeDecorator |
| `app/models/plan_application.py` (new) + `models/__init__.py` | `PlanApplication` table |
| `app/core/timezone.py` (new) | `resolve_timezone()` |
| `app/engines/planner.py` (new) | `PlanItem`, `PlanResult`, `plan()`, `validate_final()`, `assert_conserved()` |
| `app/engines/scheduling_engine.py` | fix #4 (`latest_end` shadow), #17, #18; `generate_schedule` → delegates to `planner`; remove "any scheduled_start = anchor" |
| `app/schemas/task.py` | `time_locked`, `planned_date` on `TaskCreate/Update/Response/Batch*`; `plan_id`, `client_ref`, `timezone`; batch response adds `adjustments/unscheduled/deduplicated/idempotent_replay`; `TaskUpdate` distinguishes "unset" vs explicit `null` |
| `app/schemas/ai.py` | `AIPlanRequest.timezone` alias `user_timezone`, `current_local_time`; `AIPlanResponse.timezone_used`, `scheduling_error` |
| `app/schemas/calendar.py` | `PlanDiff` new fields; `TaskScheduleUpdate.planned_date/expected_updated_at`; `ApplyReplanResponse` lists; `DayScheduleItem.is_suggested`, `time_locked` |
| `app/repositories/task_repository.py` | `update()` honours explicit nulls for nullable fields; non-committing `add()`; `list_open_for_day()` (the **single** day-relevance query used by day view, Today, Replan) |
| `app/services/task_service.py` | `batch_create()` (atomic, idempotent, validating); `update_task` uses `model_fields_set` |
| `app/services/calendar_service.py` | `get_day_schedule` renders persisted slots; `generate_replan` → planner; `apply_replan` rewritten per §8.2; ops resolve dates server-side |
| `app/api/routes/ai.py` | `/ai/plan` → planner; no bare swallow; `/ai/replan` unchanged route |
| `app/api/routes/tasks.py` | `batch-create-and-schedule` per §7 |
| `app/api/routes/calendar.py` | `/day` and `/replan` use `resolve_timezone`; `/apply-replan` error mapping (409/422) |
| `app/api/routes/today.py` | render persisted; use shared day query |
| `app/main.py` | dev-SQLite `ALTER TABLE tasks ADD COLUMN …` shims (columns default unlocked) + backfill using the shared predicate, only on first column add |
| `app/db/backfill.py` (new) | `LOCK_BACKFILL_WHERE` — the single backfill predicate (§11.3) |
| `alembic/versions/006_task_planning_columns.py` (new) | §11.2 (ALTER-only, fails loudly if `tasks` is missing; `-x skip_lock_backfill=1`) |
| `scripts/report_time_lock_backfill.py` (new) | read-only report, sections A/B/C (§11.3) |
| `tests/conftest.py` (new) | isolated temp-file SQLite DB per session + fixtures (finding 19); existing tests keep working |

### 10.2 Flutter (verified by `dart analyze` here; tests run by the user)
| File | Change |
|------|--------|
| `pubspec.yaml` | `flutter_timezone` (D3) |
| `lib/services/timezone_service.dart` (new) | `Future<String> localIanaName()` with safe fallback (null ⇒ omit field; never an abbreviation) |
| `lib/services/ai_plan_service.dart` | send `timezone` (IANA), `current_local_time`, `plan_id`; read `timezone_used`, `scheduling_error` |
| `lib/providers/app_state_provider.dart` | `replanDay` tz; `confirmCandidates` → batch endpoint, no optimistic insert, no swallowed errors, id swap via `client_ref`; `rescheduleTask` stops sending `deadlineAt`, uses `plannedDate`, sends explicit nulls; `applyReplan` uses returned `persisted_tasks`; remove `_applyPlanDiffLocally` `afterSchedule.first` guess |
| `lib/services/task_service.dart` | `updateTask` rethrows; `batchCreateAndSchedule()` |
| `lib/models/calendar_models.dart` | `toApplyRequest` uses `new_start/new_end`, valid `source`, preserves priority/type; parse new diff fields |
| `lib/models/task_item.dart`, `lib/models/ai_plan_models.dart` | `timeLocked`, `plannedDate`; `toTaskItem` sets `timeLocked` from provenance; `toJson` includes both |
| `lib/screens/brain_dump_sheet.dart` | remove date-rebuild branch (`:469-484`); inline error + retry; local engine does not override server slots |
| `lib/engines/scheduling_engine.dart` | skip tasks with server slot / `timeLocked` in `enrichTasksWithOptimalSlots` |
| `lib/screens/parsed_plan_confirm_sheet.dart`, `lib/components/edit_task_sheet.dart`, `reschedule_task_sheet.dart` | set `timeLocked` on explicit time edits; date-only → `plannedDate` |
| `lib/screens/replan_day_sheet.dart`, `lib/components/plan_diff_view.dart` | show unscheduled / skipped-immutable / roll-over proposals / 409 stale → auto re-plan prompt; loading/error/empty states (Phase 6) |
| `lib/screens/onboarding_flow_screen.dart` | store device IANA tz instead of hard-coded `Asia/Kolkata` |
| `lib/screens/calendar_tab.dart`, `today_dashboard_tab.dart` | show "suggested" vs "fixed" styling from `is_fixed/is_suggested`; unscheduled section |

---

## 11. Alembic migration, production-schema evidence (D4), and data-migration strategy

### 11.1 D4 — what the repository proves about the production `tasks` table

**Conclusion: the repository does not contain enough evidence to determine how a production `tasks` table is created, or whether a production database exists. I am not guessing.** Evidence gathered:

| Question | Evidence | Reading |
|---|---|---|
| Does Alembic create `tasks`? | `grep create_table alembic/versions/*.py` → only `readiness_*`, `personalization_settings`, `flow_*` (9), `privacy_grievances`. Model `__tablename__`s with **no** creating migration: `users`, `user_preferences`, **`tasks`**, `task_performance`, `ai_usage_records`, `ai_planning_requests`, `recommendation_decisions`, `recommendation_outcomes`. | Alembic is an *incremental* chain that presupposes a pre-existing base schema. |
| Does the chain assume a base schema? | `001_readiness.py:19-23` calls `inspector.get_columns('users')` unguarded and `ALTER TABLE users`; its `down_revision` is `None`. | On an empty database, `alembic upgrade head` fails at 001. |
| Does app code bootstrap tables in production? | `Base.metadata.create_all` appears once (`main.py:26`), inside `if not is_production and DATABASE_URL.startswith("sqlite")`; the comment says "Production relies strictly on Alembic migrations". | In production nothing creates `tasks`; the comment is contradicted by the migration chain (Alembic cannot create it). |
| Deployment config? | `git ls-files` shows no Dockerfile, Procfile, compose file, CI workflow, `.sql`, or `supabase/` directory. Only `run.ps1`, `requirements.txt`, `alembic.ini` (`sqlalchemy.url = sqlite:///./flowstate.db`). | No documented deploy/bootstrap procedure. |
| Which DB do the env files point to? | `backend/.env` and `.env.example`: `DATABASE_URL=sqlite:///./flowstate.db`. README: "`# Or postgresql://…`". `config.py`: "PostgreSQL via Supabase in production". Supabase is configured for **auth (JWKS)**; no Supabase SQL/migrations are in the repo. | A Postgres target is stated in docs; there is no evidence a production DB exists. |
| History? | 13 commits; Alembic introduced in `4b1cc62`; `create_all` introduced in `3cae428`; no commit adds a baseline schema. | — |
| Local dev DB state | `backend/flowstate.db` has an `alembic_version` table at `004_compliance_and_consent` (migrations 001–004 were run after `create_all`), **not** at 005. | In dev, the real bootstrap order is `create_all` → `alembic upgrade`. |
| Postgres enum details | `Task.status/task_type/priority/difficulty/source` use `SQLEnum` (SQLAlchemy stores enum **names**; native enum types on Postgres). Actual type names/labels in any production DB are unknown. | The backfill predicate's string literals must be verified against the real DB before use. |

**What is missing (needed only for the *production* track):**
1. Whether a production/staging database exists at all, and its engine (Supabase Postgres? other?).
2. How its base tables (`users`, `tasks`, …) were created — e.g. a manual one-off `create_all`, the Supabase SQL editor, a script outside this repo.
3. The current Alembic state there: `SELECT * FROM alembic_version;` (or "table does not exist").
4. The live `tasks` definition: `SELECT column_name, data_type, udt_name, is_nullable, column_default FROM information_schema.columns WHERE table_name='tasks';` and `SELECT t.typname, e.enumlabel FROM pg_enum e JOIN pg_type t ON e.enumtypid=t.oid WHERE t.typname IN ('taskstatus','tasksource','tasktype');`
5. `SELECT source, status, count(*), count(scheduled_start) FROM tasks GROUP BY 1,2;` (to size the backfill).

**How this affects the plan — two tracks:**
- **Dev/test track (proceeds after approval):** SQLite. `create_all` creates the new columns/table for fresh DBs; the existing dev-startup `ALTER TABLE` shim adds them to existing dev DBs; Alembic 006 is tested against a SQLite fixture DB built from the *current* schema. Nothing here depends on production facts.
- **Production track (BLOCKED until items 1–5 are answered):** I will write migration 006, but it will **not** be declared production-ready. I will not write a baseline migration or choose a bootstrap strategy until you supply the facts above. If a production DB exists with an `alembic_version`, 006 chains off `005_privacy_grievances`. If it was bootstrapped another way, whether to `alembic stamp 005_privacy_grievances` or add a baseline revision is a decision for you — not something I will assume.

### 11.2 Revision `006_task_planning_columns` (`down_revision = '005_privacy_grievances'`) — ALTER-only; fails loudly

Change from Rev 1: it **no longer silently skips** when `tasks` is absent, because silent skipping would hide a mis-bootstrapped database.
```python
insp = sa.inspect(op.get_bind())
if "tasks" not in insp.get_table_names():
    raise RuntimeError("006_task_planning_columns requires an existing 'tasks' table; "
                       "Alembic does not create it (see spec §11.1). Bootstrap the base schema first.")
cols = {c["name"] for c in insp.get_columns("tasks")}
```
Each object is created only if missing (idempotent):
- `ALTER TABLE tasks ADD COLUMN time_locked BOOLEAN NOT NULL DEFAULT FALSE` (**default unlocked**)
- `ALTER TABLE tasks ADD COLUMN planned_date DATE NULL`
- `CREATE TABLE plan_applications (user_id VARCHAR NOT NULL REFERENCES users(id) ON DELETE CASCADE, plan_id VARCHAR(100) NOT NULL, kind VARCHAR(20) NOT NULL, response_json TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL, PRIMARY KEY (user_id, plan_id))`
- `CREATE INDEX ix_tasks_user_scheduled_start ON tasks (user_id, scheduled_start)`

The backfill runs **only when `time_locked` was just added** and **only if not disabled**: `alembic -x skip_lock_backfill=1 upgrade head` skips it; `alembic upgrade head --sql` (offline mode) prints the exact statements without touching data. No new enum values are introduced, so there is no enum migration.

**Downgrade:** drop the index, drop `plan_applications`, drop the two columns (SQLite via `batch_alter_table`). This loses only lock flags and planned dates.

### 11.3 Exact backfill predicate (D2) and inspection

```sql
UPDATE tasks
   SET time_locked = TRUE
 WHERE scheduled_start IS NOT NULL
   AND source IN ('calendar', 'imported')
   AND status IN ('todo', 'postponed', 'in_progress');
```
That is the **entire** predicate. Explicitly **not** used: `task_type`, title keywords, a bare `scheduled_start`, priority, creation time. Completed/cancelled/archived rows are never touched. Today it would lock **0 rows** in the local dev DB (no row has `source` = `calendar`/`imported`, and no code path in the backend or Flutter produces those sources — verified by grep and a read-only query), so it is forward-looking safety for future importers.

The predicate lives in **one constant** (`app/db/backfill.py::LOCK_BACKFILL_WHERE`) imported by the migration, the dev shim and the report script, and a test asserts all three use the identical string (no drift).

**Read-only report — `backend/scripts/report_time_lock_backfill.py`** (opens the DB read-only; never issues `UPDATE`/`ALTER`; `--database-url` optional, defaults to `settings.DATABASE_URL`):
- Section A **"Would be locked"**: rows matching the predicate (`id, user_id, title, source, task_type, status, scheduled_start`) plus totals.
- Section B **"Review list (NOT locked — informational)"**: open rows with a `scheduled_start` that merely *look* fixed (`task_type='meeting'` or appointment keywords in the title). These stay unlocked; you can lock any of them through the edit sheet.
- Section C: totals by `(source, status)` and counts with/without `scheduled_start`.
- Output: a human-readable table by default; `--csv path` for a spreadsheet.
You run it **before** `alembic upgrade`. Because the migration runs the same predicate, section A is exactly the set of rows that will change.

### 11.4 Safety procedure
1. Backup first (dev: copy `flowstate.db`; prod: `pg_dump`, your action).
2. Run the report; review sections A and B.
3. Dev: `alembic upgrade head` (or let the dev shim run). Prod: only after §11.1 items 1–5 are answered and approved.
4. Verify: `SELECT count(*) FROM tasks WHERE time_locked` equals report section A's count.
5. Rollback: restore the backup, or `alembic downgrade 005_privacy_grievances`.

**Backfill predicate tests** (`tests/test_migration_time_locked.py`; SQLite fixture DB built from the **pre-006 schema**; exact expectations):
| Row | Expected `time_locked` |
|---|---|
| source=calendar, todo, has start | **TRUE** |
| source=imported, in_progress, has start | **TRUE** |
| source=calendar, postponed, has start | **TRUE** |
| source=calendar, todo, **no** start | FALSE |
| source=calendar, completed / cancelled / archived, has start | FALSE |
| source=manual, todo, has start | FALSE |
| source=ai_parsed, todo, has start, title "Dentist at 6 PM" | FALSE |
| source=ai_parsed, task_type=meeting, has start | FALSE |
| source=manual, task_type=meeting, title "Team meeting", has start | FALSE |

Plus: no other pre-existing column changes (row-wise compare before/after); `planned_date` is NULL everywhere; the migration is idempotent (run twice, same result); `-x skip_lock_backfill=1` leaves everything FALSE; report section A == rows changed; the three consumers share one predicate string; 006 on a DB without `tasks` raises the explicit error.

---

## 12. Automated test plan (every finding has a failing-first test)

All backend tests use the new isolated DB (`tests/conftest.py`), explicit `now_local` / `current_local_time` (no wall-clock dependence), and are run after each milestone with `pytest -q` (baseline 244 passing must remain green; existing tests that encoded the old "anchor everything" behaviour are updated in the same commit with a stated reason, never weakened silently).

| Finding / contract | Test file :: test | Asserts |
|---|---|---|
| 1 tz (plan) | `test_timezone_contract.py::test_plan_uses_request_iana_tz`, `::test_plan_user_timezone_alias`, `::test_plan_invalid_abbrev_falls_back_to_preference_not_utc`, `::test_plan_response_reports_timezone_used`, `::test_slot_hours_are_in_user_wake_bedtime_window_in_local_time` | `timezone_used`, local-hour bounds |
| 1 tz (replan/day) | `::test_replan_and_day_use_same_tz`, `::test_replan_ist_abbrev_does_not_fall_back_to_utc` | same zone across endpoints |
| 14 SQLite tz | `test_utc_datetime_type.py::test_aware_ist_roundtrips_to_same_instant`, `::test_naive_treated_as_utc`, `::test_between_day_bounds_after_roundtrip` | instant equality |
| 2 lock semantics | `test_time_locked.py::test_recommended_slot_not_locked`, `::test_explicit_time_locked`, `::test_calendar_tags_fixed_only_when_locked`, `::test_replan_moves_unlocked_persisted_task` | `is_fixed == time_locked` |
| 3 overlaps | `test_planner_contract.py::test_locked_overlap_reported_not_moved`, `::test_no_placement_overlaps_any_busy` | C4 |
| 4 latest_end | `test_temporal_constraints.py::test_latest_end_is_hard_bound`, `::test_latest_end_with_multi_day_candidates`, `::test_availability_window_bounds_all_candidates` | C7 |
| 5 apply new task | `test_apply_replan_semantics.py::test_new_task_valid_source_creates`, `::test_urgent_priority_preserved` | 200 + stored priority |
| 6 tomorrow move | `::test_move_to_tomorrow_diff_has_new_start`, `::test_apply_move_to_tomorrow_persists_slot`, `::test_move_to_tomorrow_infeasible_sets_planned_date` | DB shows new date |
| 7 working set | `::test_replan_and_day_view_same_task_set`, `::test_existing_task_never_classified_new`, `::test_apply_never_duplicates_existing` | C10 |
| 8 idempotency / atomic | `test_plan_confirm.py::test_replay_same_plan_id_no_duplicates`, `::test_concurrent_same_plan_id_single_create` (threads), `::test_batch_failure_rolls_back_all`, `::test_idempotency_key_honored`; `test_apply_replan_semantics.py::test_apply_replay_idempotent`, `::test_apply_atomic_rollback` | row counts |
| 9 PATCH nulls | `test_task_patch_nulls.py::test_clear_scheduled_start`, `::test_unset_field_untouched`, `::test_null_non_nullable_rejected` | explicit null honoured |
| 10 reschedule | `::test_date_only_reschedule_sets_planned_date_not_deadline` (API-level equivalent of Dart `rescheduleTask`) | no `deadline_at` written |
| 11 date preservation | `test_date_preservation.py::test_tomorrow_slot_keeps_tomorrow_date_through_confirm_and_day_view`, `::test_recommended_slot_date_field_matches_instant_in_tz` | date survives |
| 12 silent failure | `test_plan_endpoint.py::test_scheduler_exception_reported_not_swallowed`, `::test_apply_skips_listed_not_counted` | `scheduling_error`, `skipped[]` |
| 15 render determinism | `test_day_render.py::test_persisted_slots_rendered_as_stored_regardless_of_now` | same output at two `now` values |
| 16 ordering | `test_planner_contract.py::test_explicit_time_candidate_not_displaced_by_earlier_flexible_candidate` | locked first |
| 17/18 | `::test_slots_have_zero_seconds`, `::test_fallback_never_past_bedtime_or_deadline` | |
| C1 | `::test_completed_never_moved_or_selected_by_ops`, `test_apply_replan_semantics.py::test_apply_skips_completed` | |
| C2 | `::test_in_progress_busy_until_max_end_now`, `::test_running_late_does_not_move_in_progress`, `::test_apply_skips_in_progress` | |
| C5 | `::test_nothing_placed_before_now`, `::test_missed_flexible_replaced`, `::test_past_explicit_time_rejected_at_confirm`, `::test_now_near_end_of_day_rolls_to_tomorrow_or_unscheduled` | |
| C6 | `::test_deadline_never_exceeded`, `::test_deadline_infeasible_unscheduled_with_reason`, `::test_apply_rejects_deadline_violation` | |
| C9 | `::test_conservation_property` (200 seeded random scenarios; every id in exactly one bucket) | |
| C11 | `::test_unchanged_tasks_not_moved` (minimal movement), `::test_urgent_displaces_lowest_priority_first`, `::test_insufficient_time_lists_unscheduled_and_rollover`, `::test_multiple_conflicts`, `::test_replan_past_date_empty_diff`, `::test_other_dates_untouched`, `::test_next_day_boundary` | |
| C12 | `test_user_isolation.py` additions: `::test_calendar_day_scoped`, `::test_replan_ignores_other_users_tasks`, `::test_apply_other_users_task_id_skipped_not_found`, `::test_plan_applications_scoped_same_plan_id_two_users`, `::test_plan_does_not_busy_against_other_users_tasks` | |
| Build My Day inputs | `test_build_my_day_inputs.py`: simple; messy multi-sentence; multiple tasks in one paragraph; explicit time; explicit duration; deadline; time+deadline; fixed event + flexible; conflicting constraints; optional (`low`/deferred) task; duplicate-like input; DST/date-boundary (23:50 now, "tomorrow"); empty/invalid (422); AI-generated candidates via monkeypatched `extract_structured_plan_with_gemini` | each asserts contract, not exact slots |
| Migration / backfill (D2) | `test_migration_time_locked.py` | the full row matrix in §11.4, idempotency, skip flag, report == changed rows, shared-predicate identity, loud failure without `tasks` |
| D6 past explicit time | `test_past_explicit_time.py::test_engine_returns_none_with_reason_not_flexible_slot`, `::test_preview_flags_validation_issue_no_replacement`, `::test_confirm_422_structured_error_shape` (asserts `code`, `index`, `client_ref`, `field`, user-facing `message` with local time), `::test_confirm_nothing_persisted_on_error`, `::test_apply_start_in_past_422`, `::test_flexible_past_slot_is_replaced_not_rejected`, `::test_skew_tolerance_60s` | |
| D7 in-progress busy time | `test_in_progress_busy.py`: **T-C2-a** planned end later than now → busy to planned end; **T-C2-b** overrun (now > planned end) → busy until now; **T-C2-c** `started_at` earlier than `scheduled_start` → uses `started_at`; **T-C2-d** no start fields → `[now, now+estimate]`; **T-C2-e** later placements start ≥ busy end (+buffer) and never inside it; **T-C2-f** Replan never moves/cancels it; **T-C2-g** apply `skipped[reason=in_progress]`; **T-C2-h** "running late" does not move it but shifts later flexible tasks without overlap | |
| D8 lock sources | `test_time_locked.py::test_L1_explicit_text_locks`, `::test_L1_inferred_gemini_time_does_not_lock`, `::test_L2_fixed_event_without_explicit_provenance_unlocked`, `::test_L3_user_edit_locks`, `::test_L4_at_locks_around_before_by_do_not`, `::test_recommended_slot_never_locked`, `::test_replan_placement_never_locked`, `::test_preferred_start_window_relative_never_lock` | |
| #13 / #19 harness | `test_isolated_db.py::test_tests_use_temp_database_not_dev_db` (engine URL is under the temp dir and not `backend/flowstate.db`; dev DB file hash unchanged after a request), `test_migration_time_locked.py::test_006_fails_loudly_without_tasks_table` | |
| Cross-engine fixtures | `test_scheduling_contract_fixtures.py` (Python) + `test/scheduling_contract_fixtures_test.dart` (**user runs**) | §9 |
| Flutter unit/widget (written here, **run by you**) | `test/timezone_payload_test.dart` (FakeApi captures body: IANA, no `user_timezone`), `test/to_apply_request_test.dart` (move-tomorrow has start; valid `source`; urgent preserved), `test/confirm_candidates_batch_test.dart` (failure keeps preview, no phantom tasks, retry uses same plan_id), `test/date_preservation_test.dart` (tomorrow slot not rebuilt as today), `test/reschedule_payload_test.dart` (no `deadline_at`, explicit nulls, `planned_date`) | |

### 12.1 End-to-end acceptance tests (backend, API-level, real DB, engine/session disposed between phases to emulate restart)
`tests/test_e2e_build_and_replan.py`:
- **E2E-A Build My Day:** messy brain dump (mocked extraction) → `/ai/plan` preview → edit one task (change time → locked) → batch confirm → `GET /tasks/today` and `GET /calendar/day` both show identical times/dates/fixed flags → dispose engine, new session ("restart") → same reads identical → idempotent re-confirm creates nothing.
- **E2E-B Replan:** seed realistic day (locked dentist, 3 flexible with one deadline) → complete one → start another → urgent add via `/ai/replan` → apply → assert: completed unchanged (row compare), in-progress unchanged, dentist unchanged, deadline respected, no overlaps, no duplicates, conservation, DB rows == `persisted_tasks` in the apply response == `/calendar/day` and `/today`; second apply with same `plan_id` no-op; stale (`expected_updated_at`) → 409.
- **E2E-C Isolation:** user A plans/replans → user B (`/tasks`, `/today`, `/calendar/day`, `/ai/replan`, `/apply-replan` with A's ids) sees nothing and mutates nothing → A re-reads state identical to before.
- **E2E-D Time/tz edges:** `now` = 23:40 local and 00:10 local, user in `Asia/Kolkata` and `America/Los_Angeles` (DST change date), target date = tomorrow.

Milestone gates: M0 harness + failing tests (red) → M1 tz + UTC type + PATCH nulls → M2 migration + `time_locked` + planner → M3 build/confirm path → M4 replan/apply → M5 Today/Calendar render → M6 Flutter changes (`dart analyze` clean) → M7 UI hardening (Phase 6) → M8 e2e + `/code-review`. `pytest -q` is run at the end of every milestone and results reported verbatim.

---

## 13. Manual Flutter verification checklist (needed because `flutter` is blocked here)

Pre-req: run `flutter pub get`, then `flutter test` (record pass/fail counts and send me failures verbatim); run the backend against a **copy** of the dev DB.

**Setup:** device/emulator timezone = your real zone; log in as user A; note `sqlite3 flowstate.db "select title,scheduled_start,time_locked,planned_date,status from tasks where user_id='<A>'"` as the DB probe.

**A. Build My Day**
1. Brain dump: "dentist at 6pm tomorrow, finish report by friday, gym, email mom, call bank after lunch". Build.
2. Preview: dates show the correct day (tomorrow's items say Tomorrow); dentist shows a fixed/locked marker; others show suggested.
3. Edit a flexible task's time → it becomes locked; edit only its date → time of day kept.
4. Tap Add twice quickly → only one set of tasks. Turn airplane mode on, tap Add → inline error, preview stays, nothing added; turn on network, Retry → added once.
5. Today and Calendar show identical times; the dentist is tagged Fixed and others are not.
6. Force-close and reopen → identical. DB probe matches (`time_locked` = 1 only for dentist/edited-time task).
6b. (D6) Brain dump "call mom at 7am" when it is already past 7 AM → the item is flagged inline with the "has already passed. Choose a new time." message, the time picker opens, Confirm is disabled for that item until a future time is chosen or the time is cleared; nothing is added to Today/Calendar meanwhile.
7. Verify `/ai/plan` response contains `timezone_used` = your IANA zone (dev log or proxy).

**B. Replan**
1. With a realistic today: complete task 1; start task 2 (leave running); add via Replan "urgent X needs 1 hour at 6" (collides with a fixed item).
2. Diff view: completed and in-progress listed as unchanged/immutable; fixed item unchanged with conflict message; displaced flexible tasks listed as moved; any non-fit task listed under Unscheduled with a roll-over proposal.
3. Apply → Calendar/Today update immediately; reopen app → unchanged; DB probe rows equal what the diff said; double-tap Apply → one application.
4. "move gym to tomorrow" → Apply → gym shows tomorrow with a time; DB has tomorrow's `scheduled_start`.
5. "I'm running 30 minutes late" → in-progress and fixed items do not move; later flexible tasks shift without overlapping.
6. Late evening (set device time ≥ 22:30) Replan → nothing placed in the past or after bedtime; roll-over proposals shown.
7. Reschedule a task via the sheet date-only → no deadline appears on it; it shows under the date as unscheduled/needs time.

**C. Isolation**
1. User A plans; log out; log in as B → Today/Calendar empty of A's tasks; run Replan as B → no A tasks; log out; A logs in → identical to before.

**D. Timezone:** change device zone to another region, reopen → preference updates; Build My Day slots fall within wake/bed hours **local**.

**E. Visual (Phase 6):** check loading, error, empty and success states on brain dump, preview, replan diff, Today, Calendar in light and dark mode.

---

## 14. Risks and mitigations
| Risk | Mitigation |
|------|-----------|
| Behaviour change: Today/Calendar stop recomputing flexible task times | Decision D5; flagged in UI as "suggested" only for unslotted tasks; fixtures prove stability |
| Backfill misclassifies | Conservative rule, report script, user review of titles, recoverable via edit |
| Planner regression vs. scoring quality | `evaluate_best_slot_for_task` scoring untouched; existing 244 tests kept green; golden/invariant fixtures |
| Dart changes unverifiable here | `dart analyze` clean; Dart tests written; manual checklist; you run `flutter test` |
| Production schema unknown (#13) | Two-track delivery (§11.1): dev/test proceeds; production migration blocked until items 1–5 are answered; 006 fails loudly instead of skipping |
| Scope creep | Non-goals list; Flutter scheduler retained; no UI redesign beyond flows listed |

---

## 15. Decisions

### 15.1 Resolved (your replies)
| ID | Outcome | Where applied |
|----|---------|---------------|
| D1 | **Approved** — `time_locked`, `planned_date`, `plan_applications` | §3, §10, §11.2 |
| D2 | **Approved, strict** — default unlocked; single high-confidence predicate (`source IN ('calendar','imported')` + open + has start); inspectable read-only report; predicate documented and tested | §3, §11.3–11.4, §12 |
| D3 | **Approved** — `flutter_timezone` | §5, §10.2 |
| D4 | **Investigated; NOT resolvable from the repo** — production bootstrap is unknown. Two-track delivery; production migration blocked on five facts | §11.1 |
| D5 | **Approved** — Today/Calendar render persisted state; Flutter scheduler retained; no removal until equivalence is demonstrated | §2 C13, §4, §9 |
| D6 | **Approved** — past explicit time rejected with a structured, user-facing 422 | §2 C5, §4, §7.1 |
| D7 | **Approved** — in-progress busy until `max(planned end, now)`; explicit tests T-C2-a…h | §2 C2, §12 |
| D8 | **Approved with condition** — only user-explicit / existing-product-semantics fixed times lock; scheduler output never locks | §3 (L1–L5), §12 |
| D9 | **Approved** — un-complete sync out of scope | §1 |
| D10 | **Honoured** — nothing committed; the working tree is untouched apart from this spec file | — |

### 15.2 Still open (blocking only where stated)
| ID | Question | Blocks |
|----|----------|--------|
| Q1 | The five production facts in §11.1 (does a prod DB exist; how base tables were created; `alembic_version`; live `tasks` columns + enum labels; `(source,status)` counts) | **Production migration only.** Dev/test implementation is not blocked. |
| Q2 | Approval of this final Rev 2 of the spec | All implementation |

### 15.3 Known dependencies discovered during implementation (not decisions)
- M0 will read `_map_gemini_planning_context` and the Flutter handling of `planning_context.fixed_events` to establish L2 provenance; if provenance cannot be established the event is persisted **unlocked** (no auto-lock).
- `flutter_timezone`: exact version/API taken from current docs at M6; you run `flutter pub get`.

---

## 16. Traceability matrix — every finding → root cause → fix → migration → tests

Legend: **R** = reproduced by a failing probe before the fix; **C** = code-reading finding, a failing test is written *first* in M0 (red) and must be seen failing before the fix. "Test ids" are the names in §12; a finding is not "done" until each listed test exists, failed before the fix (for R/C) and passes after. Flutter tests are written here but **run by you**.

| # | Finding (short) | State | Root cause (first broken layer) | Fix (file → function) | Migration | Backend tests | Flutter tests / manual |
|---|---|---|---|---|---|---|---|
| 1 | Timezone ignored/mis-sent; UTC fallback | R | Contract mismatch Flutter→API (`user_timezone` vs `timezone`; abbreviation `timeZoneName`) + default `"UTC"` overriding preference | `core/timezone.py::resolve_timezone`; `schemas/ai.py` alias + `timezone_used`; `ai.py`, `calendar.py` routes use helper; Flutter `timezone_service.dart`, `ai_plan_service.dart`, `app_state_provider.replanDay`, onboarding | none | `test_timezone_contract.py::{test_plan_uses_request_iana_tz, test_plan_user_timezone_alias, test_plan_invalid_abbrev_falls_back_to_preference_not_utc, test_plan_response_reports_timezone_used, test_slot_hours_are_in_user_wake_bedtime_window_in_local_time, test_replan_and_day_use_same_tz, test_replan_ist_abbrev_does_not_fall_back_to_utc}` | `timezone_payload_test.dart`; manual §13-D |
| 2 | Every persisted start is an immutable "FIXED" anchor | R | Data model has no lock concept; recommended slot persisted as `scheduledStart` | `models/task.py` `time_locked`; `planner.partition`; `calendar_service` `is_fixed = time_locked`; Flutter `timeLocked` in `ai_plan_models`/`task_item` | 006: `time_locked` default FALSE; strict backfill §11.3 | `test_time_locked.py::{test_recommended_slot_not_locked, test_explicit_time_locked, test_calendar_tags_fixed_only_when_locked, test_replan_moves_unlocked_persisted_task, test_L1…test_preferred_start_window_relative_never_lock}`; `test_migration_time_locked.py` (row matrix) | `to_apply_request_test.dart`; manual §13-A5/B |
| 3 | Anchors never checked for overlap/past/deadline | R | `generate_schedule` appends anchors unvalidated | `planner.validate_final`, locked-vs-locked → `conflicts` | none | `test_planner_contract.py::{test_locked_overlap_reported_not_moved, test_no_placement_overlaps_any_busy}`; `::test_nothing_placed_before_now`; `::test_deadline_never_exceeded` | fixtures `scheduling_contract_fixtures_test.dart` |
| 4 | `latest_end` overwritten by loop variable | R | Variable shadowing in `evaluate_best_slot_for_task` (`:477` vs `:593/598`) | rename user bound vs `day_limit` | none | `test_temporal_constraints.py::{test_latest_end_is_hard_bound, test_latest_end_with_multi_day_candidates, test_availability_window_bounds_all_candidates}` | fixtures test |
| 5 | Apply fails 422 for new tasks (`quick_add`); urgent priority dropped | R (422) / C (priority) | Flutter `NewTaskCreateModel` hard-codes invalid `source`/`priority` | `calendar_models.dart::toApplyRequest` (valid source, preserve priority/type); server returns `persisted_tasks` | none | `test_apply_replan_semantics.py::{test_new_task_valid_source_creates, test_urgent_priority_preserved}` | `to_apply_request_test.dart` |
| 6 | "Move to tomorrow" diff has no new time → no-op counted as updated | C | Backend diff lacks after-slot for date moves; Dart `toApplyRequest` matches by title with `orElse` guess | server resolves dates, planner places on target date, diff carries `new_start/new_end`; apply counts only real writes; remove guess logic | none (`planned_date` used when no slot) | `test_apply_replan_semantics.py::{test_move_to_tomorrow_diff_has_new_start, test_apply_move_to_tomorrow_persists_slot, test_move_to_tomorrow_infeasible_sets_planned_date}` | `to_apply_request_test.dart`; manual §13-B4 |
| 7 | Replan working set ≠ day-view set; wrong "new"; duplicates | C | Two independent queries (`calendar_service.py:86-126` vs `:464`) | `task_repository.list_open_for_day` shared by day view, Today, Replan; classification only by `is_new` | index `ix_tasks_user_scheduled_start` | `test_apply_replan_semantics.py::{test_replan_and_day_view_same_task_set, test_existing_task_never_classified_new, test_apply_never_duplicates_existing}` | manual §13-B |
| 8 | No idempotency/atomicity (apply double-submit; batch create; swallowed per-task failures) | R (backend) / C (Flutter) | No write-once key; per-task commits; optimistic local insert | `plan_applications`; `TaskService.batch_create`; `calendar_service.apply_replan`; Flutter `confirmCandidates` → batch endpoint, no phantom tasks, retry same `plan_id` | 006: `plan_applications` | `test_plan_confirm.py::{test_replay_same_plan_id_no_duplicates, test_concurrent_same_plan_id_single_create, test_batch_failure_rolls_back_all, test_idempotency_key_honored}`; `test_apply_replan_semantics.py::{test_apply_replay_idempotent, test_apply_atomic_rollback}`; `test_user_isolation.py::test_plan_applications_scoped_same_plan_id_two_users` | `confirm_candidates_batch_test.dart`; manual §13-A4 |
| 9 | PATCH cannot clear `scheduled_start` | R | `TaskRepository.update` skips `None` | explicit-null semantics via `model_fields_set` | none | `test_task_patch_nulls.py::{test_clear_scheduled_start, test_unset_field_untouched, test_null_non_nullable_rejected}` | `reschedule_payload_test.dart` |
| 10 | Reschedule sends midnight deadline; cannot clear old start | C | Misuse of `deadline_at` for "do it on day D" | `planned_date`; Flutter `rescheduleTask` sends `planned_date` + explicit nulls, never `deadline_at` | 006: `planned_date` | `test_task_patch_nulls.py::test_date_only_reschedule_sets_planned_date_not_deadline` | `reschedule_payload_test.dart`; manual §13-B7 |
| 11 | Date lost: preview rebuilds start as today + displayed time | C | `_addAndSchedule` reconstructs from display string | use full `DateTime`; server returns `recommended_slot_date`; no rebuild branch | none | `test_date_preservation.py::{test_tomorrow_slot_keeps_tomorrow_date_through_confirm_and_day_view, test_recommended_slot_date_field_matches_instant_in_tz}` | `date_preservation_test.dart`; manual §13-A2 |
| 12 | Silent failure paths (`ai.py:288`; `updateTask`; apply skips counted) | C | Broad `except`, swallowed errors, counts not derived from writes | `scheduling_error` in response; `updateTask` rethrows; apply `skipped[]` with reasons | none | `test_plan_endpoint.py::{test_scheduler_exception_reported_not_swallowed, test_apply_skips_listed_not_counted}` | `confirm_candidates_batch_test.dart` (failure surfaced) |
| 13 | Alembic cannot create `tasks`; prod bootstrap unknown | R (evidence in §11.1) | Migration chain presupposes an undocumented base schema | 006 is ALTER-only and **fails loudly**; two-track delivery; **production track blocked on Q1** | 006 | `test_migration_time_locked.py::test_006_fails_loudly_without_tasks_table` and the full backfill matrix | — (production verification pending Q1) |
| 14 | SQLite drops tz; two readers disagree on naive datetimes | R | Storage layer returns naive values | `db/types.py::UTCDateTime` on `Task` datetime columns | none (type only) | `test_utc_datetime_type.py::{test_aware_ist_roundtrips_to_same_instant, test_naive_treated_as_utc, test_between_day_bounds_after_roundtrip}` | — |
| 15 | Day/Today re-run scheduler on every read → drift | C | Read path computes placement | render persisted slots; unslotted → `is_suggested` | none | `test_day_render.py::test_persisted_slots_rendered_as_stored_regardless_of_now` | manual §13-A5 |
| 16 | Flexible candidate can steal an explicit-time candidate's slot | C | `/ai/plan` loop processes in AI order | planner places locked/explicit first | none | `test_planner_contract.py::test_explicit_time_candidate_not_displaced_by_earlier_flexible_candidate` | fixtures test |
| 17 | Slot start keeps seconds/microseconds | C | Rounding only when `minute % 15 != 0` | zero seconds/microseconds in cursor | none | `test_planner_contract.py::test_slots_have_zero_seconds` | — |
| 18 | Fallback slot can exceed bedtime/deadline | C | Unbounded `max_busy_end + 10 min` fallback | bounded fallback; infeasible → `unscheduled` with reason | none | `test_planner_contract.py::test_fallback_never_past_bedtime_or_deadline` | fixtures test |
| 19 | Tests write to dev DB | R (1,611 rows in `flowstate.db`) | No isolated test DB | `tests/conftest.py` sets a temp-file `DATABASE_URL` before app import | none | `test_isolated_db.py::test_tests_use_temp_database_not_dev_db` | — |

### 16.1 Contract → test cross-reference
| Contract | Primary tests (§12) |
|---|---|
| C1 completed immutable | `test_completed_never_moved_or_selected_by_ops`, `test_apply_skips_completed` |
| C2 in-progress | T-C2-a…h |
| C3 only locked immovable | `test_time_locked.py` set; `test_replan_moves_unlocked_persisted_task` |
| C4 no overlaps | `test_no_placement_overlaps_any_busy`, `test_locked_overlap_reported_not_moved` |
| C5 no past / D6 | `test_nothing_placed_before_now`, `test_missed_flexible_replaced`, `test_past_explicit_time.py` set |
| C6 deadlines | `test_deadline_never_exceeded`, `test_deadline_infeasible_unscheduled_with_reason`, `test_apply_rejects_deadline_violation` |
| C7 bounds | `test_latest_end_is_hard_bound` set |
| C8 explicit > inferred | `test_L1_inferred_gemini_time_does_not_lock`, `test_explicit_time_candidate_not_displaced_by_earlier_flexible_candidate` |
| C9 no silent loss | `test_conservation_property` |
| C10 no duplication | `test_apply_never_duplicates_existing`, `test_replay_same_plan_id_no_duplicates` |
| C11 replan scope/stability | `test_unchanged_tasks_not_moved`, `test_other_dates_untouched`, `test_urgent_displaces_lowest_priority_first`, `test_replan_past_date_empty_diff` |
| C12 user scoping | `test_user_isolation.py` additions, E2E-C |
| C13 deterministic render | `test_persisted_slots_rendered_as_stored_regardless_of_now` |
| C14 timezone | `test_timezone_contract.py` set, E2E-D |


---

## 17. Implementation notes — as built (appended after implementation)

Deviations and additions relative to Rev 2 above. Nothing here relaxes a contract invariant.

| Topic | As built |
|---|---|
| Planner API | `engines/planner.py::plan()` plus `check_invariants()`, `validate_placements()`, `busy_interval()`. Extra `PlanItem` fields beyond the spec: `pinned` (existing item the plan must not move, any mode), `origin_start` (persisted slot to report as "previous" when `start` is a proposal, used by "running late"), `yield_to_fixed` (a new explicit time that collides with an existing fixed item is re-placed near its time and reported, instead of overlapping it — preserves the documented Replan behaviour "the Dentist stays, the urgent task moves"). |
| Purity enforcement | `tests/test_planner_purity.py` (AST import allow-list, no clock/random/IO tokens, frozen inputs, determinism, naive datetimes rejected). |
| Adapters | `services/planning_service.py` (Build My Day, rows/candidates -> `PlanItem`, `PlanResult` -> response), `services/plan_confirm_service.py` (confirm), `services/calendar_service.py` (day render, Replan, apply). Placement logic exists only in the planner. |
| Replan apply payload | Server-authored `plan_diff.apply_request` (per-task `expected_updated_at` token, explicit nulls to clear a slot, `user_override` only for a task the user named). Flutter posts it verbatim plus its clock/zone; the old client-side rebuilding remains only as an offline fallback and now sends a valid `source` and preserves priority/type. |
| "Move X to a day" for a **locked** task | Keeps its time of day on the new date and stays locked (`user_override=true` on that update). |
| Replan op wording | "at 6" = fixed (L4), "around 6" = preferred start, "before/by 6" = hard `latest_end`. |
| D8 / L2 (fixed events) | **Superseded 2026-10-04:** a stated fixed event (start+end, start time present in the user's text, not already a task at that time) IS persisted as a locked `is_commitment` task (migration 011, `planning_service.commitments_from_context`), so Replan/Today/Calendar see it. Others stay transient busy time. (Original decision: **Not persisted separately.** The Gemini prompt already instructs the model to also emit each fixed event as a `meeting` task with `fixed_start`; those candidates lock through L1. `planning_context.fixed_events` remains busy time only (as before). No auto-lock without explicit-time provenance. |
| Flutter scheduler | Unchanged and retained. It already preserves a backend slot (`enrichTasksWithOptimalSlots`); the preview no longer labels a recommendation "Fixed" (`timeLocked` drives it). |
| Test files | The `latest_end` regressions are in new `tests/test_latest_end_bound.py` (not appended to the existing `test_temporal_constraints.py`). Existing `test_calendar_replan.py` was made deterministic (explicit client clock) and its Dentist seed is `time_locked=True`, because a bare `scheduled_start` no longer means "fixed" (finding 2). Existing Flutter `p1_acceptance_test.dart` mock gained the batch-confirm endpoint. |
| Legacy `SchedulingEngine.generate_schedule` | Retained untouched for compatibility (still anchors every `scheduled_start`); no product path calls it any more. |
| Not done | Production migration readiness (blocked on D4 facts, §11.1). Flutter tests were written but could not be executed in this environment. |


---

## 18. Release gates (PostgreSQL) — NOT yet verified

All automated tests so far ran on **SQLite only**. The production target is PostgreSQL, so the following are **release gates**: none of them may be considered done until they have been executed against a disposable PostgreSQL database and the results reviewed. Nothing below has been run in this environment.

| Gate | What must be verified on PostgreSQL | How |
|---|---|---|
| G1 full suite | the whole backend suite passes | `FLOWSTATE_TEST_DATABASE_URL=postgresql://…/flowstate_test pytest -q` (the database name must contain `test`; its tables are dropped and recreated; `tests/conftest.py` refuses anything else) |
| G2 instants | `UTCDateTime` round-trips aware values and the day-bound `BETWEEN` queries return the same rows as SQLite (`test_utc_datetime_type.py`) | part of G1 |
| G3 enums | `Task.status/source/task_type/priority` native enum labels match the strings used in the backfill predicate (`status IN ('todo','postponed','in_progress')`, `source IN ('calendar','imported')`) — query `pg_enum` first | spec section 11.1 query 4 |
| G4 ordering | `ORDER BY tasks.priority DESC` sorts by enum **declaration order** on PostgreSQL but by label text on SQLite (`TaskRepository.list_open_for_day`); confirm Today/Calendar ordering is acceptable or sort explicitly | manual check of `GET /today` and `/calendar/day` on a seeded PG database |
| G5 migration | `alembic upgrade head` from the real production Alembic state (spec section 11.1 facts 1–5), the backfill report reviewed first, then `downgrade 005_privacy_grievances` rehearsed on a copy | blocked on D4 |
| G6 idempotency | concurrent identical `plan_id` requests from separate worker processes create exactly one result (the primary key, not the in-process lock, must carry this) | run two workers against PG and replay `test_plan_confirm.py::test_concurrent_same_plan_id_single_create` across processes |
| G7 timezone data | the PG server and the app both resolve `Asia/Kolkata` / `America/Los_Angeles` (tzdata installed) | `SELECT now() AT TIME ZONE 'America/Los_Angeles'` and the app's `ZoneInfo` |

Until G1–G7 are signed off, the migration must not be applied to any shared or production database.

## 19. Integrity-review fixes (as built)

| Review finding | Resolution | Regression tests |
|---|---|---|
| Replan 500s on out-of-range durations / long titles / hour > 23 | Deterministic `422 {"detail": {"code": "invalid_replan_request", "errors": [{field, code, message}]}}`. Limits: 5–480 min, title ≤ 255, message 1–500 chars, hour 0–23 (1–12 with am/pm), minute 0–59, delay 1–720 min. Requests are **refused, never clamped** into a different task. | `tests/test_replan_robustness.py` |
| Timezone divergence | One rule (docstring of `core/timezone.py`): valid IANA request value, else stored preference, else UTC. Applied to Today, Calendar, Replan, Build My Day, `/tasks/today`, `/tasks/parse`, "Later", the AI extractors and Flow. Today, `/tasks/today` and `/today/override` accept `timezone` and Flutter sends it. A guard test forbids `ZoneInfo(...)` outside `core/timezone.py`. | `tests/test_timezone_unification.py` |
| "Later" / "Do this now" bypassed the planner | `/today/override` asks the shared planner (`planning_service.place_single_task`): never in the past, never overlapping another task, never after the deadline; if no valid slot exists the task is **left unchanged** and the response says so. A plain `earliest_start` is now an absolute instant (it used to be re-anchored per day, which let "Later" land earlier than chosen). | `tests/test_override_planner.py`, `test_planner_contract.py::test_earliest_start_is_an_absolute_instant…` |
| Dev database migrated silently | `ensure_planning_columns` runs before anything else at dev startup and refuses (touching nothing) unless `FLOWSTATE_DEV_AUTO_MIGRATE=1`; the message points to the report script and `alembic upgrade head`. | `tests/test_dev_db_gate.py` |
| Property-test gaps | Seeded property tests now cover temporal bounds, `planned_date`, dependencies (incl. cycles), `yield_to_fixed`, pinned items, extra busy time, ranks and replan scope; a guard test fails if the generator stops producing any dimension; a scratch mutation check confirmed six deliberate planner bugs are all caught. | `tests/test_planner_property_extended.py` |
| Hygiene | Unused imports/dead locals removed, small duplicated helpers consolidated (`planning_service.clock_label/enum_value`, `plan_applications` idempotency store, `PAST_TOLERANCE`), `task_repository.py` formatting fixed, new Dart files formatted. | static checks in the final report |
