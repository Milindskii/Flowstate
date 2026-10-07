# Flowstate M2 UI/UX QA Handoff Log

**Milestone:** M2 Polish, Bug Catching & Visual QA  
**Scope:** Flutter Frontend UI / UX / Layout / Aesthetics / Micro-interactions  
**Screenshot Folder:** `docs/ui-qa/screenshots/`  
**Purpose:** Single source of truth for visual defects, layout issues, UX friction points, and design polish opportunities for Claude to inspect, triage, and implement.

---

## Severity Rubric

| Level | Tag | Description |
| :--- | :--- | :--- |
| **P0** | `[P0 Blocker]` | App crash, layout overflow / yellow-black RenderFlex stripe, completely unresponsive touch target, broken core flow. |
| **P1** | `[P1 High]` | Severe UX friction, misleading temporal sequence, inverted hierarchy, broken theme / invisible text, unhandled error banner. |
| **P2** | `[P2 Medium]` | Redundant actions, awkward spacing / padding, missing state feedback, suboptimal responsive layout on desktop / wide viewport. |
| **P3** | `[P3 Polish]` | Inconsistent border radius, low contrast caption text, unpolished micro-copy, missing haptic / transition polish. |
| **Idea**| `[Idea/Enhancement]` | UX suggestion, aesthetic enhancement, delight / animation improvement. |

---

## Quick Reference Index

| ID | Screen | Issue Summary | Severity | Status |
| :--- | :--- | :--- | :--- | :--- |
| **UI-001** | Brain Dump Plan Preview | Temporal inversion & 4:30 PM placed above 9:30 AM + Error banner UX | `[P1 High]` | Open |
| **UI-002** | Living Flow Hub | Sticky "Auth required" banner over zero-state companion | `[P1 High]` | Open |
| **UI-003** | Tasks Screen | Triple redundant "Add Task" entry points on empty state | `[P2 Medium]` | Open |
| **UI-004** | Task Completion Sheet | Wide emoji spread across horizontal viewport + Inverse button weight | `[P2 Medium]` | Open |
| **UI-005** | _[Screen Name]_ | _[Quick title for new finding]_ | _[Severity]_ | Draft |

---

## Logged UI/UX Findings

---

### [UI-001] Brain Dump Plan Preview: Temporal Inversion & Save Error UX
1. **Screen**: Brain Dump Plan Preview Sheet (`ParsedPlanConfirmSheet` / `BrainDumpSheet`)
2. **Screenshot/reference**: `docs/ui-qa/screenshots/m2_brain_dump_temporal_inversion.png`
3. **Issue**:
   * **Temporal Inversion**: "Go to the gym in the morning" was scheduled for `Today · 4:30 PM` (late afternoon instead of morning) and listed *above* "Cook breakfast after that then head to work" scheduled for `Today · 9:30 AM`. Chronology is inverted in the UI preview list.
   * **Save Failure Banner**: A peach-colored banner appears above the action buttons stating *"Couldn't save your plan right now. Your plan is still here — try again."* without giving a specific reason (e.g. session expired / offline) or a direct inline retry button.
   * **Theme & Styling**: The sheet renders in Light Theme (`#FFFFFF` surface) while the parent app is in Dark Theme, causing a jarring visual flash. "Priority not specified" is italicized raw placeholder-style copy.
4. **Expected behavior/design**:
   * Tasks must always be presented in strict ascending chronological order (`9:30 AM` before `4:30 PM`).
   * "In the morning" constraint should be prioritized over afternoon slots unless morning is hard-blocked.
   * Error banner should provide actionable context (e.g., *"Session expired. Sign in to sync your schedule."*) and a direct retry affordance.
   * Bottom sheet theme should match the active app theme (Sleek dark obsidian card with `#151B2B` background and teal accents).
5. **Severity**: `[P1 High]`
6. **Notes**:
   * Occurred after API returned 401 Unauthorized for `POST /api/v1/tasks/batch-create-and-schedule`.
   * Good: user input and plan candidates were preserved in state without crashing or dropping the sheet.

---

### [UI-002] Living Flow Hub: Sticky Auth Error over Companion State
1. **Screen**: Living Flow Hub (`FlowScreen` / `LivingFlowHub`)
2. **Screenshot/reference**: `docs/ui-qa/screenshots/m2_living_flow_auth_banner.png`
3. **Issue**:
   * A full-width dark error banner at the top reads: *"☁️ Authentication required. Please sign in. [Retry]"*.
   * Underneath, the companion UI still renders with zeroed-out state (`0 Day Streak`, `0 / 3 Shields`, `0 Flow`, `Baby · Level 1`, `Ready to focus`), which can make users feel like their real companion data and streaks have been wiped permanently.
   * The tab bar has `Journey` highlighted with a solid vibrant green pill, while `Quests`, `Badges`, and `Customize` are faint grey icon buttons, making the tab bar look asymmetrical.
   * On wide aspect ratios (desktop/tablet), the companion card floats with excessive empty vertical padding.
4. **Expected behavior/design**:
   * If unauthenticated, show a dedicated unauthenticated view or a non-alarming banner that clarifies: *"You're viewing offline mode. Sign in to sync your cloud progress."*
   * Tap on `[Retry]` should attempt silent JWT token refresh via `auth_service` before failing.
   * Tab bar active indicator should have balanced elevation and typography across all four tabs.
5. **Severity**: `[P1 High]`
6. **Notes**:
   * Check token refresh lifecycle in `lib/services/flow_service.dart` and `lib/providers/flow_provider.dart`.

---

### [UI-003] Tasks Screen: Redundant Entry Points in Empty State
1. **Screen**: Tasks Screen (`TasksScreen`)
2. **Screenshot/reference**: `docs/ui-qa/screenshots/m2_tasks_redundant_add_buttons.png`
3. **Issue**:
   * Choice overload on empty state: there are **three distinct ways to add a task** visible simultaneously:
     1. Top input bar: `+ What do you need to get done?` (with submit arrow inside).
     2. Center card CTA button: `Add task`.
     3. Bottom-right Floating Action Button (FAB): `+ Add Task`.
     4. (Plus a 4th button: `Brain dump a messy day`).
   * Visual clutter: The top search bar has an external lightning bolt icon (`⚡`) on the far right and an inner blue arrow icon (`↑`), with ambiguous affordance.
   * Double nested box: The empty state card is a dark rounded box inside another dark container, creating an awkward nested box aesthetic on wide screens.
4. **Expected behavior/design**:
   * When the inbox is empty, hide the FAB or simplify the center card into a cohesive hero welcoming the user.
   * Clear distinction between Quick Single Task input (top bar) and AI Brain Dump (special action button with Gemini sparkle/glow).
   * Streamline icons: Remove redundant lightning icon if top bar already has direct submit.
5. **Severity**: `[P2 Medium]`
6. **Notes**:
   * Consider making `Brain dump a messy day` the primary hero action on zero-task days to encourage adoption.

---

### [UI-004] Task Completion Reflection: Visual Hierarchy & Emoji Spread
1. **Screen**: Task Completion Feedback Sheet (`TaskCompletionSheet` / `PostSessionReflection`)
2. **Screenshot/reference**: `docs/ui-qa/screenshots/m2_reflection_sheet_spacing.png`
3. **Issue**:
   * **Inverted Button Visual Hierarchy**: The top action buttons are `Keep in progress` (high-contrast cyan outlined button) and `Yes, mark complete` (dark solid background that fades into the card). The primary desired action (completion) has less visual prominence than the secondary escape hatch.
   * **Emoji Dispersion**: On wide viewports or landscape/desktop, the 4 feedback emojis (`😫`, `😐`, `😊`, `🔥`) are stretched across the full width, leaving massive empty gaps between them and disconnecting them as a unified rating scale.
   * **Missing Labels**: The emojis lack text descriptors (e.g. "Drained", "Neutral", "Good", "In Flow"), making subjective reflection ambiguous.
4. **Expected behavior/design**:
   * `Yes, mark complete` should be the solid vibrant primary button (`#00D2B4` or theme accent), while `Keep in progress` should be a subtle ghost/text button.
   * Emoji rating scale should have a constrained `maxWidth` (e.g., 360–400px), centered horizontally, with consistent 16–24px gaps and clear label text underneath each icon.
   * Selected emoji should have a smooth spring animation and distinct active glow/border.
5. **Severity**: `[P2 Medium]`
6. **Notes**:
   * Connected to `lib/components/task_completion_sheet.dart` or post-session feedback dialog.

---

## New Entry Template

<!-- Copy and paste this block to record a new issue -->

### [UI-XXX] Short Descriptive Title
1. **Screen**: _[e.g. Today Screen, Onboarding Screen, Focus Timer, Calendar View, Settings]_
2. **Screenshot/reference**: `docs/ui-qa/screenshots/m2_screen_issue.png`
3. **Issue**:
   * _Detailed description of what is visually wrong, misaligned, broken, or unintuitive._
   * _Device/viewport context (e.g., Mobile portrait, Tablet, Desktop web)._
4. **Expected behavior/design**:
   * _How it should look and behave according to Flowstate design principles._
5. **Severity**: _[P0 Blocker | P1 High | P2 Medium | P3 Polish | Idea/Enhancement]_
6. **Notes**:
   * _Any error logs, related provider/screen files, or reproduction steps._

---

## Polish & Enhancement Ideas

* **Consistent Theme Palette**: Standardize all modal sheets and bottom sheets to share dark obsidian background tokens (`#0B0F19` background, `#151B2B` surface cards, `#00D2B4` cyan accent) to avoid light/dark sheet flashes.
* **Micro-interaction Feedback**: Add subtle haptics (`HapticFeedback.lightImpact()`) on emoji selection, plan confirmation, and tab switching.
* **Empty State Illustrations**: Replace plain text boxes on empty screens with delightful minimalist Noya mascot illustrations matching companion level and stage.
* **Responsive Max-Width Constraints**: Wrap mobile-first bottom sheets and reflection dialogs in a `ConstrainedBox(constraints: BoxConstraints(maxWidth: 520))` to prevent awkward wide-screen stretching on desktop/tablet.
