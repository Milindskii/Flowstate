# Flowstate — Noya Motion System & UI Refinement Specification

| | |
|---|---|
| Status | **Approved 2026-10-02 (Rev 2 — approval resolutions in §24).** Permanent source of truth for Flowstate motion and UI refinement. No implementation has started; the implementation plan is `docs/superpowers/plans/2026-10-02-noya-motion-ui-refinement.md`. |
| Date | 2026-10-02 |
| Scope | Part A: motion + Noya animation system. Part B: refinement of existing UI (containers, Calendar, dark mode, custom task colors, tokens, consistency). |
| Out of scope | Visual redesign, new visual identity, layout restructuring beyond the evidence-backed refinements in Part B, backend/scheduling behavior, auth architecture. |
| Product code changed by this document | None. No Dart, asset, or backend file was modified. |

## Evidence legend

Every claim in this document carries one of these tags:

- **[VERIFIED]** — observed directly in a screenshot or in the repository (file path given).
- **[PROPOSED]** — a behavior or change this spec asks to be implemented. Nothing tagged PROPOSED exists today.
- **[MISSING ASSET]** — requires artwork that does not exist in the repository.
- **[UNCERTAIN]** — needs validation (profiling, device test, product decision) before implementation.

## Evidence sources

**Screenshots.** The brief names `docs/superpowers/specs/ui-reference/` as the screenshot source. **That folder does not exist** [VERIFIED]. The screenshots used here are the eight Flowstate captures taken 2026-10-02 14:10–14:20 in the user's OneDrive `Pictures/Screenshots` folder. Unrelated screenshots in that folder were ignored. Recommended: copy these eight files into `docs/superpowers/specs/ui-reference/` so the evidence lives next to the spec.

| ID | File | Screen | State shown |
|---|---|---|---|
| S1 | `Screenshot 2026-10-02 141028.png` | Calendar | Today selected, empty day |
| S2 | `Screenshot 2026-10-02 141602.png` | Calendar | Yesterday selected, loading |
| S3 | `Screenshot 2026-10-02 141657.png` | Calendar | Today, two scheduled items, NOW marker |
| S4 | `Screenshot 2026-10-02 141049.png` | Today | First-run empty state ("What's on your plate?") |
| S5 | `Screenshot 2026-10-02 141111.png` | Living Flow Hub | Auth error banner, Noya card |
| S6 | `Screenshot 2026-10-02 141326.png` | Build My Day sheet | Input state, keyboard open, AI/Shields status loading |
| S7 | `Screenshot 2026-10-02 141536.png` | Plan Result (Brain Dump preview) | Two planned tasks |
| S8 | `Screenshot 2026-10-02 142000.png` | Tasks inbox | Filter pills + two task cards |

**No dark-mode screenshot exists** [VERIFIED]. All dark-mode findings in Part B are derived from code, and their visual impact is [UNCERTAIN] until captured on a device.

**Repository.** Every file referenced below was read in this session. Flutter tests cannot be executed in Claude's shell on this machine (Windows Application Control blocks the `flutter` tool; only `dart analyze` runs). The user must run widget tests.

---

# PART A — MOTION & NOYA ANIMATION SYSTEM

## 1. Executive summary

Flowstate already has most of what a motion system needs:

- a motion token file, `lib/theme/flow_motion.dart`
- a reduced-motion convention (`MediaQuery.disableAnimations`)
- a canonical Noya widget with 7 poses, `lib/components/noya_companion_view.dart`
- a companion state controller, `lib/components/companion/flow_companion_animation_controller.dart`
- one good piece of character motion: Noya "pacing" with a ground shadow in `lib/components/routine_building_view.dart` [VERIFIED]

What it lacks is the layer that connects them. Today Noya is a static PNG whose pose **cuts instantly** when state changes (`NoyaCompanionView` is a `StatelessWidget` with no transition) [VERIFIED]. Most screens never animate it. The two loops that do run are either too strong (a ±4% scale pulse, a 0.92–1.04 splash pulse) or run when nothing is happening (the pulse controller repeats in every state but is only applied while focusing) [VERIFIED].

This spec adds **one motion layer on top of the unchanged UI**:

1. **`NoyaMotionView`** [PROPOSED] wraps the existing `NoyaCompanionView` and adds:
   - pose crossfades
   - entrance and exit
   - a subconscious idle "breath" that stops on its own
   - one-shot reactions (greet, task done, plan ready, celebrate, recover)
   - sustained moods (thinking, pacing, focusing, wind-down)

   All of it is built from the **existing static poses plus Flutter-native transforms**. No new package is needed.
2. **Motion tokens**: extend `FlowMotion` with character timings, curves and spring constants, so the 61 hard-coded `Duration(milliseconds: …)` literals can converge on one system [VERIFIED count].
3. **Reaction plumbing** [PROPOSED]: task completion, plan ready, focus milestones and errors all trigger Noya through the existing `FlowCompanionAnimationController` (extended with a one-shot `react()` API), not through ad-hoc per-screen code.
4. **Performance fixes** that motion depends on:
   - stop always-on loops
   - decode Noya at display size instead of 1024×1024
   - isolate the always-animating ambient background behind a `RepaintBoundary`

The test for success is the brief's own: **if animation is paused, every screen looks exactly like today's Flowstate. With animation on, Noya visibly responds to what the user just did.**

Real walking, waving-arm, blinking and exercise animation **cannot be produced from the current assets** (see §2 and §15). This spec defines honest interim behavior for each and lists the exact artwork needed to upgrade later.

---

## 2. Current Noya asset audit

### 2.1 What is registered in code [VERIFIED]

`pubspec.yaml` bundles `assets/images/companions/` and `assets/images/companions/noya/`. `NoyaState` (7 values) maps to the `noya/` subfolder:

| `NoyaState` | Asset | Pose (visually inspected) | Same framing as default? |
|---|---|---|---|
| `idle` | `noya/noya_default.png` | Sitting upright, one paw raised, soft smile, navy collar with gold star medallion | — (reference) |
| `thinking` | `noya/noya_thinking.png` | Same sit, paw at chin, closed mouth, blue "?" above | **Yes** — expression change only |
| `focusing` | `noya/noya_focusing.png` | At desk with laptop, books, green leaf headband | No (props, different body) |
| `celebrating` | `noya/noya_celebrating.png` | Mid-jump, both paws up, open mouth, gold sparkles | No |
| `encouraging` | `noya/noya_encouraging.png` | Same sit, right paw raised in a wave, motion lines, orange sparkles | Mostly (arm differs) |
| `proud` | `noya/noya_proud.png` | Sitting, winking, gold sparkles | No — different proportions (see 2.4) |
| `sleepy` | `noya/noya_sleepy.png` | **Curled up asleep**, eyes closed, purple "zzz" | No |

`test/noya_visual_system_test.dart` asserts `NoyaState.values.length == 7` and the exact asset paths [VERIFIED]. Adding states means deliberately updating that test (decision D2).

### 2.2 Distinct art that exists but is not registered [VERIFIED]

| File (root `companions/`) | Pose | Notes |
|---|---|---|
| `noya_success.png` | Default sit with **star-sparkle eyes**, blush, small sparkles | Same framing as default, so it crossfades cleanly. Ideal "plan ready / delighted" expression. |
| `noya_sleeping.png` (byte-identical to `noya_tired.png`) | Default sit, **drowsy half-closed eyes**, blush, faint "zzz" | Same framing as default. Ideal "evening wind-down". **The filename is misleading**: this is the drowsy one, while `noya/noya_sleepy.png` is the asleep one. |
| `winking_fox.png` | Soft **3D-rendered** fox, open-mouth wink | **Different art style** (3D shading versus flat cel art). Not referenced in `lib/`. **Must not be used**; it would break Noya's identity. |

### 2.3 Duplicates and bundle weight [VERIFIED by MD5]

- **11 filenames are byte-identical** to `noya_default.png` (836,289 bytes each): `noya.png`, `noya_default.png`, `noya_idle.png`, `noya_ready.png`, `noya_hero.png`, `noya_card.png`, `fox.png`, `fox_card.png`, `fox_hero.png`, `fox_winking.png` (despite its name, *not* winking), and `noya/noya_default.png`.
- Every `noya/*.png` file duplicates a root file.
- The whole `companions/` folder is **27 MB** and is bundled in full by `pubspec.yaml`. That includes debug and test images (`test_*`, `inspect_*`, `preview_*`, `im1_fox.png`, `hero_from_im1.png`, `fox_from_screenshot.png`, ≈1.4 MB).
- Asset cleanup is **not** part of this spec's implementation scope, because the brief says not to modify assets. It is listed as a follow-up requiring approval (decision D7).

### 2.4 Art consistency issues [VERIFIED visually; severity UNCERTAIN, needs art review]

- `noya_proud.png` appears to show **two tails** (one behind the body on the left, one curling on the right). Its collar is a brighter royal blue and the head proportions differ slightly from default. Next to the default pose in a crossfade, this reads as a different character for ~250 ms.
- `noya/noya_sleepy.png` (curled) has a **light-blue collar with a dangling star tag** instead of the canonical navy collar with gold medallion.
- These are the only identity breaks. All other poses share collar, palette, line weight and eye style.

### 2.5 Technical properties [VERIFIED]

- All Noya poses are **1024×1024 RGBA PNGs with true transparency**. Background pixels have alpha = 0, decoded and checked for `noya_default`, `noya_focusing` and `noya_sleepy`. Transparent pixels carry white RGB (255,255,255,0).
- Possible light fringing on dark surfaces at small sizes is [UNCERTAIN]. Verify on a dark-mode device (§22).
- Sparkles, "?", "zzz" and motion lines are **baked into the PNGs**. They cannot be animated independently.
- No layered or rigged source exists:
  - no PSD/SVG/Rive/Lottie files in the repo
  - no sprite sheets
  - no `rive`, `lottie` or `flame` dependency in `pubspec.yaml`

### 2.6 What the assets can and cannot support

| Capability | Supported? | Basis |
|---|---|---|
| Static pose switching | **Yes** | 7 registered + 2 unregistered distinct poses |
| Expression change without a visible "cut" | **Partially** — between default, thinking, success and sleeping, which share framing | Visual comparison §2.1/2.2 |
| Whole-body procedural motion (breathe, bob, tilt, hop, squash, pace) | **Yes** — transforms on a transparent PNG anchored at bottom-center | Already proven by `routine_building_view.dart` pacing |
| Blink | **No** [MISSING ASSET] | Needs an eyes-closed frame with identical framing |
| Arm wave cycle | **No** [MISSING ASSET] | The wave is one frozen frame |
| Walk cycle | **No** [MISSING ASSET] | No leg frames; only translation-based "pacing" is possible |
| Exercise/gym pose | **No** [MISSING ASSET] | Today physical tasks fall back to `encouraging` (waving) [VERIFIED `resolveStateForTask`] |
| Concerned/reassuring pose | **No** [MISSING ASSET] | Errors currently show `idle` |
| Independently animated sparkles/zzz | **No** | Baked in |
| Frame-based / Rive / Lottie animation | **No** | No assets, no packages |

---

## 3. Screenshot-based motion opportunities

Only problems visible in the screenshots or provable in code are listed.

| ID | Observed [VERIFIED] | Motion opportunity [PROPOSED] |
|---|---|---|
| S1 | Calendar has **no Noya**. The empty day uses a generic `event_note` icon. Two primary blue buttons compete ("✨ Replan My Day" and "Build My Day"). | Noya replaces the generic icon in the empty state with a one-time greet. No Noya on the timeline itself. |
| S2 | Loading shows a lone `CircularProgressIndicator` under "Scheduled Timeline" with a large blank area. | Replace the spinner with a 3-row timeline skeleton using a shared shimmer. The date change gets a direction-aware content slide. |
| S3 | NOW marker is a static dot + line. Items are stacked bordered cards. No motion on completion or date change. | NOW dot gets a slow, low-amplitude pulse (only on Today, only while visible, bounded). Completion animates the check and collapses the row to its muted state. |
| S4 | Today empty state: Noya (`encouraging`, 76 px, static) beside "What's on your plate?". The lower ~50% of the screen is empty ambient background. | Noya enters and greets once per day on this card, then idles. No added motion in the empty area. Motion must not fill space that layout should fix. |
| S5 | Flow Hub shows the raw string "Authentication required. Please sign in. Retry". Noya sits static in a framed card. | Friendly sign-in prompt (Part B §B6) with a calm `recover` motion. Noya greets once on entry and reacts when tapped (`onTap` already exists [VERIFIED `flow_screen.dart:346`]). |
| S6 | Build My Day sheet: Noya header card, then an "✨ AI planning" status box with loading pills ("… Shields", "Checking…") and a 3-line paragraph, then the input. Keyboard open: Noya shrinks 72→40 px **instantly** [VERIFIED `brain_dump_sheet.dart:626`]. | Animate the Noya size change. Noya `idle → encouraging` crossfade when input becomes valid (today it's an instant cut). `thinking` + think loop while planning. Escalate to pacing on long waits. |
| S7 | Plan Result: "Noya organized your plan" card with static `proud` Noya. Plan rows appear all at once. | One orchestrated reveal: Noya `delighted` reaction (sparkle eyes), then plan rows stagger in once. On confirm, the new rows get a highlight pulse where they land (Calendar/Today). |
| S8 | Tasks inbox: a small static Noya **repeated on every card** (idle for one, waving `encouraging` for the gym task). | Repeated per-card Noyas stay **static** (no loops in lists; performance and calm). Only the card whose task was just completed plays a reaction. |

**Non-motion issues observed (recorded, not addressed by motion):**

- S3 shows "Go to the gym…" at 4:00 PM with a "✦ FLOWSTATE / Scheduled by Flowstate" badge. S7 showed the same task as "4:00 PM · Fixed time · [Fixed]". The fixed state is **not reflected in Calendar** for this item [VERIFIED across screenshots; cause UNCERTAIN: `isFixed` not propagated versus a different response]. Part B Calendar work depends on correct fixed/flexible data, so this must be diagnosed first (rollout M2, step 0).
- S3/S7: "At night I have to take shower" was scheduled at 2:15 PM and typed as "High Focus / Deep Work". That is a parsing/scheduling issue, out of scope here.

---

## 4. Motion design principles

1. **The paused test.** With every animation frozen at its resting frame, the screen must be pixel-identical to the current design. Motion never introduces resting-state visual elements (no permanent glows, rings or particles).
2. **One character, one voice.** Noya is the only character-like moving element. UI motion (rows, chips, sheets) is fast, short and functional, and never competes with Noya for attention at the same moment.
3. **Motion answers something.** Each animation answers "what does this tell the user?" One of:
   - *I noticed you* (greet)
   - *I'm working* (think/pace)
   - *That worked* (react/celebrate)
   - *It's late, slow down* (wind-down)
   - *Something needs you, calmly* (recover)
   - *This is what changed* (UI highlight)

   Motion without an answer is cut.
4. **Honest motion.** Loading motion reflects real work only. No fake step-by-step progress for a single network request. (Note: `routine_building_view.dart` advances its four "steps" on a 650 ms timer, not on real work [VERIFIED]. It is kept as onboarding theatre, but the pattern must not spread to AI planning.)
5. **Quiet by default, loud rarely.** Level 3 (hero) motion is capped per day (§9, §13).
6. **Bounded loops.** No Noya loop runs indefinitely. Idle breathing stops after a fixed window, and every loop stops when offstage, backgrounded, or under reduced motion.
7. **Motion is never the only signal.** Every state Noya expresses is also expressed in text or UI state (§18).

---

## 5. Noya state machine

Noya has two layers [PROPOSED]:

- **Mood**: sustained, derived from app state, at most one at a time. Moods are `rest`, `thinking`, `pacing`, `focusing`, `windDown` and `asleep`.
- **Reaction**: a one-shot overlay that plays, then returns to the current mood. Reactions are `greet`, `taskDone`, `planReady`, `celebrate` and `recover`.

```
                 ┌──────────── reactions (one-shot, return to mood) ────────────┐
                 │ greet · taskDone · planReady · celebrate · recover           │
                 └───────────────▲──────────────────────────────┬───────────────┘
                                 │ react(r)                     │ done → resume mood
   app state ──► MOOD ───────────┴──────────────────────────────▼
                 rest ⇄ thinking ⇄ pacing        focusing        windDown ⇄ asleep
                 (default)  (AI/plan work)       (focus session) (evening / day done)
```

### 5.1 Mood resolution (highest applicable wins)

| Priority | Mood | Condition (existing signals) [VERIFIED source] |
|---|---|---|
| 1 | `focusing` | An active focus session (`FlowProvider._activeSessionId != null` → `animController.setFocusing`, `flow_provider.dart:142`), or a Noya bound to an in-progress task (`resolveStateForTask`) |
| 2 | `pacing` | An AI/planning request has been pending for longer than 4 s (§12) |
| 3 | `thinking` | An AI/planning request is pending (`brain_dump_sheet._isLoading`, `replan_day_sheet._isLoading`) |
| 4 | `asleep` | The day is finished (`today_dashboard_tab.dart` `isDayActuallyFinished`, line ~942) |
| 5 | `windDown` | Local time ≥ 20:00 (via `FlowClock`) **and** no pending tasks remain today [PROPOSED threshold; decision D5] |
| 6 | `rest` | Otherwise |

### 5.2 Reactions

| Reaction | Trigger | Pose during | Level |
|---|---|---|---|
| `greet` | First view of a Noya-bearing screen per session (Today: per calendar day); onboarding complete; Noya tapped | `encouraging` | L2 |
| `taskDone` | `AppStateProvider.toggleTaskCompletion` marks a task complete (`app_state_provider.dart:660`, callback `onTaskCompletedForFlow` at 688/715) | `proud` (or `delighted` if decision D3 replaces `proud`) | L2 |
| `planReady` | Build My Day / Replan returns a plan | `delighted` (`noya_success.png`) | L2 |
| `celebrate` | Last pending task of the day completed; focus session completed (`animController.triggerSuccess`, `focus_ritual_screen.dart:396`); companion level-up/evolution (`triggerLevelUp`/`triggerEvolution`) | `celebrating` | **L3** |
| `recover` | Network/auth/planning failure surfaced on a Noya-bearing screen | Current mood pose (no "worried" pose exists) | L1 |

### 5.3 Rules

- **Priority:** `celebrate > taskDone > planReady > recover > greet`. A higher reaction interrupts a lower one, crossfading from the current frame. A lower one arriving during a higher one is dropped.
- **Coalescing:** multiple `taskDone` within 1.5 s (e.g. a batch check-off) play **once**.
- **Rate limits:**
  - `greet` at most once per screen per app session, and once per day on Today
  - `celebrate` at most **3 per day**, with further celebrations downgraded to `taskDone`
  - tapping Noya at most once per 2 s
- **Interruption by user:** if the user navigates away mid-reaction, the reaction is discarded (not replayed on return).
- **Mood change during reaction:** the reaction finishes, then crossfades to the new mood's pose.

---

## 6. Noya animation states

All transforms are **anchored at bottom-center** of the Noya box (her "feet/ground"), so she never appears to float off the layout. Amplitudes are given as a fraction of the rendered Noya size `s`, so behavior scales from a 28 px pill to a 156 px hero. Sizes below 48 px get **no loops** (§17).

Each entry follows the brief's template: **Trigger → Start → Animation → Duration → Easing → End → Fallback → Reduced motion.**

### 6.1 Enter (any Noya appearing on screen for the first time)

- **Trigger:** a `NoyaMotionView` is first mounted *and* `enter: true` (default off for list items).
- **Start:** opacity 0, scale 0.92, translateY +0.06·s.
- **Animation:** fade + rise + scale to rest.
- **Duration:** `FlowMotion.characterEnter` = 420 ms.
- **Easing:** `FlowMotion.emphasized` (Cubic 0.2, 0, 0, 1). No overshoot.
- **End:** rest frame of the current mood.
- **Fallback:** if the asset fails, the existing `errorBuilder` → default pose → `Icons.pets_rounded` [VERIFIED] still fades in.
- **Reduced motion:** opacity 0→1 over 150 ms, no scale/translate.

### 6.2 Exit

- **Trigger:** Noya removed while still visible (sheet closing, state view swap).
- **Start:** current frame. **Animation:** fade to 0, scale to 0.96. **Duration:** `characterExit` = 200 ms. **Easing:** `Curves.easeInCubic`.
- **End:** unmounted. **Fallback:** none needed.
- **Reduced motion:** instant removal.

### 6.3 Pose change (any mood or reaction that changes the PNG)

- **Trigger:** the resolved pose differs from the displayed pose.
- **Start:** old pose at rest.
- **Animation:**
  - Old pose fades out while the new pose fades in, stacked bottom-center (an `AnimatedSwitcher` with a custom `layoutBuilder`).
  - The **incoming pose scales 0.97 → 1.0**.
  - For same-framing pairs (default ↔ thinking ↔ success ↔ sleeping), use a pure crossfade so it reads as an expression change.
- **Duration:** `posePivot` = 260 ms.
- **Easing:** `easeInOutCubic`.
- **End:** new pose at rest. **Fallback:** if the new asset is not yet decoded, keep the old pose until `precacheImage` completes (max 300 ms), then switch.
- **Reduced motion:** 120 ms opacity crossfade only. A crossfade is not "motion" in the vestibular sense and preserves state legibility.

### 6.4 Idle / rest ("breath")

- **Trigger:** mood `rest`, Noya size ≥ 48 px, screen visible.
- **Start:** rest frame.
- **Animation:**
  - scaleY 1.000 ↔ 1.012 with scaleX 1.000 ↔ 0.996 (volume-preserving), anchored bottom-center
  - plus translateY 0 ↔ −0.006·s
- **Duration:** period 3,800 ms (`breathPeriod`), sine in-out.
- **Bounded:** plays for **30 s after the last trigger** (mount, user interaction on the screen, reaction end), then eases to rest over one half-period and stops. It restarts on the next interaction.
- **End:** rest frame (pixel-identical to today's static image).
- **Fallback:** static image.
- **Reduced motion:** no breath. Static.

This must be "almost subconscious". At 76 px the vertical travel is under 1 px of scale and 0.5 px of rise. If a reviewer notices it consciously in the first 3 seconds, the amplitude is too high.

### 6.5 Greet (`greet` reaction)

- **Trigger:** see §5.2.
- **Start:** current mood frame.
- **Animation:**
  1. Pose change to `encouraging` (waving), 260 ms.
  2. A **wave sway**: rotation about bottom-center 0° → −4° → +3° → −1.5° → 0°, with a small hop of translateY −0.03·s at the first peak.
  3. Hold 600 ms.
  4. Pose change back to the mood pose.
- **Duration:** ≈ 1,500 ms total (260 + 640 sway + 600 hold).
- **Easing:** sway uses `FlowMotion.reactionSpring` (stiffness 420, damping 30, ζ≈0.73, ≈3.5% overshoot).
- **End:** mood pose at rest.
- **Fallback:** if `encouraging` is unavailable, sway the current pose.
- **Reduced motion:** pose crossfade to `encouraging`, hold 1,200 ms, crossfade back. No rotation or hop.
- **Limitation:** the paw itself cannot wave (no arm frames) [MISSING ASSET A2]. The body sway is the honest substitute.

### 6.6 Thinking (mood)

- **Trigger:** an AI/planning request starts.
- **Start:** any.
- **Animation:**
  1. Pose change to `thinking` (same framing as default, so it reads as Noya pausing to think).
  2. Loop: a slow head-tilt of the whole figure, rotation 0° ↔ +2° about bottom-center, with translateY 0 ↔ −0.008·s.
- **Duration:** loop period 2,600 ms (`thinkPeriod`), sine in-out. Runs while the request is pending.
- **End:** on success → `planReady` reaction; on failure → `recover`; on cancel → crossfade to `rest`.
- **Fallback:** static `thinking` pose.
- **Reduced motion:** static `thinking` pose plus the text status (which already exists, e.g. "Noya is thinking...").

### 6.7 Pacing (mood; substitute for walking)

- **Trigger:** a request has been pending longer than 4 s (§12), or the onboarding build step (existing).
- **Start:** `thinking` loop.
- **Animation:**
  - Reuse the existing proven motion from `routine_building_view.dart:209–255` [VERIFIED]: horizontal sway dx = sin(2πt)·0.08·s, step bob dy = −|sin(4πt)|·0.025·s.
  - A ground shadow ellipse scales with the bob.
  - The pose stays `thinking` (do **not** cycle poses on a timer the way `routine_building_view` does today; that produces instant cuts).
- **Duration:** 4,000 ms period (`pacePeriod`).
- **End:** same exits as thinking.
- **Fallback:** thinking loop.
- **Reduced motion:** static `thinking` + text.
- **Limitation:** this is gliding, not walking [MISSING ASSET A3: walk cycle].

### 6.8 Focus / study (mood)

- **Trigger:** a focus session is active, or Noya is bound to an in-progress task.
- **Start:** any.
- **Animation:**
  - Pose `focusing` (desk, laptop, books, so it covers both study and deep work).
  - Loop: a "typing" micro-bob of translateY 0 ↔ −0.004·s, period 5,200 ms (`focusPeriod`).
  - It **replaces** the existing ±4% `_pulseAnimation` scale in `FlowCompanionView` (0.96–1.04 over 2,400 ms [VERIFIED]), which is too strong for a state meant to protect focus.
  - Bounded: runs for 20 s after session start or resume, then holds still for the rest of the session (the user should be looking at their work, not at Noya).
- **End:** session complete → `celebrate`; paused/abandoned → crossfade to `rest`. No sad state.
- **Fallback:** static `focusing`.
- **Reduced motion:** static.

### 6.9 Exercise / gym

- **Current:** physical tasks resolve to `encouraging` (waving) [VERIFIED `noya_companion_view.dart:161–164`].
- **Interim [PROPOSED]:** keep `encouraging` and add an "energetic" bob only when that task is **in progress**: translateY 0 ↔ −0.02·s, period 1,200 ms, bounded to 6 cycles. Otherwise the pose stays static (S8 lists must not loop).
- **Target:** a dedicated stretching/exercise pose [MISSING ASSET A4]. When it exists, add `NoyaState.exercising` and route `isPhysical` to it.
- **Reduced motion:** static pose.

### 6.10 Task completion (`taskDone` reaction)

- **Trigger:** a task is marked complete.
- **Start:** the Noya nearest the completed item: the Noya on that task card/row if present, otherwise the Today header pill.
- **Animation:**
  1. Pose change to `proud` (260 ms).
  2. A **hop**: translateY 0 → −0.06·s → 0 with a landing squash of scaleY 0.97 / scaleX 1.02 for 90 ms.
  3. Hold 1,200 ms.
  4. Crossfade to the task's resolved pose (`proud` is already the completed-task pose in `resolveStateForTask`, so for a card Noya the end pose is `proud`).
- **Duration:** ≈ 1,700 ms total.
- **Easing:** hop uses `reactionSpring`.
- **Paired UI motion:** the completion check (§8.2) plus `FlowHaptics.success()` (existing).
- **End:** resolved pose at rest.
- **Fallback:** UI check animation only.
- **Reduced motion:** pose crossfade only, plus haptic.

### 6.11 Plan ready (`planReady` reaction)

- **Trigger:** Build My Day / Replan returns a plan.
- **Start:** `thinking` / `pacing`.
- **Animation:**
  1. Pose change to `delighted` (`noya_success.png`, sparkle eyes, same framing as thinking, so it reads as Noya lighting up).
  2. Scale 1.0 → 1.04 → 1.0 via `reactionSpring`.
  3. Hold 900 ms.
  4. Crossfade to `proud` (the existing preview pose, `brain_dump_sheet.dart:614` [VERIFIED]).
- **Duration:** ≈ 1,400 ms.
- **End:** `proud` at rest.
- **Fallback:** the existing instant switch to `proud`.
- **Reduced motion:** crossfade `thinking → delighted → proud`, no scale.
- **Requires:** registering `noya_success.png` as `NoyaState.delighted` (decision D2).

### 6.12 Celebration (`celebrate` reaction, Level 3)

- **Trigger:** see §5.2 and §13.
- **Start:** current pose.
- **Animation:**
  1. Pose change to `celebrating`.
  2. **Two hops**: −0.12·s then −0.07·s, each landing with a squash (scaleY 0.96 / scaleX 1.03, 90 ms).
  3. Simultaneously, a single soft radial glow behind Noya (the existing `showAmbientGlow` gradient, alpha animated 0 → 0.18 → 0).
  4. No particles (sparkles are baked into the pose).
- **Duration:** `celebration` = 1,600 ms, then hold the pose 1,500 ms, then crossfade to `proud` (task contexts) or `rest`.
- **Easing:** `celebrationSpring` (stiffness 420, damping 22, ζ≈0.55, ≈12% overshoot). This is the **only** spring allowed to overshoot visibly.
- **Paired UI:** `FlowHaptics.success()`. Supporting text such as "You're clear for now ✨" already exists [VERIFIED `today_dashboard_tab.dart` ~939].
- **End:** settled pose.
- **Fallback:** static `celebrating` pose (today's behavior).
- **Reduced motion:** crossfade to `celebrating` with no hops or glow, plus haptic and text.

### 6.13 Wind-down (mood) and asleep (mood)

- **Wind-down:**
  - **Trigger:** §5.1 priority 5.
  - **Animation:** crossfade to `windDown` (`noya_sleeping.png`, drowsy eyes, same framing as default), then a slow breath (period 6,000 ms, amplitude ×0.8 of idle), bounded to 30 s.
  - **Reduced motion:** static pose.
- **Asleep:**
  - **Trigger:** day finished.
  - **Animation:** crossfade (400 ms, slower than normal: tiredness reads as slowness) to `sleepy` (curled). A breath of scaleY ↔ 1.015 at a 6,000 ms period, bounded to 30 s.
  - **Reduced motion:** static.
- **Requires:** registering `noya_sleeping.png` as `NoyaState.windDown` (decision D2).
- **Art caveat:** the curled pose's collar differs (§2.4).

### 6.14 Error / recovery (`recover` reaction)

- **Trigger:** a recoverable failure is surfaced (network, auth-required, planning fallback).
- **Start:** current pose.
- **Animation:**
  - **No pose change to anything alarming.** If coming from `thinking`/`pacing`, crossfade to `rest`.
  - A single **settle**: translateY 0 → +0.02·s → 0 (a small "exhale" downward, never a shake), 500 ms, `easeInOutCubic`.
  - The UI message and action carry the meaning, using the existing copy where it is already friendly, e.g. "AI planning isn't available right now, so Flowstate used its built-in planner." [VERIFIED `brain_dump_sheet.dart:245`].
- **End:** `rest`.
- **Fallback:** static.
- **Reduced motion:** crossfade only.
- **Never:** shake, red tint, rapid motion, or the `thinking` "?" pose (it reads as confusion).
- **Target:** a calm reassuring pose [MISSING ASSET A5].

---

## 7. Screen-by-screen Noya behavior

Placement never changes from today unless stated. The table gives the delta.

### 7.1 Calendar (`lib/screens/calendar_tab.dart`)

- **Today [VERIFIED S1–S3]:** no Noya anywhere.
- **Empty day [PROPOSED]:**
  - Replace the 36 px `event_note_outlined` icon with `NoyaMotionView(rest, size 72, enter: true)`.
  - On first view of an empty day per session, `greet`. Under `windDown`/`asleep` mood (evening, nothing left), use that pose instead and no greet.
- **Loading:** no Noya; skeleton rows (§12). Calendar loads are usually short, and structure communicates better than a character here.
- **Timeline:** **no Noya inside the timeline by default.** An optional P2 enhancement: a 24 px static Noya head on the NOW marker that crossfades to `focusing` when the NOW item is in progress. Decision D6, because the timeline must not be interrupted.
- **Completion from Calendar:** row completion animation (§8.2). No Noya on Calendar to react, so no character reaction. Keep it quiet.

### 7.2 Build My Day (`lib/screens/brain_dump_sheet.dart`)

| Moment | Today [VERIFIED] | Proposed |
|---|---|---|
| Sheet opens | Noya header, `idle` | `enter` (420 ms) with sheet; no greet (the sheet itself is the acknowledgment) |
| Input becomes valid | Instant cut `idle → encouraging` (line 622) | Pose crossfade + a single small sway (greet-lite: rotation ±2°, 500 ms), **once per sheet open** |
| Keyboard opens/closes | Size jumps 72 ↔ 40 px (line 626) | Animate size over `standard` 220 ms, `easeOutCubic` |
| Submit | Instant cut to `thinking`; spinner in button (line 1400) | Crossfade to `thinking` + think loop. The button keeps its inline progress indicator (functional clarity). |
| Pending > 4 s | No change | `pacing` |
| Pending > 12 s | No change | Status text changes to a reassurance line (e.g. "Still organizing. Long lists take a little longer.") with a `liveRegion` announcement |
| Success → preview | Instant cut to `proud` | `planReady` reaction, then `proud`; plan reveal (§7.3) |
| Fallback planner used | Notice shown | `recover` (calm), no celebration |
| Edit mode | `focusing` (line 618) | Crossfade, no loop (the user is typing; Noya stays still) |

### 7.3 Plan Result (preview in `brain_dump_sheet.dart`, `ai_plan_preview_sheet.dart`, `parsed_plan_confirm_sheet.dart`)

- **Noya:**
  - `planReady` once, when the preview first appears.
  - `ai_plan_preview_sheet.dart:148` uses `thinking` when confirmation is needed, otherwise `proud`. Keep the mapping and add crossfades.
- **Reveal:**
  - Plan rows enter with a **single** stagger: 40 ms between rows, max 6 rows animated (later rows appear with the 6th).
  - Each row: opacity 0→1, translateY 8→0 px, `standard` 220 ms, `easeOutCubic`.
  - This is the one orchestrated moment on this screen. Nothing else animates on entry.
- **Edit a row:** inline `AnimatedSize` (220 ms) for expansion. No Noya reaction.
- **Confirm ("Add & Schedule"):**
  - Sheet exits with the standard route transition.
  - On the destination (Today/Calendar), the newly inserted rows get a **highlight pulse** (§8.6).
  - No `celebrate`; confirming a plan is not a milestone.

### 7.4 Today (`lib/screens/today_dashboard_tab.dart`)

| Location [VERIFIED line] | Today | Proposed |
|---|---|---|
| Header pill "Noya · L1" (≈540, 28 px idle) | static | Static (below 48 px: no loops). Acts as the `taskDone` reaction target when no closer Noya exists; at 28 px the hop is scaled and the pose crossfades. |
| "What's on your plate?" card (≈658, 76 px `encouraging`) | static | `enter` + `greet` once per calendar day, then bounded breath |
| "Completed one, more remain" banner (≈255, `proud`) | static | Appears with `taskDone` hop on first show |
| Completion card (≈942/970: `sleepy` / `proud` / `celebrating`) | static | Mood mapping kept. `celebrate` plays when the **last** task completes (L3); `asleep` crossfades in slowly once the day is finished |
| Hub entry (≈810, `idle`) | static | Static |

### 7.5 Task details / options (`lib/components/edit_task_sheet.dart`, `task_card.dart` options menu, `reschedule_task_sheet.dart`)

- No Noya is added. Task details are a precision tool, so Noya stays out.
- The task-card Noya (`NoyaCompanionView.fromTask`, 40 px) remains static. On completion it plays `taskDone` (crossfade to `proud` + hop scaled to 40 px). No idle loops in lists.
- Reschedule success: the moved row's highlight pulse at its new position (§8.6).

### 7.6 Quest / Focus (resolved, D8)

The focus-session experience is **`FocusRitualScreen`** (`lib/screens/focus_ritual_screen.dart`) [VERIFIED]. It is launched from Flow Hub's "Focus with Noya" (`flow_screen.dart:380`) and driven by `FlowCompanionAnimationController`. Daily Quests are Flow Hub's Quests tab (`_buildQuestsTab`, `flow_screen.dart:780`); claiming a quest reward (`flow.claimDailyQuest`, `flow_screen.dart:139`) triggers a `taskDone`-style hop on the Flow Hub Noya. `WhatShouldIDoScreen` is the task-start decision screen and is **not** the Quest experience.

| Controller call [VERIFIED] | Today | Proposed |
|---|---|---|
| `setStarting` (234) | `encouraging` static | `enter` + greet-lite |
| `setFocusing` (267) | `focusing` + ±4% pulse forever | `focusing` + bounded typing bob (§6.8) |
| `triggerMilestone(25)` (306) | status text only | Quiet `taskDone`-style hop without pose change (no interruption of focus), haptic `selection` |
| `triggerSuccess` (396) | `celebrating` static | `celebrate` (L3) |

### 7.7 Flow Hub (`lib/screens/flow_screen.dart`)

- Framed `FlowCompanionView` (156 px) with paw badge [VERIFIED S5] is kept as-is (identity).
- `greet` once per session on entry. Tap → small hop + crossfade to `encouraging` and back (rate-limited).
- Evolution ready: the existing gold badge gets a slow opacity pulse (0.7 ↔ 1.0, 2,400 ms, bounded to 10 s).
- Level-up/evolution → `celebrate`.
- Auth-required: `recover` + friendly prompt (Part B §B6).

### 7.8 Questionnaire / onboarding (`onboarding_flow_screen.dart`, `routine_building_view.dart`)

- Building step: keep the pacing motion (re-expressed via `NoyaMotionView` and tokens) but replace the **instant** `thinking → idle → encouraging` timer-driven pose cuts (lines 200–207) with crossfades.
- Completion of onboarding (the "starting rhythm" card): `greet` (the brief's "after onboarding: waving"). Today this shows `proud` (line 432, static).

### 7.9 Auth & splash (`auth_screen.dart:441`, `splash_screen.dart:158`)

- **Splash:** today a repeating scale pulse 0.92 ↔ 1.04 over 1,800 ms [VERIFIED]. Proposed: a single `enter` (420 ms) then rest. Splash is short; a pulsing mascot reads as "loading game".
- **Auth screen:** `enter` + `greet` once on first open. Sign-in failure → `recover`. The error text remains the message.

---

## 8. UI micro-interactions

All are Level 1 or 2, use existing tokens, and keep the resting appearance identical.

| # | Interaction | Today [VERIFIED] | Proposed |
|---|---|---|---|
| 8.1 | Press feedback | `FlowPressScale` (0.97, 150 ms) exists but is used in only 2 files | Apply to tappable rows, chips and primary/secondary buttons that lack ink feedback. One press language: scale 0.97 **or** ink, never both on the same element |
| 8.2 | Task completion check | Instant swap to the completed style | Check circle fills (150 ms, `easeOutCubic`); title strike-through draws left→right (220 ms); row color settles to muted over 220 ms; in Calendar the row height eases to the completed height via `AnimatedSize` (220 ms) |
| 8.3 | Date chip selection | Instant fill swap (`calendar_tab.dart:130`) | `AnimatedContainer` fill/border 150 ms; selected chip auto-scrolls into view (`Scrollable.ensureVisible`, 280 ms). No `ScrollController` exists today [VERIFIED] |
| 8.4 | Date change content | Content replaced (spinner if no cache) | Direction-aware slide+fade: forward date → incoming from +16 px x; backward from −16 px; 220 ms |
| 8.5 | Row insert/remove | Instant | Insert: fade + `SizeTransition` 220 ms. Remove: fade 150 ms then collapse 180 ms |
| 8.6 | "What changed" highlight | None | Rows inserted/moved by Build My Day, Replan or Reschedule: background tint at accent 12% fading to 0 over 1,200 ms, once |
| 8.7 | NOW marker (Calendar S3; Today `timeline_current_time_marker.dart`) | Static dot | Dot opacity pulse 1.0 ↔ 0.55, 2,400 ms, only on Today's date, bounded to 3 cycles after screen view, then static |
| 8.8 | Sheets | Flutter default bottom sheet | Unchanged (already consistent) |
| 8.9 | Mode switches inside sheets (input → loading → preview) | `AnimatedSwitcher` used in places | Standardize on `FlowMotion.switcher` preset: 220 ms fade + 8 px rise for incoming |
| 8.10 | Loading skeletons | One `AnimationController` **per** `FlowShimmerBox` [VERIFIED `skeleton_loaders.dart:36`] | Shared shimmer driver (one controller per skeleton group) |

---

## 9. Motion hierarchy

| Level | Purpose | Examples | Budget |
|---|---|---|---|
| **L1 Micro** | Acknowledge input; ambient life | Press scale, chip fill, check fill, breath, NOW pulse, recover settle | ≤ 220 ms per interaction; loops ≤ 1.5% scale / ≤ 0.01·s travel; bounded |
| **L2 Contextual** | Communicate a state change | Greet, pose change, thinking/pacing, taskDone, planReady, date slide, plan reveal, highlight pulse | 220–1,700 ms; at most **one L2 Noya reaction on screen at a time** |
| **L3 Hero** | Mark a meaningful milestone | Celebrate (last task of day, focus session complete, level-up/evolution) | ≤ 3,100 ms including hold; **max 3 per day**; never two in a row within 60 s |

---

## 10. Animation timing system

Existing tokens are kept. New tokens are added to `FlowMotion` [PROPOSED].

| Token | Value | Status | Use |
|---|---|---|---|
| `instant` | 100 ms | new | Press-down, toggle thumb |
| `microDuration` | 150 ms | **existing** | Press release, chip fill, check fill |
| `standardDuration` | 220 ms | **existing** | In-place state changes, row insert, date slide, size changes |
| `screenDuration` | 280 ms | **existing** | Route transitions, ensure-visible scroll |
| `onboardingDuration` | 340 ms | **existing** | Onboarding pages |
| `posePivot` | 260 ms | new | Noya pose crossfade |
| `characterEnter` | 420 ms | new | Noya entrance |
| `characterExit` | 200 ms | new | Noya exit |
| `reaction` | 700 ms | new | Sway/hop portion of greet, taskDone, planReady |
| `celebration` | 1,600 ms | new | Celebrate hops |
| `highlightFade` | 1,200 ms | new | "What changed" tint |
| `breathPeriod` | 3,800 ms | new | Idle loop period |
| `thinkPeriod` | 2,600 ms | new | Thinking loop |
| `pacePeriod` | 4,000 ms | new (matches existing pacing) | Pacing loop |
| `focusPeriod` | 5,200 ms | new | Focus bob |
| `windDownPeriod` | 6,000 ms | new | Wind-down/asleep breath |
| `idleWindow` | 30 s | new | How long a loop runs before resting |

The 61 hard-coded `Duration(milliseconds: …)` literals in `lib/` (most common: 450, 150, 250, 200, 320, 220, 180 [VERIFIED]) migrate to these tokens **only when the file is touched for this work**. No sweeping refactor.

---

## 11. Easing / movement principles

**Curves**

| Token | Curve | Status | Use |
|---|---|---|---|
| `easeOut` | `Curves.easeOutCubic` | existing | Entrances, UI state changes |
| `easeInOut` | `Curves.easeInOutCubic` | existing | Crossfades, settle |
| `exit` | `Curves.easeInCubic` | new | Exits only |
| `emphasized` | `Cubic(0.2, 0.0, 0.0, 1.0)` | new | Character entrance |
| `loop` | `Curves.easeInOutSine` | new | All breathing/bob loops (no velocity spikes at the ends) |

**Springs** (`SpringDescription`, mass 1) [PROPOSED]

| Token | Stiffness | Damping | ζ (approx.) | Overshoot | Use |
|---|---|---|---|---|---|
| `settleSpring` | 420 | 41 | 1.0 | 0% | UI elements that must not bounce |
| `reactionSpring` | 420 | 30 | 0.73 | ≈3.5% | Greet sway, taskDone hop, planReady scale |
| `celebrationSpring` | 420 | 22 | 0.55 | ≈12% | Celebrate only |

**Amplitude limits** (`s` = rendered Noya size)

| Motion | Max translate | Max scale delta | Max rotation |
|---|---|---|---|
| Breath | 0.006·s | 1.2% | 0° |
| Think | 0.008·s | 0% | 2° |
| Pace | 0.08·s horizontal, 0.025·s vertical | 0% | 0° |
| Greet | 0.03·s | 0% | 4° |
| TaskDone / planReady | 0.06·s | 4% | 0° |
| Celebrate | 0.12·s | 4% (squash) | 0° |
| UI rows / content | 16 px | 3% | 0° |

**Rules**

- Everything Noya does pivots at bottom-center (her ground). Nothing spins or flips.
- Squash and stretch preserves volume (scaleX ≈ 1 / scaleY) and is ≤ 4%.
- No bounce on UI chrome (rows, chips, buttons, sheets). Bounce belongs to the character only.
- Opacity transitions never pass through a fully blank frame for Noya: crossfades overlap.

---

## 12. Loading and AI-processing motion

One escalation ladder for every async wait [PROPOSED]. Times are measured from the request start.

| Elapsed | Visual | Noya |
|---|---|---|
| 0–300 ms | Nothing new (avoid flash) | — |
| 300 ms – 1 s | Inline progress where the action was taken (button spinner, already present [VERIFIED `brain_dump_sheet.dart:1400`]); skeleton rows for content areas (Calendar) | — |
| > 1 s (AI/planning only) | Status line: what is happening, in one plain sentence | `thinking` |
| > 4 s | Same | `pacing` |
| > 12 s | Reassurance status line, announced via `liveRegion` | `pacing` continues |
| Success | Result reveal | `planReady` |
| Failure / fallback | Clear message + action (Retry / Sign in) | `recover` |

**Calendar day load:** a skeleton of 3 timeline rows matching the row geometry (Part B §B2) replaces `CircularProgressIndicator` (`calendar_tab.dart:241–247`). There is no Noya, because day loads are short and structure communicates better.

**Not allowed:**

- spinners alone in large empty areas (S2)
- fake numbered steps for single requests
- Noya animation as the *only* loading indication

---

## 13. Completion and celebration motion

| Event | Level | Motion |
|---|---|---|
| Single task completed | L1 UI + L2 Noya | Check fill + strike + `taskDone` on the nearest Noya + haptic success |
| Several tasks completed within 1.5 s | L1 + one L2 | Coalesced: one `taskDone` |
| Last pending task of the day completed | **L3** | `celebrate` on Today's completion card (or the header pill if the card isn't mounted) |
| Focus session completed | **L3** | `celebrate` on the focus screen |
| 25-minute focus milestone | L1 | Quiet hop, no pose change |
| Plan confirmed | L2 UI | Highlight pulse on the new rows; no celebration |
| Level-up / evolution / companion unlock | **L3** | `celebrate` on Flow Hub |
| Streak shield activated (`flow_provider.dart:367`) | L2 | `taskDone`-style hop |

Caps: §9 (max 3 L3 per day; extra ones downgrade to L2).

---

## 14. Motion transitions

| Transition | Today [VERIFIED] | Proposed |
|---|---|---|
| Tab switch | `FlowFadeIndexedStack` crossfade 240 ms, keeps state | **Keep** |
| Hierarchical push | `FlowPageRoute.fadeUp` 280 ms | **Keep**, and use it wherever `MaterialPageRoute` is still used for forward navigation (audit when files are touched) |
| Same-level / calm | `FlowPageRoute.fade` 220 ms | Keep |
| Sign in ↔ sign up | `sharedAxisHorizontal` 250 ms | Keep |
| Calendar date change | Content replaced | Direction-aware slide (§8.4) |
| Brain dump input → loading → preview | Mixed | `FlowMotion.switcher` preset (§8.9) |
| Task row → Focus screen | Route push | **Optional P2:** `Hero` shared element on Noya (task-row 40 px → focus 130 px), [UNCERTAIN] it needs both endpoints to render the same `NoyaState` at flight start; verify visually before committing |
| Return to an already-viewed screen | No entrance replay (existing rule in `flow_motion.dart` doc) | **Keep.** `greet` rate limits (§5.3) follow the same rule |

---

## 15. Asset requirements

Nothing here exists. Each item is optional. The system in §6 works without them and upgrades when they arrive.

| ID | Asset | Why it materially improves motion | Priority |
|---|---|---|---|
| A1 | **Blink frame**: `noya_default` with eyes closed, identical canvas/framing | Enables a real blink every 4–8 s during the idle window; the strongest "alive" cue for the least motion | P1 |
| A2 | **Wave frames**: 3 frames of the encouraging paw (low / mid / high) | Real wave instead of body sway | P2 |
| A3 | **Walk cycle**: 6–8 frame side-view sprite sheet | Real walking for long loads and transitions | P2 |
| A4 | **Exercise pose**: stretching or holding a small dumbbell | Correct gym/physical-task pose (today waving is used) | P1 |
| A5 | **Reassuring pose**: soft smile, paw on chest | Calm error/recovery state | P2 |
| A6 | **Art fixes**: `noya_proud` single tail + canonical collar; `noya_sleepy` canonical collar | Identity consistency during crossfades | P1 |
| A7 | **Layered source** (body / head / eyes / arm / tail) or Rive rig | Unlocks blink, tail sway, head turns without new frames | P3 (only if the team commits to Rive, §16) |

**Production constraints for any new frame:**

- 1024×1024 transparent PNG with the **same canvas, scale, baseline and bottom-center anchor** as `noya_default.png`
- the same flat cel style (not the 3D style of `winking_fox.png`)
- the canonical navy collar with gold star medallion
- sparkles and symbols on a separate layer or omitted

---

## 16. Flutter implementation architecture

### 16.1 Options compared against the repository

| Option | Fit | Verdict |
|---|---|---|
| `AnimationController` + transforms (explicit) | Already used for pacing, splash, ambient, focus [VERIFIED] | **Use** for loops and reactions |
| Implicit animations (`AnimatedSwitcher`, `AnimatedContainer`, `AnimatedSize`, `AnimatedScale`) | Already used [VERIFIED] | **Use** for pose crossfade and all UI micro-interactions |
| Physics springs (`SpringSimulation` via `controller.animateWith`) | Flutter SDK, no dependency | **Use** for reactions |
| Rive | No assets, no rig, no dependency; would need A7 | **Not now.** Revisit only if A7 is commissioned |
| Lottie | No assets; Noya is raster art, which converts poorly | **Reject** |
| Sprite/frame animation | No frames exist | **Later**, for A1–A3 frames via a tiny frame-stepper (no package) |
| `CustomPainter` | Used for the ambient background and the vector fallback | Not for Noya (raster art) |
| `Hero` | SDK | Optional P2 (§14) |

**No new dependency is recommended.**

### 16.2 Components [PROPOSED]

1. **`NoyaState`** (existing enum, `noya_companion_view.dart`): add `delighted` (`noya_success.png`) and `windDown` (`noya_sleeping.png`). The asset paths reference the files where they already are, so no asset moves. Decision D2.
2. **`NoyaCompanionView`** (existing, stays stateless): add `cacheWidth` = `(size × devicePixelRatio).round()` to its `Image.asset` calls. Today it decodes 1024×1024 even for a 28 px pill [VERIFIED]. Its public API is unchanged, so `test/noya_visual_system_test.dart` still holds.
3. **`NoyaMotionView`** (new, `lib/components/noya_motion_view.dart`): a `StatefulWidget` that renders `NoyaCompanionView` inside an `AnimatedSwitcher` (pose crossfade) and a single `Transform` driven by:
   - one loop `AnimationController` (mood loop, bounded by `idleWindow`)
   - one reaction `AnimationController` (spring/keyframes)

   Inputs: `mood`/`state`, `size`, `enter`, `reactions` (a listenable), `semanticLabel`, `onTap`. Screens replace `NoyaCompanionView` with `NoyaMotionView` **only where motion is specified in §7**; list items keep the static view.
4. **`FlowCompanionAnimationController`** (existing): add a `react(NoyaReaction r)` method that emits one-shot events (an incrementing id + type) **without** changing `state`, so existing listeners and tests are unaffected. Add `NoyaReaction` (enum: `greet`, `taskDone`, `planReady`, `celebrate`, `recover`). It owns the priority, coalescing and rate-limit rules of §5.3 in one place.
5. **Mapping:** `CompanionAnimState → NoyaState` stays in `NoyaCompanionView.fromAnimState` (existing). `FlowCompanionView` (used by Focus and Flow Hub) renders `CompanionGraphic → NoyaCompanionView`. It switches to `NoyaMotionView` internally and **drops its own `_pulseController`**, which today repeats in every state but is only used while focusing [VERIFIED `flow_companion_view.dart:70–76, 148`].
6. **Triggers:**
   - `AppStateProvider.toggleTaskCompletion` already calls `onTaskCompletedForFlow` [VERIFIED]; the `MainShell` wiring adds `flow.animController.react(taskDone | celebrate)` there.
   - Brain dump / Replan sheets call `react(planReady | recover)` on their local or provider controller.

   No new provider, no new global singleton.
7. **`FlowMotion`** (existing): new tokens (§10, §11), a `switcher(...)` preset, and a `MotionScope`-style override (an `InheritedWidget`) so widget tests can disable loops explicitly. This replaces the brittle `WidgetsBinding.instance.runtimeType.toString().contains('Test')` checks in `flow_companion_view.dart:65` and `flow_ambient_background.dart:47` [VERIFIED]. Tests need loops off because `pumpAndSettle` never settles on an unbounded `repeat()`.
8. **Shared shimmer:** `skeleton_loaders.dart` gets one controller per skeleton group instead of one per box.

### 16.3 Data flow

```
AppStateProvider.toggleTaskCompletion ─► onTaskCompletedForFlow (MainShell) ─► flow.animController.react(taskDone|celebrate)
Brain dump / Replan request lifecycle ─► local mood (thinking → pacing) ─► react(planReady | recover)
FlowProvider overview / sessions       ─► animController.setFocusing / setIdle / triggerSuccess  (existing)
FlowClock + day state                   ─► mood windDown / asleep
                                             │
                                             ▼
                              NoyaMotionView (listens; resolves pose + loop + reaction)
                                             │
                                             ▼
                              NoyaCompanionView (static render, unchanged contract)
```

---

## 17. Performance requirements

| # | Requirement | Basis |
|---|---|---|
| P1 | Loops run only while: the widget is visible (`TickerMode` enabled; `FlowFadeIndexedStack` already disables tickers for hidden tabs [VERIFIED]), the app is resumed, reduced motion is off, and `s ≥ 48 px` | Battery |
| P2 | Every loop is **bounded** (`idleWindow` 30 s; focus bob 20 s; NOW pulse 3 cycles) | Battery; also lets `pumpAndSettle` settle |
| P3 | **At most one Noya loop** active per visible screen; list-item Noyas never loop | GPU / rebuilds |
| P4 | `NoyaMotionView` animates via `Transform`/`FadeTransition` driven by `AnimatedBuilder` scoped to the Noya subtree; **no `setState` per frame**; the Noya subtree is wrapped in `RepaintBoundary` | Rebuild frequency |
| P5 | Decode at display size: `cacheWidth = size × DPR`. At 156 dp × 3.0 DPR that is 468 px wide, ≈ 0.9 MB decoded per pose versus **4 MB** at 1024² | Memory |
| P6 | Precache only the poses reachable from the current screen (e.g. Build My Day: idle, encouraging, thinking, success, proud) on screen init, at display size | No blank frame on pose change |
| P7 | All controllers are created in `initState` and disposed in `dispose`; reaction controllers stop before dispose; `Future.delayed` callbacks check `mounted` (the pattern already exists in `FlowFadeSlide` [VERIFIED]) | Leaks |
| P8 | **Ambient background:** `FlowAmbientBackground` repeats a 16 s loop forever behind every tab in `MainShell` and repaints three radial gradients each frame [VERIFIED `flow_ambient_background.dart:57`, `main_shell.dart:82`]. The app has **no `RepaintBoundary` anywhere** [VERIFIED]. Proposed: (a) wrap the painter in a `RepaintBoundary` so it can't dirty tab content; (b) [UNCERTAIN, measure first] if profiling on a low-end Android device shows sustained raster cost, run the drift for 20 s after a tab becomes visible, then hold the frame. The paused frame looks identical, so this passes the paused test. | Battery / jank |
| P9 | Target: no frame over 16 ms in the profile build on a low-end reference Android device (decision D9 picks the device) during greet, celebrate and plan reveal; idle screens show 0 animating tickers after `idleWindow` (verify with the Flutter DevTools performance overlay) | Measurable acceptance |
| P10 | Celebrate glow uses an existing gradient with alpha animation; no `BackdropFilter`, no blur `MaskFilter`, no particles | GPU |

---

## 18. Accessibility / reduced motion

**Source of truth:** `MediaQuery.disableAnimations` via `FlowMotion.isReducedMotion` (existing [VERIFIED]).

| Motion | Reduced-motion behavior |
|---|---|
| Loops (breath, think, pace, focus, NOW pulse, shimmer) | Off; static rest frame (shimmer → static placeholder tone) |
| Pose changes | 120 ms opacity crossfade (state stays legible) |
| Enter / exit | 150 ms fade / instant |
| Greet, taskDone, planReady, celebrate | Pose crossfade + hold only; no translate/scale/rotate; haptics kept |
| Date change, row insert/remove | Instant, or ≤ 150 ms fade |
| Highlight pulse | Static tint for 1,200 ms, then removed (fade ≤ 150 ms) |
| Route transitions | Existing behavior (instant) |

**Semantics**

- `NoyaCompanionView` already provides a per-state `semanticLabel` [VERIFIED].
- `NoyaMotionView` must not duplicate semantics during crossfades: exclude the outgoing child (`ExcludeSemantics`).
- State changes that matter (planning started, plan ready, failure) are announced via the **status text** with `Semantics(liveRegion: true)`, not via Noya. Idle loops and reactions are never announced.
- Noya with `onTap` keeps `button: true` (existing) and a minimum 48×48 hit area (`FlowSpacing.minTouchTarget` [VERIFIED]).

**No meaning by motion alone:** every Noya state has an accompanying text or UI state (status line, check mark, badge).

---

## 19. Reusable motion components

| Component | Status | Purpose | Inputs | States | Used by |
|---|---|---|---|---|---|
| `FlowMotion` | existing, extended | Tokens, curves, springs, switcher preset, reduced-motion helpers, test scope | — | — | Everything |
| `NoyaState` | existing, +2 values | Pose catalog | — | 7 → 9 | All Noya |
| `NoyaCompanionView` | existing, `cacheWidth` added | Static pose render, semantics, fallback | state, size, glow, onTap | — | Lists, small pills, inside `NoyaMotionView` |
| `NoyaMotionView` | **new** | Animated Noya: enter/exit, crossfade, mood loop, reactions | mood/state, size, enter, reactions listenable, onTap, semanticLabel | rest, thinking, pacing, focusing, windDown, asleep + reactions | Today card, Build My Day, Plan Result, Calendar empty, Focus, Flow Hub, onboarding, auth, splash |
| `NoyaReaction` + `FlowCompanionAnimationController.react()` | **new** on existing controller | One-shot reaction bus with priority/coalescing/rate limits | reaction | — | Providers, sheets |
| `FlowPressScale` | existing | Press feedback | child, onTap | pressed | Rows, chips, buttons |
| `FlowCompletionCheck` | **new** | Animated check + strike timing | completed, onChanged | idle/pressed/completed | Calendar rows, `TimelineItemWidget`, `TaskCard`, `RightNowTaskCard` |
| `FlowHighlightPulse` | **new** | One-shot "what changed" tint | trigger key | idle/pulsing | Calendar, Today after plan/replan/reschedule |
| Shared shimmer (`FlowShimmerBox` group) | existing, refactored | Skeleton loading | — | — | Today, Tasks, **Calendar (new)** |
| `FlowFadeSlide` | existing | One-time entrance | delay | — | Plan reveal stagger |

---

# PART B — UI REFINEMENT (evidence-backed, identity-preserving)

Each item uses **CURRENT → PROBLEM → PROPOSED → WHY → SCOPE → ACCEPTANCE**.

**Preserved everywhere:**

- Plus Jakarta Sans and the `FlowTypography` scale
- the slate neutral palette
- the user-selectable accent (`FlowAccent`)
- the Noya art
- the ambient background
- the bottom navigation
- the overall single-column composition

## B1. Container & surface refinement (P0)

**B1.1 Radius ladder**

- **CURRENT:** `FlowRadii` defines card 24, cardLarge 28, hero 30, button 18, input 18, chip 14, badge 8, pill [VERIFIED]. There are also **79 literal `BorderRadius.circular(n)`** calls with 15 distinct values (most common: 14, 10, 8, 16, 2) [VERIFIED].
- **PROBLEM:** Every element, including small rows, nested boxes and the date chips (18), uses large radii. Nested 24-radius boxes inside 24-radius sheets (S6, S7) read as "card in card".
- **PROPOSED:** keep the tokens and apply them by hierarchy:
  - **24** for sheets and top-level cards only
  - **14** (`chip`) for rows, inner groups, date chips and inputs inside sheets
  - **8** (`badge`) for small indicators
  - **pill** only for filter chips and status dots

  Literal radii migrate to the nearest token **in touched files only**.
- **WHY:** a radius hierarchy communicates nesting; uniform large radii flatten it.
- **SCOPE:** Calendar, Build My Day sheet, Plan Result, `TaskCard`, `TimelineItemWidget`.
- **ACCEPTANCE:** in touched files, no literal `BorderRadius.circular(<number>)`; no element nested inside a 24-radius container uses radius 24.

**B1.2 Border + shadow + fill stacking**

- **CURRENT:** Calendar cards combine fill + 1 px border + shadow (`calendar_tab.dart:514–528`). `TaskCard` combines fill + border + shadow (`task_card.dart:35–51`). The focus-window card adds an accent border + shadow (S1). There are 37 `BoxShadow` uses [VERIFIED].
- **PROBLEM:** Three separation devices on one element. On the bright ambient background, every item floats, so nothing reads as primary (S3, S8).
- **PROPOSED:** one separation device per element:
  - sheets/dialogs: elevation (shadow)
  - top-level cards on the page: fill + hairline border, **no shadow**
  - rows inside a timeline/list: **no container**; spacing + rail/divider
  - the active (NOW) item alone gets a tinted fill
- **WHY:** reserving elevation for floating layers restores hierarchy without new styling.
- **SCOPE:** Calendar, Today timeline, `TaskCard`, Plan Result rows.
- **ACCEPTANCE:** no list/timeline row uses `BoxShadow`; within a screen, only floating layers and at most one hero card cast shadows.

**B1.3 Nested status boxes in Build My Day (S6)**

- **CURRENT:** above the input there are three bordered boxes: the Noya header card, the "✨ AI planning" box with loading pills and a 3-line paragraph, then the question.
- **PROBLEM:** The input, the screen's purpose, starts below the fold of the visible sheet area once the keyboard is open. The status pills show loading placeholders ("… Shields", "Checking…").
- **PROPOSED:**
  - The Noya header becomes unboxed (Noya + title + one line, on the sheet surface).
  - The AI/Shields status collapses into **one line** under the input ("AI planning · 2 Shields"). It is hidden until loaded, never showing placeholders, and an ⓘ opens the explanatory paragraph.
  - Keep "What else is on your plate?" as the dominant heading.
- **WHY:** the brief's hierarchy is Noya → question → input → one action.
- **SCOPE:** `brain_dump_sheet.dart` (`_buildNoyaHeader`, `_buildAiAndShieldsBanner`).
- **ACCEPTANCE:**
  - with the keyboard open on a 360×640 dp device, the input field's top edge is within the visible sheet area
  - no "…"/"Checking…" placeholder text is ever visible
  - exactly one filled primary button

**B1.4 Plan Result rows (S7)**

- **CURRENT:** each task is a ~190 px card containing:
  - title
  - "Physical · Estimated 60 min"
  - italic "Priority not specified"
  - "4:00 PM · Fixed time"
  - "Scheduled: Today · 4:00 PM [Fixed]"
  - a boxed "Why:" line
- **PROBLEM:** Time appears twice, an unknown priority is displayed, the explanation is boxed inside the card, and the time does not lead.
- **PROPOSED:**
  - Use the Calendar row anatomy (B2.4): time gutter (4:00 PM), title, one meta line (60 min · Physical), and a Fixed indicator when fixed.
  - "Why" becomes a single muted line shown on tap/expand (`AnimatedSize`), not a box.
  - Hide priority when not specified. "Edit" stays as a trailing icon button (48 px target).
- **WHY:** the plan should read as a schedule, not as records.
- **SCOPE:** `brain_dump_sheet.dart` preview, `ai_plan_preview_sheet.dart`, `parsed_plan_confirm_sheet.dart`.
- **ACCEPTANCE:**
  - each time appears once per row
  - "Priority not specified" never renders
  - a default row (one-line title, collapsed) is ≤ 72 dp tall at 1.0 text scale
  - the primary action remains a single filled button

## B2. Calendar refinement (P0)

Calendar has **no external calendar events**. `ScheduleItem` has no event/source concept and `CalendarService` only fetches Flowstate's day schedule [VERIFIED]. "Events vs tasks" therefore maps to **fixed** (time-locked commitments: `isFixed`) versus **flexible** (placed by Flowstate).

**Step 0 (blocking):** diagnose the S3/S7 fixed-state mismatch (§3) before restyling the indicators.

**B2.1 Date strip**

- **CURRENT:** 14 chips from yesterday to +12 days, labelled "Yest / Today / Tmrw / Sun…" over the day number, 54 px wide, radius 18. Selected = filled accent [VERIFIED S1–S3, `calendar_tab.dart:83–157`].
- **PROBLEM:**
  - No month anywhere on screen.
  - Relative labels replace weekdays, so "Today 2" never says Friday or October.
  - When another day is selected, **Today is visually indistinguishable** from other days (S2).
  - The strip does not scroll the selected chip into view (no controller).
- **PROPOSED:**
  - The header subtitle ("Energy-aligned schedule & focus blocks") is replaced by the **selected date**, e.g. "Friday, October 2", which updates with selection.
  - Chips show the **weekday abbreviation** (Thu / Fri / Sat) over a **larger day number** (`titleSmall`, w700, tabular figures).
  - Today gets a small accent dot under the number in every selection state.
  - Selected stays a filled accent.
  - A month abbreviation appears above the first chip of a new month.
  - The selected chip auto-scrolls into view.
  - Chip radius 14, width sized so 6 full chips fit at 360 dp.
  - **Preserved:** chip keys (`calendar_day_chip_today/_yesterday/_tomorrow/_yyyy-MM-dd`), `Semantics(selected:)` with labels ("Today October 2"), haptic `selection`, and `state.loadCalendarDay(day)` [VERIFIED].
- **WHY:** a real date and a persistent Today marker are basic calendar affordances.
- **SCOPE:** `calendar_tab.dart` (extract as `FlowDateStrip`).
- **ACCEPTANCE:**
  - the full selected date is visible at all times
  - Today is identifiable whether or not it is selected
  - the selected chip is fully visible after selection
  - chip keys and semantics are unchanged (existing tests keep passing)

**B2.2 Action hierarchy**

- **CURRENT:** a full-width filled "✨ Replan My Day" button + 11.5 px caption sits above the Focus Window card on every day, including empty days, where a second filled "Build My Day" button also appears (S1).
- **PROBLEM:**
  - Two primary actions on an empty day.
  - Replan is the most prominent element even when there is nothing to replan.
  - "✨" emoji plus a sparkle icon are doubled (visible in S1–S3).
- **PROPOSED:**
  - Replan becomes a compact **tonal** button in the header row (right-aligned, icon + "Replan"), shown only when the day has scheduled items (decision D4 confirms empty-day Replan has no use).
  - The caption moves into the Replan sheet.
  - Remove the "✨" emoji; keep the `auto_awesome` icon.
- **WHY:** one primary action per state; the timeline becomes the main structure.
- **SCOPE:** `calendar_tab.dart`.
- **ACCEPTANCE:**
  - at most one filled primary button per Calendar state
  - the first timeline row's top edge sits within the top 45% of the viewport on a 360×640 dp device with one focus window

**B2.3 Focus window**

- **CURRENT:** a full card with accent border, shadow and a 44 px icon box (S1–S3).
- **PROBLEM:** It occupies ~2 timeline rows of height to convey one time range.
- **PROPOSED:**
  - A single compact line above the timeline: bolt icon (16 px, accent) + "Focus window 8:30–11:30 AM" (`bodyMedium`).
  - Timeline rows starting inside the window show an accent-tinted rail segment.
- **WHY:** the focus window is context for the timeline, not a peer card.
- **SCOPE:** `calendar_tab.dart`.
- **ACCEPTANCE:** the focus-window element is ≤ 32 dp tall; its range text is unchanged.

**B2.4 Timeline rows**

- **CURRENT:** each item is a bordered card (~4 lines):
  - time + an ALL-CAPS emoji badge (`● DO THIS NOW`, `✦ FLOWSTATE`, `🔒 FIXED`, `⚠ CONFLICT`, `MISSED`, `SUGGESTED`)
  - title
  - "45 min · High Focus"
  - a reason line on every item

  Default items carry a "✦ FLOWSTATE / Scheduled by Flowstate" badge [VERIFIED S3, `calendar_tab.dart:378–609`]. Calendar renders its own private cards, while Today uses `TimelineItemWidget` [VERIFIED]: two competing timeline components.
- **PROBLEM:**
  - Two items fill ~40% of the viewport (S3).
  - The default state carries a badge and an explanation that convey nothing actionable.
  - Emoji glyphs mix with Material icons.
  - Time does not align on a shared axis.
- **PROPOSED** (one shared `FlowTimelineRow`, evolved from `TimelineItemWidget`, used by both Calendar and Today):

```
 9:30 AM  ●─  Write chapter outline                       ⋯
   60 min │   60 min · Deep work
          │
11:00 AM  ●─  Dentist appointment            🔒 Fixed
          │   45 min
          │
▸ 2:15 PM ◉━  Study arrays                               (NOW: tinted surface, accent rail,
          ┃   45 min · Deep work                           reason line shown)
          ┃   Peak focus window
```

  - **Left gutter (fixed width ≈ 64 dp, scales with text):** start time `titleSmall` w700 tabular figures, period `labelSmall` muted, duration muted below.
  - **Rail:** 2 px, `divider` color. The node dot takes the state color (default = accent, fixed = `textSecondary`, conflict = error, missed = warning, completed = filled check).
  - **Content:** title `bodyLarge` w600 (max 2 lines), one meta line `bodySmall` muted, then **at most one** state indicator: icon + sentence-case label, no emoji and no ALL CAPS ("Fixed", "Conflict", "Missed", "Suggested", "Unscheduled").
  - **Default (flexible, placed by Flowstate):** no badge and no reason line.
  - **Reason/explanation:** shown only for NOW, conflict, missed and suggested (actionable states).
  - **Containers:** none for default rows; the NOW row only gets accent 6% fill + radius 14.
  - **Completed:** muted title with strike-through, the node becomes a check, no "✓ Done" pill.
  - **Unscheduled:** a "Couldn't fit" section below the timeline in the same row anatomy without a time gutter, using `warningOf(context)` instead of `Colors.orange`.
- **WHY:** time on a shared axis plus one indicator per row lets users scan the day in about 2 seconds, which is the brief's target. A single component removes the Calendar/Today divergence.
- **SCOPE:** `calendar_tab.dart`, `timeline_item_widget.dart`, `today_dashboard_tab.dart` timeline section.
- **ACCEPTANCE:**
  - a default row with a one-line title is ≤ 72 dp tall at 1.0 text scale
  - start times are left-aligned on one vertical axis
  - default rows show no badge
  - no emoji glyph in state indicators; no ALL-CAPS state labels
  - each state (default, fixed, conflict, missed, suggested, completed, NOW, unscheduled) is distinguishable in grayscale (icon/shape, not color alone)
  - Calendar and Today render rows from the same component
- **TEST IMPACT [VERIFIED]:** `test/calendar_date_navigation_test.dart` asserts the exact current strings (`'✦ FLOWSTATE'`, `'🔒 FIXED'`, `'● DO THIS NOW'`, `'⚠ CONFLICT'`, `'UNSCHEDULED'`, `'✓ Done'`, `'NOW'`, `'8:00 AM · 20 min · Completed'`, reason strings). These tests must be **updated in the same change with equal-strength assertions**: one assertion per state, via stable `Key('timeline_state_<state>_<id>')` + label text + `Semantics` label. They must not be deleted or loosened. Decision D1.

**B2.5 Loading and empty states**

- **CURRENT:** spinner (S2); the empty state is a bordered card with a generic icon + filled button (S1).
- **PROPOSED:**
  - Loading: 3 skeleton rows in the B2.4 geometry.
  - Empty: unboxed, with Noya (§7.1), "No plan for Friday yet." (string kept: test-asserted), one line of copy, and one filled "Build My Day" button (kept: test-asserted).
- **ACCEPTANCE:** no `CircularProgressIndicator` in Calendar content; exactly one filled button in the empty state.

**B2.6 Noya in Calendar:** §7.1 (empty state only by default; NOW-marker Noya optional, D6).

**B2.7 Readability across sizes**

- Gutter width and row height derive from text metrics, not fixed pixels.
- At text scale 1.3 the title wraps to 2 lines, then ellipsizes; the time gutter grows instead of truncating.
- The date strip stays horizontally scrollable at all widths.

## B3. Dark mode (P0) — code-derived; visual impact [UNCERTAIN] until captured

Strengths to keep [VERIFIED]:

- not pure black (bg `#0B0F17`)
- a clear surface ladder (`#131B2A` → `#1A2436` → `#223046`)
- accent dark variants (Sky/Emerald/Blue/Amber/Rose-400)
- semantic dark variants via `successOf/warningOf/errorOf`

| # | CURRENT [VERIFIED] | PROBLEM | PROPOSED | ACCEPTANCE |
|---|---|---|---|---|
| B3.1 | `textSecondaryDark = #E2E8F0` vs `textPrimaryDark = #F8FAFC` | Primary and secondary text are nearly identical, so hierarchy collapses in dark | `textSecondaryDark = #CBD5E1` (Slate 300; ≈ 11:1 on `surfaceDark`); muted stays `#94A3B8` | Primary, secondary and muted text are distinguishable side by side; all ≥ 4.5:1 on `surfaceDark` |
| B3.2 | **55** uses of light-only static constants (`FlowColors.textPrimary`, `textSecondary`, `textMuted`, `darkBackground`…) outside `theme/`, e.g. `compact_readiness_card.dart` (11), `break_session_card.dart` (10), `task_inbox_tab.dart` (4) | Dark slate text on dark surfaces | Replace with the `…Of(context)` accessors in touched files; mark the light-only aliases `@Deprecated` | No light-only text constant renders on a dark surface (manual sweep §22) |
| B3.3 | Tag colors (`tagDeepWorkBg #F0F9FF`, `tagPhysicalBg #F7FEE7`…) are light-only, used by `ScheduleItem.tagBg` (rendered at `today_dashboard_tab.dart:1474`), `task_difficulty_badge.dart`, `readiness_hero_card.dart`, `scheduling_engine.dart` | Pale pills glare on dark surfaces | Derive tag backgrounds at render time: accent at 12% (light) / 18% (dark) over the surface; text uses the accent's dark variant | No near-white pill backgrounds in dark mode |
| B3.4 | `Colors.orange` (14 uses), `Color(0xFFEF4444)` (conflict), `#F97316` Noya orange literal (12 uses) | Not theme-adapted; Noya orange is not a token | Use `warningOf` / `errorOf`; add `FlowColors.noyaWarm` (+ dark variant) for Noya glow/badge | Zero `Colors.orange` in touched files |
| B3.5 | `accentLimeDark = #65A30D` (identical to light) | Only accent not lifted for dark; dimmer than siblings | `#A3E635` (Lime-400), matching the other dark accents | All six dark accents use the -400 family |
| B3.6 | Shadows on dark (`softShadowDark` 16% black) | Shadows are invisible on dark, so cards rely on them for nothing | In dark, separation = surface step (`surface` → `surfaceElevated`) + border; shadows are kept only for sheets | Elevated items are distinguishable from the page in dark without shadow |
| B3.7 | Noya ambient glow alpha 0.18 regardless of theme (`noya_companion_view.dart:284`) | Possible halo on dark | 0.12 in dark | Visual check §22 |
| B3.8 | Noya PNG transparent pixels carry white RGB | Possible light fringe at small sizes on dark [UNCERTAIN] | Verify; if visible, re-export with premultiplied/dark-matte edges (asset task, approval needed) | No visible fringe at 28/40/76 px on `surfaceDark` |
| B3.9 | Backwards-compat aliases `darkBackground = bgLight`, `darkCard = surfaceLight` (`flow_colors.dart`) | Names say "dark" but values are light, a trap for future code | `@Deprecated` with a message; no new uses | `dart analyze` shows no new uses |

**Dark-mode hierarchy (target, using existing tokens):** background `bgDark` → cards `surfaceDark` → raised/selected/NOW `surfaceElevatedDark` → inputs/chips `surfaceContainerDark`; borders `borderDark`; dividers/rail `dividerDark`; text primary/secondary/muted per B3.1. Selected chips use the accent fill with `bgDark` text (existing `onPrimary`); disabled = 38% opacity of the enabled style.

## B4. Custom task colors (P1)

**Current state [VERIFIED]:**

- No color field exists on `TaskItem`, `ScheduleItem` or the backend `tasks` model (`backend/app/models/task.py`).
- `ScheduleItem.tagBg/tagColor` are derived from task type, not user-chosen.

**Storage decision (D3, blocking):**

- **Option A (recommended):**
  - a nullable `color_key` string column on `tasks`
  - API passthrough in the task schemas
  - an Alembic migration (would be 007)
  - It syncs across devices and appears in the Calendar/Today schedule payloads.
  - **This inherits the existing D4 production-schema blocker**: the repo does not show how the production `tasks` table is created (see `build-my-day-replan.md` §11.1).
- **Option B:** a local-only map (`SharedPreferences`: taskId → colorKey). No backend change, but no sync, and it is lost on reinstall.

**Palette** [PROPOSED]: a fixed set of keys, each with a light and dark value, reusing existing accent constants where they exist:

| Key | Light | Dark | Source |
|---|---|---|---|
| `default` | (type/accent color, as today) | — | existing behavior |
| `sky` | `#0284C7` | `#38BDF8` | existing `accentCyan` |
| `mint` | `#059669` | `#34D399` | existing |
| `blue` | `#2563EB` | `#60A5FA` | existing |
| `amber` | `#D97706` | `#FBBF24` | existing |
| `rose` | `#E11D48` | `#FB7185` | existing |
| `violet` | `#7C3AED` | `#A78BFA` | new |
| `lime` | `#65A30D` | `#A3E635` | existing light / B3.5 dark |
| `slate` | `#475569` | `#94A3B8` | existing text tokens |

- Custom (free-pick) colors are **P2**. If added, the stored hex is **auto-adjusted** in lightness to ≥ 3:1 against both `surfaceLight` and `surfaceDark` (WCAG 1.4.11 for non-text graphics).
- Text is never drawn in a custom color.

**Treatment rules:**

- A task color is an **identity accent**, applied to:
  - the timeline node dot
  - a 3 px leading accent bar on rows/cards
  - the leading icon tint
  - the NOW/active fill at 8% (light) / 14% (dark)

  It is never applied as a solid card fill, to title text, or to buttons.
- **System states own the state indicator.** Conflict/missed/error indicators keep semantic colors. Completed rows desaturate the task color to muted (40% opacity). Focus/NOW emphasis uses the accent fill above.

**Where it appears:**

- **Calendar & Today:** node + accent bar (B2.4).
- **Task inbox (`TaskCard`):** leading accent bar.
- **Task details (`edit_task_sheet.dart`):** a "Color" row with a horizontal swatch picker (Default first, which acts as reset). A live preview row at the top of the sheet updates as swatches are tapped and is applied on Save (the existing save flow).
- **Plan Result:** shows existing tasks' colors; new parsed tasks use Default.
- **Flow Hub:** none (P2: active focus task header accent).

**Accessibility:** swatches are 40 dp inside 48 dp targets; selected = check icon + ring (not color alone); each swatch has a `Semantics` label ("Rose", "Default color, selected").

**ACCEPTANCE:**

- set, change and reset work and persist per the chosen storage
- each color renders correctly in light and dark
- no text uses a task color
- conflict/missed/completed indicators look identical regardless of task color
- swatch labels are announced by TalkBack

## B5. Design tokens audit

| Area | Existing [VERIFIED] | Usage reality [VERIFIED] | Recommendation |
|---|---|---|---|
| Spacing | `FlowSpacing` 4/8/12/16/20/24/32, responsive `pageMargin` 20/24, `minTouchTarget` 48 | Calendar uses the page margin; many ad-hoc `SizedBox` values (6, 10, 14) | Snap to tokens in touched files |
| Radius | `FlowRadii` | 333 token uses, 79 literals | B1.1 |
| Typography | `FlowTypography` full scale | Frequent `copyWith(fontSize: 9.5–11.5)` overrides (e.g. calendar badges 10.5, captions 11.5, unscheduled 9.5) | No text below `labelSmall` 12.5 except tabular meta; remove sub-12 overrides in touched files |
| Colors | `FlowColors` light/dark + accessors | 213 `Color(0x…)` literals outside `theme/` | B3.2–B3.4; touched files only |
| Shadows | `softShadow(context)` | 37 `BoxShadow`s with mixed blur 4–18 | B1.2 |
| Motion | `FlowMotion` | **0 uses of `FlowMotion.*` constants outside its own file**; 61 duration literals | §10 |
| Density | `DensityMode` (comfortable/compact/minimal) persisted in `ThemeProvider` | **Selectable in Settings but consumed nowhere else** (only `profile_settings_tab.dart` reads it) | Decision D10: wire Compact to the B2.4 row spacing, or hide the setting. Today it is a no-op control |
| Icons | Material Rounded | Mixed with emoji glyphs (🔒 ⚠ ✦ ● ✨) in labels | Material Rounded only; sizes 16 (inline meta), 20 (row actions), 24 (nav/primary) |

## B6. Cross-screen consistency (P1)

**B6.1 Auth-required state (S5)**

- **CURRENT:** `FlowProvider` sets `_errorMessage = 'Authentication required. Please sign in.'` (`flow_provider.dart:129,156`) and Flow Hub shows it raw with "Retry" [VERIFIED].
- **PROBLEM:** Technical copy; "Retry" does not help a signed-out user.
- **PROPOSED:**
  - Add a boolean getter `FlowProvider.isAuthRequired` (set where the message is set; no architecture change).
  - Flow Hub renders a friendly prompt, "Sign in to sync your progress", with a **Sign in** button that opens the existing auth screen.
  - Noya `recover`. Other errors keep their message with "Try again".
- **SCOPE:** `flow_provider.dart` (getter only), `flow_screen.dart`.
- **ACCEPTANCE:** the string "Authentication required" never renders; the Sign in button reaches `AuthScreen`.

**B6.2 Labels and copy**

- **CURRENT:** ALL-CAPS tracked labels ("AI DAY PLANNER" S4, "YOUR PLAN" S7, "NOW"/"DO THIS NOW" S3); doubled "✨" + sparkle icon (S1–S3, S6); "Priority not specified" shown as a chip/line (S7, S8).
- **PROPOSED:**
  - Sentence-case section labels.
  - One sparkle icon at most per action, with no emoji duplicate.
  - Never render an unspecified priority.
  - Keep the "NOW" marker as the single uppercase exception if D1 keeps it (it acts as a timeline landmark).
- **ACCEPTANCE:** no unspecified-priority text anywhere; no emoji + icon duplication on any button.

**B6.3 Task card (S8)**

- **CURRENT:**
  - Noya avatar + title + menu
  - 2–3 pills (focus level, estimate, priority)
  - category text + two icon buttons
  - ~200 px per card
- **PROPOSED:**
  - Keep the Noya avatar (identity) and the card container (the inbox is a list of independent items, so the card is justified here).
  - Metadata becomes one muted text line ("45 min · Medium focus · General") instead of pills.
  - Priority is shown only when explicit, as a single flag icon.
  - Action icons get 48 dp hit areas.
- **ACCEPTANCE:** a one-line-title card with no explicit priority is ≤ 112 dp tall at 1.0 text scale; no pills except an explicit priority flag.

## B7. Professional polish (P2)

- Tabular figures for all times (aligned columns).
- `FlowPressScale` or ink on every tappable surface, never both.
- Consistent icon sizes (B5).
- Hairline dividers only between groups, never between every row.
- Empty-state copy always ends in one action.
- Sheet headers consistent: drag handle, title `titleMedium`, close/back on the leading side.

---

# PART C — SHARED DELIVERY

## 20. Acceptance criteria

**Motion (objective)**

1. **Paused test:** with `timeDilation` frozen at the rest frame (or reduced motion on), golden/visual comparison shows no resting-state difference from the pre-change screens except the Part B refinements.
2. No Noya pose change is an instant cut when motion is enabled. Every change crossfades over `posePivot` 260 ms (verify by widget test pumping 130 ms mid-transition: two `NoyaCompanionView`s present, opacities between 0 and 1).
3. After `idleWindow` (30 s) without interaction, the screen has **zero** active Noya tickers (DevTools / widget test: `tester.binding.hasScheduledFrame == false` after advancing 31 s).
4. `FlowCompanionView` no longer runs a ticker outside the focusing state.
5. Completing a task produces, within 100 ms of the tap: a check animation start, a haptic, and a `taskDone` reaction on the nearest Noya.
6. Completing the last pending task triggers exactly one `celebrate`. Completing 5 tasks within 1.5 s triggers exactly one `taskDone`.
7. A 4th L3 event in one day plays as L2.
8. Build My Day: `thinking` within 1 s of submit; `pacing` after 4 s; reassurance text after 12 s (announced); `planReady` on success; `recover` on failure. No fake step text.
9. Reduced motion: no transform-based animation runs anywhere; pose changes ≤ 120 ms fades; all states remain understandable from text.
10. Performance: no frame over 16 ms (profile build, reference device D9) during greet, celebrate or plan reveal; Noya images decode at ≤ display size × DPR.
11. `pumpAndSettle` completes in all existing widget tests without the `runtimeType … 'Test'` check.

**UI refinement:** the acceptance criteria are listed per item in B1–B6. Summary gates:

- Calendar: full date visible; Today identifiable; ≤ 1 filled button per state; default row ≤ 72 dp; times on one axis; one shared timeline component; no spinner; the fixed-state mismatch resolved.
- Build My Day: input visible with the keyboard open at 360×640; no placeholder status text; one primary action.
- Plan Result: time once per row; no unspecified priority; reads chronologically.
- Dark: B3.1–B3.6 pass the manual sweep.
- Task colors: B4 acceptance.
- Auth: the raw string never renders.

**Functionality that must remain untouched (all phases):**

- scheduling and replan logic
- task state transitions
- the persistence/API contracts (except D3 option A, if approved)
- calendar date selection and persistence (`loadCalendarDay`, `selectedCalendarDate`)
- navigation semantics
- auth flows (B6.1 adds only a getter)

## 21. Implementation rollout order

Each phase is independently shippable. Flutter tests are written by Claude and **run by the user** (they are blocked in Claude's shell); `dart analyze lib test` must be clean after every phase.

| Phase | Priority | Contents | Components changed | Must remain untouched | Tests |
|---|---|---|---|---|---|
| **M0 Foundation** | P0 | `FlowMotion` tokens/springs/switcher/test scope; `NoyaCompanionView.cacheWidth`; remove the `'Test'` runtime checks; `FlowCompanionView` pulse only when focusing; `RepaintBoundary` on the ambient background; shared shimmer | `flow_motion.dart`, `noya_companion_view.dart`, `flow_companion_view.dart`, `flow_ambient_background.dart`, `skeleton_loaders.dart` | All visuals | Existing suite green; new: no ticker outside focusing; bounded loop settles |
| **M1 Noya motion core** | P0 | `NoyaMotionView` (enter, crossfade, breath, think, pace, focus, windDown/asleep) + `NoyaReaction`/`react()` with priority, coalescing and rate limits; register `delighted`, `windDown` (D2) | new `noya_motion_view.dart`; `flow_companion_animation_controller.dart`; `NoyaState` | Static rendering contract of `NoyaCompanionView` | Unit: reaction rules; widget: crossfade, bounded loops, reduced motion; update `noya_visual_system_test` count/paths (strengthened, not loosened) |
| **M2 Calendar** | P0 | Step 0 fixed-state diagnosis; B2.1–B2.7; `FlowTimelineRow` shared with Today; date-change motion, chip motion, skeleton, empty-state Noya; completion check | `calendar_tab.dart`, `timeline_item_widget.dart`, `today_dashboard_tab.dart` (timeline section), new `FlowDateStrip`, `FlowCompletionCheck` | `loadCalendarDay`, date persistence, chip keys, NOW-item selection logic (`calendar_tab.dart:293–326`) | `calendar_date_navigation_test.dart` updated per D1 with equal-strength assertions; new: Today identifiable when not selected; selected chip visible |
| **M3 Build My Day + Plan Result** | P0 | §7.2/§7.3 motion; B1.3, B1.4 | `brain_dump_sheet.dart`, `ai_plan_preview_sheet.dart`, `parsed_plan_confirm_sheet.dart`, `replan_day_sheet.dart` | Parse/plan/apply calls, payloads, fallback logic | `build_my_day_editor_test`, `replan_my_day_ui_test`, `gemini_brain_dump_pro_test` green; new: escalation ladder timing (fake async) |
| **M4 Completion & Today** | P0 | `taskDone`/`celebrate` wiring via `onTaskCompletedForFlow`; Today Noya behaviors; highlight pulse | `main_shell.dart`, `today_dashboard_tab.dart`, `task_card.dart`, `right_now_task_card.dart` | `toggleTaskCompletion` semantics | `today_page_test`, `flow_progression_test` green; new: coalescing, L3 cap |
| **M5 Dark mode** | P0 | B3.1–B3.9 | `flow_colors.dart`, touched components | Light-mode appearance | New contrast unit test on token pairs; manual dark sweep |
| **M6 Focus, Flow Hub, onboarding, auth, splash** | P1 | §7.6–7.9; B6.1 | `focus_ritual_screen.dart`, `flow_screen.dart`, `flow_provider.dart` (getter), `onboarding_flow_screen.dart`, `routine_building_view.dart`, `auth_screen.dart`, `splash_screen.dart` | Session/XP/streak logic; auth architecture | `flow_auth_hub_test`, `adaptive_onboarding_test`, `auth_session_test` green; new: raw auth string never renders |
| **M7 Task colors** | P1 | B4 after D3 | Storage per D3; `edit_task_sheet.dart`; row/card accent | Scheduling | Model round-trip; picker widget test; dark/light rendering |
| **M8 Polish + assets** | P2 | B6.2, B6.3, B7; integrate A1–A6 when delivered; optional NOW-marker Noya (D6) and Hero (§14) | Various | — | Per item |

## 22. Manual verification checklist

Run on a physical low-end Android device (D9) **and** an emulator at 360×640 and 412×915, in light and dark, at text scale 1.0 and 1.3.

**Noya & motion**

- [ ] Every Noya pose change crossfades; none blink or cut.
- [ ] Idle breath is not consciously noticeable in the first 3 s at 76 px, and stops after ~30 s.
- [ ] Build My Day: thinking → pacing (> 4 s) → reassurance (> 12 s) → planReady; airplane mode → calm recover + fallback notice.
- [ ] Complete one task: check + haptic + Noya hop. Complete the last task: one celebration only.
- [ ] Rapidly complete 5 tasks: one reaction.
- [ ] Focus session: no strong pulsing; the bob stops after ~20 s; completion celebrates.
- [ ] Evening (set device clock ≥ 20:00, no pending tasks): wind-down pose; day finished → asleep.
- [ ] Reduced motion on (Android "Remove animations"): no movement anywhere; all states still legible.
- [ ] Switch tabs mid-reaction: no replay on return.
- [ ] DevTools: zero animating tickers on an idle screen after 30 s; ambient background does not trigger tab content repaints ("Highlight repaints").

**Calendar**

- [ ] The full selected date is always visible; Today has its marker when another day is selected; the selected chip is fully visible.
- [ ] Fixed items show Fixed in Calendar (S3 mismatch resolved).
- [ ] Default rows show no badge; states are distinguishable in grayscale.
- [ ] Loading shows skeleton rows, not a spinner. The empty day shows Noya and exactly one button.
- [ ] Today and Calendar show the same persisted schedule for the same date.

**Dark mode**

- [ ] Primary/secondary/muted text are distinguishable; no dark-on-dark text (sweep Today, Tasks, Calendar, Insights, Settings, Flow Hub, Focus, sheets).
- [ ] No pale tag pills; no visible white fringe around Noya at 28/40/76 px.

**Other**

- [ ] Flow Hub signed out: friendly "Sign in to sync your progress" + Sign in; no raw auth text.
- [ ] Task colors (after M7): set/change/reset; correct in light and dark; conflict/missed/completed unaffected.
- [ ] Keyboard open in Build My Day at 360×640: input visible; Noya size change animates.
- [ ] Safe areas: nothing under the status bar or gesture bar.

## 23. Known limitations, missing assets, open decisions

**Limitations**

- Walking, arm-waving, blinking, exercise and reassuring motion are approximated with whole-body transforms until assets A1–A5 exist (§15).
- Sparkles/zzz/"?" are baked into the poses and cannot animate independently.
- `noya_proud` (two tails, collar) and curled `noya_sleepy` (collar) break identity slightly during crossfades until A6.
- Dark-mode findings are code-derived; no dark screenshot exists.
- Flutter widget tests cannot run in Claude's shell; the user runs them.
- The screenshot folder named in the brief does not exist; evidence came from the user's Screenshots folder (S1–S8).

**Open decisions (need approval)**

| ID | Decision | Recommendation |
|---|---|---|
| D1 | Calendar state labels change (sentence case, no emoji, no default badge), so `calendar_date_navigation_test.dart` string assertions are rewritten with keys + labels + semantics at equal strength | Approve |
| D2 | Add `NoyaState.delighted` (`noya_success.png`) and `NoyaState.windDown` (`noya_sleeping.png`); update `noya_visual_system_test` from 7 to 9 states | Approve |
| D3 | Task color storage: A (backend column + migration 007, blocked by the D4 prod-schema facts) or B (local-only) | A, after the D4 facts; B only as a stopgap |
| D4 | Hide Replan on empty days | Hide |
| D5 | Wind-down threshold (20:00 local, no pending tasks) | 20:00; could later follow the user's onboarding chronotype |
| D6 | Optional 24 px Noya on the Calendar NOW marker | Defer to M8; prototype first |
| D7 | Asset cleanup (duplicates, debug images; ≈ 27 MB folder) as a separate task | Approve as a separate task |
| D8 | Which screen "Quest" refers to (`focus_ritual_screen` vs `what_should_i_do_screen`) | Confirm |
| D9 | Reference low-end Android device for performance acceptance | User to name a device |
| D10 | `DensityMode`: wire Compact to timeline spacing or hide the no-op setting | Wire in M2 |
| D11 | Commission assets A1, A4, A6 (P1) | Approve, if an artist is available |

---

## 24. Revision 2 — approval resolutions (2026-10-02)

This section **supersedes** any conflicting statement above.

### 24.1 Decisions

| ID | Resolution |
|---|---|
| D1 | Approved: Calendar test strings are rewritten with equal-strength assertions (key + label + semantics per state). |
| D2 | Approved: `NoyaState.delighted` and `NoyaState.windDown` are added; `noya_visual_system_test` goes from 7 to 9 states. |
| D3 | Task colors are a **persistent product feature**, delivered in two milestones: **M7a** (client feature with on-device persistence; no backend change) and **M7b** (backend column, API, migration, sync). M7b is a separate milestone and must not block motion work (§24.3). |
| D4 | Approved: Replan is hidden on days with no scheduled items. |
| D5 | Approved: wind-down starts at 20:00 local when no tasks are pending. |
| D6 | Deferred to M8 (prototype first). |
| D7 | Approved as a separate task, outside this plan's milestones. |
| D8 | Resolved: Quest/Focus = `FocusRitualScreen` + Flow Hub Quests tab (§7.6). |
| D9 | Resolved: no specific physical device. Use the representative profile in §24.2. |
| D10 | Wire `DensityMode.compact` to timeline row spacing in M2. |
| D11 | The asset requests in §15 stand. Motion ships without them. |
| — | Constraint reaffirmed: no new animation package; the existing `FlowMotion`, `FlowFadeSlide`, `FlowPressScale`, `FlowFadeIndexedStack`, `FlowPageRoute` and `FlowCompanionAnimationController` are reused and extended. |

### 24.2 Representative lower-end Android performance profile (D9)

Physical devices vary and none is mandated. Performance acceptance is therefore defined in three layers. Only Layer 1 is device-independent; Layers 2 and 3 use whatever device is available.

**Reference class (what "lower-end" means for Flowstate):**

- Android 10–12 (API 29–31)
- 4–8 Cortex-A53/A55-class cores at ≤ 2.0 GHz
- 3 GB RAM
- Mali-G52 / PowerVR GE8320-class GPU
- 720×1600 display at ≈ 2.0 device pixel ratio
- 60 Hz

The frame budget is 16.6 ms.

| Layer | What | How | Pass criteria |
|---|---|---|---|
| **1 Structural (device-independent, automated)** | Ticker lifecycle, bounded loops, decode size, repaint isolation | Widget tests with fake time; `debugRepaintRainbowEnabled` / DevTools "Highlight repaints" | Zero active Noya tickers after `idleWindow`; no ticker in `FlowCompanionView` outside focusing; `Image` `cacheWidth` ≤ size × DPR; ambient background repaints do not repaint tab content; ≤ 1 Noya loop per screen |
| **2 Headroom timing (any physical Android device, profile mode)** | Frame cost of greet, taskDone, celebrate, plan reveal, Calendar date change, Build My Day thinking → pacing | `flutter run --profile` + DevTools Performance; record UI and raster thread times | On the available device, the **worst frame ≤ 8 ms** (UI + raster each) during these scenarios. The 2× headroom is a proxy for the reference class. If the available device is itself at or below the reference class, the criterion is ≤ 16 ms. |
| **3 Low-memory functional check (emulator)** | Memory and visual behavior at reference resolution | Android emulator AVD: API 30, 2 vCPU, 2 GB RAM, 720×1600, 320 dpi, debug build (emulators are not used for timing) | Noya image-cache footprint ≤ 8 MB with Build My Day open (DevTools Memory); no blank frames on pose change; layout correct at 720×1600 |

### 24.3 Custom task colors — complete behavior (supersedes B4 where they differ)

**Palette (contrast-verified in this session against `#FFFFFF`, `#F8FAFC`, `#F1F5F9` in light and `#0B0F17`, `#131B2A`, `#1A2436`, `#223046` in dark; WCAG 1.4.11 non-text minimum 3:1):**

| Key | Light | Min light ratio | Dark | Min dark ratio |
|---|---|---|---|---|
| `sky` | `#0284C7` | 3.74 | `#38BDF8` | 6.21 |
| `mint` | `#059669` | 3.44 | `#34D399` | 6.92 |
| `blue` | `#2563EB` | 4.72 | `#60A5FA` | 5.23 |
| `amber` | **`#B45309`** (amber-700; amber-600 `#D97706` measured 2.91 on `#F1F5F9`, so rejected) | 4.58 | `#FBBF24` | 7.97 |
| `rose` | `#E11D48` | 4.29 | `#FB7185` | 4.94 |
| `violet` | `#7C3AED` | 5.20 | `#A78BFA` | 4.89 |
| `lime` | **`#4D7C0F`** (lime-700; lime-600 `#65A30D` measured 2.95 on `#F8FAFC`, so rejected) | 4.56 | `#A3E635` | 8.82 |
| `slate` | `#475569` | 6.92 | `#94A3B8` | 5.19 |

`default` (null) keeps today's behavior. Custom free-pick hex stays P2 (B4 rule: auto-adjusted to ≥ 3:1).

**Data model**

- `TaskItem.colorKey` (`String?`, JSON `color_key`).
- `ScheduleItem.colorKey` (`String?`, JSON `color_key`), filled from the payload when present, otherwise looked up by `taskId` from the provider's task list.
- Unknown keys resolve to `default`, for forward compatibility.

**Persistence**

- **M7a (client):**
  - A `TaskColorStore` persists `taskId → colorKey` on device (SharedPreferences, JSON map) and is applied whenever tasks or schedules load.
  - Colors survive restarts. They are not shared across devices until M7b.
  - Parsed tasks in Build My Day carry `colorKey` on the in-memory `TaskItem`. After confirm, colors are written to the store keyed by the created task IDs. Mapping candidates to created IDs is a plan verification step: if the confirm response doesn't provide a reliable mapping, colors chosen before confirm are applied by matching created tasks to candidates in response order, and the plan must verify this ordering guarantee first.
- **M7b (backend, separate milestone):**
  - Alembic migration `007_task_color_key` adds `tasks.color_key VARCHAR(16) NULL`. It is ALTER-only and offline-SQL capable like 006, and it **inherits the D4 production-schema blocker** from `build-my-day-replan.md` §11.1.
  - `TaskCreate`, `TaskUpdate`, `TaskResponse` and the calendar/today schedule item schemas gain `color_key`, with a server-side whitelist of palette keys.
  - The client sends `color_key` in create, update and confirm payloads.
  - **Reconciliation:** on the first sync after M7b, local colors for tasks whose server `color_key` is null are uploaded once. After that the server is authoritative and the local store is a cache.

**Behavior per screen**

| Screen | Where color shows | How the user sets it |
|---|---|---|
| Calendar (`calendar_tab.dart`) | Timeline node dot + 3 px leading accent bar; NOW row fill at 8% (light) / 14% (dark) of the task color if set, else the app accent | Through task details |
| Today (`today_dashboard_tab.dart`, `TimelineItemWidget`, `RightNowTaskCard`) | Same as Calendar; `RightNowTaskCard` leading accent bar | Through task details |
| Tasks inbox (`TaskCard`) | 3 px leading accent bar | Options menu → Edit |
| Task details (`edit_task_sheet.dart`) | Live preview row at the top of the sheet | "Color" row: swatch strip (Default first = reset), applied on the existing Save |
| Add task (`add_task_sheet.dart`) | — | Same "Color" row; defaults to Default |
| Build My Day — edit mode (`brain_dump_sheet.dart` `_buildEditContent`) | Color dot on each parsed-task row | Tap the dot → the same swatch strip in a small sheet; defaults to Default |
| Plan Result (`brain_dump_sheet.dart` preview, `ai_plan_preview_sheet.dart`, `parsed_plan_confirm_sheet.dart`) | Node/accent bar on rows (B1.4 anatomy); existing tasks show their color | Via Build My Day edit mode |
| Replan diff (`plan_diff_view.dart`) | Accent bar on moved/new rows | — |
| Focus (`FocusRitualScreen`) | None. The timer ring keeps the app accent, so focus UI stays neutral (P2 revisit). | — |
| Flow Hub | None | — |

**State rules (both themes)**

- Completed: the task color drops to 40% opacity.
- Conflict, missed and unscheduled indicators always use semantic colors.
- Task color never tints text, buttons or the state indicator.
- Pressed and selected states use the existing patterns.
- The picker's selected swatch shows a check icon + ring.
- The Default swatch shows the type/accent color with a "Default" label.

**Accessibility**

- Swatches are 40 dp inside 48 dp targets.
- Semantics label "<Name> color", with selected state.
- The preview row exposes "Color: <Name>".
- Color is never the only carrier of meaning (it's identity, not state).

**Acceptance (supersedes B4):**

- set, change and reset work from task details, add task and Build My Day edit mode
- the color persists across app restart (M7a) and across devices (M7b)
- correct in light and dark
- no text uses a task color
- conflict/missed/completed indicators look identical regardless of task color
- a palette contrast unit test passes ≥ 3:1 against every listed surface

## Appendix — Files likely to change (by phase)

- **M0:** `lib/theme/flow_motion.dart`, `lib/components/noya_companion_view.dart`, `lib/components/companion/flow_companion_view.dart`, `lib/components/flow_ambient_background.dart`, `lib/components/skeleton_loaders.dart`
- **M1:** new `lib/components/noya_motion_view.dart`; `lib/components/companion/flow_companion_animation_controller.dart`; `test/noya_visual_system_test.dart`
- **M2:** `lib/screens/calendar_tab.dart`, `lib/components/timeline_item_widget.dart`, `lib/components/timeline_current_time_marker.dart`, `lib/screens/today_dashboard_tab.dart`; new date strip / completion check components; `test/calendar_date_navigation_test.dart`
- **M3:** `lib/screens/brain_dump_sheet.dart`, `lib/screens/ai_plan_preview_sheet.dart`, `lib/screens/parsed_plan_confirm_sheet.dart`, `lib/screens/replan_day_sheet.dart`
- **M4:** `lib/screens/main_shell.dart`, `lib/components/task_card.dart`, `lib/components/right_now_task_card.dart`, `lib/screens/today_dashboard_tab.dart`
- **M5:** `lib/theme/flow_colors.dart`, `lib/components/compact_readiness_card.dart`, `lib/components/break_session_card.dart`, `lib/components/task_difficulty_badge.dart`, `lib/components/readiness_hero_card.dart`, `lib/screens/task_inbox_tab.dart`, others found in the sweep
- **M6:** `lib/screens/focus_ritual_screen.dart`, `lib/screens/flow_screen.dart`, `lib/providers/flow_provider.dart` (getter), `lib/screens/onboarding_flow_screen.dart`, `lib/components/routine_building_view.dart`, `lib/screens/auth_screen.dart`, `lib/screens/splash_screen.dart`
- **M7:** `lib/models/task_item.dart`, `lib/models/schedule_item.dart`, `lib/components/edit_task_sheet.dart`, plus `backend/app/models/task.py`, `backend/app/schemas/task.py` and an Alembic migration (only if D3 = A)
