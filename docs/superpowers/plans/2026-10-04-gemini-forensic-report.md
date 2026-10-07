# Gemini / Build My Day AI — Forensic Report (2026-10-04)

Evidence = real Supabase rows + real Gemini probes (key never printed; `.env` GEMINI_API_KEY len 53, GEMINI_MODEL=gemini-3.5-flash-lite, no shell overrides).

1. **Gemini failure root cause (the manual-test failure).** Three stacked causes, all confirmed:
   a. Provider 503 UNAVAILABLE ("high demand") on every model in the chain at 18:06 UTC. Row `ai_planning_attempts` for the fresh user: `gemini_error`, `Gemini is unavailable right now (http_503)`, latency 20 326 ms. Probe reproduces the same 503 body on `gemini-flash-latest` (4.8 s per attempt).
   b. The backend walks 3 models sequentially (~5–7 s per failing attempt) = ~20 s, but Flutter `ApiService.post` times out at **12 s** (`lib/services/api_service.dart:123`). Any slow/failing primary therefore ends as a client timeout, not a server answer. Server keeps running and records the attempt after the client left.
   c. Every outcome (client timeout, no network, any 5xx, 503, 404, auth, quota) collapses to code `gemini_error` → "Gemini couldn't be reached." (`ai_plan_service.dart:97-99`, `brain_dump_sheet.dart:286`).
2. **404.** NOT reproduced. ListModels (HTTP 200) lists all configured names (`gemini-3.5-flash-lite`, `gemini-3.8-flash`, `gemini-flash-latest`); primary returns 200 in ~0.9 s. Lead L1 (stale/invalid model name) is **refuted**. The dashboard 404s did not come from the current model list; origin unknown (likely earlier model names from previous code). No code change for it.
3. **503.** Provider availability (model overloaded), transient. Our request is valid (same payload returns 200 on other models seconds apart). Retry is appropriate: the user retry is safe because failure is neither charged nor cached.
4. **Provider quota exhausted?** No evidence. No 429 / QuotaFailure observed anywhere; the only 4xx-class provider responses were none. The Flowstate `quota_exhausted` row (user eb9e8822) is the *Flowstate* entitlement, correctly distinct.
5. **Usage/Shield.** No bug found. Fresh user c04eed82: `free_uses_consumed=0`, `total_ai_uses=0` after the 503 → entitlement kept (B). User eb9e8822: success → consumed 1, cache row stored, next different request → `quota_exhausted` (A/D as designed). Usage + cache rows are per `user_id`.
6. **Retry/fallback.** Route: no silent basic fallback (confirmed; `_useBasicPlanner` is an explicit user action, labelled "Basic plan (not AI)", no credits used). Failures are not cached (`ai_planning_requests` has only completed rows). Bug: Flutter maps client timeout to the same `gemini_error`, and the 429 provider case is not distinguished (`_gemini_generate` treats 404/429/5xx identically and reports only the *last* class).
7. **New account.** No bug: usage row is created with `free_uses_total=1`, nothing inherited.
8. **"Learning your rhythm".** Intentional, not a bug: `today.py:136-141` → `new_user` (no tasks, 0 sessions) shows it; `learning` until `TaskPerformance` count ≥ `CALIBRATION_MIN_SESSIONS` (30). Fresh account has 0 rows, the test account has 8. Unrelated to Gemini.
9. **Stuck task.** Not reproduced: Supabase has **no** `in_progress` task. Only likely candidate is `boobdigyy` (todo, planned_date 2026-10-03, no slot, no deadline): by design (`list_open_for_day` docstring) a missed task without a deadline stays on its own day and is not shown Today. Not the Gemini bug; no change without a repro.
10. **Smallest fixes (confirmed only):**
    - F-A Flutter: `ApiService.post` gets an optional `timeout`; AI plan call uses 45 s.
    - F-B Backend `_gemini_generate`: classify status (404 model_not_found, 429 provider_quota → stop, 5xx provider_unavailable, timeout, network, malformed), collect all attempts, report the most significant one, overall deadline 30 s; new codes surface in `failure_code`.
    - F-C Flutter: distinct messages per code, client timeout → `timeout` code (not `gemini_error`).
    - Tests: economy A–F + error mapping + Flutter widget mapping.
