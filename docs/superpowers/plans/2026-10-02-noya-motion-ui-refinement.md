# Noya Motion & UI Refinement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Noya a living, restrained companion inside the existing Flowstate UI and refine Calendar, containers, dark mode and task colors, without changing Flowstate's visual identity.

**Architecture:**
- A new `NoyaMotionView` wraps the unchanged static `NoyaCompanionView` and adds pose crossfades, bounded mood loops and spring-driven one-shot reactions, all with Flutter SDK animation.
- Reactions flow through a `NoyaReactionController` owned by the existing `FlowCompanionAnimationController`.
- Calendar and Today converge on one shared timeline row evolved from `TimelineItemWidget`.
- Task colors ship client-first (M7a) with on-device persistence. Backend sync is a separate milestone (M7b).

**Tech Stack:** Flutter 3.47.4 / Dart 3.13.3, `provider`, `shared_preferences`, `intl` (all already in `pubspec.yaml`); FastAPI + SQLAlchemy + Alembic backend (M7b only). **No new dependencies.**

**Spec:** `docs/superpowers/specs/flowstate-noya-motion-system.md` (Rev 2). Section references below (§n, Bn) point into it. §24 supersedes earlier sections where they conflict.

**Execution skills:** `animate` (Noya motion tasks) and `tastemaker` (screenshot critique at milestone gates), both under the **Skill Usage Protocol** below. The spec stays the source of truth; neither skill can override it.

## Global Constraints

- **Never commit.** User rule; the working tree has many unrelated uncommitted changes. Every task ends at a checkpoint, not a commit.
- **Never weaken tests.** Changed assertions are replaced with equal-or-stronger assertions in the same task (spec D1).
- **No new package.** No `rive`, `lottie`, `flame` or `flutter_animate` (§16.1, §24.1).
- **Paused test (§4.1):** with animation at rest or reduced motion on, resting visuals equal today's, except the Part B refinements.
- **Noya art:** only the files listed in §2.1/§2.2. Never `winking_fox.png`. No asset files are created, moved or edited in this plan.
- **Pose → file:**
  - idle `noya/noya_default.png`
  - thinking `noya/noya_thinking.png`
  - focusing `noya/noya_focusing.png`
  - celebrating `noya/noya_celebrating.png`
  - encouraging `noya/noya_encouraging.png`
  - proud `noya/noya_proud.png`
  - sleepy `noya/noya_sleepy.png`
  - **delighted `noya_success.png`**
  - **windDown `noya_sleeping.png`** (both root `companions/`)
- **Timing/curve/spring values:** exactly as in §10 and §11 (copied into Task 1).
- **Amplitude limits (fraction of Noya size `s`):**
  - breath 1.2% scaleY / 0.006·s
  - think 2° / 0.008·s
  - pace 0.08·s horizontal / 0.025·s vertical
  - greet 4° / 0.03·s
  - taskDone and planReady 0.06·s / 4%
  - celebrate 0.12·s / 4% squash
  - energetic (in-progress physical task, §6.9) 0.02·s at a 1,200 ms period, 6 cycles max
  - UI motion ≤ 16 px
- **Typography (B5):** no `fontSize` override below 12.5 in touched files.
- **No Noya loops below 48 px.** At most one Noya loop per screen. All loops are bounded (`idleWindow` 30 s; focus bob 20 s; NOW pulse 3 cycles).
- **L3 (celebrate) cap:** 3 per local day; extras downgrade to `taskDone`.
- **Reduced motion = `MediaQuery.disableAnimations`:**
  - no transforms or loops
  - pose change is a 120 ms fade
  - enter is a 150 ms fade
- **Copy fixed by the spec:**
  - "Sign in to sync your progress" / "Sign in"
  - "Still organizing. Long lists take a little longer."
  - "Focus window <range>"
  - state labels "Fixed", "Conflict", "Missed", "Suggested", "Unscheduled"
  - "No plan for <Weekday> yet." (unchanged)
  - "Build My Day" (unchanged)
  - the "NOW" landmark (unchanged)
- **Task palette values:** exactly §24.3, including amber light `#B45309` and lime light `#4D7C0F`.
- **Untouched (all tasks):**
  - scheduling/replan logic
  - task status transitions
  - API contracts (except M7b)
  - `loadCalendarDay` / `selectedCalendarDate` semantics
  - navigation semantics
  - auth architecture (Task 24 adds a getter only)
- **Commands.** Flutter tests run in this shell (verified 2026-10-02).
  - `flutter test <file>`: pass = `All tests passed!`
  - `dart analyze lib test`: pass = no new issues beyond the 2 baseline `prefer_const_constructors` infos
  - backend `backend/venv/Scripts/python -m pytest -q`: baseline 1160 passed
- **Flutter suite baseline (2026-10-02):** 226 pass / 47 fail, mostly `pumpAndSettle timed out`. Milestone gates require the failing set to be a **subset** of the Task 0 baseline list.

- **Skills never override the spec.** `animate` and `tastemaker` are used only as defined in the Skill Usage Protocol. Any recommendation that conflicts with the spec, this plan's tests, or the existing visual identity is logged for the user, not applied.

## Skill Usage Protocol

### `animate` — Noya motion tasks (7, 8, 9, 10, 14 [Noya empty state only], 17, 20, 23, 25, and the contingent asset tasks)

- **When:** Step 0 of each listed task, before the failing tests are written. TDD order is unchanged: tests (Step 1) still come before implementation (Step 3).
- **How:** invoke the `animate` skill and walk its decision order (should it animate → purpose → tool → properties → curve → duration → interruption → exit). Each answer **comes from the spec**, not from a fresh choice:

  | animate decision | Fixed answer source |
  |---|---|
  | Should it animate / purpose | §4 principle 3 + the task's §6/§7 entry ("what does this movement communicate") |
  | Tool | Flutter SDK only: `AnimationController`, `AnimatedSwitcher`, `SpringSimulation` (§16.1, §24.1). No package. |
  | Properties | Transform (translate/scale/rotate about bottom-center) + opacity only (§11 rules) |
  | Curve / spring | §11 tokens via `FlowMotion` (Task 1): `emphasized`, `exit`, `loop`, `reactionSpring`, `celebrationSpring`, `settleSpring` |
  | Duration | §10 tokens via `FlowMotion` (Task 1) |
  | Amplitude | Global Constraints amplitude limits (§11 table) |
  | Interruption | §5.3 priority/coalescing/rate limits (`NoyaReactionController`, Task 6); dispose/navigation rules (Review Focus 4) |
  | Exit / end state | The task's §6 "End" + "Fallback" lines; loops bounded per §17 P2 |
  | Reduced motion | §18 table |

- **Output:** a short "animate walk-through" note (one line per decision, each citing its spec section) recorded in the task checkpoint summary. Code that `animate` produces must use the `FlowMotion` tokens by name (no literal durations, curves or amplitudes) and must pass the task's plan tests unchanged.
- **Deviations:** if `animate` recommends a value, curve, property or behavior that differs from the spec, **do not apply it.** Record it as `ANIMATE-DEVIATION: <what> — spec says <value> (§n) — proposed <value> — reason` in the checkpoint summary for the user to decide. A spec change goes through a spec revision, never through implementation.
- **Out of scope for `animate`:** non-Noya UI motion (date strip, rows, shimmer, highlight pulse, completion check) follows the spec and plan tests directly.

### `tastemaker` — screenshot critique at milestone gates (M2, M3, M4, M5, M6, M7a, M8)

- **When:** at each listed milestone gate, after automated tests pass and the manual screenshots are captured. A gate does not pass until the `tastemaker` findings are triaged.
- **Input:**
  - **before:** the original evidence S1–S8 (spec "Evidence sources"), or the previous milestone's after set
  - **after:** `docs/superpowers/specs/ui-reference/after/<milestone>/` in light and dark, at 360×640 and 412×915
- **Output:** a chat critique. An optional local HTML report goes in the session scratchpad. No Figma cards and no external publishing.
- **Scope:** `tastemaker`'s craft-floor rules (spacing, type, color, shadow, alignment, density) are judged **against the spec** (Part B acceptance criteria, §4 paused test, preserved identity). Its "character / point of view" findings are informational: a finding that pushes toward a new identity or a redesign is **not** actionable.
- **Triage** (every finding gets exactly one class in the gate summary):
  - **A — Spec violation** (breaks a spec acceptance criterion, the paused test, or the preserved identity): fix inside the milestone; the gate stays closed until A = 0.
  - **B — Craft defect consistent with the spec** (e.g. misaligned baseline, off-token spacing in a touched file): fix if it's in a file the milestone touched and needs no spec change; otherwise log it for M8.
  - **C — Conflicts with the spec or proposes redesign:** log as `TASTEMAKER-DEFERRED` for the user. No change.
- **Limits:** `tastemaker` does not replace the accessibility, contrast and reduced-motion checks in spec §22, or Performance Layers 1–3. Those stay mandatory.

## Review Focus

1. **Double-fired completion.** `onTaskCompletedForFlow` fires twice per completion (optimistic + after backend, `app_state_provider.dart:688,715`). Noya must react **once**. The test lives in Task 19.
2. **Un-completing a task, or completing via the title/`sched-` fallback lookup** (`toggleTaskCompletion` lines 661–668). Un-complete never reacts; completion found by fallback lookup still reacts once. Task 19.
3. **Reduced motion switched on while a loop or reaction runs.** The animation stops at the rest frame on the next frame, with no exception. Task 8 and Task 9.
4. **Screen closed mid-animation** (Build My Day sheet dismissed while planning; navigate away during greet). No `setState` after dispose, and the reaction is not replayed on return. Task 9 and Task 17.
5. **Text scale 1.3 at 360 dp width.** The date strip, timeline row gutter and plan rows render with no overflow, and the gutter grows instead of truncating the time. Task 12 and Task 13.

---

## File map

| File | Status | Responsibility | Tasks |
|---|---|---|---|
| `test/flutter_test_config.dart` | create | Global test setup: disables loops for all tests (`FlowMotion.debugLoopsEnabled = false`) | 1 |
| `lib/theme/flow_motion.dart` | modify | Tokens, curves, springs, `loopsEnabled`, `FlowMotionScope`, `switcher` | 1 |
| `lib/components/companion/flow_companion_view.dart` | modify | Remove the `'Test'` hack and the pulse controller; render via `NoyaMotionView` | 2, 10 |
| `lib/components/flow_ambient_background.dart` | modify | Remove the `'Test'` hack; `RepaintBoundary`; `loopsEnabled` | 2 |
| `lib/components/noya_companion_view.dart` | modify | `cacheWidth`; +2 `NoyaState`s; `NoyaAssets.precache` | 3, 5 |
| `lib/components/skeleton_loaders.dart` | modify | `FlowShimmerScope` shared driver | 4 |
| `lib/components/companion/noya_reaction_controller.dart` | create | `NoyaReaction`, `NoyaReactionEvent`, `NoyaReactionController` | 6 |
| `lib/components/companion/flow_companion_animation_controller.dart` | modify | Owns a `NoyaReactionController reactions` | 6 |
| `lib/components/noya_motion_view.dart` | create | `NoyaMood`, `NoyaMotionView`, `NoyaWakeScope` | 7, 8, 9 |
| `lib/components/flow_date_strip.dart` | create | Date strip extracted from Calendar | 12 |
| `lib/components/timeline_item_widget.dart` | modify | Becomes the shared row (`FlowTimelineRow`; old class kept as a typedef alias) | 13, 16, 29 |
| `lib/components/flow_completion_check.dart` | create | Animated check | 16 |
| `lib/components/flow_highlight_pulse.dart` | create | One-shot "what changed" tint | 18 |
| `lib/screens/calendar_tab.dart` | modify | Uses the strip and row; actions, focus line, skeleton, empty Noya, date slide | 11, 14 |
| `lib/components/timeline_current_time_marker.dart` | modify | Bounded NOW pulse | 15 |
| `lib/screens/today_dashboard_tab.dart` | modify | Shared row; Noya behaviors | 15, 20 |
| `lib/providers/app_state_provider.dart` | modify | `onTaskCompletedForNoya`, `hasPendingTasksToday`, `recentlyChangedTaskIds`, task colors | 18, 19, 27 |
| `lib/screens/main_shell.dart` | modify | Wires the completion → reaction hook | 19 |
| `lib/screens/brain_dump_sheet.dart` | modify | Header/status refinement, motion, escalation, plan rows, color dot | 17, 18, 29 |
| `lib/screens/replan_day_sheet.dart` | modify | Thinking/recover motion | 17 |
| `lib/screens/ai_plan_preview_sheet.dart`, `lib/screens/parsed_plan_confirm_sheet.dart` | modify | Plan row anatomy + reveal | 18 |
| `lib/components/task_card.dart`, `lib/components/right_now_task_card.dart` | modify | Completion check; color accent; card metadata line | 16, 29, 32 |
| `lib/theme/flow_colors.dart` | modify | Dark tokens, `noyaWarm`, `tagBackground`, deprecations | 21, 22 |
| `lib/components/compact_readiness_card.dart`, `break_session_card.dart`, `task_difficulty_badge.dart`, `readiness_hero_card.dart`, `lib/screens/task_inbox_tab.dart`, `lib/engines/scheduling_engine.dart` (tag colors only) | modify | Dark-mode sweep | 22 |
| `lib/screens/focus_ritual_screen.dart`, `lib/screens/flow_screen.dart` | modify | Focus/Hub motion; auth prompt | 23, 24 |
| `lib/providers/flow_provider.dart` | modify | `isAuthRequired` getter only | 24 |
| `lib/screens/onboarding_flow_screen.dart`, `lib/components/routine_building_view.dart`, `lib/screens/splash_screen.dart`, `lib/screens/auth_screen.dart` | modify | Crossfades, greet, single enter | 25 |
| `lib/theme/flow_task_colors.dart` | create | `FlowTaskColor` palette | 26 |
| `lib/services/task_color_store.dart` | create | On-device `taskId → colorKey` | 27 |
| `lib/models/task_item.dart`, `lib/models/schedule_item.dart` | modify | `colorKey` field | 27 |
| `lib/components/flow_task_color_picker.dart` | create | Swatch strip + preview | 28 |
| `lib/components/edit_task_sheet.dart`, `lib/screens/add_task_sheet.dart`, `lib/components/plan_diff_view.dart` | modify | Color row; accent rendering | 28, 29 |
| `backend/alembic/versions/007_task_color_key.py`, `backend/app/models/task.py`, `backend/app/schemas/task.py`, `backend/app/schemas/calendar.py`, `backend/app/schemas/today.py`, `backend/app/services/calendar_service.py`, `backend/app/services/plan_confirm_service.py` | create/modify | M7b only | 30 |
| `lib/services/task_service.dart` | modify | M7b only: send `color_key` | 31 |

---

## Milestone M-1 — Baseline

### Task 0: Diagnose the red baseline (no product change unless it is motion infrastructure)

**Files:** none modified, except a fix that falls inside Task 1/2 scope.

- [ ] **Step 1:** Run `flutter test --reporter json > %TEMP%\baseline.json` and save the sorted list of failing test names to the scratchpad as `baseline-failures.txt` (expected count: 47).
- [ ] **Step 2:** Using superpowers:systematic-debugging, find the root cause of `pumpAndSettle timed out` in `test/calendar_date_navigation_test.dart` "5. CalendarTab widget renders…". Hypotheses to test in order:
  1. A `CircularProgressIndicator` spins because `loadCalendarDay` never completes (timezone/http/auth path).
  2. An unbounded `repeat()` controller is mounted.
  3. A pending `Timer`.
- [ ] **Step 3:** Classify every one of the 47 failures by root cause. Report to the user:
  - causes that Task 1/2 fix (unbounded loops in tests)
  - causes outside this plan, as a separate issue list
- [ ] **Step 4:** Checkpoint. The gate for every later milestone is: the failing set ⊆ `baseline-failures.txt` minus the ones Task 1/2 were expected to fix.

---

## Milestone M0 — Foundation (P0)

### Task 1: Motion tokens, loop gate, test scope

**Files:**
- Modify: `lib/theme/flow_motion.dart`
- Create: `test/flutter_test_config.dart`, `test/flow_motion_tokens_test.dart`

**Interfaces — Produces** (in `FlowMotion`, alongside the existing members, which are unchanged):

```dart
static const Duration instant = Duration(milliseconds: 100);
static const Duration posePivot = Duration(milliseconds: 260);
static const Duration poseFadeReduced = Duration(milliseconds: 120);
static const Duration enterFadeReduced = Duration(milliseconds: 150);
static const Duration characterEnter = Duration(milliseconds: 420);
static const Duration characterExit = Duration(milliseconds: 200);
static const Duration reaction = Duration(milliseconds: 700);
static const Duration celebration = Duration(milliseconds: 1600);
static const Duration highlightFade = Duration(milliseconds: 1200);
static const Duration breathPeriod = Duration(milliseconds: 3800);
static const Duration thinkPeriod = Duration(milliseconds: 2600);
static const Duration pacePeriod = Duration(milliseconds: 4000);
static const Duration focusPeriod = Duration(milliseconds: 5200);
static const Duration windDownPeriod = Duration(milliseconds: 6000);
static const Duration idleWindow = Duration(seconds: 30);
static const Duration focusBobWindow = Duration(seconds: 20);
static const Curve exit = Curves.easeInCubic;
static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
static const Curve loop = Curves.easeInOutSine;
static const SpringDescription settleSpring = SpringDescription(mass: 1, stiffness: 420, damping: 41);
static const SpringDescription reactionSpring = SpringDescription(mass: 1, stiffness: 420, damping: 30);
static const SpringDescription celebrationSpring = SpringDescription(mass: 1, stiffness: 420, damping: 22);
static bool debugLoopsEnabled = true;                 // test/flutter_test_config.dart sets false
static bool loopsEnabled(BuildContext context);       // !isReducedMotion && (FlowMotionScope.maybeOf(context)?.loopsEnabled ?? debugLoopsEnabled)
static Widget switcher({required Widget child, Duration duration = standardDuration}); // fade + 8px rise incoming
class FlowMotionScope extends InheritedWidget { final bool loopsEnabled; static FlowMotionScope? maybeOf(BuildContext c); }
```

- [ ] **Step 1: Write failing tests** in `test/flow_motion_tokens_test.dart`:
  - `token values match spec §10`: assert each duration above.
  - `reactionSpring overshoots 2–4%`: `max(SpringSimulation(FlowMotion.reactionSpring, 0, 1, 0).x(t))` over t ∈ [0, 1.5] s at a 1 ms step is in `(1.02, 1.04)`.
  - `celebrationSpring overshoots 10–15%`: same, in `(1.10, 1.15)`.
  - `settleSpring does not overshoot`: max ≤ `1.0005`.
  - `loopsEnabled false under reduced motion`.
  - `FlowMotionScope(loopsEnabled: true) overrides debugLoopsEnabled=false`.
- [ ] **Step 2:** Run `flutter test test/flow_motion_tokens_test.dart`. Expected: FAIL (undefined members).
- [ ] **Step 3:** Implement the members above. `test/flutter_test_config.dart` uses `Future<void> testExecutable(FutureOr<void> Function() testMain) async { FlowMotion.debugLoopsEnabled = false; await testMain(); }`.
- [ ] **Step 4:** Run it. Expected: PASS. Run `dart analyze lib test`. Expected: no new issues.
- [ ] **Step 5:** Checkpoint (no commit).

### Task 2: Kill unbounded loops; isolate ambient repaint

**Files:**
- Modify: `lib/components/companion/flow_companion_view.dart:63-76`, `lib/components/flow_ambient_background.dart:45-58,~83`
- Test: `test/motion_loop_lifecycle_test.dart` (create)

**Interfaces — Consumes:** `FlowMotion.loopsEnabled`, `FlowMotionScope` (Task 1).

- [ ] **Step 1: Write failing tests:**
  - `FlowCompanionView does not tick outside focusing`: pump with `FlowMotionScope(loopsEnabled: true)`, controller state `idle`, pump 100 ms; `expect(tester.binding.hasScheduledFrame, isFalse)`.
  - `FlowAmbientBackground painter is behind a RepaintBoundary`: `find.descendant(of: find.byType(FlowAmbientBackground), matching: find.byType(RepaintBoundary))` finds the boundary wrapping the `CustomPaint`, and that boundary does not contain `child`.
  - `ambient does not animate when loops disabled`: default test config → `hasScheduledFrame` false after the first pump.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Replace both `_isTestOrReducedMotion` getters with `!FlowMotion.loopsEnabled(context)`. In `FlowCompanionView`, start `_pulseController.repeat` only when state is `focusing` (re-evaluate in `_onControllerChange` and `didChangeDependencies`); stop it otherwise. Wrap only the painter layer (both branches) of `FlowAmbientBackground` in `RepaintBoundary`.
- [ ] **Step 4:** Run the new test file plus `test/motion_navigation_test.dart` and `test/flow_progression_test.dart`. Expected: PASS. Then run the full suite. Expected: failing set ⊆ baseline. Record which baseline failures turned green.
- [ ] **Step 5:** Checkpoint.

### Task 3: Decode Noya at display size + precache helper

**Files:**
- Modify: `lib/components/noya_companion_view.dart:248-268`
- Test: `test/noya_visual_system_test.dart` (add tests)

**Interfaces — Produces:**
- `class NoyaAssets { static Future<void> precache(BuildContext context, Iterable<NoyaState> states, double size); }`
- `NoyaCompanionView`'s public constructor is unchanged.

- [ ] **Step 1: Write failing tests:**
  - `NoyaCompanionView decodes at size x DPR`: with `tester.view.devicePixelRatio = 3.0`, size 40 → the found `Image`'s `image` is a `ResizeImage` with `width == 120`.
  - `cacheWidthFor rounds size x dpr`: `NoyaCompanionView.cacheWidthFor(40, 2.625) == 105`, a `@visibleForTesting static int cacheWidthFor(double size, double dpr)` used by both the main and the `errorBuilder` `Image.asset`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Pass `cacheWidth: cacheWidthFor(size, MediaQuery.devicePixelRatioOf(context))` to both `Image.asset` calls. `NoyaAssets.precache` calls `precacheImage(ResizeImage(AssetImage(state.assetPath), width: …), context)` for each state.
- [ ] **Step 4:** Run `flutter test test/noya_visual_system_test.dart`. Expected: PASS (existing 9 + new).
- [ ] **Step 5:** Checkpoint.

### Task 4: Shared shimmer driver

**Files:**
- Modify: `lib/components/skeleton_loaders.dart:7-75`
- Test: `test/skeleton_shimmer_test.dart` (create)

**Interfaces — Produces:**
- `class FlowShimmerScope extends StatefulWidget { const FlowShimmerScope({required Widget child}); static Animation<double>? maybeOf(BuildContext c); }`
- `FlowShimmerBox` uses the scope animation when present, otherwise its own controller (backward compatible).
- `TodayDashboardSkeleton` and `TaskInboxSkeleton` wrap their content in `FlowShimmerScope`.

- [ ] **Step 1: Write failing tests:**
  - `boxes inside a scope share one animation`: the `FadeTransition.opacity` of all `FlowShimmerBox`es inside `TodayDashboardSkeleton` are `identical`.
  - `shimmer is static when loops disabled`: `hasScheduledFrame` false; opacity is the 0.55 midpoint constant.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. The scope runs the existing 1,400 ms reverse loop (0.35–0.75) only when `FlowMotion.loopsEnabled`.
- [ ] **Step 4:** Run `flutter test test/skeleton_shimmer_test.dart test/today_page_test.dart`. Expected: PASS / failing set ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M0 gate:** full suite failing set ⊆ baseline; `dart analyze lib test` clean; Performance Layer 1 checks for Tasks 2–4 pass (§24.2).

---

## Milestone M1 — Noya motion core (P0)

### Task 5: Register `delighted` and `windDown`

**Files:**
- Modify: `lib/components/noya_companion_view.dart:10-93`, `test/noya_visual_system_test.dart:11-27,112-116`

**Interfaces — Produces:**
- `NoyaState.delighted` → `'assets/images/companions/noya_success.png'`
- `NoyaState.windDown` → `'assets/images/companions/noya_sleeping.png'`
- Semantic labels:
  - delighted: `'Noya beaming with sparkling eyes, delighted with your plan'`
  - windDown: `'Noya getting drowsy as the day winds down'`
- Display names `'Delighted'`, `'Wind-down'`.

- [ ] **Step 1: Update tests first** (strengthened): `NoyaState.values.length == 9`; path assertions for both new states; file-exists + size > 10000 loop covers 9; labels non-empty for 9.
- [ ] **Step 2:** Run. Expected: FAIL (length 7).
- [ ] **Step 3:** Add the enum values and switch arms. `resolveStateForTask` and `fromAnimState` are unchanged.
- [ ] **Step 4:** Run `flutter test test/noya_visual_system_test.dart`. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 6: Reaction controller (rules in one place)

**Files:**
- Create: `lib/components/companion/noya_reaction_controller.dart`
- Modify: `lib/components/companion/flow_companion_animation_controller.dart` (add field; dispose in `FlowProvider.dispose` already calls `animController.dispose()`, which must dispose `reactions`)
- Test: `test/noya_reaction_controller_test.dart` (create)

**Interfaces — Produces:**

```dart
enum NoyaReaction { greet, taskDone, planReady, celebrate, recover }
// priority: celebrate(4) > taskDone(3) > planReady(2) > recover(1) > greet(0)
// active window: greet 1500ms, taskDone 1700ms, planReady 1400ms, celebrate 3100ms, recover 500ms
class NoyaReactionEvent { final int id; final NoyaReaction reaction; final DateTime at; }
class NoyaReactionController extends ChangeNotifier implements ValueListenable<NoyaReactionEvent?> {
  NoyaReactionController({DateTime Function()? clock}); // default: () => FlowClock().now
  NoyaReactionEvent? get value;
  NoyaReactionEvent? react(NoyaReaction r);        // returns emitted event or null if dropped
  NoyaReactionEvent? reactToTap();                 // greet, rate-limited to 1 per 2s
  bool greetOnce(String screenKey, {bool perDay = false}); // true = caller should greet
}
// FlowCompanionAnimationController gains: final NoyaReactionController reactions = NoyaReactionController();
```

- [ ] **Step 1: Write failing tests** (fake clock):
  - `higher priority interrupts lower`: `react(taskDone)` then at +200 ms `react(celebrate)` → second returns event with reaction celebrate.
  - `lower priority dropped during higher active window`: celebrate, then +500 ms greet → null.
  - `lower priority allowed after window`: celebrate, then +3200 ms greet → event.
  - `taskDone coalesces within 1.5s`: 5 × taskDone at 0/200/400/600/800 ms → exactly 1 non-null.
  - `taskDone after 1.5s is a new event`.
  - `4th celebrate in a day downgrades to taskDone`; `celebrate count resets on next local day`.
  - `reactToTap limited to one per 2s`.
  - `greetOnce per screen per session`: true then false for the same key; true for a different key.
  - `greetOnce perDay resets next day`.
  - `event ids strictly increase`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. The session greet ledger is an in-memory `Set<String>` on the controller; perDay keys store a `yyyy-MM-dd` suffix.
- [ ] **Step 4:** Run `flutter test test/noya_reaction_controller_test.dart test/flow_progression_test.dart`. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 7: `NoyaMotionView` — pose crossfade, enter, exit

**Files:**
- Create: `lib/components/noya_motion_view.dart`
- Test: `test/noya_motion_view_test.dart` (create)

**Interfaces — Produces:**

```dart
enum NoyaMood { rest, thinking, pacing, focusing, energetic, windDown, asleep }
// default pose per mood: rest→idle, thinking→thinking, pacing→thinking, focusing→focusing,
// energetic→encouraging (interim exercise, §6.9), windDown→windDown, asleep→sleepy
class NoyaMotionView extends StatefulWidget {
  const NoyaMotionView({
    super.key,
    this.mood = NoyaMood.rest,
    this.pose,                       // overrides the mood's default pose (e.g. resolveStateForTask result)
    this.size = NoyaSize.normal,
    this.enter = false,
    this.reactions,                  // ValueListenable<NoyaReactionEvent?>?
    this.reactionFilter,             // NoyaReaction? Function(NoyaReaction)? — map/ignore incoming
    this.playRecentOnMount,          // Duration? — play value if newer than this on first build
    this.onTap,
    this.showAmbientGlow = false,
    this.semanticLabel,
  });
}
```

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for pose crossfade, enter and exit. Answer every decision from §6.1–§6.3, §18 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - `pose change crossfades over 260ms`: pump idle, rebuild with mood thinking, `pump(130ms)` → `find.byType(NoyaCompanionView)` findsNWidgets(2); `pump(140ms)` → findsOneWidget showing `NoyaState.thinking`.
  - `outgoing pose excluded from semantics`: mid-crossfade, `find.bySemanticsLabel(NoyaState.idle.semanticLabel)` finds nothing.
  - `reduced motion: pose change is a 120ms fade with no scale`: mid-transition no `ScaleTransition` with value ≠ 1.
  - `enter: true fades in over 420ms`: opacity 0 at t=0, > 0.9 at 420 ms; `enter: false` is fully opaque on the first frame.
  - `paused frame equals static view`: at rest, the composed transform is `Matrix4.identity()` and opacity is 1.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement with `AnimatedSwitcher` (bottom-center `layoutBuilder` Stack, `FlowMotion.posePivot`, incoming scale 0.97 → 1.0, `easeInOutCubic`; reduced: `poseFadeReduced`, no scale). Keep the old pose until `NoyaAssets.precache` resolves (max 300 ms). Enter: opacity 0 → 1, scale 0.92 → 1, translateY 0.06·s → 0 over `characterEnter`, `emphasized`. Wrap the subtree in `RepaintBoundary`. Semantics come from the current `NoyaCompanionView` only.
- [ ] **Step 4:** Run `flutter test test/noya_motion_view_test.dart`. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 8: Mood loops (bounded)

**Files:** Modify `lib/components/noya_motion_view.dart`; Test `test/noya_motion_view_test.dart`.

**Interfaces — Produces:** `class NoyaWakeScope extends StatefulWidget { const NoyaWakeScope({required Widget child}); }`. A `Listener(onPointerDown)` notifies descendant `NoyaMotionView`s to restart their idle window.

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for bounded mood loops (breath, think, pace, focus, energetic, wind-down, asleep). Answer every decision from §6.4, §6.6–§6.9, §6.13, §17 P1–P3, §18 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests** (all under `FlowMotionScope(loopsEnabled: true)`):
  - `rest breath runs then stops after idleWindow`: frames scheduled at 1 s; after `pump(31s)` + one half period → `hasScheduledFrame` false, transform identity.
  - `pointer down inside NoyaWakeScope restarts the window`.
  - `no loop below 48px`: size 40 → no scheduled frames after mount.
  - `TickerMode disabled stops the loop`.
  - `thinking loop rotates within 2 degrees`: sample over one 2,600 ms period; max |rotation| ≤ 2° + ε and > 1.5°.
  - `pacing translates within 0.08*s horizontally`.
  - `focusing bob stops after focusBobWindow (20s)`.
  - `energetic bob ≤ 0.02*s, stops after 6 cycles`.
  - `reduced motion turned on mid-loop stops at rest next frame` (Review Focus 3): rebuild with `MediaQuery(disableAnimations: true)` → transform identity after one pump, no exception.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement one loop `AnimationController` driven by `mood`, with periods and amplitudes from Global Constraints. Breath = volume-preserving scaleY 1.000 ↔ 1.012 / scaleX ↔ 0.996 + translateY 0 ↔ −0.006·s, anchored bottom-center. Pacing reuses the `routine_building_view.dart:209-255` formulas plus the ground-shadow ellipse. windDown/asleep breath = amplitude × 0.8 at `windDownPeriod`.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 9: Reactions

**Files:** Modify `lib/components/noya_motion_view.dart`; Test `test/noya_motion_view_test.dart`.

**Interfaces — Consumes:** `NoyaReactionController` / `NoyaReactionEvent` (Task 6). Reaction poses: greet → encouraging, taskDone → proud, planReady → delighted then proud, celebrate → celebrating, recover → current mood pose (thinking/pacing → idle).

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for reactions (greet, taskDone, planReady, celebrate, recover). Answer every decision from §5.2–§5.3, §6.5, §6.10–§6.12, §6.14, §18 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - `greet sways and returns`: emit greet; at 400 ms pose is encouraging and |rotation| > 0; at 1,600 ms rotation 0 and pose back to the mood pose.
  - `taskDone hops at most 0.06*s`: sample the max upward translation ≤ 0.06·s·1.04.
  - `planReady shows delighted then proud`.
  - `celebrate hops at most 0.12*s and settles`: pose celebrating; transform identity by 3,100 ms; glow alpha returns to 0.
  - `recover never rotates and settles within 500ms`.
  - `reduced motion reaction = pose crossfade only`: no non-identity transform at any sample.
  - `reactionFilter can downgrade or ignore`.
  - `playRecentOnMount plays an event newer than the window, ignores older`.
  - `dispose mid-reaction throws nothing and next mount does not replay` (Review Focus 4).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement with a second `AnimationController` driven by `animateWith(SpringSimulation(...))` for hops/scale (`reactionSpring`; `celebrationSpring` for celebrate) and keyframed rotation for greet (0 → −4° → +3° → −1.5° → 0 over 640 ms). Squash 90 ms on landing: scaleY 0.97 / scaleX 1.02 (taskDone), 0.96 / 1.03 (celebrate). Holds: greet 600 ms, taskDone 1,200 ms, planReady 900 ms, celebrate 1,500 ms. Listen to `reactions` with an id high-water mark so events are never replayed.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 10: `FlowCompanionView` renders through `NoyaMotionView`

**Files:** Modify `lib/components/companion/flow_companion_view.dart`, `lib/components/companion/companion_graphic.dart:32-36`; Test `test/motion_loop_lifecycle_test.dart`.

**Interfaces — Consumes:** `NoyaMotionView`, `NoyaMood`. Mapping `CompanionAnimState → mood`: focusing → focusing; idle/starting/success/tired/evolution → rest. The pose comes from the existing `fromAnimState` mapping. The view passes `controller.reactions` as `reactions`.

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for FlowCompanionView focus bob and reaction rendering. Answer every decision from §6.8, §7.6–§7.7 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - `no pulse controller remains: idle FlowCompanionView never schedules frames even with loops enabled after idleWindow`.
  - `focusing bob stops after 20s`.
  - `fox species renders NoyaMotionView; other species unchanged`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Remove `_pulseController`/`_pulseAnimation` and the `Transform.scale`. `CompanionGraphic` gains `NoyaMood mood = NoyaMood.rest` and a `reactions` parameter, forwarded to `NoyaMotionView` for fox/noya. Framed card, badges and status text are unchanged.
- [ ] **Step 4:** Run `flutter test test/motion_loop_lifecycle_test.dart test/flow_progression_test.dart test/flow_auth_hub_test.dart test/home_quest_ai_audit_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M1 gate:**
- full suite ⊆ baseline
- analyze clean
- manual: spec §22 "Noya & motion" items 1–2 and 8–9 on an emulator
- Performance Layer 1: zero Noya tickers 31 s after mount on a static screen

---

## Milestone M2 — Calendar (P0)

### Task 11: Step 0 — fixed-state mismatch (S3 vs S7)

**Files:** determined by diagnosis. Known path: `backend/app/services/calendar_service.py:136` (`is_fixed=locked or completed`, `locked` = `time_locked`); `lib/providers/app_state_provider.dart` `_candidateToBatchItem` (`time_locked` true only for user-fixed times); `lib/screens/brain_dump_sheet.dart` preview "Fixed time" label source.

- [ ] **Step 1:** Using superpowers:systematic-debugging, write a failing regression test that reproduces it. The input is a brain dump with an explicit time ("gym at 4pm"), confirmed. Expected: the persisted task has `time_locked == true`, and `GET /calendar/day` returns `is_fixed: true`. Write it at the layer where the divergence is found:
  - backend: `backend/tests/test_plan_confirm_fixed_time.py`
  - client: `test/fixed_time_roundtrip_test.dart`
- [ ] **Step 2:** Run. Expected: FAIL, reproducing the mismatch. If it cannot be reproduced, stop and report to the user with evidence.
- [ ] **Step 3:** Fix the root cause only (no visual change).
- [ ] **Step 4:** Run the test plus the backend suite (expect 1160 + new passing) and `test/build_my_day_editor_test.dart`.
- [ ] **Step 5:** Checkpoint.

### Task 12: `FlowDateStrip`

**Files:** Create `lib/components/flow_date_strip.dart`; Modify `lib/screens/calendar_tab.dart:70-157`; Test `test/flow_date_strip_test.dart` (create).

**Interfaces — Produces:** `FlowDateStrip({required List<DateTime> days, required DateTime selected, required DateTime today, required ValueChanged<DateTime> onSelect})`.

- Preserves keys `calendar_day_chip_today|yesterday|tomorrow|<yyyy-MM-dd>` and `Semantics(button: true, selected:, label:)` with the existing label formats.
- The Today marker has key `calendar_today_marker`.
- Month label key: `calendar_month_label_<yyyy-MM>`.
- The header text in `calendar_tab.dart` becomes `DateFormat('EEEE, MMMM d')` of the selected date (replacing the subtitle).

- [ ] **Step 1: Write failing tests:**
  - `chip shows weekday abbreviation and day number` ('Fri', '2').
  - `today marker visible when another day selected`.
  - `month label above first chip of a new month`.
  - `selected chip scrolled fully into view after selecting day 12` (its rect is within the strip viewport).
  - `existing keys and semantics preserved`.
  - `textScaler 1.3 at 360dp: no overflow` (Review Focus 5; `tester.takeException()` is null).
  - `header shows full selected date`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - chip radius `FlowRadii.chip` (14)
  - `AnimatedContainer` fill/border over `microDuration`
  - `Scrollable.ensureVisible` over `screenDuration`
  - `FlowHaptics.selection()` and `onSelect` unchanged in behavior (Calendar passes `state.loadCalendarDay`)
- [ ] **Step 4:** Run `flutter test test/flow_date_strip_test.dart test/calendar_date_navigation_test.dart test/date_preservation_test.dart`. Expected: the new file passes; the others are ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

### Task 13: `FlowTimelineRow` (evolved `TimelineItemWidget`)

**Files:** Modify `lib/components/timeline_item_widget.dart`; Test `test/flow_timeline_row_test.dart` (create).

**Interfaces — Produces:**

```dart
enum TimelineRowState { normal, now, fixed, conflict, missed, suggested, completed, unscheduled }
TimelineRowState timelineRowStateOf(ScheduleItem item, {required bool isNow}); // precedence: completed > conflict > fixed > missed > suggested > now > normal
class FlowTimelineRow extends StatelessWidget {
  const FlowTimelineRow({super.key, required this.item, this.isNow = false, this.isLast = false,
    this.showTimeGutter = true, this.onTap, this.onComplete, this.onStart, this.onDoThisNow});
}
typedef TimelineItemWidget = FlowTimelineRow; // keeps today_dashboard_tab.dart compiling until Task 15
```

Keys and semantics:
- the row container has `Key('timeline_row_${item.id}')`
- the state indicator has `Key('timeline_state_${state.name}_${item.id}')` (absent for `normal`)
- `Semantics(label:)` = `'<title>, <start time>, <duration> minutes, <state label>'`

- [ ] **Step 1: Write failing tests:**
  - one per state: indicator key present with label text 'Fixed' / 'Conflict' / 'Missed' / 'Suggested' / 'Unscheduled'; icon present; no emoji in any `Text` (regex `[\u{1F300}-\u{1FAFF}☀-➿]` finds none).
  - `normal row has no badge and no reason line`.
  - `now row shows reason line and tinted surface`.
  - `completed row: strike-through title, check node, no '✓ Done'`.
  - `conflict uses errorOf color, missed uses warningOf`.
  - `default row ≤ 72dp tall at textScale 1.0` (single-line title).
  - `times left-aligned on one axis` (gutter x equal across 3 rows).
  - `textScale 1.3 at 360dp: gutter grows, time not truncated, no overflow`.
  - `states distinguishable without color`: each state has a distinct `IconData` or the node shape differs.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the §B2.4 anatomy:
  - gutter = `IntrinsicWidth` with min 64 dp; time in `titleSmall` w700 with `FontFeature.tabularFigures()`, period `labelSmall` muted
  - 2 px rail in `divider` color; node 10 dp
  - title `bodyLarge` w600, `maxLines: 2`
  - meta in `bodySmall` muted
  - NOW only: fill `accent.withValues(alpha: 0.06)`, radius 14
  - no `BoxShadow`
  - Material Rounded icons at 16 px
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Checkpoint.

### Task 14: Calendar uses the row; actions, focus line, skeleton, empty Noya, date slide, density

**Files:** Modify `lib/screens/calendar_tab.dart` (whole file), `test/calendar_date_navigation_test.dart` (D1 rewrite).

**Interfaces — Consumes:** `FlowDateStrip` (12), `FlowTimelineRow`/`timelineRowStateOf` (13), `NoyaMotionView` (7–9), `FlowShimmerScope` (4), `ThemeProvider.densityMode`, `FlowProvider.animController.reactions.greetOnce` (6; a local `NoyaReactionController` if `FlowProvider` is absent, as in existing Calendar tests).

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for the Calendar empty-state Noya (enter + greet / evening mood) only. Answer every decision from §7.1, §6.1, §6.5 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Rewrite the D1 assertions first** in `calendar_date_navigation_test.dart` "6. Visual States":
  - each `find.text('🔒 FIXED')`-style assertion becomes `find.byKey(Key('timeline_state_fixed_<id>'))` + `find.text('Fixed')` scoped to that row + a semantics label containing 'Fixed'
  - '✦ FLOWSTATE' becomes "row exists and has no `timeline_state_` key"
  - '● DO THIS NOW' becomes `timeline_state_now_<id>` + reason line text
  - 'Aligned with focus window' becomes `findsNothing` (default rows show no reason, per spec B2.4)
  - '✓ Done' + '8:00 AM · 20 min · Completed' become the completed key + strike-through `TextDecoration.lineThrough` on the title + gutter '8:00'
  - 'Unscheduled Tasks' / 'UNSCHEDULED' become the section title "Couldn't fit" + `timeline_state_unscheduled_<id>`

  Add the new tests:
  - `Replan hidden on empty day`
  - `exactly one filled button in empty state`
  - `empty state shows NoyaMotionView`
  - `focus window rendered as one line 'Focus window 10:00 AM – 12:00 PM' ≤ 32dp`
  - `loading shows skeleton, no CircularProgressIndicator`
  - `date change slides content from +16px when moving forward`
  - `compact density reduces row gap`
  - `row inserted after reload fades + sizes in over 220ms; removed row fades 150ms then collapses 180ms` (§8.5; rows keyed by `item.id`)
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - Replan becomes a tonal `TextButton.icon` (`auto_awesome` icon, label "Replan", no emoji) in the header row, only when `timeline.isNotEmpty`; the caption is removed.
  - Focus window is a 16 px bolt + `bodyMedium` text.
  - The timeline is `FlowTimelineRow`s with the existing `nowItemId` logic (`calendar_tab.dart:293-326`) moved verbatim.
  - Unscheduled rows: `showTimeGutter: false`.
  - Loading: 3 skeleton rows inside `FlowShimmerScope`.
  - Empty: unboxed `NoyaMotionView(mood: <rest|windDown|asleep per Task 20 resolver>, size: 72, enter: true)` + greet when `reactions.greetOnce('calendar_empty')`.
  - Date slide via `AnimatedSwitcher` keyed by date with direction from old vs new date, 220 ms.
  - Row gap: 12 dp comfortable / 6 dp compact.
- [ ] **Step 4:** Run `flutter test test/calendar_date_navigation_test.dart test/flow_timeline_row_test.dart test/flow_date_strip_test.dart test/target_date_scheduling_regression_test.dart`. Expected: the calendar file passes entirely (including tests that were in the baseline failures if Task 0/2 fixed their cause; otherwise ⊆ baseline).
- [ ] **Step 5:** Checkpoint.

### Task 15: Today timeline uses the row; bounded NOW pulse

**Files:** Modify `lib/screens/today_dashboard_tab.dart:~1232`, `lib/components/timeline_current_time_marker.dart`, remove the typedef from Task 13; Test `test/today_page_test.dart` (add).

- [ ] **Step 1: Write failing tests:**
  - `Today timeline renders FlowTimelineRow with same states as Calendar for same ScheduleItem`.
  - `NOW marker pulses 3 cycles then is static` (`FlowMotionScope(loopsEnabled: true)`; after 3 × 2,400 ms → no scheduled frames).
  - `NOW marker static under reduced motion`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Replace `TimelineItemWidget(` with `FlowTimelineRow(`, passing the same callbacks. The marker dot opacity goes 1.0 ↔ 0.55 over 2,400 ms, 3 cycles, only for today's date.
- [ ] **Step 4:** Run `flutter test test/today_page_test.dart`. Expected: ⊆ baseline + new tests pass.
- [ ] **Step 5:** Checkpoint.

### Task 16: `FlowCompletionCheck` + completion motion

**Files:** Create `lib/components/flow_completion_check.dart`; Modify `timeline_item_widget.dart` (`FlowTimelineRow`), `task_card.dart`, `right_now_task_card.dart`; Test `test/flow_completion_check_test.dart`.

**Interfaces — Produces:** `FlowCompletionCheck({required bool completed, required VoidCallback? onToggle, double size = 24})`. 48 dp hit area; `Semantics(checked: completed, button: true, label: 'Mark complete' | 'Completed')`; `FlowHaptics.success()` on complete.

- [ ] **Step 1: Write failing tests:**
  - `fill animates over 150ms`.
  - `48dp hit target`.
  - `semantics checked state`.
  - `row strike-through animates over 220ms and row height eases via AnimatedSize`.
  - `reduced motion: instant`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement; replace the existing check affordances in the three components (callbacks unchanged).
- [ ] **Step 4:** Run the new file + `test/noya_visual_system_test.dart` (TaskCard checkmark test) + `test/add_task_and_options_ui_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M2 gate:**
- full suite ⊆ baseline
- analyze clean
- manual: spec §22 "Calendar" (all), at 360×640 and 412×915, light and dark, text scale 1.0 and 1.3
- Performance Layer 2: date change worst frame ≤ 8 ms on the available device
- `tastemaker` (Skill Usage Protocol): Calendar (empty, loading, scheduled, NOW, completed, conflict/unscheduled) and Today timeline, before = S1–S3, after = `ui-reference/after/M2/`; gate requires A = 0

---

## Milestone M3 — Build My Day + Plan Result (P0)

### Task 17: Build My Day header/status + Noya motion + escalation; Replan sheet motion

**Files:** Modify `lib/screens/brain_dump_sheet.dart:594-808,1377-1460`, `lib/screens/replan_day_sheet.dart:285-355`; Test `test/build_my_day_motion_test.dart` (create).

**Interfaces — Consumes:** `NoyaMotionView`, `NoyaReactionController` (a local instance per sheet), `FlowMotion.switcher`.

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for Build My Day / Replan Noya (crossfades, size change, thinking → pacing escalation, planReady, recover). Answer every decision from §7.2, §12, §6.6–§6.7, §6.11, §6.14 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests** (fake async; the planning call stubbed with a `Completer`):
  - `thinking within 1s of submit`.
  - `pacing after 4s`.
  - `reassurance text after 12s with liveRegion`: `find.text('Still organizing. Long lists take a little longer.')` and the ancestor `Semantics(liveRegion: true)`.
  - `success plays planReady then proud`.
  - `fallback planner notice plays recover, never celebrate`.
  - `valid input crossfades idle→encouraging and sways once per sheet open`.
  - `keyboard open animates Noya 72→40 over 220ms` (`viewInsets` change).
  - `no '…'/'Checking...' placeholder ever rendered while status loads`.
  - `with keyboard at 360x640 the input top edge is visible`.
  - `exactly one filled primary button in input mode`.
  - `sheet dismissed mid-planning: no exception, no setState after dispose` (Review Focus 4).
  - Replan: `replan loading shows thinking; failure shows recover`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement:
  - The Noya header is unboxed.
  - The AI/Shields status is one line under the input, hidden until `_usageStatus != null`, with an ⓘ `IconButton` (48 dp, `tooltip: 'About AI planning'`) opening the existing paragraph in a dialog.
  - Escalation timers are cancelled in `dispose`.
  - The inline button progress indicator is kept.
- [ ] **Step 4:** Run `flutter test test/build_my_day_motion_test.dart test/build_my_day_editor_test.dart test/replan_my_day_ui_test.dart test/gemini_brain_dump_pro_test.dart test/confirm_candidates_batch_test.dart`. Expected: new tests pass; others ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

### Task 18: Plan Result rows, single reveal, highlight pulse

**Files:** Create `lib/components/flow_highlight_pulse.dart`; Modify `brain_dump_sheet.dart:865-1157`, `ai_plan_preview_sheet.dart`, `parsed_plan_confirm_sheet.dart`, `app_state_provider.dart` (`confirmCandidates`, `applyReplan`, reschedule success paths), `timeline_item_widget.dart`; Test `test/plan_result_rows_test.dart` (create).

**Interfaces — Produces:**
- `FlowHighlightPulse({required bool active, required Widget child})`: tint `accent @ 0.12 → 0` over `highlightFade`, once.
- `AppStateProvider.recentlyChangedTaskIds` (`Set<String>`, cleared after 3 s) is filled from the confirm response `tasks[].id`, applied-replan moved/new IDs, and the rescheduled ID.
- `FlowTimelineRow` wraps itself in `FlowHighlightPulse(active: recentlyChangedTaskIds.contains(item.taskId ?? item.id))`.

- [ ] **Step 1: Write failing tests:**
  - `plan row shows time once` (count of '4:00' == 1 per row).
  - `'Priority not specified' never rendered`.
  - `why line hidden until row expanded (AnimatedSize)`.
  - `default collapsed row ≤ 72dp`.
  - `rows stagger 40ms, max 6 animated` (row 7 is fully opaque at the same time as row 6).
  - `confirm marks created ids as recently changed; matching Calendar row pulses once`.
  - `reduced motion: no stagger, static tint 1200ms`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the rows with B1.4 anatomy (reuse the `FlowTimelineRow` layout with `showTimeGutter: true`; the Edit trailing `IconButton` is 48 dp). Stagger via `FlowFadeSlide(delay: 40ms × min(i, 5))`.
- [ ] **Step 4:** Run the new file + `test/build_my_day_editor_test.dart test/apply_replan_flow_test.dart test/plan_diff_view_test.dart test/reschedule_later_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M3 gate:**
- full suite ⊆ baseline
- manual: spec §22 Build My Day items, including airplane mode
- Performance Layer 2: plan reveal + planReady worst frame ≤ 8 ms
- `tastemaker`: Build My Day (input, keyboard open, planning, fallback) and Plan Result, before = S6–S7, after = `ui-reference/after/M3/`; gate requires A = 0

---

## Milestone M4 — Completion & Today (P0)

### Task 19: Single-fire completion hook

**Files:** Modify `lib/providers/app_state_provider.dart:88,660-707`, `lib/screens/main_shell.dart:63-69`; Test `test/noya_completion_hook_test.dart` (create).

**Interfaces — Produces:**
- `void Function(TaskItem task, {required bool clearedDay})? onTaskCompletedForNoya;`
- `bool get hasPendingTasksToday`: any task that is not completed, status not cancelled/archived, with `scheduledStart` on today's local date (`FlowClock`).

`MainShell` wires `state.onTaskCompletedForNoya ??= (t, {required clearedDay}) => flow.animController.reactions.react(clearedDay ? NoyaReaction.celebrate : NoyaReaction.taskDone);`.

- [ ] **Step 1: Write failing tests:**
  - `fires exactly once per completion although onTaskCompletedForFlow fires twice` (Review Focus 1; stub the backend completion success so the second callback runs).
  - `un-completing never fires` (Review Focus 2).
  - `completion found via 'sched-' prefix or title fallback fires once` (Review Focus 2).
  - `clearedDay true only when the last pending task of today completes`.
  - `celebrate cap: 4th clearedDay in a day emits taskDone` (through the controller).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Call the hook once, inside `if (willComplete)` after `_tasks[index]` is updated and before the backend call.
- [ ] **Step 4:** Run the new file + `test/today_page_test.dart test/flow_progression_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

### Task 20: Today Noya behaviors + day-mood resolver

**Files:** Modify `lib/screens/today_dashboard_tab.dart:~255,~540,~658,~810,~940-980,~1135`; Create a resolver in `lib/components/noya_motion_view.dart`; Test `test/today_noya_motion_test.dart` (create).

**Interfaces — Produces:** `NoyaMood resolveDayMood({required DateTime now, required bool hasPendingToday, required bool isDayFinished})`:
- `asleep` if `isDayFinished`
- else `windDown` if `now.hour >= 20 && !hasPendingToday`
- else `rest`

`isDayFinished` reuses the existing `isAtOrPastBedtime && !hasUpcomingTasks` computation (`today_dashboard_tab.dart:~905`).

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for Today Noya behaviors (greet once per day, reaction filtering, celebrate on mount, wind-down/asleep, energetic). Answer every decision from §7.4, §13, §5.1, §6.9, §6.12–§6.13 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - resolver table: 19:59 no pending → rest; 20:00 no pending → windDown; 21:00 pending → rest; finished → asleep.
  - `plate card enters and greets once per day` (second build the same day: no greet; next day: greet).
  - `header pill downgrades celebrate to taskDone` (`reactionFilter`).
  - `completion card plays celebrate on mount when event < 2s old` (`playRecentOnMount`).
  - `list Noyas never loop` (TaskCard Noya size 40: no scheduled frames).
  - `RightNowTaskCard: in-progress physical task at ≥48px uses NoyaMood.energetic; not in progress → rest` (§6.9; pose from `resolveStateForTask`).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Replace the relevant `NoyaCompanionView(` instances with `NoyaMotionView(` per spec §7.4. Wrap the Today scroll view in `NoyaWakeScope`.
- [ ] **Step 4:** Run the new file + `test/today_page_test.dart test/micro_interactions_polish_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M4 gate:** full suite ⊆ baseline; manual: spec §22 completion, evening and tab-switch items; Performance Layer 2: celebrate worst frame ≤ 8 ms; `tastemaker`: Today (empty plate card, mid-day with completions, all-done, evening wind-down) rest frames, before = S4, after = `ui-reference/after/M4/`; gate requires A = 0.

---

## Milestone M5 — Dark mode (P0)

### Task 21: Dark tokens + contrast test

**Files:** Modify `lib/theme/flow_colors.dart`; Test `test/flow_colors_contrast_test.dart` (create).

**Interfaces — Produces:**
- `textSecondaryDark = Color(0xFFCBD5E1)`
- `accentLimeDark = Color(0xFFA3E635)`
- `noyaWarm = Color(0xFFF97316)`, `noyaWarmDark = Color(0xFFFB923C)`
- `static Color noyaWarmOf(BuildContext)`
- `static double noyaGlowAlpha(BuildContext)` → 0.18 light / 0.12 dark
- `@Deprecated('Light-only value; use the …Of(context) accessor')` on `darkBackground`, `darkSurface`, `darkCard`, `darkCardElevated`, `darkBorder`, `darkDivider`, `textPrimary`, `textSecondary`, `textMuted`

- [ ] **Step 1: Write failing tests:** a WCAG contrast helper in the test. Assert:
  - primary, secondary and muted dark text ≥ 4.5 on `surfaceDark` and `surfaceElevatedDark`
  - secondary vs primary luminance ratio ≥ 1.2 (hierarchy)
  - every dark accent ≥ 3.0 on `surfaceDark`
  - `accentLimeDark != accentLime`
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Apply the values; `noya_companion_view.dart:264,284` uses `noyaWarmOf` / `noyaGlowAlpha`.
- [ ] **Step 4:** Run the new file + `dart analyze lib test`. Expected: PASS. Deprecation infos are expected only at existing call sites; list them for Task 22.
- [ ] **Step 5:** Checkpoint.

### Task 22: Dark sweep

**Files:** Modify `lib/components/compact_readiness_card.dart`, `break_session_card.dart`, `task_difficulty_badge.dart`, `readiness_hero_card.dart`, `progress_header.dart`, `permission_nudge_row.dart`, `secondary_button.dart`, `plan_diff_view.dart`, `lib/screens/task_inbox_tab.dart`, `today_dashboard_tab.dart:1474-1480`, `profile_settings_tab.dart`, `lib/engines/scheduling_engine.dart:510-525`; Test `test/dark_mode_sweep_test.dart` (create).

**Interfaces — Produces:** `static Color FlowColors.tagBackground(BuildContext context, Color tone)` → `tone` at alpha 0.12 (light) / 0.18 (dark) over `surface(context)`.

- [ ] **Step 1: Write failing tests:** pump each listed component under `FlowTheme.darkTheme()`. No `Text` has color `textPrimaryLight`, `textSecondaryLight` or `textMutedLight`, and no `Container` decoration color equals any `tag*Bg` constant.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:**
  - Replace light-only constants with the `…Of(context)` accessors and tag backgrounds with `tagBackground`.
  - `Colors.orange` → `warningOf(context)`; `Color(0xFFEF4444)` → `errorOf(context)` in touched files.
  - In dark, shadows drop to none on cards and are kept on sheets (B3.6).
- [ ] **Step 4:** Run the new file + full suite ⊆ baseline; `dart analyze` shows zero uses of the deprecated aliases in `lib/`.
- [ ] **Step 5:** Checkpoint.

**M5 gate:** manual: spec §22 "Dark mode" sweep on all tabs and sheets, including the Noya fringe check at 28/40/76 px (B3.8; if a fringe is visible, record it for the asset task, with no code workaround); `tastemaker`: dark-mode pairs (light vs dark of the same screen) for Today, Tasks, Calendar, Insights, Settings, Flow Hub, Focus and the Build My Day sheet, after = `ui-reference/after/M5/`, judged against B3 hierarchy; gate requires A = 0.

---

## Milestone M6 — Focus/Quest, Flow Hub, onboarding, auth, splash (P1)

### Task 23: Focus (Quest) + Flow Hub motion

**Files:** Modify `lib/screens/focus_ritual_screen.dart:234-400,664,758,942`, `lib/screens/flow_screen.dart:139,346,~380`; Test `test/focus_hub_motion_test.dart` (create).

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for Focus (Quest) and Flow Hub Noya (starting, focusing, milestone, celebrate, tap, quest claim). Answer every decision from §7.6–§7.7, §13 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - `setStarting enters with greet`.
  - `milestone(25) hops without pose change and with selection haptic`.
  - `triggerSuccess plays celebrate`.
  - `Flow Hub greets once per session`.
  - `tap Noya reacts, rate-limited 2s`.
  - `claimDailyQuest success hops (taskDone)`.
  - `evolution badge pulses ≤10s then static`.
  - `shield activation (flow_provider.dart:367) emits taskDone, not celebrate` (§13).
  - `level-up/evolution (flow_provider.dart:287) emits celebrate`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement via `controller.reactions` (`react`, `reactToTap`, `greetOnce('flow_hub')`). The milestone uses `react(taskDone)` with `reactionFilter` keeping the focusing pose.
- [ ] **Step 4:** Run the new file + `test/flow_progression_test.dart test/home_quest_ai_audit_test.dart test/flow_auth_hub_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

### Task 24: Friendly auth prompt

**Files:** Modify `lib/providers/flow_provider.dart:129,156` (add `bool get isAuthRequired`, set alongside the existing message), `lib/screens/flow_screen.dart` (error banner); Test `test/flow_auth_hub_test.dart` (add).

- [ ] **Step 1: Write failing tests:**
  - `signed-out Hub never renders 'Authentication required'`.
  - `shows 'Sign in to sync your progress' and a 'Sign in' button that pushes AuthScreen`.
  - `other errors keep their message with 'Try again'`.
  - `Noya plays recover`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. The provider's message strings stay (other code may read them); only the UI branches on `isAuthRequired`.
- [ ] **Step 4:** Run `flutter test test/flow_auth_hub_test.dart test/auth_session_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

### Task 25: Onboarding, splash, auth screen

**Files:** Modify `lib/components/routine_building_view.dart:40-255`, `lib/screens/onboarding_flow_screen.dart:432`, `lib/screens/splash_screen.dart:30-60,158`, `lib/screens/auth_screen.dart:441`; Test `test/onboarding_motion_test.dart` (create).

- [ ] **Step 0 (animate):** Invoke the `animate` skill per the Skill Usage Protocol for onboarding pacing/crossfades, onboarding greet, splash single enter, auth greet/recover. Answer every decision from §7.8–§7.9, §6.7 and the `FlowMotion` tokens; record the walk-through and any `ANIMATE-DEVIATION` in the checkpoint summary. Spec values are not changed.
- [ ] **Step 1: Write failing tests:**
  - `building-step pose changes crossfade (two NoyaCompanionViews mid-transition)`.
  - `pacing uses NoyaMotionView pacing mood`.
  - `onboarding completion card greets`.
  - `splash: single enter, no repeating scale (no scheduled frames after 500ms)`.
  - `auth screen greets once; sign-in failure plays recover`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Replace the hand-rolled pacing `AnimatedBuilder` with `NoyaMotionView(mood: NoyaMood.pacing, pose: …)`; remove the splash `repeat(reverse: true)`. The step timer behavior (650 ms) is unchanged.
- [ ] **Step 4:** Run the new file + `test/adaptive_onboarding_test.dart test/new_user_questionnaire_and_isolation_test.dart test/auth_session_test.dart`. Expected: PASS / ⊆ baseline.
- [ ] **Step 5:** Checkpoint.

**M6 gate:** full suite ⊆ baseline; manual: spec §22 focus, Hub signed-out and reduced-motion items; `tastemaker`: Focus (Quest) session, Flow Hub (signed-in, signed-out prompt), onboarding completion, splash and auth rest frames, before = S5, after = `ui-reference/after/M6/`; gate requires A = 0.

---

## Milestone M7a — Task colors, client (P1)

### Task 26: `FlowTaskColor` palette

**Files:** Create `lib/theme/flow_task_colors.dart`; Test `test/flow_task_colors_test.dart`.

**Interfaces — Produces:**
- `enum FlowTaskColor { sky, mint, blue, amber, rose, violet, lime, slate }` with `Color light`, `Color dark`, `String get label`, `Color resolve(BuildContext)`
- `static FlowTaskColor? fromKey(String? key)` (unknown → null = default)
- `String get key` (= name)

Values: exactly §24.3.

- [ ] **Step 1: Write failing tests:**
  - every light value ≥ 3.0 contrast on `#FFFFFF`, `#F8FAFC` and `#F1F5F9`
  - every dark value ≥ 3.0 on `#0B0F17`, `#131B2A`, `#1A2436` and `#223046`
  - `fromKey('nope') == null`
  - `fromKey(null) == null`
  - amber light `== Color(0xFFB45309)`, lime light `== Color(0xFF4D7C0F)`
- [ ] **Steps 2–5:** Run (FAIL) → implement → run (PASS) → checkpoint.

### Task 27: Model field, on-device store, provider API, confirm mapping

**Files:** Create `lib/services/task_color_store.dart`; Modify `lib/models/task_item.dart` (field, `copyWith`, `fromJson` `color_key`, `toJson` `color_key` only when non-null), `lib/models/schedule_item.dart` (field + `fromJson`), `lib/providers/app_state_provider.dart` (load/apply/set; `confirmCandidates` mapping); Test `test/task_color_store_test.dart`.

**Interfaces — Produces:**
- `class TaskColorStore { Future<Map<String,String>> load(); Future<void> put(String taskId, String? key); }` (SharedPreferences key `flowstate_task_colors_v1`, JSON map; `null` removes the entry)
- `Future<void> AppStateProvider.setTaskColor(String taskId, FlowTaskColor? color)`
- `FlowTaskColor? AppStateProvider.taskColorFor(String? taskId)`
- After `confirmCandidates` succeeds: for each `i`, if the candidate with id `res['client_refs'][i]` has a `colorKey`, `put(res['tasks'][i]['id'], colorKey)`. The backend returns `client_refs` aligned with `tasks` [verified `backend/app/schemas/task.py:211`; client sends `client_ref: t.id` at `app_state_provider.dart:1357`].

- [ ] **Step 1: Write failing tests:**
  - `set/change/reset persists across provider re-creation` (`SharedPreferences.setMockInitialValues`).
  - `unknown key in store ignored`.
  - `color for a deleted task is dropped on load`.
  - `confirm maps candidate colors to created ids via client_refs`.
  - `demo-mode confirm keeps color on temp ids`.
  - `TaskItem JSON round-trip keeps color_key; absent stays null`.
  - `ScheduleItem.colorKey falls back to provider lookup by taskId`.
- [ ] **Steps 2–5:** Run (FAIL) → implement → run with `test/confirm_candidates_batch_test.dart test/task_editing_test.dart` (PASS / ⊆ baseline) → checkpoint.

### Task 28: Picker + Task details + Add task

**Files:** Create `lib/components/flow_task_color_picker.dart`; Modify `lib/components/edit_task_sheet.dart`, `lib/screens/add_task_sheet.dart`; Test `test/task_color_picker_test.dart`.

**Interfaces — Produces:** `FlowTaskColorPicker({required FlowTaskColor? value, required ValueChanged<FlowTaskColor?> onChanged})`:
- Default swatch first (`null`)
- swatches 40 dp inside 48 dp targets
- selected = check icon + ring
- `Semantics(label: '<Name> color' | 'Default color', selected:)`

The sheets show a live preview row (`FlowTimelineRow` with the pending color) at the top while the picker changes, and persist on the existing Save via `setTaskColor`.

- [ ] **Step 1: Write failing tests:**
  - `tapping Rose updates preview accent before save`.
  - `cancel discards`.
  - `save persists`.
  - `Default resets to null`.
  - `semantics labels and selected state`.
  - `48dp targets`.
  - `works in dark theme`.
- [ ] **Steps 2–5:** Run (FAIL) → implement → run with `test/add_task_and_options_ui_test.dart test/task_editing_test.dart` (PASS / ⊆ baseline) → checkpoint.

### Task 29: Render accents everywhere + Build My Day color dot

**Files:** Modify `lib/components/timeline_item_widget.dart` (`FlowTimelineRow`), `right_now_task_card.dart`, `task_card.dart`, `plan_diff_view.dart`, `lib/screens/brain_dump_sheet.dart` (`_buildEditContent`, preview rows); Test `test/task_color_rendering_test.dart`.

- [ ] **Step 1: Write failing tests:**
  - `row node + 3px accent bar use task color; title text color unchanged`.
  - `NOW fill uses task color at 0.08 light / 0.14 dark, else app accent`.
  - `completed row task color at 40% opacity`.
  - `conflict/missed indicator colors identical with and without task color`.
  - `TaskCard leading bar`.
  - `plan_diff moved row shows accent`.
  - `Build My Day edit row color dot opens picker; chosen color survives into confirm payload candidate`.
  - `Focus screen ring unaffected`.
- [ ] **Steps 2–5:** Run (FAIL) → implement → run with `test/plan_diff_view_test.dart test/build_my_day_editor_test.dart test/today_page_test.dart` (PASS / ⊆ baseline) → checkpoint.

**M7a gate:** full suite ⊆ baseline; manual: spec §22 task-color item in light and dark with TalkBack announcing swatches; colors persist across an app restart; `tastemaker`: each palette color on Calendar, Today, task card, Task details picker and Build My Day edit row, in both themes, after = `ui-reference/after/M7a/`, judged against §24.3 treatment rules (accent only, never fills/text); gate requires A = 0.

---

## Milestone M7b — Task colors, backend sync (P1, separate; blocked)

**Blocked until** the five D4 production-schema facts in `docs/superpowers/specs/build-my-day-replan.md` §11.1 are supplied. **Do not start M7b inside the motion milestones.**

### Task 30: Migration 007 + schemas + payloads

**Files:**
- Create `backend/alembic/versions/007_task_color_key.py` (revision `007_task_color_key`, down_revision `006_task_planning_columns`)
- Modify `backend/app/models/task.py` (`color_key = Column(String(16), nullable=True)`)
- Modify `backend/app/schemas/task.py` (`TaskCreate`, `TaskUpdate`, `TaskResponse`, batch item: `color_key: Optional[Literal['sky','mint','blue','amber','rose','violet','lime','slate']] = None`)
- Modify `backend/app/schemas/calendar.py:18,81`, `backend/app/schemas/today.py` (schedule item `color_key: Optional[str] = None`)
- Modify `backend/app/services/calendar_service.py` (populate from the task), `backend/app/services/plan_confirm_service.py` (persist)
- Test `backend/tests/test_task_color_key.py`

- [ ] **Step 1: Write failing tests:**
  - `create/update/read round-trips color_key`.
  - `invalid key → 422`.
  - `null clears`.
  - `calendar/day and today items include color_key`.
  - `batch confirm persists color_key per item`.
  - `migration upgrade --sql emits only ALTER TABLE tasks ADD COLUMN color_key VARCHAR(16)` (offline mode, like 006).
  - `downgrade drops the column`.
- [ ] **Step 2:** Run `backend/venv/Scripts/python -m pytest backend/tests/test_task_color_key.py -q`. Expected: FAIL.
- [ ] **Step 3:** Implement. The migration is ALTER-only and fails loudly without a `tasks` table, matching 006's style and docstring.
- [ ] **Step 4:** Run the full backend suite. Expected: 1160 + new, all passing.
- [ ] **Step 5:** Checkpoint.

### Task 31: Client sync + one-time reconciliation

**Files:** Modify `lib/services/task_service.dart` (send `color_key` on create/update), `lib/providers/app_state_provider.dart` (`_candidateToBatchItem` adds `color_key`; `setTaskColor` calls update; reconciliation); Test `test/task_color_sync_test.dart`.

- [ ] **Step 1: Write failing tests:**
  - `setTaskColor sends PATCH with color_key`.
  - `confirm payload includes color_key`.
  - `first sync uploads local colors only where server color_key is null, exactly once (flag flowstate_task_colors_reconciled_v1)`.
  - `afterwards server value wins over local cache`.
  - `offline set keeps local value and retries on next sync`.
- [ ] **Steps 2–5:** Run (FAIL) → implement → run with `test/confirm_candidates_batch_test.dart test/task_editing_test.dart` (PASS / ⊆ baseline) → checkpoint.

---

## Milestone M8 — Polish + asset integration (P2)

### Task 32: Labels, metadata, icons (B6.2, B6.3, B7)

**Files:** Modify `lib/screens/today_dashboard_tab.dart` ("AI DAY PLANNER"), `brain_dump_sheet.dart` ("YOUR PLAN", "✨ AI planning"), `calendar_tab.dart` (any remaining "✨"), `task_card.dart` (metadata line, priority flag only if explicit, 48 dp action targets); Test `test/polish_labels_test.dart`.

- [ ] **Step 1: Write failing tests:**
  - `no button contains both an auto_awesome icon and '✨'`.
  - `section labels are sentence case` ('Your plan', 'AI day planner').
  - `'Priority not specified' never rendered anywhere`.
  - `TaskCard one-line title without explicit priority ≤ 112dp; no pills except explicit priority flag`.
  - `card action icons have 48dp targets`.
  - `tappable rows/chips in touched screens use exactly one press language` (`FlowPressScale` xor ink; §8.1).
- [ ] **Steps 2–5:** Run (FAIL) → implement → run with `test/micro_interactions_polish_test.dart test/add_task_and_options_ui_test.dart test/noya_visual_system_test.dart` (PASS / ⊆ baseline) → checkpoint.

**M8 gate:** full suite ⊆ baseline; analyze clean; `tastemaker` final pass over every touched screen in both themes (after = `ui-reference/after/M8/`), including all B-class findings logged at earlier gates; gate requires A = 0, and the user receives the `TASTEMAKER-DEFERRED` list.

### Contingent tasks (start only when the asset arrives; each gets its own TDD task)

Each contingent Noya-motion task starts with Step 0 (animate) under the Skill Usage Protocol. The new frame's timing (e.g. the A1 blink: 120 ms, every 4–8 s) is taken from this table and the spec, not chosen by the skill.

| Asset (§15) | Integration |
|---|---|
| A1 blink frame | `NoyaState.blink` (non-selectable) + a 120 ms blink every 4–8 s inside the idle window only; tests: blink only while the breath loop is active; never in reduced motion |
| A4 exercise pose | `NoyaState.exercising`; `resolveStateForTask` routes `isPhysical` to it; update `noya_visual_system_test` test 4 |
| A6 art fixes | File replacement only (same paths); re-run `noya_visual_system_test` |
| A2 / A3 / A5 | Frame stepper inside `NoyaMotionView` (no package) / `NoyaState.reassuring` for `recover` |
| D6 NOW-marker Noya | Prototype behind a const flag; requires user sign-off on screenshots |

---

## Dependencies

- **Packages:** none added. Uses Flutter SDK (`animation`, `physics` `SpringSimulation`/`SpringDescription`, `AnimatedSwitcher`, `AnimatedSize`, `RepaintBoundary`, `ResizeImage`), plus existing `provider`, `shared_preferences`, `intl`. Backend: existing Alembic/SQLAlchemy/Pydantic.
- **Task order:**
  - 0 → 1 → 2, 3, 4 (parallel) → 5 → 6 → 7 → 8 → 9 → 10
  - 11 → 12 → 13 → 14 → 15 → 16 (M2 needs 4, 7–9)
  - 17 → 18 (needs 13)
  - 19 → 20 (needs 9, 13)
  - 21 → 22
  - 23, 24, 25 (need 10)
  - 26 → 27 → 28 → 29 (29 needs 13, 17)
  - 30 → 31 (blocked by D4; 31 needs 27)
  - 32 last

## Migration requirements

- **Only M7b** has a schema change: `007_task_color_key` adds a nullable `tasks.color_key VARCHAR(16)`. It is ALTER-only and offline `--sql` capable. Downgrade drops the column.
- **It inherits the D4 blocker:** production `tasks` table provenance is unknown (`build-my-day-replan.md` §11.1). It must be resolved before running 007 anywhere but the test DB.
- M7a stores colors under SharedPreferences key `flowstate_task_colors_v1` (no migration). M7b reconciliation sets `flowstate_task_colors_reconciled_v1`.
- No other data or API change. Task 24 adds a client-side getter only.

## Test requirements (summary)

- **TDD per task:** failing test first, run red, implement, run green. Commands and expected output are in each task.
- **New test files:**
  - `flow_motion_tokens_test`, `motion_loop_lifecycle_test`, `skeleton_shimmer_test`
  - `noya_reaction_controller_test`, `noya_motion_view_test`
  - `flow_date_strip_test`, `flow_timeline_row_test`, `flow_completion_check_test`
  - `build_my_day_motion_test`, `plan_result_rows_test`
  - `noya_completion_hook_test`, `today_noya_motion_test`
  - `flow_colors_contrast_test`, `dark_mode_sweep_test`
  - `focus_hub_motion_test`, `onboarding_motion_test`
  - `flow_task_colors_test`, `task_color_store_test`, `task_color_picker_test`, `task_color_rendering_test`, `task_color_sync_test`
  - `polish_labels_test`
  - backend `test_task_color_key.py`, plus the Task 11 regression test
- **Modified (strengthened):** `noya_visual_system_test` (7 → 9 states), `calendar_date_navigation_test` (D1 key + label + semantics rewrite), additions to `today_page_test` and `flow_auth_hub_test`.
- **Gates:**
  - every milestone: failing set ⊆ Task 0 baseline
  - `dart analyze lib test`: no new issues
  - backend suite green whenever backend files change

## Manual verification requirements

Use spec §22 as the checklist, run at the milestone gates noted above. Configurations:
- emulator 360×640 and 412×915
- light and dark
- text scale 1.0 and 1.3
- Android "Remove animations" on/off
- a physical Android device when available

Evidence to capture per milestone: before/after screenshots of each touched screen in both themes, saved to `docs/superpowers/specs/ui-reference/after/<milestone>/` (screenshots only; the folder is created during verification).

These screenshots are the input to the `tastemaker` critique at the M2, M3, M4, M5, M6, M7a and M8 gates (Skill Usage Protocol). The triage summary (A/B/C counts plus the `TASTEMAKER-DEFERRED` list) is part of each gate report. `tastemaker` is additive: every §22 accessibility, contrast and reduced-motion check still runs.

## Performance verification (spec §24.2)

| Layer | When | Pass |
|---|---|---|
| 1 Structural (automated) | M0, M1, M2, M4 gates | Zero Noya tickers 31 s after mount; no `FlowCompanionView` ticker outside focusing; Noya `ResizeImage.width` = size × DPR; ambient `RepaintBoundary` present and "Highlight repaints" shows tab content not repainting; ≤ 1 Noya loop per screen; shimmer uses one controller per skeleton |
| 2 Headroom timing | M2 (date change), M3 (plan reveal), M4 (celebrate), M1 (greet) | `flutter run --profile` on the available physical Android device: worst UI and raster frame ≤ 8 ms per scenario (≤ 16 ms if the device is at or below the reference class) |
| 3 Low-memory | M3 gate | Emulator API 30, 2 vCPU, 2 GB, 720×1600 @ 320 dpi (debug): Noya image cache ≤ 8 MB with Build My Day open; no blank frame on pose change |

**Conditional:** if Layer 2 shows sustained raster cost from `FlowAmbientBackground`, add a task to hold its frame 20 s after a tab becomes visible (§17 P8). Otherwise no change.

## Missing asset requirements

From spec §15. **Motion ships without any of these.** Each is optional and plugs in through the contingent tasks above. Production constraints:
- 1024×1024 transparent PNG with the same canvas, scale, baseline and bottom-center anchor as `noya/noya_default.png`
- flat cel style (not `winking_fox.png`)
- the canonical navy collar with gold star medallion

| ID | Asset | Priority | Without it |
|---|---|---|---|
| A1 | Blink frame (default framing, eyes closed) | P1 | No blink; breath only |
| A4 | Exercise pose | P1 | Physical tasks keep `encouraging` + bounded energetic bob |
| A6 | `noya_proud` single tail + canonical collar; `noya_sleepy` canonical collar | P1 | Slight identity break during crossfades |
| A2 | 3 wave frames | P2 | Body sway stands in for the wave |
| A3 | 6–8 frame walk cycle | P2 | Pacing glide stands in for walking |
| A5 | Reassuring pose | P2 | `recover` uses the current/idle pose |
| A7 | Layered source / Rive rig | P3 | Not pursued (no package) |
| — | Separate task (D7): remove the 11 duplicate files and debug images from `assets/images/companions/` (27 MB folder) | — | Larger app bundle |
