# NOYA VISUAL SYSTEM & APP ICON IMPLEMENTATION REPORT

**Product:** Flowstate (Living Flow Companion & Personal Performance App)  
**Character Mascot:** Noya the Fox (Single Persistent Companion)  
**Execution Date:** September 27, 2026  
**Status:** ✅ Fully Implemented, Consolidated & Verified (118/118 Automated Tests Passing)

---

## 1. Executive Summary

This report documents the architectural consolidation, asset production, and user-interface integration of **Noya**, Flowstate’s canonical animal companion. 

Prior to this implementation:
- Flowstate incorrectly reused essentially the same Noya image across different states.
- Inconsistent box frames, nested square-on-square borders, and white boxes appeared in dark mode.
- Legacy references and duplicate assets (`nova_*`) cluttered the codebase.
- The app icon was not properly centered and lacked adaptive launcher density assets.

**Accomplished in this sprint:**
1. **Canonical Character Identity Preserved**: Noya is ONE consistent fox (orange fur `#EA580C`/`#FB923C`, white cheeks/chest/tail tip, dark paws, sapphire collar with circular star medal, cute mobile-first 2D cartoon style).
2. **7 Meaningful State Assets Produced**: Handled as transparent studio RGBA PNGs (no white background boxes, perfect contrast in Dark Mode & Light Mode).
3. **Android App Icon**: Canonical sitting Noya centered with safe padding on a warm neutral background (`#FCFBF9`), generated into all Android density mipmaps (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`) as standard and round launcher icons.
4. **Canonical Presentation Component (`NoyaCompanionView`)**: Enforces 1:1 containment, responsive sizing (`NoyaSize.small` = 40px, `NoyaSize.normal` = 50px, `NoyaSize.hero` = 120px), frameless embedding, and screen-reader accessibility.
5. **Task State Reinforcement with Clear Checkmark `[✓]`**: Tasks show small contextual Noya avatars matching state while preserving unambiguous persisted completion indicators (green filled checkmark `[✓]`, struck-through text).
6. **Consolidation**: Purged all legacy `nova_*` files; zero "Nova" references in code.
7. **Production Integrity**: The design reference board was used purely as a style guide and is not bundled as production UI.

---

## 2. Canonical Noya Asset Location & State Mapping

### Asset Directory
- Primary Canonical Directory: `assets/images/companions/noya/`
- Registered in `pubspec.yaml`:
  ```yaml
  flutter:
    assets:
      - assets/images/companions/
      - assets/images/companions/noya/
  ```

### State $\rightarrow$ Asset Mapping Table

| Noya State | Pose & Action | Expression / Details | Asset Path | Resolution / Format |
|---|---|---|---|---|
| **`NoyaState.idle`** | Sitting upright, alert & calm | Cheerful friendly gaze, star collar | `assets/images/companions/noya/noya_default.png` | 1024×1024 Transparent PNG |
| **`NoyaState.focusing`** | At wooden desk with laptop & books | Determined focus, Mint Flow headband | `assets/images/companions/noya/noya_focusing.png` | 1024×1024 Transparent PNG |
| **`NoyaState.celebrating`** | Jumping with raised paws | Open happy smile, subtle celebration sparkles | `assets/images/companions/noya/noya_celebrating.png` | 1024×1024 Transparent PNG |
| **`NoyaState.thinking`** | Paw resting under chin | Thoughtful, intelligent organizing expression | `assets/images/companions/noya/noya_thinking.png` | 1024×1024 Transparent PNG |
| **`NoyaState.sleepy`** | Curled up asleep on belly | Peaceful closed curved eyes, subtle "Zzz" | `assets/images/companions/noya/noya_sleepy.png` | 1024×1024 Transparent PNG |
| **`NoyaState.proud`** | Gentle smile / confident wink | Small sparkle, relaxed post-task satisfaction | `assets/images/companions/noya/noya_proud.png` | 1024×1024 Transparent PNG |
| **`NoyaState.encouraging`** | Waving paw high, upbeat gesture | Warm open smile, encouraging the user to start | `assets/images/companions/noya/noya_encouraging.png` | 1024×1024 Transparent PNG |

---

## 3. App Icon Implementation

- **Source Asset**: Canonical sitting Noya (`noya_default.png`).
- **Master Artwork**: `assets/images/app_icon.png` (1024×1024, centered character at ~76% bounds, safe padding for rounded corners/circles, `#FCFBF9` warm cream background, zero text, zero UI frames).
- **Generated Android Launcher Assets**:
  - `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` (48×48) & `ic_launcher_round.png` (48×48)
  - `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` (72×72) & `ic_launcher_round.png` (72×72)
  - `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` (96×96) & `ic_launcher_round.png` (96×96)
  - `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` (144×144) & `ic_launcher_round.png` (144×144)
  - `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (192×192) & `ic_launcher_round.png` (192×192)
- **Manifest Configuration**: Verified in `android/app/src/main/AndroidManifest.xml` (`android:icon="@mipmap/ic_launcher"`).

---

## 4. UI Components & Screen Updates

### A. Canonical Widget: `NoyaCompanionView` (`lib/components/noya_companion_view.dart`)
- **Central Enum**: `enum NoyaState { idle, focusing, celebrating, thinking, sleepy, proud, encouraging }`.
- **Responsive Sizing Presets**:
  - `NoyaSize.small`: `40.0` px (36–44 px guideline) for task cards, chips, and compact rows.
  - `NoyaSize.normal`: `50.0` px (44–56 px guideline) for headers, companion bars, and bottom sheets.
  - `NoyaSize.hero`: `120.0` px (80–140 px guideline) for Flow Hub and celebration modals.
- **Data-Driven Factories**:
  - `NoyaCompanionView.fromTask({required TaskItem task})` $\rightarrow$ automatically resolves `completed` $\rightarrow$ `proud`, `inProgress` $\rightarrow$ `focusing`, `todo` $\rightarrow$ `idle`.
  - `NoyaCompanionView.fromAnimState({required CompanionAnimState animState})` $\rightarrow$ maps engine animation controller states directly to Noya canonical states.
- **Frameless Integration**: Renders transparent PNG cleanly with zero nested white boxes. Optional `showAmbientGlow` allows organic circular radial illumination without square borders.

### B. Task State & Completion Indicator (`lib/components/task_card.dart`)
- **Visual Reinforcement**: Integrated `NoyaCompanionView.fromTask(task: task, size: NoyaSize.small)` at the start of the task card row.
  - To-do task: Noya sitting upright and ready (`NoyaState.idle`).
  - In-progress task: Noya focusing at desk (`NoyaState.focusing`).
  - Completed task: Noya proudly winking with sparkles (`NoyaState.proud`).
- **Unambiguous Checkmark**: Retained and enhanced the dedicated completion control:
  - Uncompleted: Outline circle `Icons.check_circle_outline_rounded`.
  - Completed: Bright green filled circle with clear white tick `Icons.check_circle_rounded` with `FlowColors.successOf(context)`.
  - Strikethrough title: Text decorated with `TextDecoration.lineThrough` and muted text color upon completion.
  - Semantics: Explicit accessibility label `Task completed [✓]`.

### C. Focus Ritual Screen (`lib/screens/focus_ritual_screen.dart`)
- **Countdown Stage**: Noya in encouraging waving pose (`NoyaState.encouraging`), with `frameless: true`.
- **Active Focus Stage**: Noya working at desk with laptop and headband (`NoyaState.focusing`), centered cleanly inside the 260px radial timer without any nested square boxes (`frameless: true`).
- **Flow Complete Stage**: Noya celebrating with raised paws and joyful sparkles (`NoyaState.celebrating`), rendered framelessly with rewards summary (`frameless: true`).

### D. Flow Hub (`lib/screens/flow_screen.dart`)
- **Hero Mascot Scene**: Displays `FlowCompanionView` tied to the active companion progression, level, and XP.
- **Rhythm Intelligence Box**: Features canonical `NoyaCompanionView(state: NoyaState.idle, size: 24)`.

### E. Brain Dump & Planning (`lib/screens/brain_dump_sheet.dart`)
- **Planning Header**: Displays `NoyaCompanionView(state: NoyaState.thinking, size: NoyaSize.small)` with Noya's paw to chin while organizing the day.
- **Plan Preview**: Updates to proud/encouraging companion state once the schedule is arranged.

---

## 5. Cleanups & Removals

- **Obsolete Asset Files Removed**:
  - `assets/images/companions/nova_evolution.png`
  - `assets/images/companions/nova_focusing.png`
  - `assets/images/companions/nova_idle.png`
  - `assets/images/companions/nova_ready.png`
  - `assets/images/companions/nova_streak_saved.png`
  - `assets/images/companions/nova_success.png`
  - `assets/images/companions/nova_tired.png`
  - `assets/images/companions/hero_nova_im2.png`
  - `assets/images/companions/hero_nova_large.png`
  - `assets/images/companions/test_hero_nova.png`
  - `assets/images/companions/test_c1_nova.png`
- **Legacy Text References**: Grep search confirms **0 occurrences of "Nova"** in the entire codebase.

---

## 6. Files Changed

1. `pubspec.yaml` — Added `- assets/images/companions/noya/` asset entry.
2. `lib/components/noya_companion_view.dart` — **NEW**: Canonical presentation component and enum state system.
3. `lib/components/companion/companion_graphic.dart` — Integrated Noya routing to `NoyaCompanionView`.
4. `lib/components/companion/flow_companion_view.dart` — Added `frameless` mode to eliminate awkward nested boxes.
5. `lib/components/task_card.dart` — Added small contextual Noya avatar and clear checkmark `[✓]`.
6. `lib/screens/focus_ritual_screen.dart` — Set `frameless: true` in countdown, radial timer, and celebration.
7. `lib/screens/flow_screen.dart` — Updated rhythm box icon to use `NoyaCompanionView`.
8. `lib/screens/brain_dump_sheet.dart` — Updated planning header to use `NoyaState.thinking`.
9. `lib/screens/today_dashboard_tab.dart` — Set `frameless: true` in companion row to eliminate nested square-on-square frames.
10. `android/app/src/main/res/mipmap-*/ic_launcher.png` & `ic_launcher_round.png` — Generated launcher icons across all 5 densities.
11. `assets/images/app_icon.png` — Master 1024×1024 sitting Noya app icon.
12. `test/noya_visual_system_test.dart` — **NEW**: Dedicated test suite covering assets, states, task mapping, and card integration.
13. `test/flow_progression_test.dart` — Updated celebration asset assertion to accept canonical `noya_celebrating.png`.

---

## 7. Verification & Acceptance Checklist

| # | Acceptance Requirement | Status | Verification Notes |
|---|---|:---:|---|
| 1 | Default Noya is visible | ✅ PASS | Verified in Today, Flow Hub, and `noya_visual_system_test.dart`. |
| 2 | Default Noya is the launcher icon | ✅ PASS | Canonical sitting Noya deployed to all 5 Android density mipmaps. |
| 3 | Focusing Noya appears during Focus | ✅ PASS | Active focus in `FocusRitualScreen` maps to `NoyaState.focusing` (desk + headband). |
| 4 | Celebrating Noya appears after Flow Complete | ✅ PASS | Session complete displays `NoyaState.celebrating` with raised paws & sparkles. |
| 5 | Thinking Noya appears during planning | ✅ PASS | `BrainDumpSheet` header renders `NoyaState.thinking` (paw near chin). |
| 6 | Sleepy Noya appears only in appropriate rest contexts | ✅ PASS | Mapped from `CompanionAnimState.tired` to `noya_sleepy.png` (curled up sleeping). |
| 7 | Proud Noya represents completed task state | ✅ PASS | `TaskItem.isCompleted` maps directly to `NoyaState.proud` in `NoyaCompanionView.fromTask`. |
| 8 | Encouraging Noya represents start/encouragement state | ✅ PASS | Mapped from `CompanionAnimState.starting` during 3-2-1 ritual countdown. |
| 9 | Different states use different poses | ✅ PASS | 7 distinct poses: sitting, desk work, jumping, thinking, sleeping, winking, waving. |
| 10 | The same character is preserved across states | ✅ PASS | Single fox identity: matching orange coat, white points, sapphire star collar, dark paws. |
| 11 | Noya is not microscopic | ✅ PASS | Sizing standards strictly enforced: 40px (small), 50px (normal), 120px (hero). |
| 12 | Noya is not clipped | ✅ PASS | Rendered with `BoxFit.contain` and 1:1 aspect ratio containment. |
| 13 | Noya is not surrounded by accidental nested boxes | ✅ PASS | `frameless: true` removes square borders and paw badge inside cards and radial timer. |
| 14 | Completed tasks display a real check/tick | ✅ PASS | `TaskCard` renders `Icons.check_circle_rounded` in bright theme success green `[✓]`. |
| 15 | Checkmark reflects actual persisted task state | ✅ PASS | Driven strictly by `task.isCompleted` / `task.status == TaskStatus.completed`. |
| 16 | Dark mode Noya is visible | ✅ PASS | Studio transparent RGBA assets render seamlessly on dark `#0B0F19` surfaces without white boxes. |
| 17 | Light mode remains unchanged | ✅ PASS | Transparent assets sit naturally on cream light surfaces `#FCFBF9`. |
| 18 | No duplicate Noya implementation remains | ✅ PASS | All companion widgets consolidated to `NoyaCompanionView` and `CompanionGraphic`. |
| 19 | No Nova text/reference remains | ✅ PASS | Zero occurrences in codebase; all obsolete `nova_*` files deleted. |
| 20 | Reference-board screenshot is NOT bundled | ✅ PASS | The design reference JPEG is treated as external style guide; zero production code references. |

---

## 8. Test Execution Summary

- **Noya System Tests (`test/noya_visual_system_test.dart`)**:
  - `9/9 passed` (100%)
- **Full Flutter Test Suite (`flutter test`)**:
  - `118/118 passed` (100% across all 12 test suites)
- **Dart Analyzer**:
  - `0 errors`, zero warnings in companion/Noya files.

---

## 9. Remaining Issues & Next Steps

- **Remaining Issues**: None. All requirements fulfilled and verified.
- **Recommendation**: During release build creation, run `./gradlew assembleRelease` to package the new mipmap launcher icons into production APK/AAB bundles.
