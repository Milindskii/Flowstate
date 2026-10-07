# Flowstate final polish pass — plan

## Context
Build My Day and Replan work. This pass closes the gaps that remain without destabilizing them. Three read-only explorers (2026-10-07) found that much of the request **already exists, uncommitted**, from the 10-06 session:
- day-path anchors and stable `sched-<id>` keys
- derived auto-bypass
- the FlowClock minute tick and resume refresh
- Build My Day Remove with dependency repair and Undo
- the Replan AI layer and clarification options

The real remaining problems are:
- no month picker in Calendar
- Replan compound clauses with AI off
- learning data that is polluted or never synced
- Insights not reading server history
- the questionnaire dropping answers
- a sequential launch path with many duplicate fetches
- whole-app rebuilds

**Decisions (from the user)**
- **Companions:** every non-Noya companion shows "Coming Soon" and can't be bought. Anyone who already owns one keeps it selectable.
- **Review:** polish the per-task reflection sheet only, and make it actually sync.
- **Polluted learning data:** fix it going forward. New rows carry a provenance tag. Old rows are excluded from the rating signals.
- **Design:** Superdesign mockups for the new surfaces (month picker, Insights, reflection sheet, Coming Soon, questionnaire). Then the `impeccable` skill polishes the existing screens against the Noya visual system.

**Constraints:** don't rewrite Build My Day or Replan; no ML; no commits; don't weaken tests. Existing failing tests: see memory `flutter-baseline-test-failures`.

**Process:** on approval, I save this file as the spec at `docs/superpowers/specs/2026-10-07-final-polish-design.md`, uncommitted. Then I execute workstream by workstream with TDD (`superpowers:test-driven-development`), using `systematic-debugging` for root causes. Each workstream must pass `verification-before-completion` before the next starts.

---

## WS0 — Design (Superdesign + impeccable)
- Superdesign canvas: 2–3 variants each of:
  - (a) the Calendar header with the month-picker sheet
  - (b) the Insights layout (trends, routines, still learning)
  - (c) the reflection sheet
  - (d) the Coming Soon companion card
  - (e) a multi-select question with "Other + text"
- Feed it the existing tokens from `lib/theme/` and the Noya visual system. I'll show you the picks before implementing.
- `impeccable` critique and polish pass on Calendar, Insights, the reflection sheet, Flow companion sanctuary and onboarding, after the functional work lands.

## WS1 — Calendar (small; most of it already exists)
- **Verify what exists.** Run these tests to confirm stable keys, bypass, the minute tick and resume:
  - `calendar_live_anchor_test`
  - `day_path_skip_anchor_test`
  - `day_route_geometry_test`
  - `calendar_date_navigation_test`

  Add a regression test that runs skip, then miss (clock advance), then defer, then recover on one day. It asserts that every stop's key and `DayRouteGeometry` y-coordinate are identical before and after, and that only the route path changes.
- **Month picker (new).** A calendar icon button in the `calendar_tab.dart` header, next to `FlowDateStrip`, opens a themed bottom sheet with a full month grid. It shows previous/next month, today highlighted, and a dot on days that have tasks, using already-cached task dates only, with no new fetch.
  - Selecting a day calls the existing `loadCalendarDay(date)`.
  - Today the strip's `_days` window is fixed at -14/+12 days (`calendar_tab.dart:88-93`). Re-centre the window on the selected date so any day works.
  - New component: `lib/components/flow_month_picker.dart`.
- **Polish:** remove the duplicate `loadCalendarDay` in initState when the day is already cached. The rest is covered in WS7.

## WS2 — Replan natural language (targeted, same pipeline)
The pipeline stays: rules → `replan_understanding.understand` → `replan_ai` (Gemini through `ai_gateway`, checked by `replan_ai.validate`) → planner → proposal → apply.
- **Compound requests per clause.** In `calendar_service.py` around lines 798-804, run `replan_understanding.understand` on each `unparsed` clause before falling back to AI or to the "I didn't act on" note. Example: "can't go out, move gym to 8" becomes cancel(commitment) + move(gym, 20:00).
- **Missing information on a recognized task always asks.** Extend `_opts_for` so a multi-clause message gets one clarification per task, with the clauses it did understand kept in the proposal. Never guess a missing time (already enforced by `numbers_in` and `_time_said`; add tests for this).
- **Better Gemini prompt.** In `replan_ai.build_prompt`, add few-shot examples for colloquial phrasing ("can't make it out", "bail on", "push X", "no time for X", "X after lunch") and include each task's commitment flag so the model never proposes moving one.
  - `validate` already rejects operations on commitments unless the user explicitly cancels. Verify this, and add it if missing.
- **Tests** in `backend/tests/test_replan_understanding.py` and `test_replan_ai.py`, model mocked:
  - each phrase from the request, with AI on and with AI off
  - compound requests with a clause missing its time
  - a commitment protected against a Gemini proposal to move it

## WS3 — Build My Day Remove (verify only)
Already implemented in `brain_dump_sheet.dart:679-718` and `plan_candidates.dart:7`, with `test/build_my_day_remove_test.dart`.
- Add one test: remove a candidate that another candidate depends on, confirm, and assert the `confirmCandidates` payload has no reference to the removed id.
- Check the AI-plan path (the server re-plans on confirm). The backend `prune_dangling` must handle a dependency on an id that wasn't sent; add a test in `test_bmd_sequence_links.py`.

## WS4 — Learning data integrity + behavioural patterns (backend-centric)
**4a. Stop the pollution (root cause)**
- `app_state_provider.dart:1035-1049` (completion toggle): stop sending the made-up `focus 5 / Energized`. Send only the real `started_at`/`completed_at`, with actual minutes taken from timestamps, or null.
- `recordTaskFeedback` (`app_state_provider.dart:1630-1702`):
  - send `source: 'self_report'`
  - stop mapping the 1–4 feeling scale into `energy_rating`
  - POST `/tasks/{id}/feedback` with the real difficulty, distraction and duration choice
  - keep the local `ReflectionStore` as the offline queue, retried on the next successful call
- **Migration `010_learning_provenance`:** add `provenance` to `task_performance` and `readiness_observations`. Values: `reflection` / `timestamps` / `onboarding` / `legacy`. Existing rows become `legacy`; the onboarding baseline becomes `onboarding`.

**4b. Statistics module (new `backend/app/engines/behavior_patterns.py`, pure functions)**
- **Inputs:** completed tasks with local start time (using the user's timezone), `task_deviations`, and `task_performance` with `provenance in (reflection, timestamps)`. Rating signals come only from `reflection`.
- **Computed:**
  - completion / skip / defer / missed rates by weekday, part of day and category
  - planned vs actual duration as a median ratio, by category
  - best focus windows (reflection only)
  - postponement patterns (which categories get deferred, and to when)
- **Weekly routines:** group by normalized title (falling back to category) × weekday × 30-minute start bucket. A routine counts when all of these hold:
  - at least 3 occurrences in the last 8 weeks
  - it happens on at least 60% of those weekdays
  - the last one was within 21 days
  - with confidence from the counts

  Example: Gym · Tue · 19:00 · 4/5 weeks.
- **Rule:** every output carries `sample_size` and `confidence`. Below the threshold it returns `status: "learning"` with no number.

**4c. Using patterns (as suggestions only)**
- `PlanningProfile.from_user_context` gets an optional `learned_routines` input. It's used by Build My Day and replan only when a task has **no explicit time**: matching routines become a soft slot-score bonus in `scheduling_engine.py`, near the `learned_afternoon_focus` bonus at lines 876-880.
- An explicit time or a user constraint always wins. The proposal shows a hint: "Usually Tue 7 PM".
- `avg_duration_ratio` stays display-only (no automatic duration changes).
- Pass the same history to plan_confirm, calendar and today's override so all paths agree.

## WS5 — Insights on real history
- Extend `GET /insights/summary` (`backend/app/api/routes/insights.py`) with output from `behavior_patterns`:
  - completion rate this week vs last
  - planned vs actual by category
  - best focus windows
  - postponement patterns
  - recurring routines
  - week-over-week changes

  Align the part-of-day buckets with the client (pick one definition and share it).
- In `lib/screens/insights_tab.dart`:
  - read the summary from the server
  - keep `InsightsSnapshot.compute` only as an offline fallback
  - memoize it on a data version (see WS8)
  - each section shows "still learning — N more days/tasks" when the server says `learning`
  - remove the reflections "not synced" footnote once 4a lands
- Remove the hard-coded window text in `focus_ritual_screen.dart:392` and the unused hard-coded getters in `personal_learning_engine.dart:37`.

## WS6 — Reflection sheet + Noya
- Redesign `task_feedback_sheet.dart`:
  - a one-tap feeling row plus a duration chip (shorter / about right / longer) gives a valid submission in 2 taps
  - the energy/focus/difficulty/distraction sliders and the blocker note move into an expandable "More detail" section
  - Noya appears in a small reaction pose
  - submit shows the shared thinking state
- Companion sanctuary (`flow_screen.dart:1069-1160`, `flow_companion.dart`):
  - every non-fox companion shows a polished "Coming Soon" card (silhouette art, soft shimmer, the label) and no purchase button
  - companions already owned stay selectable
  - add the cat to `CompanionAnimalInfo.all` so the list is consistent
  - backend `/flow/shop/{species}/purchase` returns 409 `coming_soon` for species no one owns yet
- **Shared Noya thinking:** route real async work through `NoyaBusy.track`:
  - Build My Day generate and confirm
  - reflection submit
  - What Should I Do
  - edit, save and reschedule sheets

  Replace their local spinners (listed by the explorer: `what_should_i_do_screen.dart:403`, `parsed_plan_confirm_sheet.dart:376`, `edit_task_sheet.dart:252,474`, `reschedule_task_sheet.dart:409`, `brain_dump_sheet.dart:2042,2096`).
  - Silent background refreshes never show the badge.
  - The badge switches from `context.watch` to `context.select` on `busy`.

## WS7 — Questionnaire
- In `onboarding_question.dart`, add `allowOther` (shows a text field when "Other" is picked) and `optional` (a Skip affordance). Answers start **unset** instead of pre-filled defaults; Continue is enabled only for an answered or optional question.
- Make `schedule_disruptors` and `session_disruptor` multi-select with Other. Mark `unpredictable_cue`, `fatigue_symptom` and the adaptive follow-ups as optional.
- Payload (`onboarding_flow_screen.dart:202-276`):
  - send `schedule_disruptors`, `unpredictable_cue`, `session_disruptor`, the `*_other` text and `adaptive_followup_answers`
  - leave out unanswered optional questions, so they become null server-side and the backend defaults apply
- Backend schema and `readiness_service.submit_onboarding_answers` store them. Personalization uses them explicitly:
  - disruptors / low `energy_predictability` → larger default buffer in the planner
  - `session_disruptor` → an Insights tip
  - `primary_goal` → a small weight on the recommendation order

  Other text is stored and shown only, never parsed into rules.

## WS8 — Performance (root causes first, then a minimal loading UI)
Ranked from the explorer's findings:
1. **Launch:**
   - delete the duplicate `loadUserTasks`/`refreshTodayData` in the provider constructor (`app_state_provider.dart:253-259`)
   - in `onUserAuthenticated`, after `/auth/me` + profile, run tasks, today and calendar together in `Future.wait`
   - the splash navigates once auth and profile are known; data fills in behind it
   - shrink the 1.6 s minimum splash to an animation-complete minimum (~600 ms)
2. **Cached Today first:** `today_service.dart` returns the cached Today right away, then refreshes silently. `refreshTodayData` sets `_isLoading` only when nothing is cached.
3. **Silent reloads on edits:** `addTask/updateTask/removeTask/rescheduleTask` call `loadCalendarDay(silent: true)` without nulling `_selectedDateSchedule`; `updateTask` loads once.
   - Also fix the duplicated `onTaskCompletedForFlow` (`app_state_provider.dart:1045` and `:1075`). This is a real bug: it double-counts quest progress locally.
4. **Rebuilds:**
   - each tab uses `context.select`/`Selector` on the slices it actually needs
   - `FlowFadeIndexedStack` builds a tab only on first visit
   - the per-second break/focus timers move to their own `ValueNotifier` instead of `notifyListeners`
   - cache `tasks`/`schedule`/`reflections` getters (unmodifiable view, sort once per change)
   - memoize the calendar stops and `InsightsSnapshot` on a `_dataVersion` counter
   - stop `recommendedTask` writing state during build
5. **Ambient background:** pause the 16 s repeat when the app isn't resumed and when `MediaQuery.disableAnimations` is set.
6. **Backend:**
   - stop the `RecommendationDecision` commit on GET `/today`: record it only when the user acts, or upsert once per day per task
   - `/today` reuses one `get_day_schedule` result
   - `day_complete_status` takes the already-loaded open/completed lists
   - `/flow` limits the focus-session query to a window or aggregate, and creates profile/quests only when missing, with no commit on every GET
   - check `pool_pre_ping` against Supabase pooler settings; change it only if measured
7. **Measure before and after:**
   - backend: per-route timing with pytest plus a SQL query-count fixture for `/today`, `/calendar/day`, `/flow`
   - Flutter: count requests made during a simulated launch (mock `ApiService`) and count rebuilds per notify
   - performance findings go in the final report

---

## Critical files
- Flutter:
  - `lib/providers/app_state_provider.dart`
  - `lib/screens/calendar_tab.dart`
  - `lib/components/flow_month_picker.dart` (new)
  - `lib/screens/insights_tab.dart`
  - `lib/models/insights_snapshot.dart`
  - `lib/screens/task_feedback_sheet.dart`
  - `lib/screens/flow_screen.dart`
  - `lib/models/flow_companion.dart`
  - `lib/models/onboarding_question.dart`
  - `lib/screens/onboarding_flow_screen.dart`
  - `lib/services/today_service.dart`
  - `lib/theme/flow_motion.dart`
  - `lib/components/noya_thinking.dart`
  - `lib/components/flow_ambient_background.dart`
  - `lib/screens/splash_screen.dart`
- Backend:
  - `app/services/calendar_service.py`
  - `app/services/replan_understanding.py`
  - `app/services/replan_ai.py`
  - `app/engines/behavior_patterns.py` (new)
  - `app/engines/scheduling_engine.py`
  - `app/api/routes/insights.py`
  - `app/api/routes/today.py`
  - `app/api/routes/tasks.py`
  - `app/services/flow_service.py`
  - `app/services/readiness_service.py`
  - `app/schemas/readiness.py`
  - `alembic/versions/010_learning_provenance.py` (new)

**Reuse:** `NoyaBusy.track`, `FlowClock`, `DayPathAnchorStore`, `buildCanonicalDayStops`, `removeCandidateWithDeps`, `replan_ai.validate`, `ai_gateway.call_provider`, `personalization_engine` bucket helpers, `candidate_dependencies.prune_dangling`.

## Verification
- **New targeted tests:**
  - Flutter:
    - `calendar_stability_regression_test`
    - `flow_month_picker_test`
    - `build_my_day_remove_test` (extended)
    - `insights_server_summary_test` (still learning vs data)
    - `task_feedback_sheet_test` (2-tap submit, sync payload has no fake values)
    - `onboarding_questionnaire_inputs_test` (multi, Other text, optional omitted)
    - `companion_coming_soon_test`
    - `launch_request_count_test` (no duplicate `/today`/`/tasks`; parallel)
    - `provider_rebuild_scope_test`
  - Backend:
    - `test_replan_natural_language.py`
    - `test_behavior_patterns.py` (routine needs evidence and recency; learning state; legacy rows excluded)
    - `test_insights_summary_history.py`
    - `test_learning_provenance.py`
    - `test_onboarding_extended_answers.py`
    - `test_today_no_write_on_get.py`
    - query-count tests for `/today` and `/flow`
- **Runs:**
  - `cd backend && pytest -q`, full suite; the baseline was ~1227 passing
  - `alembic upgrade head` on the test DB
  - `flutter analyze`
  - Flutter tests in groups (`flutter test test/calendar_* test/day_*`, then insights/feedback/onboarding, then the rest) to avoid running out of memory. Compare with the 7 known baseline failures.
- **Manual checks still needed:**
  - Calendar left open across a task's end time and across a resume
  - month picker months ahead
  - Replan phrases against real Gemini with a key set
  - first launch and warm launch speed on a device
  - Insights for a brand-new account vs a seeded one
  - onboarding with Other text
- **Final report:** files changed, tests and their results, known failures, before/after performance numbers, and the manual checks above.
