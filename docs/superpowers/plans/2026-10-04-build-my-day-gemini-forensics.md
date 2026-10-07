# Build My Day — Gemini/AI Path Forensics & Fix Plan

> **For the implementer (Sonnet 5.5):** Run inline with `superpowers:executing-plans`. No subagents (credit budget).
> Skills to load, in this order: `superpowers:systematic-debugging` (Phase 0–1), `superpowers:test-driven-development` (Phase 2),
> `superpowers:verification-before-completion` (Phase 3). Use the installed **context7** plugin for current Gemini REST docs instead of guessing.
> Nothing is committed. Do not touch Calendar visuals, Replan, or the verified Build My Day scheduler/confirm path
> (`plan_confirm_service.py`, scheduling engine) unless Phase 1 proves a shared root cause.

**Goal:** Find and fix every confirmed root cause behind "AI planning failed: Gemini couldn't be reached."; guarantee one complimentary successful AI plan per Flowstate account; separately diagnose "Learning your rhythm" and the stuck task.

**Hard rules:** never print the API key (log `len(key)` / `key[:0]` presence only) · never fake an AI result · never auto-fall back to basic planner · preserve brain-dump text on failure · do not weaken existing tests · real Gemini calls are required where stated (keep them few: budget ≤ 10 real calls total).

---

## Pre-read leads (from planning recon — VERIFY, don't trust)

All in `backend/app/services/ai_service.py` `_gemini_generate` (≈ lines 1300–1347):

| # | Observation | Hypothesis to test |
|---|---|---|
| L1 | Default `GEMINI_MODEL = "gemini-3.5-flash-lite"` (`backend/app/core/config.py:48`); fallback list hard-codes `"gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-flash-latest"` | One or more names don't exist on v1beta → **404 NotFound** seen in AI Studio. Confirm via `GET https://generativelanguage.googleapis.com/v1beta/models` (ListModels) with the real key. |
| L2 | Any non-200, non-400/401/403 status (404, 429, 500, 503) is just recorded as `http_<code>` and the loop moves on | 404 (config bug) and 429 (quota) are treated as "transient" and retried on other models, burning provider quota. |
| L3 | Only `last_error_class` is reported; earlier attempts' classes are dropped | A real 404/429 on the primary model is masked by whatever the last fallback returned (e.g. 503). |
| L4 | Every failure → `GeminiFailure("gemini_error")` → route 502 `gemini_error` → Flutter `'gemini_error': "Gemini couldn't be reached."` (`lib/screens/brain_dump_sheet.dart:286`) | Quota, auth, model-not-found, timeout, malformed output all collapse into one message. |
| L5 | `httpx.Client(timeout=12.0)` × up to 4 models sequentially | Worst-case ~48 s request; Flutter client timeout may fire first and show a network error even if backend later succeeds. Check Flutter's AI request timeout. |
| L6 | Economy: `free_uses_total=1` (`ai_economy_service.py:69`), consume at `:238`, idempotency cache at `:123-146`, `:253-265` | Verify consume happens only after success, cache is user-scoped, and failures are never cached. |

---

## Phase 0 — Forensic investigation (NO code changes)

Write findings to `docs/superpowers/plans/2026-10-04-gemini-forensic-report.md` as you go. Each item: evidence (command + safe output), conclusion, confirmed/refuted.

### 0.1 Trace the path (read only)
Read, in order, and note file:line for each hop:
`lib/screens/brain_dump_sheet.dart` → the Flutter AI plan service it calls (grep `ai/plan`) → API base URL config (grep `baseUrl|API_BASE|localhost|10.0.2.2`) → `backend/app/api/routes/ai.py` (`/ai/plan`, lines ~60–230) → `AIService` extraction entry → `_gemini_generate` → `GeminiFailure` (`ai_service.py:93`) → `AIEconomyService` → `backend/app/schemas/ai.py` → Flutter failure/success rendering, Retry with AI, Use basic planner.

Answer: which backend URL does the running Flutter build hit (local vs deployed)? Is the deployed backend running the same code/env?

### 0.2 Config / env
- How `backend/.env` is loaded (`config.py`); is `GEMINI_MODEL` overridden in `.env` or the shell env? Print model names and `bool(GEMINI_API_KEY)`, `len(GEMINI_API_KEY)` only.
- Check for stale `GEMINI_*` vars in the process env (`python -c "import os; print([k for k in os.environ if 'GEMINI' in k or 'GOOGLE' in k])"`).

### 0.3 Real provider probe (scratch script in scratchpad dir, not in repo)
1. ListModels: `GET /v1beta/models?pageSize=200` → record which of the 4 configured names exist and support `generateContent`. **This settles L1 / the 404.**
2. One minimal `generateContent` per *existing* model with a tiny prompt; record status + `error.status` / `error.message` (redact nothing secret is in there, but never echo headers).
3. If 429 appears: record `error.details` (`QuotaFailure` / `RetryInfo`) — this is the only proof of provider quota exhaustion. The AI Studio screenshot is not proof.
4. If 503 appears: repeat once after 5 s. Consistent → model overloaded/unavailable; intermittent → transient (retry appropriate).

### 0.4 Reproduce via backend
Run backend locally, hit `/ai/plan` with a test user (curl or a pytest using the real key, marked `@pytest.mark.live_gemini`, skipped without key). Capture the log lines `ai_service.gemini_attempt ... error_class=` for every model attempt.

### 0.5 Usage / Shield accounting (read + existing tests)
Trace `AIEconomyService`: where usage rows are created (per user_id?), when `free_uses_consumed` increments relative to Gemini success, whether failures write to `AIPlanningRequestCache`, whether cache lookup filters by `user_id` (line ~130 suggests yes — confirm), whether Shield deduction can happen before Gemini returns.

### 0.6 Retry / fallback (Flutter)
Confirm: Retry with AI re-sends to `/ai/plan` (same idempotency key? if the key is reused and a failure were cached, retry would be poisoned); Use basic planner calls local path and labels "Basic plan (not AI)"; no automatic fallback anywhere (grep `basic|fallback|offline` in brain dump code).

### 0.7 "Learning your rhythm" (separate)
Grep the string in `lib/`; find the condition that shows it (readiness/personalization state, likely from `/today` or readiness service). Check the fresh account's DB values for that condition. Classify: intentional (N days of data required) / missing transition / stale provider / bad DB value / API propagation.

### 0.8 Stuck task (separate)
Query the stuck task row in Supabase (status, planned_date, slot_start, slot_end, timezone). Trace current-task selection (`today.py`, `right_now_task_card.dart` provider). Check UTC vs local date comparisons and whether a past `slot_start` with status `in_progress`/`scheduled` is ever expired.

### 0.9 Deliver forensic report
The 10 items the user listed (Gemini root cause, 404, 503, quota yes/no, usage bugs, retry/fallback bugs, new-account bugs, Learning-your-rhythm cause, stuck-task cause, smallest fix per item). **Stop and show the user this report before Phase 2.** Mark anything not reproduced as "not reproduced", don't invent a cause.

---

## Phase 1 — Decide fixes (only for confirmed items)

Likely candidates if leads hold (apply only if Phase 0 confirms):

- **F1 Model config:** set `GEMINI_MODEL` default to a model ListModels actually returned; build fallback list from config (`GEMINI_FALLBACK_MODELS` setting), drop non-existent names. No hard-coded speculative names.
- **F2 Status classification in `_gemini_generate`:**
  - 400/401/403 → `auth_or_request` (stop, no fallback) — already stops, but give it a distinct code
  - 404 → `model_not_found` (log model name; skip to next model, but if *all* 404 → config failure)
  - 429 → `provider_quota` (stop; do not burn other models; surface RetryInfo delay if present)
  - 500/503 → `provider_unavailable` (fallback to next model OK; maybe one short retry)
  - timeout / network → `timeout` / `network`
  - unparseable 200 → `malformed_output`
  - Keep a list of all attempt classes; final failure reports the most significant (quota > auth > model_not_found > unavailable > timeout > network), not just the last.
- **F3 Failure codes end-to-end:** extend `GeminiFailure` codes and `schemas/ai.py` `failure_code` Literal (keep `gemini_error` for back-compat), route maps to proper HTTP status (429 for provider quota, 502/503 otherwise), Flutter `brain_dump_sheet.dart` map gains specific messages (e.g. "Gemini is busy — try again in a moment", "AI is temporarily over capacity", "AI configuration problem — please report"). Still "Nothing was charged." Never expose raw provider text containing secrets.
- **F4 Timeout budget:** total budget so backend answers before the Flutter client timeout (e.g. per-attempt 10 s, overall ≤ 25 s; align Flutter timeout above that).
- **F5 Economy:** fix only what 0.5 found (e.g. consume-before-success, failure cached, cache not user-scoped).
- **F6/F7:** Learning-your-rhythm and stuck-task fixes — only the minimal confirmed change.

---

## Phase 2 — Implement with TDD (one fix at a time: red → green → targeted suite)

Regression tests to add (backend, `backend/tests/`, mock httpx with `respx` or monkeypatch — whatever existing AI tests use; check `test_ai_economy.py` first):

1. 404 on primary, 200 on fallback → success, attempt log contains both.
2. All models 404 → `model_not_found` code, not `gemini_error` generic.
3. 429 on primary → `provider_quota`, **no further models attempted**, not charged.
4. 503 on all → `provider_unavailable`.
5. Timeout → `timeout`.
6. 200 with garbage body → `malformed_output`.
7. Economy A–F from the user's list:
   - A new user + success → `free_uses_consumed == 1`, no Shield deducted
   - B new user + failure → `free_uses_consumed == 0`, no Shield deducted
   - C failure then retry success (same key) → consumed 1, plan returned
   - D same key replayed after success → cached result, consumed still 1
   - E user2 using user1's idempotency key → no cache hit, own usage row
   - F provider_quota failure → user entitlement unchanged, response code distinct from Flowstate `quota_exceeded`/no-shields
8. Failed attempt never written to `AIPlanningRequestCache`.

Flutter (`test/`): widget test that each failure code renders its message, brain-dump text preserved, Retry calls the AI service again, Use basic planner shows "Basic plan (not AI)" and never AI labeling.

After each fix run the targeted file; after all fixes run:
```
cd backend && python -m pytest tests/ -q -k "ai or plan or economy or build or today" 
cd backend && python -m pytest -q          # full, expect prior count ~1227 + new
flutter test test/ --plain-name "brain dump"   # then full: flutter test
```

---

## Phase 3 — Real-system verification (evidence required for each)

1. Real Gemini success via backend `/ai/plan` on a **fresh** Flowstate test account (Supabase): record model used, latency, `free_uses_consumed` 0→1 in DB.
2. Replay same idempotency key → cached, DB unchanged.
3. Real failure: temporarily set `GEMINI_MODEL=gemini-does-not-exist` and fallbacks empty → expect `model_not_found` in response and logs, DB unchanged. Restore config.
4. Retry after that failure with correct config → success, consumed = 1 (not 2).
5. Second fresh account → its own usage row, no cross-user cache hit, no tasks from account 1.
6. Restart backend → replay key still returns cached result; confirmed plan tasks still in Supabase.
7. Flutter: `flutter run` against the local backend, manual one-pass of Build My Day (success + forced failure) — if not possible from the CLI, say so explicitly and hand the user a 5-step manual checklist.

## Final report to user
Root causes · fixes · files changed · tests added/updated (with counts) · exact real Gemini result (model, status, latency) · whether provider quota was actually exhausted · remaining issues · readiness for manual testing. Nothing committed.
