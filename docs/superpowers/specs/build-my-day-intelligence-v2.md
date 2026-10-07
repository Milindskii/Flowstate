# Build My Day + Replan — Production Intelligence Architecture (v2 specification)

Status: **DRAFT FOR REVIEW — specification only. No product code was changed to produce it.**
Date: 2026-10-02
Baseline: the repository as it stands after the planner hardening (`docs/superpowers/specs/build-my-day-replan.md`, §17–§19).

### How to read this document

Every statement about the repository carries one of four tags:

| Tag | Meaning |
|---|---|
| **[VERIFIED]** | Read in the code or reproduced by running the code in this session. A `file:line` or a measurement is given. |
| **[PROPOSED]** | A design decision this specification recommends. Not yet built. |
| **[MISSING]** | Looked for in the repository and not found. |
| **[UNCERTAIN]** | Cannot be established from the repository (production data, live LLM behaviour, user behaviour). Each has a way to resolve it in §27 Phase 0. |

Major recommendations are written as numbered **cards** (R1–R18) with the same eight fields: CURRENT STATE · EVIDENCE · PROBLEM · PROPOSED BEHAVIOR · WHY · AFFECTED COMPONENTS · ACCEPTANCE CRITERIA · RISK.

What was *measured* in this session (reproducible with the scripts described in §19): deterministic-stage latency, the current deterministic parser's output on the medium acceptance test, and how Replan parses natural messages. What was **not** measured: live LLM latency/quality (no network calls were made from the audit; a live-key harness is a Phase 0 deliverable), production database behaviour, real user behaviour.

---

## 1. Executive summary

**Verdict.** The *scheduling infrastructure* (shared pure planner, hard-constraint validation, atomic/idempotent persistence, timezone rule, Replan safety, property tests) is sound and must not be rewritten. Build My Day feels poor for reasons that live **upstream and downstream of the planner**:

| Layer | Weakness | Severity |
|---|---|---|
| **Extraction fallback** | The deterministic parser fragments and fabricates: the spec's 954-character medium test becomes **25 task cards** from ~8 intentions (e.g. `"Which may take about ."` 120 min, `"Gym."` 45 min, `"Prioritize assignment"`); a dump without punctuation collapses **six tasks into one**. [VERIFIED, §4.1] | **Critical** |
| **Extraction schema (AI path)** | The Gemini task schema has no field for minimum duration, optionality ("can be skipped"), energy condition ("when I'm mentally fresh"), context/notes, location, preparation time, or **source evidence**; `description` is always `null`. Nothing makes the model's output *traceable* to the user's words. [VERIFIED `ai_service.py:93-115`] | **Critical** |
| **Post-AI re-splitting** | After the AI has chosen task boundaries, `validate_and_segment_candidates` can re-split them with regex heuristics (`act_words`, title > 85 chars, ≥ 2 sentence terminators). [VERIFIED `ai_service.py:360-420`] | High |
| **Intent preservation** | No guarantee and no trace: fixed events, travel, protected periods and availability are consumed as *busy time* and then discarded; there is no record of what happened to each part of the dump. [VERIFIED `planning_service.py:context_busy_intervals`] | **Critical** (golden rule) |
| **Replan understanding** | Replan is a regex grammar that returns after the first match. Natural statements become **invented tasks**: "Class got cancelled" and "I finished the assignment early" each create a *new task* with the sentence as its title. [VERIFIED, §4.5] | **Critical** (violates "never invent a new task") |
| **Profile integration** | Questionnaire fields are stored, but most never reach scoring: `preferred_session_minutes`, `energy_predictability`, `confidence_level`, `avg_duration_ratio`, `tired_behavior` have **zero** uses in the slot-scoring code. Learned signals are only loaded by `/ai/plan`, not by Replan, "Later", or confirm. [VERIFIED §4.3] | High |
| **Behaviour data quality** | Flutter hard-codes `perceivedFocusScore: 5` / `'Energized'` on every completion and defaults missing scores to `3`, so the learning inputs contain fabricated values. [VERIFIED `app_state_provider.dart:682-683,712`, `task_service.dart:133-135`] | High |
| **Latency/timeouts** | Flutter aborts a plan request at **12 s**; the backend may try up to 3 models × 12 s (plus a repair call) and still charge the user. Flutter silently falls back to local parsing on any error. The instruction prompt alone is **12,024 characters (~3 k tokens)** per call. [VERIFIED §4.6] | High |
| **Input limit** | `raw_text` is capped at **1,500 characters** on both endpoints; the UI shows no counter; oversize requests are indistinguishable from "AI unavailable" on the client. [VERIFIED §4.7] | High |
| **Planner (scheduling)** | Correct and fast (6 ms / 8 tasks, 41 ms / 60 tasks). Missing *capabilities* (tiers, optionality, minimum duration, travel/prep blocks, soft-preference weights), not correctness. | Medium — **extend, do not replace** |

**Strategy.** Fix the layer that is actually broken, in this order: (1) *extraction + preservation*, (2) *normalization into a richer entity/constraint model*, (3) *profile integration* (wire what already exists), (4) *clean behaviour observations*, (5) *personalized scoring and explanations*, (6) *Replan intent understanding*, (7) *latency*, then verification gates. The existing planner stays authoritative for every hard rule; the LLM never decides correctness.

**Three product rules that drive the design**

1. **Never lose user intent.** Every actionable part of a dump ends as *planned*, *explicitly unscheduled with a reason*, *merged into another entity*, or *an unresolved question for the user*. A deterministic coverage check enforces this independently of model quality (R2).
2. **One intention = one entity.** Boundaries are decided by semantics (LLM), never by punctuation; deterministic code validates and normalizes but does not re-split (R1).
3. **The fallback is conservative.** When AI is unavailable, preserve meaning: do not split on prose, do not invent tasks, say clearly that planning is degraded, and keep the raw text for a retry (R7).

---

## 2. Current implementation audit

### 2.1 Inventory (what exists / works / partial / missing / slow / weak / extend / leave alone)

| Area | Exists & works | Partial | Missing | Too slow | Semantically weak | Extend | Do not touch |
|---|---|---|---|---|---|---|---|
| Shared planner (`engines/planner.py`, `scheduling_engine.py`) | pure `plan()` for build & replan; hard bounds; keep-if-valid; displacement; yield-to-fixed; suggestions; invariants; 1,160-test suite | explanations are generic per primary reason | tiers/optionality, min duration, travel/prep blocks, weighted soft prefs | no (6–41 ms) | soft weights are hard-coded constants | add typed inputs + score-contribution trace | the hard-constraint core, invariant checker, purity contract |
| Persistence / idempotency (`plan_confirm_service`, `calendar_service.apply_replan`, `plan_applications`) | atomic, per-`plan_id` idempotent, server re-validation | — | brain-dump run/entity trace | no (34 ms) | — | link tasks to source run/entity | transaction & replay logic |
| Timezone (`core/timezone.py`) | one rule, guard test | — | — | — | — | — | all of it |
| AI extraction (`ai_service.py`) | Gemini call w/ JSON mode, model fallback, repair call, provenance fields | schema lacks attributes; AI-need heuristic lives in Flutter | structured-output schema, evidence spans, coverage check, trace | serial retries; 12 k-char prompt | re-splitting after AI; prompt forbids "leave home" entities | new schema v2 alongside v1 | the auth/error classification and token logging |
| Deterministic fallback (`ai_service._split_clauses`, Flutter `task_parse_service.dart`) | exists | works only on simple inputs | conservative mode | no | **destructive** (§4.1) | replace behaviour behind a flag | — |
| Profile (`ReadinessProfile`, `PlanningProfile`) | questionnaire stored; 6 fields used in scoring | learning only in `/ai/plan` | observed-vs-reported layering, signal confidence | no | most fields unused | signal registry | questionnaire UI |
| Behaviour data (`TaskPerformance`, `ReadinessObservation`, `RecommendationOutcome`) | tables + feedback endpoint + Insights cold-start gating | planned-vs-actual start stored only if user gives feedback | append-only plan-event log; clean (non-fabricated) inputs | no | **fabricated** completion feedback in Flutter | event log + derived stats | Insights honest-cold-start behaviour |
| Replan (`calendar_service.generate_replan`) | dry-run diff, protected completed/in-progress, server-authored apply request, stale/409, validation 422 | regex grammar, one op per message | LLM delta extraction, task-id resolution, multi-op, delta sentences | no (15 ms) | invents tasks from unrecognised text | new op extractor in front of existing ops | diff/apply/validation machinery |
| AI economy (`ai_economy_service.py`) | 1 free plan, shields, Pro, 5/h, idempotency cache, charge-after-success | charged even if client gave up | — | — | AI quality is metered while the free fallback is poor | — | usage bookkeeping |
| Flutter (`brain_dump_sheet.dart`, providers) | preview, edit, confirm w/ atomic batch, error banner, diff view | two sequential usage-status calls; generic `catch (_)` | char counter, progress, degraded banner, "everything I heard" | 12 s timeout | local parser duplicates server logic | v2 preview | confirm/apply plumbing |

### 2.2 Evidence index (all [VERIFIED])

| Fact | Evidence |
|---|---|
| Extraction input cap 1,500 chars | `backend/app/schemas/ai.py:7`; `schemas/task.py:142-143` |
| Clause splitter is regex over punctuation/conjunctions/action verbs | `ai_service.py:309-357` |
| AI output re-segmented after the fact | `ai_service.py:360-420` (`validate_and_segment_candidates`) |
| Gemini model chain, 12 s per attempt, repair call | `ai_service.py:1036-1049`, `:1133` |
| Instruction prompt 12,024 chars | measured: `len(_build_initial_gemini_prompt("x", …))` |
| Gemini task schema fields (no min-duration/optionality/energy/notes/location/evidence) | `ai_service.py:93-115` |
| Planning-context kinds consumed as busy time | `planning_service.context_busy_intervals`; `energy_preference` only `morning_heavy` handled (`planning_service.schedule_candidates`) |
| Flutter plan request timeout 12 s | `lib/services/api_service.dart:123` |
| Flutter swallows every AI error into local fallback | `lib/screens/brain_dump_sheet.dart` `_buildPlan` `catch (_)` |
| Flutter calls usage status twice per plan | `brain_dump_sheet.dart:131`, `:184` |
| Replan grammar, first-match return | `calendar_service.parse_replan_instruction` |
| Fabricated feedback | `lib/providers/app_state_provider.dart:682-683,712`; `lib/services/task_service.dart:133-135` |
| Only `/ai/plan` passes performance history | `ai.py` (passes `performance_history`); `calendar_service._profile`, `plan_confirm_service`, `today.py` do not |
| Unused profile attributes | scoring-code usage count (§4.3) |
| No RLS in repo; `.env` untracked | grep; `git ls-files backend/.env` empty |
| No raw brain-dump text in log statements | grep of `logger.*(raw_text|clean_text|user_message)` |
| Deterministic stage latency | §19 measurements |
| Backend suite | 1,160 passed, 0 failed (last full run this session, SQLite) |

> The brief mentions "627 backend tests passing on the prior full run". That was an earlier checkpoint; the latest full run in this repository is **1,160 passed**. [VERIFIED]

---

## 3. Existing strengths (build on these)

1. **A pure, deterministic planner with an invariant checker** — no overlaps, nothing in the past, deadlines/`latest_end` hard, conservation (no task lost), user-fixed times immutable. [VERIFIED `planner.py`, `test_planner_*`]
2. **Typed hand-off between interpretation and scheduling** — `PlanItem` already carries `time_locked`, `deadline_at`, `temporal` (target date, earliest/latest, preferred window, meal-relative), `depends_on`, `rank`, `pinned`, `yield_to_fixed`, `origin_start`, `planned_date`. The new intelligence layer should *feed* this, not replace it. [VERIFIED]
3. **Provenance already exists** on extracted fields (`explicit` / `inferred` / `default`, with confidence) and drives the lock rule (only explicit user times lock). [VERIFIED `schemas/task.py:FieldProvenance`, `planning_service.candidate_is_explicitly_fixed`]
4. **Safe write path** — atomic, idempotent confirm/apply with server-side re-validation and optimistic-concurrency tokens. [VERIFIED]
5. **Honest cold-start behaviour in Insights** (`MIN_SESSIONS_FOR_PATTERNS`, "never fabricates metrics"). Keep this posture for every new learned feature. [VERIFIED `insights.py`]
6. **Charge-after-success** economy and structured Gemini error classes with token/latency logging (`ai_service.gemini_ok … latency_ms input_tokens output_tokens`) — the raw material for Phase 0 latency analysis. [VERIFIED `ai_service.py:1110-1116`]
7. **A test culture that catches regressions** (property tests over every planner dimension, mutation-checked; isolation tests; e2e scenarios). [VERIFIED]

---

## 4. Current failure modes (reproduced)

### 4.1 Deterministic fallback on the medium acceptance test (§26) [VERIFIED — run in this session, network disabled]

`AIService.parse_task_dump(<the 954-character test>)` → **25 candidates** in 9.9 ms:

```
 'Class' 45m start=12:40            'Leave home by 11:50 AM.' 45m
 'I should finish my machine learning assignment because I need to submi…' 45m dl=11:00
 'It will probably take around .' 90m           <- the duration of the assignment, orphaned
 'I also want to fix a backend authentication bug in project' 45m
 'Which may take about .' 120m                  <- the duration of the bug, orphaned
 "I'd like to do that when I'm mentally fresh." 45m   <- a preference became a task
 'I want to go to the gym' 45m        'Spend about there.' 60m
 'Review DSA for at least' 45m        'Preferably earlier in the day but it can be moved…' 45m
 'Call my mom sometime' 45m           'Around .' 15m
 'I also need to clean my room' 45m   'Which will take about' 30m   'But this is' 45m (low)
 'Can be skipped if the day gets too full.' 45m
 "Don't schedule tasks on top of each other." 45m   'Keep enough travel/preparation time…' 45m
 'Gym.' 45m   'Prioritize assignment' 45m   'Class' 45m   'Backend bug' 45m   'Gym' 45m
 "DSA review in that order if there isn't enough time for everything." 45m
```

Defect classes: **attribute orphaning** (duration separated from its task), **preference-as-task**, **instruction-as-task**, **duplication** (`Gym`, `Gym.`; `Class` twice), **numbers deleted from sentences** ("take around ."), and **default 45 min on everything**. Result: a day that cannot be trusted, and an AI-quota-exhausted user (who gets this path) sees the worst version of the product.

Three isolated examples from the brief: the ML-assignment sentence → 1 task but title `"I should finish … because I need to submi…"` with the wrong duration source; the backend-bug paragraph → **2** tasks (duration orphaned); the DSA sentence → 1 task with the sentence as its title and the *minimum*-duration meaning lost. A six-intention dump written without punctuation → **1** task (`'Gym finish ml assignment before 11 call mom clean room fix backend bug'`).

The Flutter parser (`lib/services/task_parse_service.dart`) is a **second, independent implementation** of the same idea [VERIFIED to exist]; its output on this input was not executed (Flutter tooling blocked) [UNCERTAIN], but it is built from the same family of rules (comma/`and` splitting, an "AI needed?" heuristic at `:60`).

### 4.2 AI path (Gemini) [VERIFIED structure, UNCERTAIN quality]

* One monolithic prompt (12,024 chars) with rules that *conflict with intent preservation*: "DO NOT create task cards for commuting, driving, or leaving home", "DO NOT create a task card for lunch", stress/meta statements are dropped, `deferred_tasks` collapse "optional" into `priority='low'`. The medium test's "Leave home by 11:50" is exactly the kind of statement this discards. [VERIFIED `ai_service.py:142-250`]
* The raw user text is interpolated inside quotes in the prompt (`f'"{raw_text}"'`) — quote-breaking and prompt-injection surface. [VERIFIED]
* Free-form JSON mode (`responseMimeType: application/json`), no response schema, no `maxOutputTokens`; malformed JSON triggers a *second* LLM call (repair). [VERIFIED]
* Quality of the AI path on the medium test is **unknown** (not run; requires a live key). [UNCERTAIN → Phase 0]

### 4.3 Profile & learning [VERIFIED]

Uses of each `PlanningProfile` attribute **inside the slot-scoring function** (`evaluate_best_slot_with_reason`):

| Attribute | Uses | Attribute | Uses |
|---|---|---|---|
| `bedtime` | 6 | `preferred_peak_start/end` | used |
| `weekend_wake_time` | 2 | `warmup_minutes` | 1 |
| `routine_shift_preference` | 2 | `high_energy_task_types` | 1 |
| `learned_afternoon_focus` | 1 | `preferred_dip_start` | 1 |
| **`preferred_session_minutes`** | **0** | **`energy_predictability`** | **0** |
| **`confidence_level`** | **0** | **`avg_duration_ratio`** | **0** |
| **`tired_behavior`** | **0** | | |

`avg_duration_ratio` is *computed* (`personalization_engine`, `evaluation_service`) and stored, but nothing multiplies a duration by it. Learned signals are loaded only on `/ai/plan`; Replan, `/today/override`, confirm and day view build a profile **without** performance history. The behaviour log contains fabricated values (§4.4).

### 4.4 Behaviour data quality [VERIFIED]

* On completion Flutter creates feedback with `perceivedFocusScore: 5`, `energyFeeling: 'Energized'` and sends focus 5 to the backend without asking the user (`app_state_provider.dart:682-683, 712`). Missing scores default to `3` (`task_service.dart:133-135`). Any "what Flowstate learned about you" built on these inputs would be **fabricated analytics**.
* `TaskPerformance` has planned vs. actual start and minutes, but rows exist only when feedback is submitted; there is no record of *plans* (what was scheduled, moved, postponed, abandoned) independent of feedback. [VERIFIED `models/task_performance.py`; MISSING event log]

### 4.5 Replan understanding [VERIFIED — `parse_replan_instruction` run on natural messages]

| User message | Parsed operation | Verdict |
|---|---|---|
| "I'm running 30 minutes late." | `delay_remaining_schedule` | correct |
| "Move DSA to tomorrow" | `move_task_date('dsa')` | correct |
| "Urgent work came up" | `add_task('Work came up')` | acceptable but title mangled |
| "Class got cancelled" | **`add_task('Class got cancelled')`** | **invents a task** |
| "I can't go to the gym anymore" | **`add_task("I can't go to the gym anymore")`** | **invents a task**; should cancel/skip gym |
| "I finished the assignment early" | **`add_task('I finished the assignment early')`** | **invents a task**; should complete it and free its slot |
| "my professor moved the deadline to friday" | **`add_task(…)`** | should change a deadline |
| "skip the gym today and push DSA after dinner" | only `add_constraint('dsa')` | **first match wins; second intent lost** |

### 4.6 Latency and timeouts

Measured on this machine, SQLite, in-process ASGI, **extraction stubbed** (so *no LLM time*) [VERIFIED]:

| Stage | median | p95 |
|---|---|---|
| `planner.plan` build, 8 tasks | 6.1 ms | 9.0 ms |
| `planner.plan` build, 25 tasks | 14.4 ms | 19.3 ms |
| `planner.plan` build, 60 tasks | 41.1 ms | 54.1 ms |
| `POST /ai/plan` (7 candidates, auth + profile + load + plan + idempotency write) | 44.6 ms | 52.5 ms |
| `POST /tasks/batch-create-and-schedule` (7 tasks) | 34.1 ms | 40.3 ms |
| `GET /calendar/day` (7 tasks) | 20.4 ms | 21.9 ms |
| `POST /ai/replan` dry run | 15.4 ms | 17.7 ms |

So **everything except the LLM is already fast**. The latency risk is the LLM call and the way timeouts are composed:

* Flutter's POST timeout is **12 s** (`api_service.dart:123`).
* Backend: up to **3 distinct models**, **12 s each**, serial, plus an optional repair call (`ai_service.py:1036-1049, 1133`) → worst case ≈ 36 s+ while the client gave up at 12 s. [VERIFIED]
* On client timeout Flutter silently runs the local fallback ("AI planning isn't available right now") while the server may still complete and **charge** the user for a result nobody sees. [VERIFIED code path; frequency UNCERTAIN]
* Two sequential usage-status requests precede every plan (`brain_dump_sheet.dart:131, :184`). [VERIFIED]
* LLM latency, token counts and error rates in production: **[UNCERTAIN]** — existing log lines (`ai_service.gemini_ok … latency_ms input_tokens output_tokens`) can answer this without new code (Phase 0).

### 4.7 Input size [VERIFIED]

`raw_text` ≤ 1,500 characters on `/ai/plan` and `/tasks/parse`. The medium test is 954 characters; a realistic "everything in my head" dump of 250–400 words is **1,500–2,500 characters**. The UI offers a 5-line text field without a counter or limit (no `maxLength` in the widget), so a long dump is sent, rejected with 422, and then handled by the generic `catch (_)` — the user is told AI is "not available" and receives the fragmenting fallback. This is the worst possible behaviour for the product's core input.

### 4.8 Layer-by-layer root-cause verdict

| Suspected layer | Verdict |
|---|---|
| Extraction | **Primary cause** — schema, boundaries, preservation, fallback |
| Normalization | **Primary** — no entity/constraint model for what extraction finds; no consolidation, dedupe, supersession |
| AI availability | Contributing — chain/timeouts/charging; fallback quality makes outages visible |
| Profile integration | **Significant** — most signals unused, learning not shared across paths, fabricated inputs |
| Scheduling | **Not the problem** — correct and fast; needs *capabilities*, not a rewrite |
| UI representation | Contributing [UNCERTAIN — preview cards were read, not user-tested] |
| Fallback | **Primary** — destructive |
| Latency | Contributing — LLM + timeout composition; deterministic parts are fine |

---

## 5. Product goal

Build My Day should read as *"I dumped my head and Flowstate understood me"*, not *"AI turned my paragraph into calendar rows"*. The loop this specification builds toward:

```
MESSY DUMP → understand intent → preserve everything → understand time/deadlines/context
   → know the user → build a feasible day → explain it → user lives the day
   → observe what actually happened → learn → improve the next plan
   → reality changes → replan the remaining day
```

Quality bar (each is testable, §26): coherent (one intention = one entity), calm (few cards, scannable), intelligent (reasons that correspond to real inputs), personalized (visible only once earned), trustworthy (nothing lost, nothing invented, nothing overlapping), fast (§19), and **honest** (degraded modes and cold-start states are stated, never disguised).

---

## 6. Semantic extraction architecture

### 6.1 Responsibilities (hard separation)

| Concern | Owner | Why |
|---|---|---|
| Task boundaries; "one intention vs several"; which sentence is an attribute of which entity | **LLM** | semantic, not syntactic |
| Extracting constraints and preferences in natural language; resolving "that", "it", "the other one"; "actually…" corrections; understanding "mentally fresh", "if the day gets too full" | **LLM** | language understanding |
| Arithmetic on dates/durations; timezone conversion; relative dates (`tomorrow`, `Friday`); validating that evidence quotes exist in the input; entity dedupe; coverage; tier assignment; overlap/deadline/bound checking; persistence; authorization; idempotency | **Deterministic server code** | must be reproducible and testable |
| Placement | **Existing pure planner** (extended, §14) | already authoritative and tested |

The LLM output is **untrusted input**: it is schema-validated, evidence-checked and normalized before it can influence a plan, and it never writes to the database.

### R1 — Intent-graph extraction (schema v2)

| | |
|---|---|
| **CURRENT STATE** | One free-form-JSON Gemini call → `TaskCandidateResponse` list + `PlanningContext`; deterministic regex re-segmentation afterwards; a 12 k-char rules prompt. [VERIFIED] |
| **EVIDENCE** | `ai_service.py:93-115` (schema), `:142-250` (prompt), `:360-420` (re-segmentation), §4.1–4.2 |
| **PROBLEM** | The model is asked for *tasks*, so everything that is not a task (a preference, a duration, an instruction) is either dropped, turned into a task, or lost. There is no evidence linking an output to the user's words, so nothing can be audited. |
| **PROPOSED BEHAVIOR** | Ask for an **intent graph**: `entities[]` of kind `task` / `event` / `note` / `question`, each with typed, individually-evidenced `attributes` (§8), plus `global_instructions[]` and `unresolved[]`. **Boundary rule (in the prompt and in the evaluation set):** *one entity per outcome the user could tick off; every sentence that only describes timing, duration, reason, preference or optionality of that outcome is an attribute of it, not a new entity.* Use the model's **structured-output (response-schema) mode**, `temperature 0`, an explicit `maxOutputTokens`, raw text passed as a **delimited data block** (never interpolated into instructions), and the three boundary examples from the product brief as few-shot examples. Evidence is a **verbatim quote ≤ 80 chars** per attribute; the server finds it in the input to derive offsets (LLMs are unreliable at offsets). One call; a single bounded retry only when validation fails. Deterministic code **does not re-split** AI entities (it may only validate, normalize and merge exact duplicates). |
| **WHY** | Boundary decisions are the thing LLMs do well and regex cannot. Quotes make every claim checkable. A response schema removes the repair call in the common case. |
| **AFFECTED COMPONENTS** | new `app/services/brain_dump_extractor.py` (prompt, schema, validator, normalizer, coverage); `AIService.extract_structured_plan_with_gemini` kept as v1 behind a flag; `schemas/ai.py` (v2 response alongside v1 `tasks`); `routes/ai.py` |
| **ACCEPTANCE CRITERIA** | On the gold corpus (§26): boundary accuracy ≥ 95 % (over-split rate ≤ 3 %, under-merge rate ≤ 3 %); the three brief examples are always exactly one entity; every attribute with a value has a quote that is a substring of the input; zero entities without evidence; v1 clients keep working. |
| **RISK** | Model variance → mitigated by schema validation, coverage check (R2) and a recorded-response regression suite (§25). Provider structured-output feature differences [UNCERTAIN] → Phase 0 spike. |

### 6.2 Deterministic post-processing of an extraction (pipeline stage "consolidate")

In order, all pure functions, all individually tested:

1. **Schema validation** (types, enums, ranges). Failure → one repair retry → else fallback mode (R7).
2. **Evidence check** — each quote must be a substring of the normalized input; otherwise the attribute is dropped to `source=inferred, confidence×0.5` and flagged, never silently kept as explicit.
3. **Value normalization** — durations re-parsed from their own quote (`"1.5 hours"` → 90; `"at least 45 minutes"` → `min=45, planned=45`); if the model's number disagrees with every number parsable from the quote (±10 %), the quote wins and `normalized_from_quote` is recorded. Dates: the model returns an *expression* (`tomorrow`, `friday`, ISO date); the **server resolves it** with the timezone rule (`core/timezone.py`) — the model never does date arithmetic.
4. **Supersession** — "actually…", corrections and repeated thoughts arrive as `supersedes` edges; the superseded entity is excluded from planning and kept in the trace as `superseded_by`.
5. **Duplicate merge** — entities whose normalized titles are near-identical (token Jaccard ≥ 0.8) *and* whose attributes are compatible are merged; the merge is recorded (`merge_reason`).
6. **Coverage check** (R2).
7. **Mapping** to planner inputs (§8–§10).

### 6.3 Model strategy — what needs the LLM, and what does not

| Work | Needs LLM? | Where it runs | Why |
|---|---|---|---|
| Boundary detection, attribute attachment, resolving "that/it", corrections, preference/optionality language | **Yes** — 1 call per Build My Day (+ at most 1 bounded repair) | extractor | genuine language understanding |
| Replan: understanding free-form changes | **Only when the deterministic grammar misses** — 0 or 1 small call | `replan_intent` | the common cases ("late N min", "move X to day", "cancel X") need no model |
| Date/duration/timezone arithmetic, dedupe, coverage, tiers, feasibility | No | deterministic | must be reproducible and cheap |
| Placement, overlap/deadline checking, validation | No | pure planner | authoritative and tested |
| Explanations and delta sentences | **No** (templates over recorded facts) | server | an LLM-written reason could be fabricated |
| Profile retrieval, effective profile | No | DB + cache | stable data |
| Behaviour statistics, learning | No (statistics, shrinkage, EWMA) | `behavior_service` | explainable and testable |
| Insights wording | No (templates + counts) | server | never fabricate analytics |

**Model calls per flow:** Build My Day = 1 (+≤ 1 repair when the response schema fails); Replan = 0–1; everything else = 0. **Model choice** is a corpus decision, not an assumption: a flash-class model with structured output is the default; a larger model is considered only as an *escalation* for a failure class the corpus shows it fixes, and only if it fits the latency targets. More calls are rejected unless a corpus metric improves enough to justify the added latency and cost.

### R6 — Input size strategy

| | |
|---|---|
| **CURRENT STATE** | Hard cap **1,500 characters**; no UI counter; oversize looks like "AI unavailable". [VERIFIED §4.7] |
| **EVIDENCE** | `schemas/ai.py:7`, `schemas/task.py:142-143`, `brain_dump_sheet.dart` (no `maxLength`; generic `catch (_)`) |
| **PROBLEM** | The product's core input is a long, messy dump. 1,500 characters ≈ 250 words, below a realistic full-day dump. |
| **PROPOSED BEHAVIOR** | **Tiered limit, one extraction call:** (a) **soft target ≤ 4,000 characters** (~650 words, ~1 k tokens) — normal path; (b) **hard cap 8,000 characters** (~1,300 words, ~2 k input tokens) per request; (c) request-body ceiling 32 KB at the middleware (abuse); (d) server-side **estimated-token guard** (input + the 12 k-char instruction prompt, which should itself shrink to ≤ 4 k chars with structured output) and an explicit `maxOutputTokens` sized to ≈ 40 entities; (e) above 8,000 characters return **`422 input_too_large {limit, length}`** with a clear message and let the client offer *"split into two dumps"* (client splits at a paragraph boundary and submits sequentially; consolidation happens at confirm via the existing dedupe). Flutter shows a live counter from ~3,000 characters, never a silent failure, and **never** reports "AI unavailable" for a validation error. A true long-dump path (chunk by paragraph, parallel extraction, deterministic merge) is **deferred** until Phase 0 telemetry shows > 2 % of dumps exceed the cap. |
| **WHY** | 8 k characters covers the realistic long tail at a bounded and predictable cost; output length — not input — dominates latency for this task class [UNCERTAIN, Phase 0 measures], and a 40-entity ceiling bounds it. Unlimited input makes cost and latency unpredictable and is an abuse vector; a 1.5 k cap makes the core experience fail. |
| **AFFECTED COMPONENTS** | `schemas/ai.py`, `schemas/task.py`, new size-error code in `routes/ai.py`, `brain_dump_sheet.dart` (counter + error mapping), rate-limit middleware |
| **ACCEPTANCE CRITERIA** | A 7,500-character dump is accepted and fully accounted for (R2); 8,001 characters returns the structured error and the UI shows the limit and a split suggestion; no input-size failure is ever presented as AI outage; per-request cost bounded by the token guard. |
| **RISK** | Larger inputs raise latency → mitigated by the soft target, progress UI (§19) and the output cap. Cap value is a **decision** (§30, D1) pending Phase 0 data. |

---

## 7. Intent preservation contract

**Golden rule: never lose user intent.** Stated as testable invariants:

| # | Invariant |
|---|---|
| I1 | Every **actionable** sentence of the input is covered by at least one entity's evidence **or** appears in `unresolved[]`. |
| I2 | Every entity ends in exactly one **outcome**: `placed`, `unscheduled(reason)`, `merged_into(entity)`, `superseded_by(entity)`, or `needs_input`. |
| I3 | `entities_total = placed + unscheduled + merged + superseded + needs_input` (the preview shows these counts; a mismatch is a server bug and fails the request in test/dev, logs at error level in prod). |
| I4 | A *non-task* meaningful statement (preference, context, reason, location, preparation, global instruction) is stored as an **attribute, note, or global instruction** — never dropped for "looking unimportant". |
| I5 | Nothing is **invented**: every entity and every attribute has evidence from the input or is explicitly marked `default` (e.g. "duration not stated — assumed 45 min"). |
| I6 | After confirmation the question *"what happened to this part of my dump?"* is answerable from stored metadata (R15), without retaining the raw text. |

### R2 — Preservation ledger, coverage check, and trace

| | |
|---|---|
| **CURRENT STATE** | No ledger. Planning context items are used as busy time and dropped; unschedulable candidates return `unscheduled_reason`; nothing records dropped sentences. [VERIFIED/MISSING] |
| **EVIDENCE** | `planning_service.context_busy_intervals`; `TaskCandidateResponse` has no source reference; `description` always null (`ai_service.py:93`) |
| **PROBLEM** | The product cannot currently prove it kept everything, and cannot tell a user where something went. |
| **PROPOSED BEHAVIOR** | Build a **ledger** per run: `RAW SPAN → ENTITY → PLAN OUTCOME`. **Coverage check (deterministic, independent of the model):** split the input into sentences *for coverage only* (never for task creation); a sentence is **actionable** if it contains a modal/need verb ("need to", "should", "have to", "want to", "must"), an imperative from a small action lexicon, a clock time, a duration, or a deadline expression. If no entity quote overlaps an actionable sentence → create an `unresolved` item ("I wasn't sure about: *'…'*. Add it as a task / ignore") — **never discard**. Non-actionable uncovered sentences (greetings, emotion) are retained only as the run's hash/length, not shown. The preview exposes an **"Everything I heard"** summary (planned · flexible · optional/unscheduled with reasons · needs your input). After confirmation, persist **metadata only** (R15): run id, entity id, kind, span offsets, outcome, reason code, linked task id — **not** the raw text. |
| **WHY** | Makes the golden rule enforceable and measurable instead of aspirational; works even if the model is wrong; supports support/debugging without storing private text. |
| **AFFECTED COMPONENTS** | new coverage module; `brain_dump_runs` / `brain_dump_entities` tables (§21); `/ai/plan` v2 response; confirm service links tasks to entities; Flutter preview |
| **ACCEPTANCE CRITERIA** | Semantic-preservation property test (§26): for every gold dump, `accounted = entities + unresolved` covers 100 % of gold-actionable sentences; I3 holds on 100 % of runs; deleting an entity from a mocked model response makes its sentence appear in `unresolved`; no raw text appears in any table or log. |
| **RISK** | Over-flagging noise ("I wasn't sure about…" too often) → tune the actionable-sentence lexicon on the corpus; cap `unresolved` shown to 5 with "+N more". |

---

## 8. Task / entity model

### 8.1 Entity kinds

| Kind | Meaning | Becomes |
|---|---|---|
| `task` | something the user will do | a `Task` row (existing table) |
| `event` | a thing at a fixed time the user attends (class, meeting, appointment) | a `Task` with `task_type=meeting`, `time_locked=true` (existing semantics, lock source L1) |
| `note` | context or a reason not tied to a schedulable outcome | stored as note text on the nearest entity or in the run's summary |
| `question` | the model could not resolve something | `unresolved[]` item |

**Attached blocks (derived, not separate tasks):** `travel` ("leave home by 11:50") and `preparation` are **attributes of an event/task** (`leave_by`, `travel_minutes`, `prep_minutes`). The planner materializes them as **hard busy blocks adjacent to the event**, and the UI renders them on the timeline ("Leave home 11:50 → Class 12:40"). *Rationale:* the golden rule says the "leave home" intention must survive and be visible; making it a free-standing "task" would let the planner move it away from its event. [PROPOSED; decision D4 in §30]

### 8.2 Task attributes (v2)

Every attribute is `{value…, source: explicit|inferred|default, confidence, evidence: quote}`.

| Attribute | Notes | Maps to (existing → new) |
|---|---|---|
| `title` | concise, from the user's words | `Task.title` |
| `duration` | `planned_min`, optional `min_min`/`max_min`, `approx` | `estimated_minutes` (existing) + `min_minutes` (new) |
| `deadline` | date/time, `hard` vs `soft` | `deadline_at` (existing; hard) + `deadline_kind` (new) |
| `fixed_time` | explicit clock time | `time_locked` + `scheduled_start` (existing lock rule) |
| `time_preference[]` | `before`/`around`/`earlier`/`later`/`window` with weight | `PlanTemporal.preferred_*` (existing) + weighted preferences (new) |
| `time_bounds` | earliest/latest, availability | `PlanTemporal.earliest_start/latest_end` (existing) |
| `energy` | `need` (high/low/any) and an explicit condition ("mentally fresh") | new `energy_demand`, `energy_condition` |
| `optionality` | `required` / `preferred` / `optional` + evidence | new (drives §10 tier) |
| `importance_signals[]` | consequence ("it is due tomorrow"), explicit priority, urgency language | evidence for §10 |
| `depends_on[]` | ordering edges | `PlanItem.depends_on` (existing) |
| `location`, `travel`, `prep` | attached blocks (§8.1) | new `travel_minutes`, `prep_minutes`, `leave_by` |
| `context_note` | the reason/context sentence | new `notes` (text) |

### R3 — Entity model and mapping

| | |
|---|---|
| **CURRENT STATE** | `TaskCreate`/`TaskCandidateResponse` + `TemporalConstraints` + `PlanningContext`; `PlanItem` for the planner. Fields above that are **new** do not exist. [VERIFIED] |
| **EVIDENCE** | `schemas/task.py`, `engines/planner.py:PlanItem` |
| **PROBLEM** | The data model cannot carry minimum duration, optionality, energy condition, notes or attached blocks, so even a perfect extraction would be flattened. |
| **PROPOSED BEHAVIOR** | Keep `PlanItem` as the planner contract and **extend** it with optional fields (`min_minutes`, `optionality`, `energy_demand`, `energy_condition`, `prep_minutes`, `travel_minutes`, `leave_by`, `soft_preferences[]`, `entity_id`). Persist the non-planner attributes in a side table `task_planning_meta(task_id, optionality, min_minutes, preferences_json, notes, source_run_id, source_entity_id)` — **additive**, `tasks` is not widened. Entities map one-to-one to tasks; attached blocks stay attributes. |
| **WHY** | Smallest change that carries the information; preserves every existing planner invariant and test. |
| **AFFECTED COMPONENTS** | `planner.PlanItem` (optional fields only), `planning_service` (mapping), new table + migration (§21), `TaskResponse` (optional new fields for v2 clients) |
| **ACCEPTANCE CRITERIA** | All 1,160 existing tests still pass unchanged; round-trip test: extraction → `PlanItem` → persisted → reloaded preserves every attribute; adding the optional fields changes no existing planner result (property test: identical output when new fields are absent). |
| **RISK** | Planner churn → fields are optional with neutral defaults, guarded by the existing property suite and mutation checks. |

---

## 9. Constraint model

### 9.1 Hard vs. soft

| Class | Examples | Planner treatment |
|---|---|---|
| **HARD** | fixed events; explicit fixed times (lock source L1–L5); hard deadlines; availability windows; explicit sleep window *when configured*; **travel/prep blocks around events**; dependencies (ordering); "don't schedule on top of each other"; time already past | filtered **before** scoring (existing `evaluate_best_slot_with_reason` hard filter) |
| **SOFT** | "around 6 PM", "preferably earlier", "sometime in the evening", "when I'm mentally fresh", expected energy, history fit, density, context-switching, fatigue | contribute to the **score** inside the feasible set (§14) |
| **GLOBAL INSTRUCTIONS** | "don't schedule tasks on top of each other", "keep enough travel/preparation time around class and gym", "prioritize A, B, C in that order" | extracted as `global_instructions[]`: *no-overlap* is already an invariant; *buffer_around* sets `travel/prep` defaults for named entities; *priority_order* sets `rank` |

### R4 — Constraint extraction, contradictions, corrections

| | |
|---|---|
| **CURRENT STATE** | Temporal fields on candidates; `planning_context` for fixed events/travel/protected/availability/dependencies/priority_order/deferred/energy/buffer. Contradictions are not detected; corrections are not modelled; dependency matching is by title substring. [VERIFIED `ai_service.py:118-140`, `planning_service.candidates_to_plan_items`] |
| **EVIDENCE** | `planning_service.py` (substring dependency match; only `morning_heavy` energy handled) |
| **PROBLEM** | "Prioritize the assignment, class, backend bug, gym and DSA in that order" and "keep travel time around class and gym" are instructions about the *whole plan*; they are currently only partly representable. A contradiction ("before 9" but "not until 10") silently yields an unschedulable task with a generic reason. |
| **PROPOSED BEHAVIOR** | (1) Extract `global_instructions[]` as above. (2) **Contradiction detector** (deterministic, after normalization): deadline < earliest start; duration > window; two fixed times overlapping; dependency cycle; fixed time in the past. Each produces a *named conflict* with a user-facing question ("You asked for the assignment before 11 but also after 10:30 — which should I keep?") instead of a silent failure. (3) **Corrections** via `supersedes` (R1 step 4). (4) Dependencies reference entity **ids**, not title substrings. (5) `energy_preference` honours all three values (today only `morning_heavy` is applied). |
| **WHY** | Moves ambiguity handling from silent loss to an explicit, answerable question. |
| **AFFECTED COMPONENTS** | extractor validator, `planning_service` mapping, planner conflict codes, preview UI (questions) |
| **ACCEPTANCE CRITERIA** | The five contradiction fixtures produce the expected named conflicts and no 500; superseded entities are never scheduled; the global priority order sets `rank` exactly as stated; `afternoon_heavy`/`evening_heavy` change scoring in a property test. |
| **RISK** | Too many questions annoys users → ask only when the planner cannot satisfy the hard constraints; cap questions per run at 3 and offer a sensible default action. |

---

## 10. Priority model

"Priority" is not one number. Keep these **separate fields** and derive a **tier** deterministically.

| Dimension | Source | Computed? |
|---|---|---|
| `explicit_priority` | user words ("urgent", "low priority") — existing `priority` + `priority_source` | extracted [VERIFIED exists] |
| `urgency` | deadline pressure: `slack = deadline − now − duration` (and fixed time proximity) | **computed** deterministically |
| `importance` | consequence/reason evidence ("because I need to submit it tomorrow") | extracted evidence flag, not a number |
| `optionality` | `required` / `preferred` / `optional` ("if I have time", "can be skipped") | extracted |
| `consequence_of_delay` | evidence of a downstream hard dependency or deadline | derived from deadline/dependency graph |
| `user_rank` | "prioritize X, Y, Z in that order" | from `global_instructions.priority_order` — existing `PlanItem.rank` |
| `user_preference` | likes/dislikes about when | soft preference (§9) |

### Tier assignment (deterministic, evidence-based)

| Tier | Rule (first match wins) |
|---|---|
| **FIXED** | events and explicitly fixed times |
| **REQUIRED** | hard deadline within the planning horizon **or** `optionality=required` with consequence evidence **or** in the user's `priority_order` top *k* (default 3) |
| **HIGH** | explicit high/urgent priority, or `slack` below a threshold, or dependency of a REQUIRED item |
| **FLEXIBLE** | everything else with no optionality evidence |
| **OPTIONAL** | `optionality=optional`, or explicit low priority with skip language |
| *(outcome)* **UNSCHEDULED** | any tier that could not be placed — always with a reason |

User `rank` orders items **within** a tier and overrides tier order only for the tiers the user named. Capacity shedding when the day is overloaded drops from the bottom: OPTIONAL → FLEXIBLE (lowest rank/slack first); **FIXED and REQUIRED are never shed** — if they cannot all fit the result is a named conflict, not a silent drop.

### R5 — Priority tiers, overload buckets, unscheduled reasons

| | |
|---|---|
| **CURRENT STATE** | `priority` (low…urgent) + `rank`; planner orders by `(rank, overdue/due-today/high, priority weight, type weight)` and displaces by urgency key; unscheduled reasons are `no_capacity`, `deadline_infeasible`, `bound_infeasible`, `explicit_time_in_past`. [VERIFIED `planner.order_key`, `Unplaced.reason`] |
| **EVIDENCE** | `planner.py` (`order_key`, displacement loop, `classify`) |
| **PROBLEM** | No notion of *optional*; an overloaded day sheds by a single number; reasons do not say *what* blocked the task ("clean room wasn't scheduled because fitting it would push your assignment past its deadline"). |
| **PROPOSED BEHAVIOR** | Add `tier` and `optionality` to `PlanItem`; order/shed by `(tier, rank, slack)`; `Unplaced` carries a **structured blocker**: `{code, blocking_entity_ids[], constraint_id}`. Blocker computation is **counterfactual and deterministic**: re-run placement for the unplaced item with one constraint relaxed at a time; the first relaxation that makes it fit names the blocker (e.g. relaxing `deadline` of *assignment* frees the slot ⇒ "fitting it would push *Assignment* past its deadline"). Buckets in the response: `FIXED, REQUIRED, HIGH, FLEXIBLE, OPTIONAL, UNSCHEDULED`. |
| **WHY** | Satisfies "never silently delete" and "the user should understand the decision" with reasons derived from real inputs, not templates. |
| **AFFECTED COMPONENTS** | `planner.py` (ordering, `Unplaced.blocker`), `planning_service` (response buckets), Flutter preview/diff |
| **ACCEPTANCE CRITERIA** | Overload fixtures: with 12 h of work in a 9 h day, FIXED+REQUIRED are placed, OPTIONAL are unscheduled first, each unscheduled item has a blocker naming real entities; the existing invariants/property tests unchanged; reasons never reference an entity that did not participate (property test over generated overload cases). |
| **RISK** | Counterfactual runs cost CPU → bounded to unscheduled items only (≤ 5), ~6 ms each at current speed. |

---

## 11. Questionnaire / profile architecture

**Principle.** The questionnaire is the **initial profile — a starting hypothesis**, not permanent truth and not biology. Three layers, never merged destructively:

| Layer | Meaning | Source | Mutability |
|---|---|---|---|
| **REPORTED** | "What the user told Flowstate" | onboarding questionnaire, settings | changed only by the user; versioned (`ReadinessProfile.version` exists [VERIFIED]) |
| **OBSERVED** | "What Flowstate has learned from behaviour" | append-only plan/behaviour events (§12) | recomputed from events; carries `n`, `confidence`, `last_updated` |
| **EFFECTIVE** | what the scheduler actually uses | blend of the two | derived per request, never stored as truth |

`effective = (1 − w)·reported + w·observed`, where `w = personalization_weight(signal)` ∈ [0, 0.6] grows with sample size, spread across days, and recency (§12.3) and is **0 below the minimum sample**. A signal with `w = 0` is exactly the questionnaire answer. The user can see and reset every learned signal (§22/§23).

### 11.1 Current state of the questionnaire fields [VERIFIED]

Fields sent at onboarding: `preferred_peak_start/end`, `weekday_wake_time`, `weekend_wake_time`, `bedtime`, `sleep_inertia_minutes`, `preferred_session_minutes`, `draining_work_types`, `fatigue_symptom`, `routine_shift_preference`, `session_disruptor`, `primary_goal`, `energy_predictability`, `timezone` (`onboarding_flow_screen.dart`, `schemas/readiness.py`). Stored in `readiness_profiles`. Used by the planner via `PlanningProfile.from_user_context` — see §4.3 for which attributes reach scoring. `session_disruptor` and `schedule_disruptors` are stored and used only for companion nudges. [VERIFIED `FLOWSTATE_SCHEDULER_AUDIT.md`, scoring-usage counts]

### R8 — Profile layering and the questionnaire → planner contract

| | |
|---|---|
| **CURRENT STATE** | One flat `PlanningProfile` built per call; six attributes affect scoring; learned values only on `/ai/plan`. [VERIFIED] |
| **EVIDENCE** | `scheduling_engine.PlanningProfile.from_user_context`; callers listed in §4.3 |
| **PROBLEM** | Reported data is treated as fixed; stored answers do nothing; the learning path is not shared by Replan, "Later", confirm, or day view; there is no per-signal confidence. |
| **PROPOSED BEHAVIOR** | (1) A **signal registry** (`user_profile_signals`) — one row per `(user, signal_key)` with `reported_value`, `observed_value`, `observed_n`, `confidence`, `updated_at`. (2) One function `effective_profile(user, now)` (pure, given rows) feeding **every** planner caller (build, confirm, replan, override, day view). (3) The contract table below, implemented as data (signal → planner input → effect → confidence ceiling), unit-tested row by row. (4) Copy rules: the UI says *"you told us"* for reported, *"we've noticed"* for observed, and *"measured"* only for device/manual data. |
| **WHY** | Makes personalization consistent everywhere and prevents the "two profiles" problem; keeps reported answers intact so the user can always return to them. |
| **AFFECTED COMPONENTS** | new `profile_service.py`; `PlanningProfile.from_user_context` (callers switch to `effective_profile`); `readiness_profiles` untouched; new table (§21); onboarding unchanged |
| **ACCEPTANCE CRITERIA** | Every caller of the planner receives the same effective profile for the same user/time; with zero observations the effective profile equals the questionnaire exactly (golden test); each contract row has a test proving the stated scheduling effect and the stated ceiling. |
| **RISK** | Silent behaviour change for existing users once learned signals activate → staged rollout (§12.3), feature flag, and a visible "learned" label with reset. |

### 11.2 The contract (QUESTIONNAIRE FIELD → PROFILE ATTRIBUTE → PLANNER SIGNAL → SCHEDULING EFFECT → CONFIDENCE)

"Today" = verified current effect. "Proposed" = what the contract adds. Confidence is the **initial** ceiling for a reported-only value; it rises only through observation.

| Questionnaire field | Profile attribute | Planner signal | Scheduling effect — **today** [VERIFIED] | Scheduling effect — **proposed** | Initial confidence | How behaviour updates it |
|---|---|---|---|---|---|---|
| `weekday_wake_time`, `weekend_wake_time` | `weekday_wake`, `weekend_wake` | day start | no slot before wake; warm-up window starts here | unchanged (hard) | high (stated) | observed first-activity time may *suggest* a change; never auto-applied to a hard bound |
| `bedtime` | `bedtime` | day end | hard end of day; sleep-protection penalty near bedtime; imminent-deadline overrun ≤ 90 min | unchanged (hard) | high | same as above |
| `sleep_inertia_minutes` | `warmup_minutes` | warm-up window | cognitive tasks penalised (−0.85) before wake+warm-up | unchanged (soft) | medium | observed time-to-first-focused-completion adjusts within ±15 min |
| `preferred_peak_start/end` ("strongest work window") | `focus_window` | `energy_fit(slot)` | +0.45 for cognitive tasks inside the window | soft preference; weight × `confidence`; replaced by the **observed** window as evidence accrues | **low** (a self-report) | completion rate / on-time start of cognitive tasks by time bucket (§12) |
| (derived) dip window | `dip_window` | `energy_fit` for light work | +0.35 inside | same layering | low | same |
| `draining_work_types` | `cognitive_types` | task is "cognitive?" | classifies tasks for peak/warm-up/late-fatigue | also marks `energy_demand=high` | medium | task types the user repeatedly postpones/abandons at specific times |
| `fatigue_symptom` | `tired_behavior` | late-day penalty shape | **stored, not used in scoring** (0 uses) | modulates the late-evening penalty and post-session buffer (e.g. "distracted" ⇒ shorter blocks, more breaks) | low | late-day abandon/overrun rate |
| `preferred_session_minutes` | `session_minutes` | block length / splitting | **stored, not used** | cap for a single focus block; long tasks may be proposed as blocks (never auto-split silently) | low | actual durations of completed focus sessions |
| `energy_predictability` | `predictability` | weight of time-of-day signals | **stored, not used** | scales how strongly `energy_fit` counts (predictable ⇒ trust windows more) | low | variance of observed outcomes across days |
| `routine_shift_preference` | `weekend_shift` | weekend/shifted-day adjustment | applied on days > 0 and weekends | unchanged | low | weekday-vs-weekend completion differences |
| `primary_goal` | `optimization_goal` | tie-break objective | **stored, not used** | breaks ties between equally feasible plans (e.g. "start difficult work first" prefers hard tasks earlier) | medium (explicit intent) | never auto-changed |
| `session_disruptor`, `schedule_disruptors` | `disruptors` | companion nudges | not a scheduling input | remain non-scheduling (context for nudges/insights only) | n/a | — |
| `timezone` | `timezone` | zone rule | one rule everywhere | unchanged | high | device zone preferred per request |
| (learning, not questionnaire) | `duration_ratio[type]` | duration estimate | computed, **unused** (`avg_duration_ratio` 0 uses) | multiplies an *inferred* duration (never an explicit one), clamped 0.7–1.6, only with ≥ 5 samples | none → grows | EWMA of actual/planned by task type |

The contract is **data**, not prose: each row is a registry entry with a unit test.

---

## 12. Behavioural learning model

### 12.1 What is observed (append-only event log)

One row per event in `plan_events` (§21), **metadata only**. Events are things the user (or the system on the user's behalf) *did*, not things inferred:

| Event | Fields |
|---|---|
| `plan_created` | run id, entity count, mode (ai/degraded), profile stage |
| `task_scheduled` | task id, planned start/end, tier, time-bucket, planner reason code |
| `task_moved` | from/to, **by** (`user` / `replan` / `later` / `do_now`) |
| `task_started` | actual start (time the user pressed Start) |
| `task_completed` | actual end, actual minutes; **explicit feedback only if the user gave it** |
| `task_postponed` / `task_skipped` | count, reason if the user gave one |
| `task_abandoned` | cancelled with no completion |
| `replan_applied` | trigger category, #moved/#unscheduled |

Context stored with each: task type, difficulty, tier, optionality, weekday, local time bucket (e.g. 90-minute bins), planned vs. actual duration. **No titles, no raw text.**

### 12.2 What is learned (all optional, each gated)

| Learned quantity | Estimator | Used for |
|---|---|---|
| `duration_ratio[type]` | EWMA of `actual/planned` over completed tasks, winsorised at the 10th/90th percentile | adjust *inferred* durations; show "usually takes you ~X" for explicit ones |
| `start_delay[type, bucket]` | median of `actual_start − planned_start` | gently shift planned start / add lead time |
| `completion_rate[type, bucket]` | smoothed (Beta-prior) completion proportion per cell | `history_fit` soft term (§14) |
| `focus_window` | time bucket(s) with highest smoothed completion of cognitive tasks | replaces the reported window as evidence accrues |
| `postpone_tendency[type]` | smoothed postpone rate | choose more robust placements; Insights |
| `density_tolerance` | completion rate vs. planned load per day | cap how packed to schedule |
| `session_length` | median actual focus-session minutes | cap block length |

### 12.3 Confidence, recency, and stability rules (the "do not change dramatically" rules)

1. **Minimum sample per cell.** No learned signal influences scheduling below `N_min = 5` observations *and* ≥ 3 distinct days (duration ratio: 5 observations of the same task type).
2. **Shrinkage.** `estimate = (n·observed + k·prior) / (n + k)` with pseudo-count `k = 5`; the prior is the reported value or the global default.
3. **Recency.** Exponential half-life 21 days; one day contributes at most **20 %** of any cell's weight, so a single unusual day cannot dominate.
4. **Step cap.** A signal may move at most **15 % of its range per week**.
5. **Unusual-day guard.** A day with ≥ 3 replans, an explicit "sick/travel" marker, or abnormal volume is down-weighted (×0.3) rather than learned from at face value.
6. **Explicit duration is sacred.** Learned ratios never overwrite a duration the user stated.
7. **Clean inputs only.** Only user-given feedback counts as feedback; completion *timing* is recorded without scores. The Flutter code that fabricates `focus 5 / Energized` (§4.4) must be removed **before** any learning is enabled (Phase 3 prerequisite).

### 12.4 Stages

| Stage | Observations | Behaviour |
|---|---|---|
| **0 cold start** | 0 | questionnaire/defaults only; labelled "based on what you told us" |
| **1 early** | 1–9 completed, < 3 days | duration ratios computed but **display-only** ("usually ~X"); no scheduling influence |
| **2 emerging** | 10–29, ≥ 3 days | learned terms enabled at weight ≤ 0.25; Insights shows *only* statistics with enough data |
| **3 established** | ≥ 30, ≥ 14 days | weight ≤ 0.60; focus window and duration ratios may replace reported values; "What Flowstate learned about you" visible |
| **4 long-term** | months | seasonal/weekly drift tracked via the half-life; quarterly recompute; user can reset |

### R9 — Behaviour observation and learning

| | |
|---|---|
| **CURRENT STATE** | `TaskPerformance` (feedback-driven), `ReadinessObservation` (rating-driven), `RecommendationOutcome` (postponed_at); `PersonalizationEngine.recompute_profile` runs after feedback; Insights gates on `MIN_SESSIONS_FOR_PATTERNS`. [VERIFIED] |
| **EVIDENCE** | `models/task_performance.py`, `models/readiness_observation.py`, `models/recommendation.py`, `routes/tasks.py` (feedback hook), `routes/insights.py` |
| **PROBLEM** | Behaviour is recorded only when the user fills in feedback; plans, moves, postponements and abandonment leave no trace; inputs are polluted by fabricated scores; the learned values are not consumed by the scheduler. |
| **PROPOSED BEHAVIOR** | Add `plan_events` (above) written at the existing write points (confirm, start, complete, override, replan apply); a derived `user_behavior_stats` table **rebuildable from events**; the estimators and guards of §12.2–12.3; expose stage and sample counts so every learned statement can say how much evidence supports it. |
| **WHY** | One observation stream feeds the scheduler *and* Insights (§12.5) so they cannot drift apart; metadata-only events are safe to keep. |
| **AFFECTED COMPONENTS** | new `behavior_service.py`; hooks in `task_service.start/complete`, `plan_confirm_service`, `calendar_service.apply_replan`, `today.record_override`; `personalization_engine` (consumes stats); Flutter (remove fabricated feedback; ask for feedback only when the user chooses) |
| **ACCEPTANCE CRITERIA** | Replaying a recorded event stream reproduces the same stats (determinism); a single outlier day moves no signal by more than the step cap; with < `N_min` samples scheduling output is byte-identical to the questionnaire-only plan; no event row contains task titles or raw text; isolation test: user A's events never influence user B's plan. |
| **RISK** | Learning feels creepy or wrong → labelled, resettable, staged, and conservative; sparse users never see learned claims. |

### 12.5 Learning → Insights contract (one data model, not five systems)

```
behaviour  →  plan_events (append-only)  →  user_behavior_stats (derived)  →  effective profile  →  scheduler
                                                       │
                                                       └──────────────────────→  Insights (reads the SAME stats)
```

Insights statements are produced from `user_behavior_stats` **with their sample counts**, each guarded by its stage:

| Insight | Requires | Wording rule |
|---|---|---|
| "Your strongest focus window" | stage ≥ 3 for that cell | "Based on N sessions over D days" |
| "Tasks planned in the morning are completed more consistently" | ≥ 10 planned in each compared bucket | show both rates and counts, never only the winner |
| "You usually take ~X% longer on <type>" | ≥ 5 completions of that type | shown as a range |
| anything else | — | **not shown** — no placeholder analytics |

Existing Insights cold-start gating stays and is extended with the same stage thresholds. [PROPOSED; existing posture VERIFIED]

---

## 13. Sleep and energy data model

Three evidence levels, **never blended into a single unlabelled number**:

| Level | Meaning | Examples | Allowed claims |
|---|---|---|---|
| **REPORTED** | the user told us | questionnaire wake/bed/peak window; manually typed "slept 5 h" | "you told us…" |
| **OBSERVED** | inferred from what the user *did in the app* | first activity of the day, time-bucket completion rates | "we've noticed you…" |
| **MEASURED** | produced by an actual sensor/log | device sleep data (future), a manual sleep log with quality | "measured…" — only when such data exists |

* `ReadinessObservation` already has `sleep_minutes`, `sleep_quality`, `wake_time`, `energy_rating`, `source` (`observed`/other). [VERIFIED `models/readiness_observation.py`] Whether any UI currently captures sleep data is **[UNCERTAIN]**; this specification does not require it.
* The scheduler treats energy as a **soft planning signal with a stated source and confidence** — e.g. *reported morning energy + observed morning deep-work completions ⇒ prefer cognitively demanding tasks there when feasible*. A reported-only energy pattern has a low ceiling (§11.2).
* Forbidden: cortisol/circadian-physiology claims, medical language, a "readiness score" presented as fact without MEASURED inputs. Any score shown must name its inputs and level.
* Today's *recent-fatigue* signal is derived only from observed behaviour (consecutive heavy sessions, late-day overruns), labelled as such.

---

## 14. Personalized scheduling

**Layering — hard constraints always win; personalization optimizes only inside the feasible set.**

| Layer | Content | Owner | Status |
|---|---|---|---|
| **L0 hard** | fixed events/times, hard deadlines, availability, configured sleep window, calendar conflicts, travel/prep blocks, dependencies, no overlaps, nothing in the past | pure planner (existing hard filter + new travel/prep blocks) | existing + extend |
| **L1 capacity** | tiers; shed OPTIONAL → FLEXIBLE; never shed FIXED/REQUIRED (conflict instead) | planner ordering (R5) | extend |
| **L2 soft** | `energy_fit`, `history_fit`, task type fit, preferred time (weighted), difficulty, context-switch cost, density preference, recent fatigue, buffers, user rhythm | scoring inside `evaluate_best_slot_with_reason` | extend |
| **L3 explanation** | reasons built from the **score contributions that actually decided** the slot, plus the constraint that forced it | planner result | new |

### R10 — Personalized scoring with honest explanations

| | |
|---|---|
| **CURRENT STATE** | Scoring uses hard-coded constants (peak +0.45, dip +0.35, late −0.35/−0.50, sleep −1.00, anti-procrastination −0.35, preferred-window +0.60/−0.55, deadline tiers); explanation strings chosen by `primary_reason` ("Best feasible slot matching your availability" is the generic default); learned input limited to `learned_afternoon_focus`. [VERIFIED `scheduling_engine.py` scoring block] |
| **EVIDENCE** | `scheduling_engine.py` (scoring loop), §4.3 |
| **PROBLEM** | Weights cannot be tuned or tested individually; explanations are not guaranteed to match what decided the slot; most personal signals have no effect. |
| **PROPOSED BEHAVIOR** | (1) Move weights into a typed `ScoringWeights` and make each term return `(code, delta, input_ref)`. (2) Add terms `history_fit` (smoothed completion rate for this task type × bucket), duration estimation (learned ratio on **inferred** durations only), `context_switch`, `fatigue` (consecutive heavy blocks), `density`, optionality-aware spreading. Learned terms are multiplied by the stage weight (§12.4). (3) Keep a **top-contribution trace** for the chosen slot; the explanation is rendered from the top two contributions that exceed a threshold, using templates that reference the actual input ("because *Assignment* is due tomorrow 11:00", "your reported focus window", "you usually finish this type of task in the morning (12 of 15 sessions)"). (4) If a hard constraint forced the time, compute it counterfactually (re-run without that constraint; if the slot changes, that constraint is named). (5) **If no real contribution exists, say nothing** — no filler like "Best feasible slot". (6) Optional later improvement: a deterministic *repair* pass (try alternative orderings by slack when a REQUIRED item is unplaced). |
| **WHY** | Personalization becomes testable (each term has a unit test and a property), and every sentence the user reads is traceable to data. |
| **AFFECTED COMPONENTS** | `scheduling_engine.py` (scoring only; hard filter untouched), `planner.Placement` (`contributions[]`), `planning_service`/`calendar_service` (render), Flutter explanation line |
| **ACCEPTANCE CRITERIA** | With all learned weights at 0 the output equals today's output on the full existing suite (golden); each new term changes the chosen slot in a targeted unit test and never violates a hard rule (property suite); a test fails if an explanation names a signal whose contribution was zero or an entity that was not an input; 100 % of explanations in the acceptance suite map to a recorded contribution. |
| **RISK** | Score-weight tuning drifts quality → weights are versioned and covered by golden fixtures; learned terms off by default until stage ≥ 2. |

**Not changed:** the hard-constraint filter, invariant checker, keep-if-valid/displacement logic, user-lock semantics, atomic persistence.

---

## 15. Build My Day pipeline

Latency columns: **measured** values are from §4.6 (deterministic stages, SQLite, no network); **target** values are [PROPOSED] and must be confirmed in Phase 0 — in particular the LLM stage, which has **not** been measured here [UNCERTAIN].

| # | Stage | Purpose | Input → Output | Owner | Latency (p50 / p95) | Failure behaviour | Test strategy |
|---|---|---|---|---|---|---|---|
| 1 | **Raw brain dump** | capture text unchanged | user text → `raw` (kept on the device, hashed on the server) | Flutter | — | draft survives app kill (local storage) | widget + restart test |
| 2 | **Preprocess** | size check, normalise whitespace/unicode, strip control chars, language hint, delimit as data | `raw` → `clean`, `input_hash`, `input_chars` | server (deterministic) | ≤ 5 ms | `422 input_too_large {limit,length}`; empty → `422 empty_input` | unit + fuzz (NUL, RTL, emoji, 100 k chars) |
| 3 | **Semantic extraction** | boundaries, intents, attributes, evidence | `clean` + today/tz → intent graph v2 | **LLM** (one call) | target ≤ 3.5 s / ≤ 8 s [UNCERTAIN] | timeout/provider error → conservative fallback (R7), run recorded `degraded` | recorded-response suite + live eval (§25) |
| 4 | **Entity consolidation** | validate, evidence-check, normalise values, dedupe, apply supersession | graph → consolidated entities + `merge`/`superseded` records | server (deterministic) | ≤ 10 ms | schema failure → one repair retry → fallback | property + golden |
| 5 | **Constraint extraction / normalisation** | resolve date expressions in the user's zone; derive hard/soft; global instructions → ranks/buffers | entities → typed constraints | server | ≤ 5 ms | unresolvable expression → `needs_input` question | table-driven date tests incl. DST/midnight |
| 6 | **Profile load** | effective profile (R8) | user id → `EffectiveProfile` + stage | server (cached) | ≤ 5 ms hit / ≤ 20 ms miss | missing profile → defaults, stage 0 | isolation + golden |
| 7 | **Calendar load** | fixed events/blocks for the target days | user, days → busy intervals | server (DB) | ≤ 15 ms | DB error → request fails closed (no partial plan) | isolation + PG gate |
| 8 | **Existing-task load** | pinned/completed/in-progress tasks as planner context | user, window → `PlanItem[]` | server (DB) | ≤ 15 ms | as above | existing tests |
| 9 | **Context load** | day-level context from the dump (travel, prep, protected periods, availability) | graph → busy blocks & bounds | server | ≤ 2 ms | — | unit |
| 10 | **Dependency analysis** | build the ordering graph from entity ids; detect cycles | entities → DAG or named conflict | server | ≤ 2 ms | cycle → conflict question | property (cycles) |
| 11 | **Feasibility analysis** | *before* scheduling: capacity vs. required minutes, deadline slack, contradictions, expected overload | items + calendar → `FeasibilityReport` (tiers, overload flag, conflicts) | server (deterministic) | ≤ 5 ms | infeasible hard set → named conflict, **still returns a plan for the rest** | fixtures (overload, contradictions) |
| 12 | **Personalized scheduling** | place items (R5, R10) | items + profile + calendar → `PlanResult` | **pure planner** | **6 / 9 ms (8 tasks); 41 / 54 ms (60)** measured | planner invariant error → 5xx + logged diagnostic, never a partial write | existing property suite + new dimensions |
| 13 | **Plan validation** | re-check every invariant (existing `check_invariants`) + preservation I1–I3 | result → pass / error | server | ≤ 5 ms | error → fail the request in dev, alert in prod | existing + ledger tests |
| 14 | **Explanation generation** | reasons from recorded contributions (R10) | result → per-item reason + bucket summary | server (deterministic templates) | ≤ 10 ms | no contribution → no sentence | explanation-fidelity test |
| 15 | **Preview** | scannable, editable plan; "Everything I heard" | v2 response → UI | Flutter | network + render ≤ 300 ms | render error → fall back to v1 card list | widget tests |
| 16 | **User confirmation** | explicit consent; edits re-validated | edits → confirm request (`plan_id`, `run_id`) | Flutter | — | past explicit time → structured 422 (existing) | existing + new |
| 17 | **Atomic persistence** | tasks + task metadata + ledger + `plan_applications` in one transaction | confirm → rows | server (DB) | **34 / 40 ms** measured (SQLite) | rollback; retry-safe by `plan_id` (existing) | existing + PG gate |

**Concurrency.** Stages 6–9 are independent reads; run them as one batched load (or concurrently) rather than sequentially. Stages 4–5 and 10–11 are microseconds. **The LLM stage is the only large cost.**

---

## 16. Replan pipeline

Replan must **regenerate the remaining feasible schedule**, not nudge one task. Inputs: the persisted plan, the current time, the user's new input, completed and in-progress work, fixed events, remaining tasks, deadlines, the effective profile and observed behaviour. Output: a validated proposal plus a human-readable delta.

| # | Stage | Detail | Owner |
|---|---|---|---|
| 1 | trigger & auth | user taps Replan; request carries IANA zone and client clock | Flutter / server |
| 2 | load current state | day-relevance query (existing, shared with day view and Today) | server |
| 3 | classify | completed (immutable), in-progress (busy to `max(planned end, now)`), fixed/locked, missed, flexible, optional | planner partition (existing) |
| 4 | **understand the change** | hybrid *delta extraction* (R11): deterministic fast path for the known grammar; LLM only for everything else; **task references resolved to ids the server supplied** | deterministic + LLM |
| 5 | apply ops to planner **input** | ops never move times themselves | server (existing pattern) |
| 6 | feasibility | capacity after change; deadline slack; contradictions | server |
| 7 | plan | `plan(mode="replan")`: keep-if-valid + **stability-weighted re-optimisation** (below) | pure planner |
| 8 | validate | existing invariants + preservation (nothing lost / duplicated / invented) | server |
| 9 | delta | structured lines + counts (R12) | server (templates) |
| 10 | preview → confirm → apply | existing: server-authored apply request, `expected_updated_at`, 409/422, `plan_id` idempotency | existing |

**Stability-weighted re-optimisation [PROPOSED].** Today the planner keeps a flexible task where it is if valid and only moves what is invalid or displaced (minimal churn). That is right for small changes, but after a *large* change (an event cancelled, a task finished early, > 60 min late) freed time is not exploited. Add a movement-cost term (`λ` per moved task, larger for moves across the day) so the remaining flexible tasks are re-scored with the profile **only when the change category is "broad"**, and otherwise keep today's minimal-change behaviour. Completed, in-progress, locked and out-of-scope items are never touched.

### R11 — Replan intent extraction (delta operations)

| | |
|---|---|
| **CURRENT STATE** | Regex grammar (`parse_replan_instruction`) → one `ReplanOperation`; unrecognised text becomes `add_task`. No LLM. [VERIFIED] |
| **EVIDENCE** | §4.5 table; `calendar_service.py` |
| **PROBLEM** | Violates the brief's safety rule **"never invent a new task"**; cannot express "class got cancelled", "I finished early", "I can't go to the gym", deadline changes, multi-part messages. |
| **PROPOSED BEHAVIOR** | A **delta schema** — ops: `shift_remaining(minutes)`, `complete(ref)`, `cancel(ref)`, `skip_today(ref)`, `postpone(ref, until)`, `move(ref, day|time|window)`, `change_duration(ref, minutes)`, `change_deadline(ref, when)`, `event_cancelled(ref)`, `event_added(entity)`, `unavailable(window)`, `add_task(entity)`, `energy_state(low|normal)`; **multiple ops per message**. Flow: (1) deterministic fast path first (late N min, move X to day, cancel X, add task with explicit time) — no LLM, ~tens of ms; (2) otherwise one small LLM call whose prompt contains **only** the user's message and today's items as `{id, title, status, start, tier}` (≈ a few hundred tokens), returning ops that reference **ids**; (3) the server **validates every id belongs to this user and day**; (4) **unknown or ambiguous reference ⇒ `needs_input` question, never `add_task`**; `add_task` is allowed only when the message states a new activity and carries evidence. The LLM never proposes times; the planner does. |
| **WHY** | Covers the real vocabulary of a changing day while keeping the model out of correctness; id-based references remove title-matching ambiguity (today `cancel gym` with two gym tasks refuses; ids make it answerable). |
| **AFFECTED COMPONENTS** | new `replan_intent.py`; `calendar_service.parse_replan_instruction` (becomes the fast path); `ReplanOperation` schema; economy accounting for replan LLM calls (decision D5/D7) |
| **ACCEPTANCE CRITERIA** | The 8 messages of §4.5 produce the correct ops (`event_cancelled`, `skip_today`, `complete`, `change_deadline`, two ops for the compound message); **zero** invented tasks in the adversarial replan suite (§26); unknown reference ⇒ question; LLM unavailable ⇒ fast path still works and the rest returns "I couldn't understand that — try 'move X to tomorrow'" (never a fabricated task); no raw message in logs. |
| **RISK** | Cost/latency of an extra call → small prompt, only on fast-path miss; budget in §19. Mis-resolved reference → ids supplied by the server + confirmation preview (Replan is already a dry-run the user confirms). |

---

## 17. Replan delta experience

Return **what changed**, not only a new schedule. A compact, structured summary built **deterministically from the diff** (no LLM text, so no fake explanations).

```
Replan summary                                   3 moved · 1 day-moved · 1 unscheduled · 2 unchanged

 ↻  Backend bug      3:00 PM → 5:15 PM     to make room for your urgent client call
 →  DSA review       today → tomorrow      you asked to move it
 ⚠  Clean room       stays unscheduled     fitting it would push the assignment past its deadline
 🔒 Gym              6:00 PM  (unchanged)  fixed
 ✓  Assignment       done · kept as is
```

| Line kind | Template (user's zone/12-h time) | Reason source |
|---|---|---|
| `moved` | "{title} moved from {old} to {new}." | `reason_code` ∈ {`made_room_for(entity)`, `running_late(min)`, `slot_freed`, `missed`, `deadline_protection`, `user_request`} |
| `moved_day` | "{title} moved to {day}." | `user_request` / `no_capacity_today` |
| `kept_fixed` | "{title} stays at {time}." | lock source |
| `unscheduled` | "{title} remains unscheduled." + blocker clause | structured blocker (R5) |
| `completed_protected` | "{title} — done, left as is." | status |
| `conflict` | "{title} overlaps {title}; neither was moved." | planner conflict |
| `rolled_over` | "{title} proposed for {day} {time}." | planner suggestion (never auto-applied) |

### R12 — Delta summary

| | |
|---|---|
| **CURRENT STATE** | `PlanDiff` carries moved/new/unchanged/cancelled/unscheduled/protected lists, `conflicts[]` strings and one `explanation` sentence; Flutter renders sections. Reasons are generic ("Rescheduled around other tasks"). [VERIFIED `schemas/calendar.py`, `calendar_service._build_response`] |
| **EVIDENCE** | same |
| **PROBLEM** | The user cannot see *why* each item moved; the summary sentence is not per-item; "Before → After" is split across sections. |
| **PROPOSED BEHAVIOR** | Add `delta_lines[]` (`kind`, `task_id`, `before`, `after`, `reason_code`, `reason_refs[]`, `text`) and `counts`; reason codes are produced where the planner already knows the cause (displacement victim ↔ displacer; delay op; missed; freed capacity). Keep the existing diff fields for backward compatibility. |
| **WHY** | Builds trust that Replan understood the change; reasons are traceable to planner facts. |
| **AFFECTED COMPONENTS** | `planner.Placement`/`Unplaced` (cause fields), `calendar_service._build_response`, `PlanDiff` schema (additive), Flutter `plan_diff_view.dart` |
| **ACCEPTANCE CRITERIA** | Every moved/unscheduled item has exactly one delta line with a non-generic reason; counts equal the diff lists; text uses the user's zone; the line for a displaced task names the task that displaced it; existing diff tests unchanged. |
| **RISK** | Wrong attribution of cause → cause recorded at the decision point (displacement loop), covered by property tests. |

**Replan safety (unchanged and re-asserted):** never move completed tasks; never overlap; never beyond a hard deadline; never in the past; never violate fixed times; never lose or duplicate a task; **never invent a task or a preference**; every result passes deterministic validation **before** persistence. [VERIFIED for all but "invent" — which R11 closes]

---

## 18. AI / fallback strategy

### 18.1 States and what the user sees

| Condition | Behaviour | User message | What is retained |
|---|---|---|---|
| **AI available** | extraction v2 → full pipeline | none (optional "Planned with AI") | run metadata only |
| **AI slow (> soft budget 5 s)** | keep waiting to the hard budget; show progress stages | "Still organising…" | — |
| **AI timeout / provider error / quota / rate limit** | **conservative fallback** (R7) | "I couldn't use AI right now, so I kept your notes as written. Tap *Retry with AI* when you're ready." | raw text stays on the **device** (draft); server stores nothing unless the user opts in |
| **Schema-invalid AI output** | one bounded repair → else fallback | same | — |
| **Input too large** | `input_too_large` with limit | "That's longer than I can read at once (limit N). Split it in two?" | draft on device |
| **Offline** | fallback (device-side conservative parser) | "You're offline — here's your list as written." | draft on device |
| **DB failure at confirm** | transaction rolls back; preview stays open | "Couldn't save your plan. Nothing was changed. Try again." (same `plan_id`) | draft + plan on device |

### R7 — Safe, semantically conservative fallback

| | |
|---|---|
| **CURRENT STATE** | Regex clause splitter (server) + similar local parser (Flutter) → fragments (§4.1). Flutter decides AI-need heuristically and silently falls back on *any* error. [VERIFIED] |
| **EVIDENCE** | §4.1; `task_parse_service.dart:60`; `brain_dump_sheet.dart` `catch (_)` |
| **PROBLEM** | The fallback is the product for every user who runs out of AI quota or is offline, and it is the worst version: it invents tasks, orphans durations, and collapses/duplicates. |
| **PROPOSED BEHAVIOR** | **Preservation mode** (identical rules on server and Flutter, shared fixtures): (1) split **only** on hard separators — blank line, newline, bullets/numbering, semicolons; (2) inside a line, split on commas/"and" **only** when every part is a short noun/verb phrase (≤ 5 words, no clause of its own) — a *list*, e.g. "gym, groceries, laundry"; (3) split a sentence only when both sides have their own subject-plus-modal/verb ("…class at 12:40 **and I need to** leave home…"); (4) a sentence that starts with a dependent/anaphoric marker (*it, which, but, I'd like, preferably, around*) or has no verb of its own is an **attribute/note of the previous entity**, never a new entity; (5) instruction sentences ("Don't schedule…", "Prioritize…") become **global notes**, not tasks; (6) extract attributes only from high-confidence anchored patterns (`N minutes/hours`, `1.5 hours`, explicit `at 6 PM`, `by/before <time>`, `tomorrow/weekday`) and attach them to **their own entity**; (7) unknown duration is shown as *estimated*, unspecified priority stays unspecified; (8) output is flagged `degraded: true`, the preview shows the banner and a **Retry with AI** button, and a **Split** control lets the user separate an under-split row. *The fallback is allowed to under-split; it is never allowed to fragment or invent.* |
| **WHY** | A slightly coarser preview that preserves the user's meaning beats five fragments. The user is told plainly and can retry. |
| **AFFECTED COMPONENTS** | `ai_service._split_clauses`/`parse_task_dump` (behind a flag), `task_parse_service.dart` (same rules), shared `extraction_fixtures.json`, preview banner/Retry/Split |
| **ACCEPTANCE CRITERIA** | On the medium test: **≤ 1.3 × the gold entity count** (no fragmentation), no entity without a verb phrase or own title, every duration attached to its own entity, **zero** instruction-sentences-as-tasks, no duplicates; the six-intention no-punctuation dump becomes **one reviewable row with a "Split" affordance and the degraded banner** rather than silent mis-structuring; Flutter and server outputs identical on the shared fixtures. |
| **RISK** | Under-splitting frustrates → explicit Split action, Retry with AI, and prompt AI quota messaging; rule set tuned on the corpus (§25). |

### 18.2 Timeout, retry and charging policy [PROPOSED]

* **One time budget** owned by the server: soft 5 s, hard ≈ 9 s for extraction; the serial 3-model × 12 s chain is replaced by **one primary call** and a second model **only if the first fails fast** (HTTP error/429/5xx, not timeout). No further waiting after the hard budget.
* Flutter's plan request timeout becomes **20 s** with visible progress; all other endpoints stay at 12 s.
* **Late results**: if extraction finishes after the client gave up, store the result as `completed_late` for 15 minutes under the run id; the client may adopt it ("AI result ready — use it?"). *Optional; decision D6.*
* **Charging**: charge only for a result the user can use — on delivery (or adoption), not on extraction completion (today: after Gemini success regardless of delivery). *Decision D5.*
* Idempotency key reuse stays; two sequential usage-status calls collapse into the plan call (it already returns 402 with details).

---

## 19. Performance architecture

### 19.1 Where time goes today

| Stage | Today | Source |
|---|---|---|
| Flutter text → request | negligible | — |
| Two usage-status round trips | 2 × RTT (unmeasured) | `brain_dump_sheet.dart:131,184` [VERIFIED code] |
| Preprocess + consolidation + load + plan + persist | **< 150 ms combined** (SQLite) | §4.6 [VERIFIED] |
| **LLM extraction** | **unknown** — 12 k-char instruction prompt (~3 k tokens) + user text; free-form JSON; up to 3 serial attempts × 12 s; optional repair call | `ai_service.py` [VERIFIED structure; latency UNCERTAIN] |
| Flutter fallback + local engines | fast CPU | — |
| Flutter render | unmeasured | [UNCERTAIN] |

### 19.2 Targets [PROPOSED — to be ratified by Phase 0 measurements]

| Scenario | p50 | p95 | Notes |
|---|---|---|---|
| Normal Build My Day (≤ 4,000 chars, AI) | ≤ 4 s | ≤ 8 s | extraction ≤ 3.5 s p50; everything else ≤ 0.3 s |
| Large Build My Day (4,000–8,000 chars) | ≤ 7 s | ≤ 12 s | progress stages mandatory |
| Replan, deterministic fast path | ≤ 250 ms | ≤ 600 ms | measured server cost 15 ms (SQLite) + network |
| Replan, LLM-assisted | ≤ 2.5 s | ≤ 5 s | tiny prompt (ids + titles + message) |
| Fallback path (no AI) | ≤ 400 ms | ≤ 1 s | purely local/deterministic |
| Confirm | ≤ 300 ms | ≤ 500 ms | measured 34 ms server-side |
| Day view / Today | ≤ 200 ms | ≤ 300 ms | measured 20 ms server-side |

### R13 — Latency and timeout architecture

| | |
|---|---|
| **CURRENT STATE** | See §19.1. [VERIFIED / UNCERTAIN as marked] |
| **EVIDENCE** | §4.6 |
| **PROBLEM** | The only slow stage (LLM) is un-instrumented end-to-end, its timeouts do not compose with the client's, and its prompt is large. |
| **PROPOSED BEHAVIOR** | (1) **Measure first** (Phase 0): replay the corpus against the live model with a dedicated key, record per-stage timings; also mine the existing `ai_service.gemini_ok … latency_ms input_tokens output_tokens` log lines. (2) Shrink the instruction prompt to ≤ 4 k chars (structured schema carries the field definitions) and verify quality does not drop on the corpus. (3) Response schema + `maxOutputTokens` to remove the repair call in the common case. (4) Single time budget (§18.2). (5) Merge the usage-status checks into the plan call. (6) Cache the **effective profile** per user (key = profile version + stats `updated_at`, TTL 5 min). (7) Load profile/calendar/tasks as one batched read. (8) Keep deterministic scheduling server-side and unchanged; do **not** sacrifice quality (no model downgrade) to save milliseconds unless the corpus shows no loss. (9) **Streaming only if** Phase 0 shows p95 above target: send stage events (`reading → organising → planning`) over SSE; otherwise a staged client animation suffices. (10) Add per-stage timings to the structured diagnostics (§20). |
| **WHY** | Optimising what is not slow wastes effort; optimising what is slow without measuring risks quality. |
| **AFFECTED COMPONENTS** | `ai_service`/new extractor, `routes/ai.py`, `api_service.dart` (timeouts), `brain_dump_sheet.dart` (single usage call, progress), profile cache, diagnostics |
| **ACCEPTANCE CRITERIA** | Phase 0 produces a table of real per-stage p50/p95 for the corpus; after the work the §19.2 targets hold on that corpus (or the targets are revised with evidence); no request path can exceed the stated hard budget plus network; fallback p95 ≤ 1 s. |
| **RISK** | Provider variance and quota → targets are stated as p50/p95 on a recorded corpus, re-measured per release, with the fallback as the guaranteed floor. |

---

## 20. Observability

Goal: be able to answer *why* — for AI use, fallback, boundaries, placement, unscheduling, Replan moves and latency — **without logging what the user wrote**.

### R14 — Structured diagnostics

| | |
|---|---|
| **CURRENT STATE** | Free-text log lines with request id, model, error class, latency and token counts for Gemini calls; `parse_task_dump` logs path and candidate count; planner results carry `primary_reason`/`secondary_reasons`. No per-run record, no stage timings, no boundary or placement reasons retained. [VERIFIED `ai_service.py:447-516, 1110-1116`] |
| **EVIDENCE** | same; raw text is not logged by any statement found by grep [VERIFIED] |
| **PROBLEM** | Questions like "why did this request become slow", "why was this task not split", "which constraint forced 5:15 PM" cannot be answered after the fact. |
| **PROPOSED BEHAVIOR** | One structured **run record** per Build My Day / Replan request (JSON log line + the `brain_dump_runs` row, §21) with the fields below, a registry of reason codes, and a user-scoped **"Why?"** endpoint that returns the stored reasons for *that user's own* entities. |
| **WHY** | Diagnosability and trust; also the data source for the quality dashboard and for Phase 0/7 measurements. |
| **AFFECTED COMPONENTS** | new `diagnostics.py`; `routes/ai.py`, `calendar_service`, `plan_confirm_service`; `brain_dump_runs`; admin view |
| **ACCEPTANCE CRITERIA** | A test asserts every question in the table is answerable from a run record; a scrubber test fails the build if any log line or run record contains a user title/raw text (canary strings in fixtures); stage timings sum to within 5 % of total latency. |
| **RISK** | Over-collection → fields are codes, ids, hashes, counts and timings only; sampling raw text is **off** and would need explicit opt-in (decision D9). |

| Question | Field(s) | Values / source |
|---|---|---|
| Why was AI used? | `ai_decision.used`, `.reason` | `prose`, `size`, `ambiguity`, `forced`, `list_like_no_ai` |
| Why was fallback used? | `fallback.used`, `.reason` | `timeout`, `provider_error`, `rate_limit`, `quota`, `schema_invalid`, `coverage_fail`, `offline`, `too_large` |
| Why did extraction fail? | `error_class`, `repair_attempted` | existing classes (`timeout`, `network`, `auth`, `bad_request`, `model_unavailable`, `rate_limit`, `server_error`, `http_N`) |
| Why was a task split / not split? | per entity `boundary` | AI: enum `one_intention_with_attributes · separate_intention · list_item · continuation_attribute`; fallback: **rule id** (e.g. `R-sep-newline`, `R-attr-anaphora`) |
| Why was it scheduled here? | per placement `contributions[]` | `(code, delta, input_ref)` from R10 |
| Which constraint forced this time? | `forced_by[]` | counterfactual result (R10) |
| Which profile signal influenced it? | contribution `input_ref` | `signal_key`, `level` (reported/observed), `weight`, `stage` |
| Why unscheduled? | `blocker` | `{code, blocking_entity_ids[], constraint_id}` (R5) |
| Why did Replan move a task? | delta `reason_code` | R12 registry |
| Why is the request slow / which stage? | `stage_timings_ms` | the 17 stages of §15 |
| Was anything lost? | `ledger` counts | I3 balance |

---

## 21. Persistence / data model

All **additive** — new tables only, no ALTER of existing tables, no changes to `tasks`. Every table carries `user_id` and is deleted with the user (`ON DELETE CASCADE`). **No raw brain-dump text is stored.**

| Table | Purpose | Key columns | Retention |
|---|---|---|---|
| `brain_dump_runs` | one row per extraction | `id`, `user_id`*, `created_at`, `input_hash`, `input_chars`, `extractor_version`, `mode` (`ai`/`degraded`), `ai_status`, `fallback_reason`, `entity_count`, `unresolved_count`, `placed_count`, `unscheduled_count`, `timings_json`, `status` (`preview`/`confirmed`/`abandoned`), `plan_id` | 90 days |
| `brain_dump_entities` | the ledger | PK(`run_id`,`entity_id`), `user_id`*, `kind`, `attached_to`, `span_start`, `span_end` (offsets into the text the **client** holds), `outcome`, `reason_code`, `tier`, `optionality`, `merged_into`, `task_id` (nullable, `SET NULL`) | 90 days |
| `task_planning_meta` | attributes tasks cannot carry | PK `task_id` (cascade), `user_id`*, `optionality`, `min_minutes`, `energy_demand`, `energy_condition`, `prep_minutes`, `travel_minutes`, `leave_by`, `preferences_json`, `notes`, `source_run_id`, `source_entity_id` | with the task |
| `plan_events` | append-only behaviour log (§12.1) | `id`, `user_id`*, `task_id`, `event_type`, `occurred_at`*, planned/actual start/end/minutes, `context_json`, `source`, `run_id` | 18 months raw, then aggregated into stats |
| `user_profile_signals` | reported vs. observed per signal | PK(`user_id`,`signal_key`), `reported_value`, `observed_value`, `observed_n`, `observed_days`, `confidence`, `updated_at`, `version` | until reset/deletion |
| `user_behavior_stats` | **derived**, rebuildable from `plan_events` | PK(`user_id`,`stat_key`,`dims`), `n`, `value`, `spread`, `updated_at` | rebuilt |

`*` = indexed. Existing `plan_applications` (idempotency) is unchanged; `task_planning_meta.source_run_id` links a confirmed task back to its run so *"what happened to this part of my dump?"* is answerable (I6).

**Migrations.** Two revisions, `007_brain_dump_runs_entities_meta` and `008_events_signals_stats` — each creates tables only and is trivially reversible (`DROP TABLE`). They inherit the open **D4 blocker** (production schema bootstrap is not evidenced in the repository — `build-my-day-replan.md` §11.1) and must pass the PostgreSQL gates (§24) before any shared/production database sees them. JSON columns use the SQLAlchemy `JSON` type (SQLite text / PostgreSQL JSON); PostgreSQL behaviour is **[UNCERTAIN] until gated**.

### R15 — Persistence of ledger, planning meta and events

| | |
|---|---|
| **CURRENT STATE** | `tasks` (+ `time_locked`, `planned_date`), `plan_applications`, `task_performance`, `readiness_observations`, `recommendation_*`. [VERIFIED] |
| **EVIDENCE** | `models/` |
| **PROBLEM** | No place to keep what extraction found beyond the task row; no link from a task to the dump that produced it; no behaviour log independent of feedback. |
| **PROPOSED BEHAVIOR** | The six tables above, written in the **same transaction** as the plan (ledger + meta with confirm) or at the existing event points (events). |
| **WHY** | Traceability and learning without storing private text; additive and reversible. |
| **AFFECTED COMPONENTS** | new models + migrations; `plan_confirm_service`; `behavior_service`; hooks listed in R9 |
| **ACCEPTANCE CRITERIA** | Confirm persists tasks + meta + ledger atomically (rollback test: failure in any leaves none); deleting a user removes everything; `user_behavior_stats` equals a from-scratch rebuild of `plan_events`; schema contains no column that can hold raw text except `task_planning_meta.notes` (task content the user owns). |
| **RISK** | Table growth → retention jobs; PG index/volume behaviour [UNCERTAIN] → gate G9. |

---

## 22. Security and user isolation

| Check | Status | Evidence / action |
|---|---|---|
| Authentication on every planning route | **[VERIFIED]** `Depends(get_current_user)` on `/ai/*`, `/calendar/*`, `/tasks/*`, `/today/*` | keep |
| `user_id` filtering in repositories/services | **[VERIFIED]** `TaskRepository.*`, `calendar_service` queries, `plan_applications` PK includes `user_id` | new tables must follow; add a static test that every new model has `user_id` and every query filters it |
| Task / plan isolation tests | **[VERIFIED]** `test_user_isolation.py`, E2E-C, replan/apply cross-user cases | extend to profile, events, stats, ledger |
| Profile isolation | **[MISSING]** (no per-user signal tables yet) | R8 tests |
| Behaviour-data isolation; **no cross-user personalization** | **[PROPOSED]** priors are static product defaults, never other users' data; any future population prior must be opt-in and k-anonymous | isolation property test: A's events never change B's output |
| Row-Level Security | **[MISSING]** in the repository (no policies/SQL); how production connects (service role vs. user role) is **[UNCERTAIN]** | decision D10: either rely on application-level scoping + tests, or add RLS policies as defence-in-depth for the *new* tables (requires the D4 facts) |
| Raw brain dump in logs | **[VERIFIED]** none by grep; Gemini failure logs only the error class/message | add the canary-string scrubber test (R14) |
| Raw text sent to a third party | **[VERIFIED]** to Gemini; Flutter shows a privacy disclosure before first use (`checkAndShowGeminiPrivacyDisclosure`) | keep; state retention (none server-side) in the disclosure |
| Prompt injection | **[VERIFIED]** raw text is interpolated into the instruction prompt in quotes | R1: delimited data block + schema-validated output + **ownership check of every id** the model returns (Replan) + the model never writes to the database |
| Idempotency cache retention | **[MISSING]** `ai_planning_requests.response_json` has no TTL found | purge after 24 h |
| Rate limiting | **[VERIFIED]** AI 5/h per user is **in-process** (not shared across workers) | move to a shared store before multi-worker production |
| Admin routes | **[UNCERTAIN]** `routes/admin.py` exists; authorization was not audited here | audit before exposing diagnostics |
| Account deletion covers new tables | **[UNCERTAIN]** an account-purge page/endpoint exists (`app/main.py` ~lines 270–398) and states that tasks, preferences, focus logs and companion data are purged; whether it removes rows by FK cascade or explicit deletes was not audited | every new table has `ON DELETE CASCADE` on `user_id`; add a test that deleting a user leaves no row in any new table |
| Minimising raw text retention | **[PROPOSED]** server keeps hash + length + counts only; raw text lives on the device; optional server retention only as an explicit opt-in "retry later" with a 24 h TTL (D9) | R14/R15 |

### R16 — Privacy-preserving diagnostics and isolation guarantees

| | |
|---|---|
| **CURRENT STATE** | Strong application-level scoping; no RLS; no retention policy for derived AI payloads. [VERIFIED/MISSING] |
| **EVIDENCE** | table above |
| **PROBLEM** | New behaviour/profile data increases the privacy surface; a scoping bug would now expose *learned characteristics* of a person, not only tasks. |
| **PROPOSED BEHAVIOR** | The checks above; a single `scoped_query(user)` helper for new tables; canary-string tests; TTL purge; "export my data" and "reset what Flowstate learned" endpoints. |
| **WHY** | Learned data is sensitive; guarantees must be tested, not assumed. |
| **AFFECTED COMPONENTS** | new repositories/services, tests, retention job, settings UI |
| **ACCEPTANCE CRITERIA** | Isolation suite for each new table passes; canary test passes; reset deletes observed signals/stats and the next plan equals the questionnaire-only plan; no table other than `task_planning_meta.notes` can store free text. |
| **RISK** | RLS decision deferred → application-level tests are the control until D10 is decided. |

---

## 23. Flutter ↔ backend contract

### 23.1 Build My Day response (v2, additive; v1 `tasks[]` kept for installed clients)

```jsonc
{
  "schema_version": 2,
  "run_id": "run_…",
  "mode": "ai" | "degraded",                    // degraded => show banner + Retry with AI
  "timezone_used": "Asia/Kolkata",
  "summary": { "entities": 8, "placed": 7, "unscheduled": 1, "needs_input": 0, "merged": 0 },
  "entities": [ {
      "id": "e3", "kind": "task" | "event" | "attached",
      "title": "Finish machine learning assignment",
      "tier": "REQUIRED", "optionality": "required",
      "outcome": "placed" | "unscheduled" | "merged" | "needs_input",
      "time": { "start": "…Z", "end": "…Z", "locked": false },
      "attributes": { "duration": {"minutes": 90, "source": "explicit", "approx": true},
                      "deadline": {"at": "…Z", "hard": true},
                      "preferences": [ {"kind": "energy", "label": "when mentally fresh"} ] },
      "reason": "Before your 11 AM deadline (due tomorrow).",       // null when no real contribution
      "unscheduled": { "reason_code": "blocked", "blocker": {"entity_ids": ["e3"], "text": "…"} }
  } ],
  "blocks": [ {"kind": "travel", "attached_to": "e1", "start": "…", "end": "…", "label": "Leave home"} ],
  "unresolved": [ {"id": "q1", "question": "…", "options": ["Add as task", "Ignore"]} ],
  "conflicts": [ … ],
  "tasks": [ … v1 shape … ]
}
```
Errors are structured (`code`, `message` safe to display): `input_too_large {limit,length}`, `empty_input`, `ai_unavailable` (carries `fallback` payload, **not** an error screen), `quota_required`, plus the existing `validation_failed` at confirm. **The client must never convert a validation error into "AI unavailable".**

Confirm request gains `run_id` and per-item `entity_id`; the server writes the ledger and `task_planning_meta` in the same transaction as the tasks (existing atomic/idempotent flow).

Replan response gains `delta_lines[]`, `counts`, and optional `needs_input` (`{question, options}`) when a reference is ambiguous.

### 23.2 Flutter experience

| Surface | Change |
|---|---|
| Input | live character counter from ~3,000 chars; clear limit message; draft persisted locally; one usage check (inside the plan call) |
| Waiting | staged progress ("Reading your notes → Organising → Planning your day") instead of a blind spinner; cancel keeps the draft |
| Preview | top line with counts; **Fixed** (class, events, travel blocks) · **Your plan** (timeline with time, duration, locked/flexible, one-line reason) · **Flexible / optional** · **Couldn't fit** (with the blocker sentence) · **Needs your input**; "Everything I heard" expandable; degraded banner + **Retry with AI** + **Split** |
| Edit | unchanged editing; edits re-validated server-side at confirm |
| Replan | delta lines under the new schedule; questions when something is ambiguous |
| Insights | only stage-gated statements (§12.5) |

### 23.3 Parity rules

* The **server planner is authoritative**. The Dart engine remains a preview/offline helper and must not overwrite a server slot (already true for tasks with a server slot [VERIFIED `enrichTasksWithOptimalSlots`]).
* Shared **JSON fixtures** keep implementations honest: `scheduling_contract_cases.json` (exists [VERIFIED]); new `extraction_fixtures.json` for the preservation-mode parser; new JSON-Schema files for the v2 response consumed by both a Python contract test and a Dart test.
* The Dart conservative parser is a **port of the same rules** with identical fixtures, replacing the current local splitter.

### R17 — v2 contract and preview

| | |
|---|---|
| **CURRENT STATE** | v1 `tasks[]` + `planning_context`; preview renders cards from tasks; no summary/ledger/blocks/questions/degraded flag. [VERIFIED] |
| **EVIDENCE** | `schemas/ai.py`, `brain_dump_sheet.dart`, `ai_plan_models.dart` |
| **PROBLEM** | The UI can only show "tasks", so even a perfect backend would look like AI JSON turned into cards. |
| **PROPOSED BEHAVIOR** | §23.1–23.3. |
| **WHY** | Presents understanding, preservation, fixed-vs-flexible and reasons — the product value — in a scannable way. |
| **AFFECTED COMPONENTS** | `schemas/ai.py`, `routes/ai.py`, `ai_plan_models.dart`, `brain_dump_sheet.dart`, `plan_diff_view.dart`, tests |
| **ACCEPTANCE CRITERIA** | v1 clients keep working against v2 (contract test); the preview for the medium test shows counts that balance (I3), a visible "Leave home 11:50" block, each reason either present-and-true or absent; widget tests for degraded, overload and needs-input states; **Flutter tests actually run and pass** (release gate F1). |
| **RISK** | UI scope creep → phase the UI with the backend (§27); keep the existing card list as the fallback renderer. |

---

## 24. PostgreSQL and parity — production gates

**No production-readiness claim is made or implied by this specification.** The following are release gates; each needs an executed result recorded in the repository. Items G1–G7 are inherited from `build-my-day-replan.md` §18 (all **not yet run**).

| Gate | Requirement | Status |
|---|---|---|
| **G1** | full backend suite passes on a disposable PostgreSQL DB (`FLOWSTATE_TEST_DATABASE_URL`) | not run [UNCERTAIN] |
| **G2** | `UTCDateTime` round-trip and day-bound queries identical to SQLite | not run |
| **G3** | native enum labels match backfill/predicate strings | not run |
| **G4** | `ORDER BY priority` semantics (PG enum order vs SQLite text) reviewed | not run |
| **G5** | `alembic upgrade head` from the real production state; backfill report reviewed; downgrade rehearsed (**blocked on D4 facts**) | blocked |
| **G6** | cross-process idempotency (`plan_id`) | not run |
| **G7** | tzdata present on server and DB | not run |
| **G8** *(new)* | JSON columns (`timings_json`, `context_json`, `preferences_json`) behave identically (types, null handling, size) | not run |
| **G9** *(new)* | `plan_events` / `brain_dump_entities` indexes and query plans at ≥ 1 M events per 10 k users; stats rebuild time | not run |
| **G10** *(new)* | concurrent `plan_events` inserts and stats rebuild under load | not run |
| **G11** *(new, if RLS adopted)* | policies enforce `user_id` for every new table with the real connection role | not designed |
| **F1** | `flutter test` passes (currently **cannot run** in the development shell — Windows Application Control) | **not run** |
| **F2** | `scheduling_contract_fixtures_test.dart` agrees with the backend planner (written, unrun) | not run |
| **F3** *(new)* | `extraction_fixtures.json` parity between server and Dart preservation-mode parser | not built |
| **F4** *(new)* | `TimezoneService` returns the true IANA zone on real Android/iOS devices | not run |
| **F5** *(new)* | widget tests for preview v2 states | not built |
| **M1** | every migration reviewed and rehearsed on a copy before any shared DB | process |
| **L1** *(new)* | live-LLM evaluation on the gold corpus meets the §25 thresholds | not run |

---

### R18 — Verification gates before any production-readiness claim

| | |
|---|---|
| **CURRENT STATE** | SQLite-only test runs; a PostgreSQL mode exists in `tests/conftest.py` (`FLOWSTATE_TEST_DATABASE_URL`) but has **never been executed**; Flutter tests exist but cannot run in the development shell; no CI configuration in the repository. [VERIFIED / MISSING] |
| **EVIDENCE** | `backend/tests/conftest.py`; Flutter tool blocked by Windows Application Control; `git ls-files` shows no CI workflow |
| **PROBLEM** | Production readiness would otherwise be asserted from SQLite-only evidence and unrun client tests. |
| **PROPOSED BEHAVIOR** | The gates table above is a **release checklist**: each gate has an owner, a command, and a recorded result committed to the repository; production migrations are blocked until M1/D14 are satisfied; the build-my-day feature may not be described as "production ready" in any document until all gates are green. |
| **WHY** | The previous work already had unverified surfaces; this makes the gap explicit and enforceable. |
| **AFFECTED COMPONENTS** | CI configuration (new), `tests/conftest.py`, Flutter test environment, release checklist |
| **ACCEPTANCE CRITERIA** | A committed results file lists every gate with date, environment and pass/fail; a failing or missing gate blocks release. |
| **RISK** | Environment access (PostgreSQL instance, Flutter toolchain) → Phase 8 owns provisioning. |

---

## 25. Test architecture

| Layer | Proves | Examples | Runs |
|---|---|---|---|
| **Unit** | each deterministic function | duration/quote normalisation, date-expression resolver, dedupe, coverage, tier assignment, preservation-mode rules, delta templates | every commit |
| **Property / fuzz** | invariants over generated inputs | existing planner dimensions + tiers, optionality, travel blocks, min-duration; preservation (I1–I3) for random *mock* extractions; fallback never fragments (output entity count ≤ lines × 1.3); no raw text in logs | every commit |
| **Contract** | wire shapes | JSON-Schema for v2 response; v1 compatibility; error codes | every commit |
| **Recorded-response (VCR)** | pipeline correctness against *fixed* model outputs | for each corpus item a recorded Gemini response → expected entities/plan | every commit (deterministic) |
| **Live evaluation (L1)** | actual model quality/latency | corpus replayed against the real model with a dedicated key and budget | nightly / pre-release, **not** in the unit run |
| **Isolation** | no cross-user leakage | profile, events, stats, ledger, runs; account switching | every commit |
| **Fault injection** | graceful degradation | AI timeout, provider 5xx/429, malformed JSON, DB failure mid-confirm, process restart, duplicate submit | every commit |
| **Performance regression** | budgets | planner 60 tasks ≤ 100 ms; `/ai/plan` with stubbed extraction ≤ 150 ms (CI box); fallback ≤ 50 ms for 8 k chars | every commit |
| **E2E** | the loop | extend A–D scenarios with ledger, degraded mode, replan natural language | every commit |
| **Flutter** | UI states and parity | widget, fixture-parity, timezone | release gate F1–F5 |
| **PostgreSQL** | production behaviour | G1–G11 | release gate |

### 25.1 Evaluation corpus and metrics

* **Corpus (synthetic or consented only — never real user data):** ≥ 120 dumps: 20 clean, 30 messy, 20 long (3–8 k chars), 20 adversarial, 15 contradiction/correction, 15 mixed-language/slang (decision D11). Each is annotated with gold entities, attributes, boundaries and expected outcomes; a second annotator reviews a 20 % sample.
* **Metrics and release thresholds (proposed):**

| Metric | Threshold |
|---|---|
| Boundary accuracy (entities correctly delimited) | ≥ 95 % AI, ≥ 85 % fallback |
| Over-split rate / fragment rate | ≤ 3 % AI; **fallback ≤ 1.3 × gold count** |
| Attribute accuracy (duration, deadline, fixed time) | ≥ 95 % where stated explicitly |
| **Preservation rate** (actionable sentences accounted for) | **100 %** |
| **Fabricated-entity rate** | **0 %** |
| Invariant violations in produced plans | **0** |
| Explanation fidelity (every shown reason maps to a recorded contribution) | **100 %** |
| Latency | §19.2 targets on the corpus |

---

## 26. Acceptance suite

### 26.1 The medium test — gold annotation

Input: the 8-paragraph text in the product brief (954 characters). "Tomorrow" in the first sentence sets the planned day for the whole dump.

| Gold entity | Ledger kind | Attributes that must survive (with source) | Tier | Outcome expected |
|---|---|---|---|---|
| **Class** | `event` | fixed 12:40 PM tomorrow (explicit → locked); duration not stated → **default 60 min, shown as assumed** | FIXED | placed, locked |
| **Leave home** | `attached(travel)` of Class | `leave_by` 11:50 AM (explicit); implied travel ≈ 50 min (derived from two explicit times) | FIXED | **visible block** on the timeline; nothing scheduled inside it |
| **Machine learning assignment** | `task` | duration 90 min (explicit, approximate); hard deadline 11:00 AM on the planned day (explicit "before 11 AM"); context "needs to submit it tomorrow" (note + importance evidence); optionality *required* | REQUIRED, rank 1 | placed; **ends ≤ 11:00** |
| **Fix backend authentication bug** | `task` | duration 120 min (explicit, approximate); energy condition "when mentally fresh" (soft preference, explicit); rank 3 | REQUIRED (user rank ≤ 3) | placed in the best available focus window |
| **Gym** | `task` | **"around 6 PM" ⇒ preferred 18:00, NOT locked**; duration 60 min (explicit); rank 4; buffers around gym (global instruction; amounts assumed and labelled) | HIGH | placed within ±45 min of 18:00 if feasible; **never locked** |
| **Review DSA** | `task` | **minimum** 45 min (explicit); soft preference "earlier in the day"; "can be moved" ⇒ flexible; rank 5 | HIGH | placed; earlier preferred *when feasible* |
| **Call mom** | `task` | 15 min (explicit); soft window "evening" | FLEXIBLE | placed in the evening |
| **Clean room** | `task` | 30 min (explicit); **optional**, low priority, "can be skipped" | OPTIONAL | placed if room; first to be unscheduled under overload |
| *global* | `global_instruction` ×3 | no overlap; buffers around class and gym; **priority order** assignment > class > backend bug > gym > DSA | — | applied (rank / buffers) and shown in the ledger |

**Acceptance conditions (all must hold):**

1. **One intention = one entity.** Exactly 8 ledger entities (7 + the attached travel block) and 3 global instructions; no orphan fragments; no instruction-sentence became a task.
2. Every constraint above is preserved with its source and evidence quote; the model is **not** required to reproduce these titles.
3. **Ledger balances** (I3) and `unresolved` is empty or contains only questions the text genuinely leaves open.
4. **No overlaps; nothing in the past; assignment ends by 11:00; Class exactly 12:40; no task inside the 11:50–12:40 leave/travel block; gym not locked.**
5. Every shown reason corresponds to a real input or profile signal; none for items without one.
6. **Overload variant** (add ≥ 6 h of required work): FIXED and REQUIRED are kept, **Clean room is unscheduled first**, with a blocker sentence naming the entities that displaced it; nothing disappears.
7. **Fallback variant (AI disabled):** ≤ 10 entities, durations attached to their own entities, no fragments, degraded banner + Retry with AI shown.
8. **Replan variants:** "Class got cancelled" → Class removed, travel block removed, freed time may be used by remaining flexible items (stability-weighted), **no new task**; "I finished the assignment early" → assignment completed, slot released; "I can't go to the gym anymore" → gym skipped today, not invented; "running 30 minutes late" → remaining flexible items shift, fixed items and completed work untouched; each with a delta summary.

*An illustrative feasible plan* (**not** a golden time — wake 07:00, warm-up 30 min, defaults assumed): 07:30–09:00 ML assignment · 09:15–11:15 backend bug · 11:50 leave home · 12:40–13:40 Class · 14:15–15:00 DSA (earlier slots were needed for the REQUIRED work — *"Moved DSA later to protect the assignment deadline"*) · 18:00–19:00 Gym (buffers around it) · 19:30–19:45 Call mom · 20:15–20:45 Clean room (optional).

### 26.2 Adversarial matrix

Each row is a test family (input class → expected behaviour → layer). **Preservation (I1–I3) and zero fabrication are asserted on every row.**

| ID | Class | Expected behaviour | Layer |
|---|---|---|---|
| A01 | very long dump (7.5 k chars, ~25 intentions) | accepted; all accounted for; latency within §19.2 | VCR + live |
| A02 | dump over the hard cap (8,001 chars) | `input_too_large {limit,length}`; UI offers split; **not** "AI unavailable" | contract + widget |
| A03 | no punctuation, six intentions | six entities (AI) / one reviewable row + banner + Split (fallback); never one fused mis-structured task | VCR + fallback fixtures |
| A04 | punctuation everywhere, ellipses, emoji | same entity count as the clean version | VCR |
| A05 | several tasks in one paragraph | one entity per intention | VCR |
| A06 | one task described over several sentences | **one** entity with merged attributes (3 brief examples) | VCR + live |
| A07 | typos ("finsih ml assignmnt before 11am") | same as corrected text | live |
| A08 | contradictory constraints | named conflict + question, no silent loss, no 500 | unit + VCR |
| A09 | multiple deadlines on different tasks | each deadline on its own task; tiers by slack | unit |
| A10 | relative dates (tomorrow, next Friday, in 3 days) | resolved by the server in the user's zone, DST-safe | unit |
| A11 | exact dates and past dates | past explicit time rejected with the existing user-safe error | unit |
| A12 | approximate times ("around", "sometime") | soft preference, **never locked** | unit |
| A13 | dependencies ("after the report", "before class") | ordering edges by id; cycle → conflict | property |
| A14 | optional tasks ("if I have time") | OPTIONAL tier; first shed | property |
| A15 | very overloaded day | buckets + blockers; nothing disappears | property + e2e |
| A16 | duplicate intentions ("call mom … also call mom") | merged with `merge_reason` | unit |
| A17 | repeated corrections / "actually…" | superseded entity not scheduled, recorded | VCR |
| A18 | "preferably…", "if possible…" | soft preference / optionality attributes | VCR |
| A19 | "I forgot…" appended at the end | extracted as an entity, not dropped | VCR |
| A20 | very long single-task description | one entity; notes preserved; title concise | VCR |
| A21 | very short ("gym") | one entity; defaults labelled as assumed | unit |
| A22 | invalid times ("at 25", "13pm") | question/validation, never a crash | unit |
| A23 | extreme durations ("20 hours", "1 minute") | validation question, never silently clamped | unit |
| A24 | empty / whitespace input | `empty_input`, no model call | unit |
| A25 | prompt-injection text inside the dump ("ignore previous instructions…") | treated as data; no behaviour change; output schema-validated | live + VCR |
| A26 | AI timeout | degraded preview ≤ 1 s after the hard budget; draft kept; Retry works | fault injection |
| A27 | AI provider failure (5xx/429/auth) | same; no charge for undelivered result | fault injection |
| A28 | malformed/non-schema AI output | one repair → fallback; never partial garbage | fault injection |
| A29 | database failure mid-confirm | rollback, preview intact, retry with same `plan_id` creates once | fault injection |
| A30 | app restart between preview and confirm | draft restored; confirm idempotent | e2e + Flutter |
| A31 | account switching | A's draft/profile/events invisible to B; A restored intact | isolation + e2e |
| A32 | duplicate submit / double tap | one result (existing idempotency) | e2e |
| A33 | Replan: natural statements (§4.5 table) | correct ops; **zero invented tasks**; unknown reference → question | VCR + unit |
| A34 | Replan: compound message | both ops applied | unit |
| A35 | Replan with AI down | fast path works; otherwise helpful message, no fabricated task | fault injection |
| A36 | learning cold start | output equals the questionnaire-only plan (byte-identical) | golden |
| A37 | one unusual day of behaviour | no signal moves beyond the step cap | property |
| A38 | fabricated feedback removed | completion without feedback records timing only | Flutter + unit |
| A39 | explanation fidelity | every reason maps to a recorded contribution | property |
| A40 | logs/run records | canary strings never appear | scrubber |

**Semantic-preservation property (universal):** for every generated or recorded run, *every actionable input sentence is covered by an entity or an `unresolved` item, every entity has exactly one outcome, and counts balance* — across AI, fallback and every fault-injection row.

---

## 27. Implementation phases

Principles: **no rewrite**; each phase ships behind a flag and is independently revertible; each phase has measurable acceptance criteria; the existing planner, persistence and timezone machinery are extended, never replaced. Phase 0 is not in the brief's list but is a prerequisite: without a measured baseline "better" cannot be shown.

```
Phase 0 (baseline) ──► 1 (extraction) ──► 2 (normalisation) ──► 3 (profile) ──► 4 (observation) ──► 5 (personalised scheduling)
                              └──────────────► 6 (Replan intelligence; safety patch ships with Phase 1)
                                         7 (latency, measurement-driven) ──► 8 (PG + Flutter parity) ──► 9 (production acceptance)
```

Flags (all default **off** until their phase's acceptance passes): `BMD_EXTRACTION_V2`, `BMD_FALLBACK_PRESERVE`, `BMD_LEDGER`, `PROFILE_EFFECTIVE`, `LEARNING_STAGE_MAX`, `REPLAN_LLM_DELTA`.

### Phase 0 — Baseline, corpus and measurement

| | |
|---|---|
| **Scope** | gold corpus (start with 50 dumps, grow to ≥ 120), evaluation harness, live-latency harness, log mining, input-length/telemetry counters |
| **Files likely affected** | new `backend/tests/eval/` (corpus JSON + runner), new `backend/scripts/measure_build_my_day.py`, `core/diagnostics.py` (skeleton), no runtime behaviour change |
| **Dependencies** | a dedicated Gemini key and an agreed spend cap (**user decision**) |
| **Tests** | harness self-tests; corpus schema validation; the v1 extractor scored on the corpus to establish the baseline |
| **Risks** | spend; corpus bias → synthetic + hand-written messy cases, second-annotator sample |
| **Rollback** | delete scripts; nothing in the request path changes |
| **Acceptance** | a report with real per-stage p50/p95 and token counts; v1 baseline metrics (§25.1) on the corpus; a ratified or revised §19.2 target table; answers to every **[UNCERTAIN]** about LLM latency/quality |

### Phase 1 — Semantic extraction reliability

| | |
|---|---|
| **Scope** | R1 intent-graph extraction, R2 coverage + `unresolved`, R6 input limit (1,500 → 8,000 with structured error and counter), R7 server-side preservation-mode fallback, time-budget (§18.2), merge usage-status into the plan call, **Replan safety patch** (unrecognised text ⇒ clarification, never `add_task`; no LLM needed) |
| **Files likely affected** | new `services/brain_dump_extractor.py`; `services/ai_service.py` (v1 behind flag); `schemas/ai.py`, `schemas/task.py`; `routes/ai.py`; `services/calendar_service.parse_replan_instruction`; Flutter `ai_plan_service.dart`, `brain_dump_sheet.dart` (counter, error mapping, degraded banner), `task_parse_service.dart` (port of preservation rules) |
| **Dependencies** | Phase 0 corpus and harness |
| **Tests** | unit (normaliser, coverage, rules), VCR recorded responses, fault injection (A26–A28), property (preservation), contract (v1 compatibility), shared `extraction_fixtures.json` |
| **Risks** | model variance and provider structured-output quirks; under-splitting in fallback frustrating users |
| **Rollback** | `BMD_EXTRACTION_V2=off` and `BMD_FALLBACK_PRESERVE=off` restore v1 behaviour exactly; the Replan safety patch is a strict improvement and stays |
| **Acceptance** | §25.1 AI thresholds met on the corpus; medium test: one entity per intention, fallback ≤ 1.3 × gold; 0 fabricated entities; 100 % preservation; no HTTP 500 on any adversarial input; no input-size error shown as AI outage |

### Phase 2 — Task / constraint normalisation and the entity model

| | |
|---|---|
| **Scope** | R3 entity model, R4 constraints/contradictions/supersession/global instructions, R5 tiers + optionality + blockers, attached travel/prep blocks, ledger persistence (migration 007), confirm links tasks to entities |
| **Files likely affected** | `engines/planner.py` (optional `PlanItem` fields, ordering/shedding, `Unplaced.blocker`), `services/planning_service.py`, new models + `alembic/versions/007_…`, `plan_confirm_service.py`, `schemas/task.py` (optional fields), Flutter preview models |
| **Dependencies** | Phase 1 |
| **Tests** | **all 1,160 existing tests unchanged**; extended planner property suite (tiers, optionality, min duration, travel blocks); counterfactual blocker tests; migration tests; isolation tests; PG gates G8–G9 for the new tables |
| **Risks** | planner churn; scope creep into scoring |
| **Rollback** | new fields optional/neutral; flag off ignores them; migration downgrade drops the new tables |
| **Acceptance** | with new fields absent, planner output is byte-identical to today (golden); overload fixtures shed OPTIONAL first with true blockers; ledger balances (I3) on 100 % of corpus runs |

### Phase 3 — Personalised profile integration

| | |
|---|---|
| **Scope** | R8 signal registry + `effective_profile` for **every** planner caller; the questionnaire contract table as data + tests; **remove fabricated feedback in Flutter** (prerequisite for learning); no learned weight yet (all 0) |
| **Files likely affected** | new `services/profile_service.py`; `engines/scheduling_engine.PlanningProfile.from_user_context`; `calendar_service._profile`, `plan_confirm_service`, `routes/today.py`, `routes/ai.py`; migration 008 (signals); Flutter `app_state_provider.dart`, `task_service.dart` |
| **Dependencies** | Phase 2 (stable `PlanItem`) |
| **Tests** | contract row-by-row tests (§11.2); "zero observations ⇒ questionnaire-only plan, byte-identical"; all callers receive the same profile (property); Flutter test for no-fabricated-feedback |
| **Risks** | hidden behaviour change for existing users |
| **Rollback** | `PROFILE_EFFECTIVE=off` restores today's per-caller profiles |
| **Acceptance** | stored-but-unused fields (`preferred_session_minutes`, `energy_predictability`, `tired_behavior`, `primary_goal`) each have a tested, documented effect or are explicitly marked non-scheduling; no caller bypasses the shared profile |

### Phase 4 — Behaviour observation storage

| | |
|---|---|
| **Scope** | R9 `plan_events` + hooks, derived `user_behavior_stats`, retention job, Insights reading the same stats (stage-gated) |
| **Files likely affected** | new `services/behavior_service.py`; hooks in `task_service` (start/complete), `plan_confirm_service`, `calendar_service.apply_replan`, `routes/today.record_override`; `routes/insights.py`; models + migration 008 |
| **Dependencies** | Phase 3 |
| **Tests** | determinism (replay ⇒ same stats); outlier-day step cap; privacy canaries (no titles in events); isolation; PG gates G9–G10 |
| **Risks** | write amplification; event-schema churn |
| **Rollback** | flag stops writing; tables can be ignored or dropped |
| **Acceptance** | one outlier day moves no signal beyond the step cap; < `N_min` ⇒ no influence; Insights shows no statement without its sample count |

### Phase 5 — Personalised scheduling

| | |
|---|---|
| **Scope** | R10 `ScoringWeights`, new terms (`history_fit`, duration estimate, context-switch, fatigue, density), score-contribution trace, explanations from contributions, counterfactual "forced by", stage-gated learned weights |
| **Files likely affected** | `engines/scheduling_engine.py` (scoring only), `engines/planner.py` (`Placement.contributions`), `planning_service.py`, `calendar_service.py`, Flutter explanation line |
| **Dependencies** | Phases 3–4 |
| **Tests** | zero-weight golden equality; per-term targeted tests; explanation-fidelity property; existing property suite unchanged |
| **Risks** | quality regression; over-fitting to sparse data |
| **Rollback** | `LEARNING_STAGE_MAX=0` ⇒ questionnaire-only plans |
| **Acceptance** | 100 % of explanations map to a recorded contribution; no hard-rule violation in the extended property suite; stage-0 users see no learned claim |

### Phase 6 — Replan intelligence

| | |
|---|---|
| **Scope** | R11 delta extraction (fast path + small LLM call, id-based references, multi-op, `needs_input`), stability-weighted re-optimisation for broad changes, R12 delta lines |
| **Files likely affected** | new `services/replan_intent.py`; `calendar_service.py`; `schemas/calendar.py` (additive); Flutter `replan_day_sheet.dart`, `plan_diff_view.dart` |
| **Dependencies** | Phase 1 infrastructure; Phase 2 entities |
| **Tests** | adversarial replan suite (A33–A35); property: never invents/duplicates/loses; fault injection (LLM down ⇒ fast path); delta-line fidelity |
| **Risks** | extra LLM cost/latency; mis-resolved reference |
| **Rollback** | `REPLAN_LLM_DELTA=off` ⇒ fast path + clarification only |
| **Acceptance** | the 8 messages of §4.5 behave as specified; zero invented tasks; every moved/unscheduled item has one non-generic delta line |

### Phase 7 — Latency optimisation (measurement-driven)

| | |
|---|---|
| **Scope** | apply only the optimisations Phase 0 data justifies: prompt shrink, response schema, `maxOutputTokens`, single time budget, profile cache, batched loads, Flutter 20 s plan timeout and progress, streaming **only if** p95 misses target |
| **Files likely affected** | extractor, `routes/ai.py`, profile cache, `api_service.dart`, `brain_dump_sheet.dart` |
| **Tests** | performance regression tests; live L1 re-run; timeout-composition tests |
| **Risks** | quality loss from a smaller prompt → A/B on the corpus before adoption |
| **Rollback** | each optimisation individually flaggable |
| **Acceptance** | §19.2 targets hold on the corpus (or are revised with evidence); no path exceeds the hard budget + network |

### Phase 8 — PostgreSQL and Flutter parity verification

| | |
|---|---|
| **Scope** | execute G1–G11 and F1–F5; fix what they find; add CI (none exists in the repository **[MISSING]**) |
| **Files likely affected** | `tests/conftest.py` (PG mode exists), CI configuration (new), parity fixtures, Flutter tests |
| **Dependencies** | environment with PostgreSQL and a working Flutter toolchain (the development shell currently blocks `flutter`) |
| **Tests** | the gates themselves |
| **Risks** | environment availability; defects found late |
| **Rollback** | n/a (verification) |
| **Acceptance** | every gate has a recorded passing result committed to the repository |

### Phase 9 — Production acceptance

| | |
|---|---|
| **Scope** | live L1 evaluation, staged rollout (internal → 5 % → 25 % → 100 %), dashboards from run records, soak, sign-off |
| **Files likely affected** | dashboards/queries, runbook, release checklist |
| **Tests** | the full acceptance suite (§26) + live corpus |
| **Risks** | provider drift after launch → pin model version, nightly corpus run alerts on regression |
| **Rollback** | flags off per feature; migrations reversible |
| **Acceptance** | all release gates green; §25.1 thresholds met on the live corpus; no P1 diagnostics (lost entity, fabricated entity, invariant violation) in the soak |

### 27.1 What becomes more valuable with use (and what is never gated)

| When | What Flowstate does | Evidence level |
|---|---|---|
| **Day 1** | understands today's dump; preserves everything; builds a feasible, explained day; safe Replan | stage 0 — questionnaire + defaults, labelled as such |
| **Week 1** | notices timing habits; shows "usually takes you ~X"; better duration suggestions | stage 1–2 — display-first, small weights |
| **Week 2+** | learns recurring behavioural patterns; scheduling confidence rises; Replan adapts to when you actually work | stage 2–3 |
| **Longer term** | knows your rhythm and what belongs where; Replan is personal; Insights explains what it learned, with counts | stage 3–4 |

**Principle (D12):** correctness, preservation, the conservative fallback, planner safety, Replan safety and questionnaire-based personalisation are **never** behind Pro. A paid tier adds *depth* — e.g. longer history/weekly reviews, larger AI allowance, multi-day planning — not the fix for broken free behaviour. *Note:* today the AI-quality path is metered while the free path is the fragmenting fallback; R7 removes that tension.

---

## 28. Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| 1 | LLM variance or provider model change degrades extraction | medium / high | recorded-response suite in CI; live corpus nightly; pinned model version; schema + coverage checks so errors surface as questions, not silent loss |
| 2 | LLM latency or cost higher than assumed (**unmeasured today**) | medium / high | Phase 0 first; token guard; output cap; revise targets with evidence |
| 3 | Over-asking questions annoys users | medium / medium | ask only for hard-constraint ambiguity, cap 3, sensible default action |
| 4 | Fallback under-splits | medium / medium | Split control, Retry with AI, corpus-tuned rules |
| 5 | Learned personalisation feels wrong or creepy | medium / high | staged weights, labels, reset, step caps, minimum samples |
| 6 | Planner regression from new fields | low / high | optional fields, golden equality tests, existing property + mutation checks |
| 7 | PostgreSQL behaviour differs from SQLite (enum ordering, JSON, timestamps) | medium / high | gates G1–G11 before any migration reaches production |
| 8 | Flutter changes unverified (tests cannot run in the current shell) | high / high | F1–F5 are release gates; no readiness claim without them |
| 9 | Privacy: richer behaviour data increases sensitivity | medium / high | metadata-only events, canary tests, TTLs, export/reset, isolation tests |
| 10 | Scope creep ("rewrite the planner", "make the LLM schedule") | medium / high | explicit non-goals; layer-by-layer verdict (§4.8); phase gates |
| 11 | Single AI provider dependency | medium / medium | conservative fallback is the guaranteed floor; optional second provider later (D2) |
| 12 | Production schema bootstrap unknown (D4 from the previous spec) | certain / high | blocks all production migrations until answered |
| 13 | Replan LLM misresolves a reference | low / medium | ids supplied by server, ownership check, dry-run preview, confirmation |

---

## 29. Known limitations (of this specification and of v2)

* **LLM quality and latency are not measured** here; every number attributed to the model is a target (Phase 0 resolves).
* The Flutter preview, the Dart local parser's output, and the UI's perceived quality were **not executed** (Flutter tooling is blocked in the development shell); they are described from source only.
* Production database behaviour, data volumes and real user behaviour are **unknown**; the PostgreSQL schema bootstrap remains unresolved (D4).
* v2 does **not** include recurring tasks/habits, external calendar sync, map-based travel-time estimates (travel and prep are user-stated or labelled defaults), voice input, multi-day optimisation beyond the existing 8-day horizon, or any medical/physiological inference.
* English-first; other languages and code-switching are **[UNCERTAIN]** until the corpus covers them (D11).
* Learning needs weeks of use; early users get questionnaire-level personalisation by design.
* A correct fallback can still be coarser than AI output; the product states this instead of hiding it.
* Duration of an event whose length is not stated (e.g. Class) is an **assumption** shown as such.
* Counterfactual blockers explain *one* sufficient cause, not every contributing cause.

---

## 30. Open decisions (need an answer before the named phase)

| ID | Decision | Recommendation | Needed by |
|---|---|---|---|
| **D1** | Hard input cap | **8,000 characters**, soft target 4,000; revisit with Phase 0 length telemetry (alternatives: 6,000 / 12,000 with chunking) | Phase 1 |
| **D2** | LLM provider/model, structured-output mode, pinned version, per-user/day budget, whether a second provider is justified | keep the current provider; one flash-class model with response schema; larger-model escalation **off** unless the corpus proves a failure class it fixes | Phase 0/1 |
| **D3** | Spend cap and dedicated key for Phase 0/L1 live evaluation | needed from you | Phase 0 |
| **D4** | Travel/prep: derived attached blocks (recommended) vs persisted tasks | derived blocks | Phase 2 |
| **D5** | Charge on delivery rather than on extraction completion | yes | Phase 1 |
| **D6** | Late-result adoption ("AI result ready — use it?") | optional; defer unless timeouts are frequent | Phase 7 |
| **D7** | Does a Replan LLM call count against the AI economy? | fast path free; LLM delta metered only by the existing rate limit | Phase 6 |
| **D8** | Default assumptions (event duration 60 min; gym buffers 20/15 min; how "assumed" is shown) | label every default in the UI | Phase 2 |
| **D9** | Raw-text retention and diagnostic sampling | **none** by default; opt-in "retry later" with 24 h TTL; no sampling without explicit consent | Phase 1 |
| **D10** | Row-Level Security stance | application scoping + tests now; RLS for new tables once D4 facts exist | Phase 2 |
| **D11** | Language scope (English only vs. Hinglish/code-switching) | English first; add corpus rows before claiming more | Phase 0 |
| **D12** | Free vs. Pro split | correctness/safety/fallback/questionnaire personalisation always free; Pro = depth (§27.1) | before launch |
| **D13** | CI introduction (none exists in the repository) | add before Phase 8 | Phase 8 |
| **D14** | Production schema bootstrap (carried from `build-my-day-replan.md` §11.1) | answer the five facts | before any migration beyond dev |

---

## Appendix A — Reason-code registry (initial)

`placement`: `deadline_protection`, `fixed_time`, `preferred_window`, `focus_window_reported`, `focus_window_observed`, `warmup_protection`, `sleep_protection`, `dependency_order`, `slack_ordering`, `history_fit`, `density_spread`.
`unscheduled`: `blocked_by(entity)`, `deadline_infeasible`, `bound_infeasible`, `no_capacity`, `explicit_time_in_past`, `optional_shed`.
`replan_move`: `made_room_for(entity)`, `running_late(min)`, `slot_freed`, `missed`, `deadline_protection`, `user_request`, `event_cancelled`.
`boundary` (fallback): `R-sep-newline`, `R-sep-bullet`, `R-list-short-parts`, `R-split-own-clause`, `R-attr-anaphora`, `R-instruction-note`.

## Appendix B — What this specification deliberately does **not** change

The hard-constraint planner core, the invariant checker, user-lock semantics, atomic/idempotent confirm and apply, the timezone rule, the Replan safety machinery (stale/409, server re-validation), the AI economy's charge-after-success principle (refined by D5), and the Insights cold-start honesty. These are working, verified, and tested; v2 builds on them.
