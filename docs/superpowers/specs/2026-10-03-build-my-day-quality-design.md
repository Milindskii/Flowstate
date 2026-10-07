# Build My Day — Quality Pass (Design)

Date: 2026-10-03 · Status: approved (rev 2: persist sources + explicit preferred windows)
Scope: Build My Day only (brain dump → Gemini → schedule → confirm → Supabase → Flutter Plan Result).
Out of scope: Replan, Insights, Auth, Calendar UI, any visual redesign.
Builds on: `build-my-day-replan.md` (planner, `planned_date` ownership, M3/M4 fixes).

## 1. Root causes (verified by code reading)

| # | Root cause | Location |
|---|---|---|
| R1 | Silent local fallback on Gemini error / empty result / quota exhausted / privacy declined; local parser lacks priority → "Priority not specified" | `lib/screens/brain_dump_sheet.dart:192-270` |
| R2 | Flutter re-schedules backend-scheduled AI plans with its own `SchedulingEngine`, so preview can diverge from backend | `brain_dump_sheet.dart` (`enrichTasksWithOptimalSlots` after `generatePlan`) |
| R3 | Prompt mandates `priority=null` when unstated → UI renders absence instead of a reasoned value | `ai_service.py` prompt (~l.209), `ai_plan_preview_sheet.dart:363`, `brain_dump_sheet.dart:1094` |
| R4 | "before Tuesday" → Tue 23:59 instead of end of Monday | prompt + `_parse_single_clause` deadline block (~l.940-990) |
| R5 | No focus field anywhere in the task model | `schemas/task.py`, `models/task.py` |
| R6 | Sequential relations ("after that", "then") not extracted per task; confirm rebuilds `PlanItem` without `depends_on` / preferred windows | prompt, `plan_confirm_service.py:119` |

## 2. Candidate contract

Every candidate carries these fields end-to-end:

| Field | Values | Notes |
|---|---|---|
| `candidate_id` | stable string, server-assigned (`c_<12 hex>`) | identity for dependencies and confirm |
| `title`, `task_type` | existing | |
| `planned_date` | date, always set | source of truth for ownership |
| `scheduled_start/end` | aware datetime or null | null ⇒ `unscheduled_reason` set |
| `unscheduled_reason` | `no_capacity` \| `deadline_infeasible` \| `bound_infeasible` \| `explicit_time_in_past` \| `dependency_unschedulable` | never a placeholder slot |
| `time_locked` + `fixed_start` | explicit fixed time | |
| `preferred_start` / `preferred_window_start/end` | preferred time, never locks | |
| `estimated_minutes` + `duration_source` | `explicit` \| `inferred` | explicit is never overwritten |
| `priority` + `priority_source` | low/medium/high/urgent + `explicit` \| `inferred` | never null, never "unspecified" |
| `focus_level` + `focus_source` | low/medium/high + `explicit` \| `inferred` | |
| `deadline_at` + `deadline_kind` | aware datetime + `hard` \| `soft` | |
| `depends_on` | list of `candidate_id` | validated (§4) |

## 3. Extraction (Gemini prompt + mapper, `ai_service.py`)

- Gemini returns per task: `ref` ("t1", "t2", …), `depends_on: [ref]`, `focus_level`, `focus_source`, `deadline_kind`.
- "after that" / "then" / "once X is done" → `depends_on` the previous/named task. "after class/dinner" stays a relative anchor (not a task dependency) unless "class" is itself a candidate.
- Do not merge unrelated activities; do not invent tasks (existing rules retained).
- Priority: explicit kept with `priority_source=explicit`. Otherwise inferred (hard deadline today/tomorrow → high; "optional"/"if time" → low; else medium) with `priority_source=inferred`. The mapper applies the same inference if Gemini still returns null.
- Duration: explicit kept with `duration_source=explicit`; mapper only fills a missing value (type-based default) and marks `inferred`.
- Focus: "deep focus"/"no distractions"/"need to concentrate" → high, explicit. Otherwise inferred from `task_type` (deep_work/study → high, admin/physical → low, else medium).
- Dates: all relative dates resolved against the client clock (`current_local_time`) in the user's timezone.
- **"before <weekday>"** → `deadline_at = <weekday> 00:00 local` (done by end of the previous day), `deadline_kind=hard`. "by <weekday>" / "due <weekday>" → `<weekday> 23:59`. "before HH:MM" unchanged. The deterministic parser applies the same rule.

## 4. Dependency validation (mapper)

1. Mapper assigns `candidate_id` to every task and translates Gemini `ref`s to `candidate_id`s.
2. Unknown reference → dropped, `validation_issues += {code: "unknown_dependency"}`.
3. Self-reference → dropped.
4. Cycle (DFS) → every edge in the cycle dropped, `validation_issues += {code: "dependency_cycle"}` on each member.
5. Planner: a successor is placed only after its predecessor ends; if the predecessor is unscheduled, the successor gets `unscheduled_reason=dependency_unschedulable`.

## 5. Deadline semantics

- **hard**: the planner never places any part of the task ending after `deadline_at`. If it cannot fit → `unscheduled_reason=deadline_infeasible`. Explicit "before/by/due/deadline/must" → hard.
- **soft**: preferred target ("ideally by", "try to finish by", "sometime before … if possible"). Planner first tries to place it before `deadline_at`; only if no such slot exists does it place it after, setting `scheduling_reasons.soft_deadline_exceeded=true` and an explanation. Confirm validation (`deadline_before_end`) applies to hard deadlines only.

## 6. Scheduling

- `planning_service` maps `depends_on`, `focus_level`, `deadline_kind` into `PlanItem`. `focus_level=high` uses the existing peak-hour preference (same as deep_work today); low focus prefers off-peak.
- `plan_confirm_service` rebuilds `PlanItem` with `depends_on` (translated to new task ids), preferred windows, `deadline_kind`, `focus_level`.
- No placeholder schedules: unplaced tasks are returned with `unscheduled_reason` and remain unscheduled in the preview.

## 7. Gemini reliability, idempotency, diagnostics

**"Charging" means Flowstate's internal AI usage/credit accounting** (free uses + Flow Shields in `ai_usage_records`), not the external Gemini provider's billing.

- **Planning request ID**: Flutter generates one stable `idempotency_key` per brain dump submission; "Retry with AI" reuses it.
- **Attempt ID**: every real Gemini call gets a distinct `attempt_id` (uuid). New table `ai_planning_attempts(attempt_id PK, request_id, user_id, status, failure_code, failure_reason, latency_ms, created_at)`.
- **Single charge**: credit is charged and the request row is marked `completed` only on the first attempt where Gemini succeeded **and** ≥1 task was scheduled. Subsequent calls with a completed request ID return the cached response with no charge and no new Gemini call.
- **Failure codes**: `gemini_error`, `malformed` (unparseable after one repair attempt), `empty`, `scheduling_failed`, `quota_exhausted`, `privacy_declined`. Server-side codes are recorded by the route. `privacy_declined` (client-only) and client-detected network failures are recorded via `POST /ai/planning-attempts` (small diagnostic endpoint, no charge, no Gemini call). Error responses carry `{failure_code, message}`.
- No silent backend fallback: when the route is called, it never substitutes the local parser for Gemini.

## 8. Flutter

- AI plans: preview renders backend slots as-is; client `SchedulingEngine` is not run on AI results (still used for the basic planner).
- Priority label: explicit → "High priority"; inferred → "Suggested: High". "Priority not specified" removed from `ai_plan_preview_sheet.dart` and `brain_dump_sheet.dart`.
- Focus shown as a small "High focus" chip when `focus_level=high`.
- **AI failure state** (input requires AI and any failure code occurs): the raw dump stays in the editor; message "AI planning failed: <reason>"; buttons **Retry with AI** (same request ID) and **Use basic planner**. A basic plan is labeled "Basic plan (not AI)", never labeled AI, and never calls the charging endpoint.
- `ExtractedTaskItem` gains `candidateId`, `prioritySource`, `focusLevel`, `focusSource`, `deadlineKind`, `durationSource`, `dependsOn`; batch confirm sends them.

## 9. Persistence

Migration `009_build_my_day_quality`:
- `tasks.focus_level`, `tasks.deadline_kind`, `tasks.priority_source`, `tasks.duration_source`, `tasks.focus_source` (varchar, nullable), `tasks.depends_on` (JSON list of task ids, nullable).
- `tasks.preferred_start`, `tasks.preferred_window_start`, `tasks.preferred_window_end` (timestamptz, nullable) — written **only** when the user explicitly stated a preferred time/window (provenance `explicit`); never invented, never filled from defaults or inference.
- New table `ai_planning_attempts` (§7), RLS enabled (consistent with 007).

Confirm saves `planned_date`, slot, `estimated_minutes`, `priority`, `focus_level`, `deadline_at`, `deadline_kind`, `depends_on`, `time_locked`, the three `*_source` fields, and explicitly stated preferred windows. Verification: confirm on Supabase → restart backend → `GET` tasks → field-by-field diff.

## 10. Contract coverage matrix

✓ = field must survive the hop; a test asserts it. "consumed" = used to compute the slot, not stored.

| Field | Gemini JSON | Mapper → Candidate | Scheduler (`PlanItem`) | API response | Flutter model | Confirm payload | Confirm `PlanItem` | DB (`tasks`) | Reload API → Flutter |
|---|---|---|---|---|---|---|---|---|---|
| candidate_id | `ref` | ✓ | ✓ (id) | ✓ | ✓ | ✓ | ✓ | → task id | task id |
| planned_date | target_date | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| scheduled_start/end | — | — | ✓ output | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| unscheduled_reason | — | — | ✓ output | ✓ | ✓ | — | — | — | — |
| fixed_start / time_locked | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| preferred window (explicit only) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| estimated_minutes | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| duration_source | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| priority | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| priority_source | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| focus_level | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| focus_source | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| deadline_at | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| deadline_kind | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| depends_on | ✓ (refs) | ✓ (ids) | ✓ | ✓ | ✓ | ✓ | ✓ (task ids) | ✓ | ✓ |

`*_source` fields persist so user-stated vs inferred values stay distinguishable for learning/debugging. If the user edits a field in the preview before confirming, its source becomes `explicit`.

## 11. Tests (targeted only; no full-suite loops)

Backend `tests/test_build_my_day_quality.py` (Gemini stubbed with fixture JSON, `current_local_time` pinned):
messy multi-task dump · explicit time · explicit duration · explicit priority (+ inferred labelled) · explicit focus · hard deadline · soft deadline exceeded only when necessary · "before Tuesday" · timezone/local time · "after that" dependency + unknown ref + cycle · unschedulable task reason · Gemini failure / malformed → failure code recorded, not charged · scheduling failure → not charged · retry: distinct attempt IDs, single charge · contract matrix round-trip (plan → confirm → DB → GET).

Flutter `test/build_my_day_quality_test.dart`: priority labels · focus chip · failure state shows both buttons and keeps dump · basic plan labelled and does not call charging endpoint · AI plan not re-scheduled client-side · confirm payload carries new fields.

Live: one real Gemini + Supabase run with a messy dump → confirm → restart backend → reload → diff.

## 12. Constraints

No commits (per user rule). Never weaken existing tests. No "fixed" claims without test or live evidence.
