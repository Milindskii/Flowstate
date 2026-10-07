# Flowstate Senior QA & Red-Team Audit Report
**Date:** 2026-10-02  
**Reviewer:** Senior Independent QA & Red-Team Auditor  
**Scope:** Flutter Mobile Client + FastAPI Backend + Supabase Auth / PostgreSQL Architecture  
**Working Context:** Concurrent active work by Claude Sonnet (Backend Replan/Build My Day) & Claude Opus (UI/UX Motion & Noya Presentation).  
**Rules of Engagement:** Zero product code modifications. Strictly independent verification and evidence-based assessment.

---

## Executive Summary

An exhaustive, multi-vector architectural and runtime audit of the Flowstate application was conducted across all 10 priority domains: **Auth & Session Management**, **User Isolation**, **Calendar & Tasks**, **Build My Day & Replan**, **Focus & Quest**, **Flow Hub & Insights**, **Noya Companion System**, **Security & Migrations**, **Test Coverage**, and **Flutter Runtime Stability**.

The backend architecture exhibits high sophistication with robust adversarial handling in the temporal scheduling engine (685 unit/integration tests passing). However, critical vulnerabilities and architectural friction points were uncovered that pose severe risks to session continuity, data integrity, client performance, and user retention.

### Key Severity Breakdown
- **P0 Critical:** 2 issues (Uncaught Database Integrity Error during user auth provisioning; Double-dispose crash in Focus Ritual exit navigation)
- **P1 High:** 3 issues (Focus session data loss on network failure; Hardcoded LAN IP breaking Android emulator/Wi-Fi; Insights UI disconnected from backend engine)
- **P2 Medium:** 5 issues (Continuous idle 60fps animation loop in companion view; Uncompressed 1024x1024 companion texture memory bloat; Read-only Calendar cards; Inverted sleep calculation in onboarding; Plaintext API secrets)
- **P3 Low & Info:** 3 issues (Silent task fetch failure; Permissive replan date parsing; 59 Starlette deprecation warnings)

---

## Priority Audit Findings

### [P0 Critical] Issue 1: Unhandled `IntegrityError` in `get_current_user` Locks Out Users on Re-Authentication or Account Switching
- **Status:** `VERIFIED` & `REPRODUCED`
- **Classification:** P0 Critical
- **Category:** Auth & Session / Database Integrity
- **Relevant File/Function:** [`backend/app/core/security.py:get_current_user`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/backend/app/core/security.py#L156-L173)

#### Exact Problem
When a user signs in with an existing email that is already present in the local database under a different `user_id` (e.g. Supabase account re-creation, OAuth migration, provider re-linking, or testing environment reset), `get_current_user` attempts an `INSERT INTO users` without verifying email uniqueness. This triggers an uncaught `sqlalchemy.exc.IntegrityError: UNIQUE constraint failed: users.email`, which returns an unhandled **HTTP 500 Internal Server Error** on **EVERY** authenticated request, permanently bricking the app for that user.

#### Reproduction Steps
1. Insert a user record with `email="user@flowstate.local"` and `id="user-old-uuid"`.
2. Generate a valid Supabase JWT for the same email with `sub="user-new-uuid"`.
3. Make an authenticated request: `GET /api/v1/tasks` or `GET /api/v1/today`.
4. Observe the uncaught database integrity explosion.

#### Evidence
Reproduced directly against the running FastAPI instance:
```text
sqlalchemy.exc.IntegrityError: (sqlite3.IntegrityError) UNIQUE constraint failed: users.email
[SQL: INSERT INTO users (id, email, name, avatar_url, is_active, is_admin, onboarding_completed, ...) VALUES (?, ?, ?, ?, ?, ?, ?, ...)]
[parameters: ('user-new-uuid', 'user@flowstate.local', 'user', None, 1, 0, 0, ...)]
Status: 500 Internal Server Error
```

#### Why It Matters
Any user who deletes and recreates their account in Supabase, resets their credentials, or logs in via a social provider with the same email address is greeted by a continuous stream of HTTP 500 errors across all screens.

#### Regression Risk
Not a regression; an unhandled edge case in lazy user profile provisioning.

#### Suggested Fix Direction
In `backend/app/core/security.py:get_current_user`:
Query by `(User.id == user_id) | (User.email == email)`. If a user with that email already exists, update their `id` to the current `sub` (or link identity), rather than blindly issuing an `INSERT`.

---

### [P0 Critical] Issue 2: Double `AnimationController.dispose()` Crashes Flutter Runtime When Leaving Focus Session
- **Status:** `VERIFIED` & `REPRODUCED`
- **Classification:** P0 Critical
- **Category:** Focus / Quest Runtime Crash
- **Relevant File/Function:** [`lib/screens/focus_ritual_screen.dart:_onWillPop`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/screens/focus_ritual_screen.dart#L449-L460) and [`lib/screens/focus_ritual_screen.dart:dispose`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/screens/focus_ritual_screen.dart#L554-L561)

#### Exact Problem
When a user decides to leave an in-progress focus session, `_onWillPop()` explicitly calls `_timerController.dispose()` on line 450 before returning `true`. When `Navigator.of(context).pop()` finishes unmounting the route, Flutter automatically executes the state's `dispose()` lifecycle method on line 557, which calls `_timerController.dispose()` a **second time**. Calling `.dispose()` on an already-disposed `AnimationController` triggers an unhandled `FlutterError` in the framework.

#### Reproduction Steps
1. Start a focus ritual for any task from Today or Flow Hub.
2. Tap the back button or trigger the system back navigation gesture.
3. In the confirmation dialog ("Leave Focus Session?"), tap "Leave".
4. Flutter immediately asserts: `AnimationController.dispose() called more than once`.

#### Evidence
Source code in `lib/screens/focus_ritual_screen.dart`:
```dart
// Line 449 in _onWillPop():
if (shouldLeave == true && mounted) {
  _timerController.dispose(); // FIRST DISPOSE
  _countdownTimer?.cancel();
  ...
  return true;
}

// Line 555 in dispose():
@override
void dispose() {
  _countdownTimer?.cancel();
  _timerController.dispose(); // SECOND DISPOSE (CRASH)
  _animController.dispose();
  _soundService.stop();
  super.dispose();
}
```

#### Why It Matters
Every user who chooses to leave an ongoing focus session triggers an unhandled framework exception and potential app freeze or red error screen in debug/profile modes.

#### Suggested Fix Direction
Remove `_timerController.dispose()` from `_onWillPop()`. Let Flutter's canonical state lifecycle method `dispose()` perform the cleanup once when the widget tree unmounts.

---

### [P1 High] Issue 3: Focus Session Completion Irrevocably Drops Progress, XP, and Streak on Transient Network Error
- **Status:** `VERIFIED` & `REPRODUCED`
- **Classification:** P1 High
- **Category:** Focus / Quest Data Integrity
- **Relevant File/Function:** [`lib/providers/flow_provider.dart:completeSession`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/providers/flow_provider.dart#L240-L247)

#### Exact Problem
When a user finishes a focus session (e.g. 50 minutes of deep work) and taps "Complete Session", `FlowProvider.completeSession()` executes a network POST to `/api/v1/flow/session/{id}/complete`. If this network request encounters a temporary network blip, timeout, or unreachable gateway, the `catch (e)` block immediately wipes `_activeSessionId = null`, cancels the timer, and resets `_sessionElapsedSeconds = 0` before rethrowing.

The local session ID is permanently obliterated without being stored in local cache or enqueued for background retry. The server session remains orphaned and unclosed, the user receives 0 XP, 0 Flow Points, the daily quest does not record completion, and the user is barred from retrying.

#### Reproduction Steps
1. Start a focus session in `FlowProvider`.
2. Disable device Wi-Fi/cellular or toggle Airplane Mode.
3. Tap "Complete Session".
4. `completeSession()` catches the `SocketException`.
5. Observe that `_activeSessionId` is immediately set to `null` and lost forever.

#### Evidence
`lib/providers/flow_provider.dart` lines 240-247:
```dart
    } catch (e) {
      _activeSessionId = null; // PERMANENT LOSS
      _sessionTimer?.cancel();
      animController.setIdle();
      notifyListeners();
      rethrow;
    }
```

#### Why It Matters
Focusing is the primary value proposition of Flowstate. Losing 45–90 minutes of verified effort due to a 2-second Wi-Fi drop destroys user trust and corrupts streak progression.

#### Suggested Fix Direction
Do NOT nullify `_activeSessionId` on network failure. Retain `_activeSessionId` and session metadata in `SharedPreferences` as a `pending_completion` queue. Provide an inline "Retry sync" banner so the user can claim their earned XP once connection is restored.

---

### [P1 High] Issue 4: Hardcoded LAN IP in `ApiService` Breaks All Connectivity on Android Emulators and Standard Wi-Fi Networks
- **Status:** `VERIFIED` & `REPRODUCED`
- **Classification:** P1 High
- **Category:** Networking / Client-Server Integration
- **Relevant File/Function:** [`lib/services/api_service.dart:baseUrl`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/services/api_service.dart#L23-L44)

#### Exact Problem
`ApiService._defaultLanIp` is hardcoded to `192.168.1.9`. On Android, `baseUrl` returns `http://192.168.1.9:8000` unless `--dart-define=API_BASE_URL` is explicitly passed.
On standard Android emulators (`emulator-5554`), the host machine is routed via `10.0.2.2`, and standard user Wi-Fi subnets vary (e.g. current host IP is `192.168.43.199`). As a result, the Android client attempts to connect to an unreachable LAN address, causing every single API request to time out or fail. Because exceptions are swallowed silently throughout `AppStateProvider`, the app operates in an uncalibrated, disconnected state without notifying the user.

#### Reproduction Steps
1. Run `flutter run -d emulator-5554` without `--dart-define=API_BASE_URL`.
2. Inspect network traffic: requests are addressed to `192.168.1.9:8000` instead of `10.0.2.2:8000`.
3. All network operations fail with `Connection refused / timed out`.

#### Evidence
Current Windows host network configuration:
```text
Wireless LAN adapter Wi-Fi:
   IPv4 Address: 192.168.43.199
```
`lib/services/api_service.dart` line 23:
```dart
static const String _defaultLanIp = '192.168.1.9'; // Broken on emulator and non-192.168.1.x subnets
```

#### Why It Matters
Any developer, automated CI test runner, or QA tester spinning up an Android emulator will experience 100% network failure by default.

#### Suggested Fix Direction
Check for emulator environment: on Android, if running in an emulator (or as a fallback when `_configuredBaseUrl` is empty), default to `http://10.0.2.2:8000`.

---

### [P1 High] Issue 5: Insights Tab Calls Wrong Backend Endpoint, Bypassing the Entire Evidence-Driven Insights Engine
- **Status:** `CODE-LEVEL RISK` & `VERIFIED`
- **Classification:** P1 High
- **Category:** Insights / Analytics Integrity
- **Relevant File/Function:** [`lib/screens/insights_tab.dart:_loadEvaluationMetrics`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/screens/insights_tab.dart#L36) vs [`backend/app/api/routes/insights.py:get_insights_summary`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/backend/app/api/routes/insights.py#L74)

#### Exact Problem
The backend team engineered a rich, evidence-driven insights service: `GET /api/v1/insights/summary`, which computes `total_sessions`, `total_focus_minutes`, `completion_rate`, `time_of_day_performance`, `duration_accuracy`, and `hourly_rhythm` across all historical observations.

However, `InsightsTab` in Flutter calls `GET /api/v1/personalization/evaluation` instead. That endpoint is designed solely for statistical model calibration scoring (Brier calibration score). Because of this mismatch:
1. Historical database sessions are ignored.
2. The UI falls back to filtering `state.tasks.where((t) => t.isCompleted)`, which only contains in-memory tasks from today.
3. The Circadian Rhythm curve is forced to fall back to hardcoded binary strings:
   ```dart
   state.personalData.focusPeak.toLowerCase() == 'afternoon' ? '2 PM (Peak)' : '10 AM (Peak)'
   ```
   completely ignoring the user's actual database readiness profile peak and dip times.

#### Evidence
In `lib/screens/insights_tab.dart` line 36:
```dart
final res = await appState.apiService.get('/api/v1/personalization/evaluation');
```
In `backend/app/api/routes/insights.py` line 73:
```python
@router.get("/summary", response_model=InsightsSummaryResponse)
def get_insights_summary(...):
```

#### Why It Matters
Insights claims to be "evidence-driven learning from verified focus sessions", but the client is disconnected from the backend insights engine, showing heuristic client approximations instead of true personalized data.

#### Suggested Fix Direction
Wire `InsightsTab` to call `GET /api/v1/insights/summary` and populate the charts directly from `InsightsSummaryResponse`.

---

### [P2 Medium] Issue 6: Unnecessary Continuous 60/120fps Animation Loop in `FlowCompanionView` Drains Battery
- **Status:** `VERIFIED`
- **Classification:** P2 Medium
- **Category:** Noya Motion / Performance
- **Relevant File/Function:** [`lib/components/companion/flow_companion_view.dart`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/components/companion/flow_companion_view.dart#L75-L76) and lines 154-159

#### Exact Problem
In `_FlowCompanionViewState`, `_pulseController.repeat(reverse: true)` is launched inside `didChangeDependencies()`. This controller repeats indefinitely every 2400ms at 60/120 fps regardless of the companion's state.

Line 157 evaluates:
```dart
final scale = reduceMotion ? 1.0 : (state == CompanionAnimState.focusing ? _pulseAnimation.value : 1.0);
```
When `state != CompanionAnimState.focusing` (which is true 95% of the time, such as in `idle`, `sleepy`, `starting`, `evolution`), `scale` is locked to `1.0`. Yet because `AnimatedBuilder` listens directly to `_pulseAnimation`, it rebuilds its child subtree on **every single frame**, consuming CPU/GPU cycles for zero visual change.

#### Evidence
`lib/components/companion/flow_companion_view.dart` lines 75 and 157-158.

#### Why It Matters
Flowstate is designed to sit open on desks during study and work. Running continuous ticker animations when the companion is completely idle causes unnecessary thermal heating and battery degradation on mobile devices.

#### Suggested Fix Direction
Only invoke `_pulseController.repeat()` when `state == CompanionAnimState.focusing`. Call `_pulseController.stop()` and reset to `1.0` when transitioning out of `focusing`.

---

### [P2 Medium] Issue 7: Uncompressed 1024x1024 Companion PNG Assets Loaded Without Downsampling
- **Status:** `VERIFIED`
- **Classification:** P2 Medium
- **Category:** Noya Assets / Memory Overhead
- **Relevant File/Function:** [`lib/components/noya_companion_view.dart:build`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/components/noya_companion_view.dart#L248-L260)

#### Exact Problem
The 7 canonical Noya state assets in `assets/images/companions/noya/` are 1024x1024 RGBA PNGs averaging ~900 KB each (totaling ~6.1 MB).
In `NoyaCompanionView`, `Image.asset` displays these images at `NoyaSize.small = 40.0` or `NoyaSize.normal = 50.0`.
Because `cacheWidth` and `cacheHeight` are omitted from `Image.asset`, Flutter's image cache decodes the complete 1024x1024 RGBA bitmap (~4.2 MB of uncompressed memory per image) into RAM rather than a ~120x120 thumbnail.

#### Evidence
Asset directory inspection:
- `noya_celebrating.png`: 1024x1024, 963 KB
- `noya_focusing.png`: 1024x1024, 1.04 MB
- `noya_thinking.png`: 1024x1024, 960 KB
- `noya_default.png`: 1024x1024, 836 KB

In `lib/components/noya_companion_view.dart` line 248:
```dart
Widget characterImage = Image.asset(
  state.assetPath,
  width: size,
  height: size,
  fit: BoxFit.contain,
  filterQuality: FilterQuality.high,
  // MISSING: cacheWidth / cacheHeight
);
```

#### Why It Matters
When several Noya widgets appear on screen or switch states rapidly in lists or sheets, decoding full-resolution textures creates avoidable memory pressure, GC pauses, and frame drops on low-to-mid-tier devices.

#### Suggested Fix Direction
Specify `cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round()` on `Image.asset`.

---

### [P2 Medium] Issue 8: Calendar Day Timeline Cards are 100% Static / Read-Only
- **Status:** `VERIFIED`
- **Classification:** P2 Medium
- **Category:** Calendar / UX Consistency
- **Relevant File/Function:** [`lib/screens/calendar_tab.dart:_buildTimelineCard`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/screens/calendar_tab.dart#L514-L609)

#### Exact Problem
Unlike the Today tab and Tasks tab where task cards support tapping to complete, edit, reschedule, or launch focus, every timeline card rendered on the Calendar tab (`_buildTimelineCard`) is a plain, unclickable `Container`.
There is no checkbox, no tap listener, no long-press action, and no options sheet. A user inspecting their schedule on the Calendar who wishes to mark a task as completed, change its time, or start working on it has no interactive recourse except leaving the tab and searching for it on Today.

#### Reproduction Steps
1. Navigate to the Calendar tab.
2. Tap on any scheduled task card.
3. Observe zero response and complete lack of interactive affordance.

#### Evidence
`lib/screens/calendar_tab.dart` lines 514-609: `card` has no `GestureDetector`, `InkWell`, or button callback.

#### Suggested Fix Direction
Wrap `_buildTimelineCard` with a `GestureDetector` that opens `EditTaskSheet.show(context, matchingTask)` or provides contextual action icons (Complete, Reschedule, Focus).

---

### [P2 Medium] Issue 9: Onboarding Questionnaire Persists Heuristic Sleep Duration Rather Than User Input
- **Status:** `CODE-LEVEL RISK` & `VERIFIED`
- **Classification:** P2 Medium
- **Category:** Questionnaire / Personalization State
- **Relevant File/Function:** [`lib/screens/onboarding_flow_screen.dart`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/screens/onboarding_flow_screen.dart#L287-L294)

#### Exact Problem
When completing the onboarding questionnaire, line 290 calculates the user's `sleepHours` using:
```dart
sleepHours: (inertiaMins / 60.0) + 7.5
```
Sleep inertia (`inertiaMins`) represents waking grogginess (typically 15 to 45 minutes), not total sleep duration. This formula forces sleep duration into an arbitrary range of 7.5 to 8.25 hours, entirely discarding the user's actual bedtime (`sleep_time`) and wake time (`wake_weekday`).

#### Evidence
`lib/screens/onboarding_flow_screen.dart` lines 287-294.

#### Why It Matters
Users who sleep 5 hours or 9 hours have their local `PersonalData` corrupted with a synthetic 7.75-hour value, degrading the accuracy of the client-side scheduling engine.

#### Suggested Fix Direction
Calculate `sleepHours` by taking the time difference between `_answers['wake_weekday']` and `_answers['sleep_time']`.

---

### [P2 Medium] Issue 10: Live Production Supabase Credentials and Plaintext AI Keys in Config Files
- **Status:** `CODE-LEVEL RISK` & `VERIFIED`
- **Classification:** P2 Medium
- **Category:** Security & Environment Configuration
- **Relevant File/Function:** [`backend/app/core/config.py`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/backend/app/core/config.py#L16-L19) and [`lib/core/config/env_config.dart`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/core/config/env_config.dart#L4-L12)

#### Exact Problem
1. `backend/app/core/config.py` hardcodes live default fallback strings for `SUPABASE_URL`, `SUPABASE_KEY`, and `SUPABASE_JWT_SECRET = "flowstate-local-dev-secret-replace-in-production"`.
2. `lib/core/config/env_config.dart` hardcodes default values pointing to the live Supabase production project (`drfjprhnynktjkiplbzy.supabase.co`).
3. While `backend/.env` is gitignored, the presence of hardcoded live fallbacks in committed source code risks accidental exposure if secrets change.

#### Evidence
Lines 16-19 in `config.py` and lines 4-12 in `env_config.dart`.

#### Suggested Fix Direction
Ensure default configuration values fail closed in non-development environments, requiring explicit environment variable injection.

---

### [P3 Low] Issue 11: `loadUserTasks()` Silently Discards Network and Authorization Exceptions
- **Status:** `VERIFIED`
- **Classification:** P3 Low
- **Category:** Error Handling / Resilience
- **Relevant File/Function:** [`lib/providers/app_state_provider.dart:loadUserTasks`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/lib/providers/app_state_provider.dart#L1542-L1550)

#### Exact Problem
In `AppStateProvider.loadUserTasks()`, `try { final remoteTasks = await taskService.getTasks(); ... } catch (_) {}` silently swallows all exceptions without setting an error state, logging to telemetry, or showing an offline retry banner.

#### Suggested Fix Direction
Set `_errorMessage` or an offline state variable when `loadUserTasks()` fails so the Tasks tab can present an offline indicator or retry button.

---

### [P3 Low] Issue 12: Permissive Date Parameter Handling on `/calendar/replan`
- **Status:** `VERIFIED`
- **Classification:** P3 Low
- **Category:** Input Validation
- **Relevant File/Function:** [`backend/app/schemas/calendar.py:ReplanRequest`](file:///c:/FULL%20STACK%20WEBDEVLOPMENT/FLowstate/backend/app/schemas/calendar.py#L49)

#### Exact Problem
The endpoint `POST /api/v1/calendar/replan` accepts arbitrary date strings like `"1970-01-01"` or `"invalid-date"` without rejecting them with HTTP 422. When an invalid date is passed, it silently defaults to today; when `1970-01-01` is passed, it returns a 200 response with an empty plan for 1970.

#### Suggested Fix Direction
Enforce ISO 8601 YYYY-MM-DD regex or Pydantic `datetime.date` validation on `ReplanRequest.selected_date`.

---

### [INFO] Issue 13: 59 Starlette Deprecation Warnings in Backend Test Suite
- **Status:** `VERIFIED`
- **Classification:** INFO
- **Relevant File/Function:** `backend/tests/`
- **Description:** Pytest outputs 59 deprecation warnings: `StarletteDeprecationWarning: HTTP_422_UNPROCESSABLE_ENTITY is deprecated, use HTTP_422_UNPROCESSABLE_CONTENT instead`.
- **Recommendation:** Replace `status.HTTP_422_UNPROCESSABLE_ENTITY` with `status.HTTP_422_UNPROCESSABLE_CONTENT` across backend test assertions when updating dependencies.

---

## Red-Team Adversarial Matrix Results

| Vector / Input | Target Endpoint | Expected Behavior | Observed Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| Empty `user_message` | `POST /calendar/replan` | HTTP 422 Unprocessable | HTTP 422 (`invalid_replan_request`) | **PASS** |
| 100k Character Message | `POST /calendar/replan` | HTTP 422 / 413 | HTTP 422 (`message_too_long`) | **PASS** |
| 0-Minute Task Duration | `POST /tasks` | HTTP 422 Validation Error | HTTP 422 (`ge=5`) | **PASS** |
| 1-Minute Task Duration | `POST /tasks` | HTTP 422 Validation Error | HTTP 422 (`ge=5`) | **PASS** |
| 20-Hour Task Duration | `POST /tasks` | HTTP 422 Validation Error | HTTP 422 (`le=480`) | **PASS** |
| Empty Task Title | `POST /tasks` | HTTP 422 Validation Error | HTTP 422 (`min_length=1`) | **PASS** |
| 10k Character Task Title | `POST /tasks` | HTTP 422 Validation Error | HTTP 422 (`max_length=255`) | **PASS** |
| Malformed JSON Payload | `POST /tasks` | HTTP 422 JSON Decode Error | HTTP 422 (`json_invalid`) | **PASS** |
| Cross-User Task Read | `GET /tasks/{victim_id}` | HTTP 404 Not Found | HTTP 404 (`Task not found`) | **PASS** |
| Cross-User Task Patch | `PATCH /tasks/{victim_id}`| HTTP 404 Not Found | HTTP 404 (`Task not found`) | **PASS** |
| Cross-User Apply Replan | `POST /calendar/apply-replan`| Reject or Ignore Victim | HTTP 200, 0 tasks altered | **PASS** |
| Replan Conflicting Fixed Tasks | `POST /calendar/replan` | Flag Conflict, No Crash | HTTP 200 with conflict noted | **PASS** |
| Impossible Past Deadline | `POST /calendar/replan` | Flag Warning, No Crash | HTTP 200 with conflict noted | **PASS** |
| Non-Existent `plan_id` Apply | `POST /calendar/apply-replan`| No-op / Idempotent Safe | HTTP 200 with 0 updated | **PASS** |
| Existing Email New `user_id` | `GET /tasks` (Auth hook) | Link or Graceful Auth | **HTTP 500 Uncaught DB Error** | **FAIL (P0)** |

---

## Synthesis & Category Breakdown

### 1. Critical Issues (P0)
1. **User Provisioning Crash:** Unhandled `IntegrityError` in `backend/app/core/security.py:get_current_user` causes HTTP 500 on all endpoints when user credentials contain an email already bound to a prior `user_id`.
2. **Focus Navigation Crash:** Double `_timerController.dispose()` call in `lib/screens/focus_ritual_screen.dart` crashes the Flutter framework when backing out of a focus session.

### 2. High-Priority Issues (P1)
1. **Focus Session Abandonment on Network Failure:** `FlowProvider.completeSession()` wipes the session ID on any network exception, permanently discarding user focus duration, XP, and streak.
2. **Hardcoded Emulator LAN IP:** `ApiService._defaultLanIp = '192.168.1.9'` prevents standard Android emulators (`10.0.2.2`) and non-matching Wi-Fi subnets from connecting to the backend.
3. **Insights API Routing Disconnect:** `InsightsTab` calls `/api/v1/personalization/evaluation` instead of `/api/v1/insights/summary`, stranding the evidence-driven insights engine and displaying heuristic approximations.

### 3. Medium & Low Issues (P2 / P3)
1. **Unnecessary Continuous Animation:** `FlowCompanionView` loops a 2400ms pulse animation at 60/120 fps even when companion state is idle, causing continuous rebuilds.
2. **Texture Memory Overhead:** 1024x1024 companion PNG assets (~1MB each) decoded without `cacheWidth` for 40–50px thumbnail avatars.
3. **Read-Only Calendar Cards:** Calendar day timeline cards lack tap listeners or action sheets for completion, editing, or rescheduling.
4. **Heuristic Onboarding Sleep Duration:** Onboarding calculates `sleepHours = (inertiaMins / 60.0) + 7.5` instead of using actual user sleep and wake timestamps.
5. **Permissive Replan Date Parsing:** `/calendar/replan` accepts invalid or historical dates like `"1970-01-01"`.

### 4. Regression Risks
- **Replan Temporal Ordering:** Claude Sonnet's active work on backend replan must ensure that newly inserted tasks never overwrite `time_locked = True` commitments or produce start times in the past.
- **Noya Motion State Transitions:** Claude Opus's active UI motion work must verify that animation controllers are disposed exactly once, and that `TickerProvider` tickers are paused when screens are pushed offstage.

### 5. Missing Test Coverage
1. **Auth Re-provisioning:** No existing pytest covers user re-registration where `email` matches an existing row but `sub` differs.
2. **Offline Focus Completion:** No Flutter integration test covers network interruption during `completeSession()`.
3. **Calendar Card Interactions:** No test verifies tap gestures on calendar day timeline cards (because none exist).

### 6. Security Findings
1. User-scoped data isolation on tasks, flow sessions, and replanning is strictly enforced at the database query level; cross-user tampering attempts are cleanly rejected.
2. Rate limiting (`RateLimitMiddleware`, `MAX_PARSE_PER_MINUTE = 10`) is operational and verified.
3. Hardcoded default secret strings in `config.py` and `env_config.dart` should be scrubbed for production deployments.

### 7. Runtime Findings
- Live execution on `emulator-5554` confirmed smooth 60fps Impeller rendering of the Today Dashboard.
- `flutter analyze` completed with 0 errors.
- Visual inspection of the Splash Screen identified a subtle tinted bounding rectangle behind Noya caused by `RadialGradient` inside a square container.

---

## Recommended Next Actions

1. **For Backend (Claude Sonnet):**
   - In `backend/app/core/security.py:get_current_user`, catch `IntegrityError` or query `User` by `(id == user_id) | (email == email)` and update the `id` mapping instead of failing with HTTP 500.
   - Add strict `date` validation to `ReplanRequest.selected_date`.

2. **For Frontend (Claude Opus):**
   - Remove `_timerController.dispose()` from `_onWillPop()` in `lib/screens/focus_ritual_screen.dart` to resolve the P0 framework crash.
   - Guard `FlowProvider.completeSession()` against network drops by caching pending session completions in `SharedPreferences` instead of clearing `_activeSessionId`.
   - Update `FlowCompanionView` to only animate `_pulseController` when `state == CompanionAnimState.focusing`.
   - Wire `InsightsTab` to `GET /api/v1/insights/summary`.
   - Add `cacheWidth` to `Image.asset` in `NoyaCompanionView` to prevent high-resolution texture memory bloat.
   - Support `http://10.0.2.2:8000` fallback in `ApiService` for Android emulators.
