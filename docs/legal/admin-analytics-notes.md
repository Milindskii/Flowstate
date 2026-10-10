# Future admin analytics page: what the existing data supports

Nothing was collected, added or exposed in this pass. This lists what already exists so a later admin page can be built without
new collection. Source: `backend/app/models`, `backend/app/api/routes/admin.py` (exists; `require_admin` guards it).

## Questionnaire answers that are stored (via the onboarding profile write)

`preferred_peak_start/end` (from peak_window), `weekday_wake_time`, `weekend_wake_time`, `bedtime`, `sleep_inertia_minutes`,
`preferred_session_minutes`, `draining_work_types` (list), `fatigue_symptom`, `routine_shift_preference`, `session_disruptor`,
`primary_goal`, `energy_predictability`, `timezone`.
Not stored: `unpredictable_cue`, `schedule_disruptors` (answered, never sent).

## Aggregate metrics the data supports today

- Onboarding completion: `users.onboarding_completed` vs `users.created_at` (the share who finish). Per-question drop-off is **not**
  available: partial progress is kept only on the device.
- Broad distributions, bucketed: peak window (4 values), primary_goal (6), session_disruptor (9), energy_predictability (4),
  preferred_session_minutes (5 buckets), draining_work_types (counts per type), wake/bed time by hour band.
- Planner use: tasks created per user and per day, completed vs skipped/missed (`task_deviations.kind`), routines count.
- Build My Day: attempts and outcomes from `ai_planning_attempts` (status, failure_code, latency_ms) and `ai_requests` (charge_source). These
  hold codes and timings; `failure_reason` is free-form error text and should stay out of the dashboard.
- Economy: Shield balances and grants (`flow_progression`, `shield_rewards`), Pro status (`ai_usage`: tier, status).
- Consent: `terms_accepted`, `privacy_accepted`, `age_confirmed`, `consent_at`.

## Recommendations

1. Aggregate or de-identified by default: counts, percentages and histograms; suppress any bucket under a minimum size (for
   example fewer than 10 users) so small groups cannot be identified.
2. Never show raw task titles, routine titles, reflection notes, privacy-request messages or Build My Day content. None of it is
   needed for the metrics above.
3. No per-user answer view in the dashboard. Support cases should go through a separate, logged lookup.
4. Time-series by signup week, not by individual.

## What the page would still need (all backend, none built)

- Aggregate endpoints under `require_admin`, returning pre-bucketed numbers only; read-only database role or views for them.
- Audit log of admin access; a decision on who the admins are (`users.is_admin`) and how that flag is set.
- Retention rules for what the page reads, matching the Privacy Policy (retention periods are not yet defined).
- If per-question completion or funnel data is wanted: that is **new collection**, needs a Privacy Policy update first.
- The Privacy Policy should mention aggregate product analysis once it exists.
