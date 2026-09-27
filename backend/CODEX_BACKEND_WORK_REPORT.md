# Flowstate Backend Work Report

## 1. Ground-truth repository state

- Initial branch: `main`.
- Initial working tree: clean (`git status --short` produced no entries).
- Recent scheduler, parser, AI-economy, Supabase/JWKS, and Noya commits were already present.
- Backend entry point: `app/main.py` (FastAPI).
- Database: SQLAlchemy with SQLite as the local default and PostgreSQL/Supabase as the production target. Alembic migrations live in `alembic/versions`.
- No Flutter/Dart, Android, asset, navigation, or UI file was changed.

## 2. Existing systems verified

- Protected routes use `get_current_user`, which verifies a Supabase JWT/JWKS token and derives the local user from its `sub`; task/service queries are scoped to that user.
- The Build My Day route (`POST /api/v1/ai/plan`) invokes Gemini extraction and then the deterministic `SchedulingEngine`; Gemini is not the scheduling authority.
- `PlanningProfile.from_user_context` consumes readiness questionnaire values and uses completed-task history for duration-ratio and afternoon-focus learning.
- The existing economy has one free plan, shields, status API, idempotency cache, and a five-request-per-hour in-process limit.

## 3. Bugs actually confirmed and fixed

| Old behavior | New behavior | Evidence |
| --- | --- | --- |
| The AI plan route used `datetime` and `timezone` without importing them, then swallowed the failure in its scheduling fallback. | The imports are present and candidate schedule enrichment runs. | Full suite passes. |
| `around 6 PM` became a rigid `scheduled_start`; `tomorrow` became an invented deadline. | Flexible phrasing is retained in `temporal`; `tomorrow` is a target date unless `by`/`due` creates a deadline. | New temporal regression tests. |
| The scheduler only enforced collisions, deadlines, and past time. | It now filters target dates, earliest starts, latest ends, and bedtime-relative constraints before scoring; preferred windows remain soft. | New after-dinner and bedtime cases pass. |
| The no-feasible-slot fallback could violate a deadline/bound. | It returns no recommendation when a hard constraint makes the task impossible. An imminent explicit deadline can exceed bedtime by at most 90 minutes. | Existing deadline safety test passes. |
| Idempotency caching failed once scheduling enrichment added datetimes. | Cached payloads are JSON API values. | Economy retry test passes. |
| The production development JWT secret was accepted. | Production startup rejects the known development secret. | Static compilation and full suite pass. |
| An opaque client purchase token could grant Pro. | Subscription and streak recovery now fail closed (503) until server-to-server Google Play verification exists. | Added non-spoofing test; full suite passes. |

## 4. Parser, priority, duration, and scheduler changes

- Added `TemporalConstraints` to task candidates: fixed/earliest/latest/preferred timing, target date, relative constraint, flexibility, confidence, and provenance.
- Added segmentation for filler-led independent clauses such as `, maybe clean …`.
- Preserved coherent outcomes such as `finish my assignment and submit it` as one task.
- Priority provenance remains distinct from the internal enum default: unspecified user priority stays `unspecified` in provenance.
- Explicit duration remains explicit; defaults remain separate provenance.
- Candidate explanations are produced from the winning final slot, not from an earlier candidate.

## 5. Authentication and economy changes

- Authentication remains Supabase/JWKS based; no custom auth system was introduced.
- A same-user in-process lock serializes AI-plan authorization, extraction, cache creation, and finalization so simultaneous taps cannot double-consume in one app process.
- Idempotency keys cannot be read from or overwritten across users.
- Usage status stays server-authoritative and exposed through `GET /api/v1/ai/status`.

## 6. Gemini request and token findings

- Local deterministic parsing: **0 Gemini requests**.
- Normal successful Gemini extraction: **1 request** (the first configured model that responds successfully).
- JSON repair after a malformed successful response: **2 requests**.
- Failure: **1–4 requests**, because the configured model plus up to three fallback model names are attempted; no usage/shield finalization occurs on failure.
- The extractor now logs model, request count, latency, prompt tokens, candidate/output tokens, and total tokens when Gemini returns `usageMetadata`. It does not log raw task content or secrets.
- No live Gemini call was made during this work, so actual provider billing/token values remain to be observed in production logs.

## 7. Regression coverage and results

Added `tests/test_temporal_constraints.py` covering:

- DBMS-deadline task split from a later room-cleaning task;
- coherent-outcome preservation;
- `around` as a preference rather than a fixed appointment;
- after-dinner hard boundary;
- gym → after-dinner login bug → before-bed DSA relationships.

Updated legacy tests whose old assertions treated any `tomorrow` as an invented deadline. Added an opaque-token entitlement rejection assertion.

Final result: **105 passed**.

## 8. Exact commands executed

```powershell
git branch --show-current; git status --short; git log --oneline -8
.\venv\Scripts\python.exe -m pytest -q
$env:PYTHONPATH = "$PWD\venv\Lib\site-packages;$PWD"
& <bundled-python> -m pytest tests\test_temporal_constraints.py -q
& <bundled-python> -m pytest -q
& <bundled-python> -m py_compile app\core\security.py app\services\ai_economy_service.py app\api\routes\ai.py app\schemas\task.py app\services\ai_service.py app\engines\scheduling_engine.py
git diff --check
```

The direct virtual-environment interpreter is stale because its base Python 3.12 installation no longer exists. The passing runs used the bundled local Python with the existing environment's `site-packages`; no dependency was installed or upgraded.

## 9. Remaining limitations and frontend contract

- The five-per-hour rate-limit cache and same-user lock are process-local. A multi-instance deployment should replace them with a database/Redis reservation keyed by user and idempotency key.
- Google Play verification is intentionally disabled until a Google Play Developer API verifier and service credentials are integrated; the frontend must treat HTTP 503 as “verification unavailable,” not as a purchase success.
- Temporal constraints are returned in the AI preview candidate contract. Persisting them on confirmed tasks requires a follow-up task-model migration and client submission support; no Flutter contract was changed here.
- Frontend should display `temporal` separately from `recommended_slot_*`, show `priority` as unspecified when `field_provenance.priority.source` is `unspecified`, and never treat a recommendation as a fixed user appointment unless `temporal.fixed_start` exists.
