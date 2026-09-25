# Flowstate - Modern Mobile Productivity App Skeleton

Flowstate is a calm, intelligent mobile productivity application built in Flutter designed to help people plan their days around their personal energy, focus windows, and circadian rhythms.

> **Important**: This is **NOT** a medical application. There are zero cortisol measurements, clinical diagnosis terms, or medical claims. All metrics are non-judgmental cognitive readiness and personal productivity indicators.

---

## Architecture & Data Flow

Flowstate implements an adaptive feedback-learning loop:

```
                     FLOWSTATE ARCHITECTURE

                              User
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
            Personal data                Task data
                 │                           │
          ┌──────┼──────┐             ┌──────┼──────┐
          ▼      ▼      ▼             ▼      ▼      ▼
        Sleep  Energy  Activity     Difficulty Duration Deadline
                 │                           │
                 └───────────┬───────────────┘
                             ▼
                    ┌─────────────────┐
                    │ Readiness Model │
                    └────────┬────────┘
                             ▼
                    ┌─────────────────┐
                    │ Scheduling       │
                    │ Engine           │
                    └────────┬────────┘
                             ▼
                         Schedule
                             │
                             ▼
                      User performs
                             │
                             ▼
                       Feedback/data
                             │
                             ▼
                    Personal Learning
                             │
                             └──────► Readiness Model
```

- **`PersonalData`**: Sleep (hours, quality, wake time), Energy (circadian curve, focus peaks, dips), Activity (physical load).
- **`TaskItem`**: Difficulty (`high`, `medium`, `light`, `physical`), Duration (minutes), Deadline, Category.
- **`ReadinessEngine`**: Calculates cognitive readiness score (`76/100`), status, and optimal peak focus windows (e.g., `9:30 AM - 11:45 AM`).
- **`SchedulingEngine`**: Allocates high difficulty/duration tasks into optimal readiness windows and lighter/physical tasks during afternoon recovery slots.
- **`PersonalLearningEngine`**: Closes the loop by capturing user session performance and perceived focus feedback to recalibrate future readiness scores.

---

## Design System

### 1. Color Direction (Zero Purple, Zero Orange)
- **Primary Background**: `#090D14` (Obsidian near-black charcoal)
- **Primary Surfaces & Cards**: `#111722` and `#161F2E`
- **Border & Subtle Lines**: `#222C3E`
- **Primary Accent**: `#06B6D4` / `#22D3EE` (Calming Electric Cyan / Aqua)
- **Secondary Accent**: `#10B981` / `#34D399` (Crisp Mint Emerald for completion & focus)
- **Peak Window Highlight**: `#38BDF8` (Glacial Ice Blue)
- **Neutral / Rest**: `#64748B` / `#94A3B8` / `#1E293B` (Slate)

### 2. Typography
- **Primary Font**: **Manrope** (via `google_fonts`)
- **Scale**:
  - Display: 26px - 32px (Bold / Extra Bold)
  - Headings: 20px - 24px (Bold / Semi-Bold)
  - Body: Minimum 16px for comfortable mobile readability (High contrast)
  - Labels & Badges: 12px - 14px (Medium / Semi-Bold)

### 3. Corner Identity
- **Cards**: `24.0px` - `28.0px`
- **Hero Containers**: `30.0px`
- **Buttons**: `18.0px` (Minimum height 52px for thumb targets)
- **Input Fields**: `18.0px`
- **Chips & Pills**: `999.0px`

### 4. Mobile Ergonomics
- **Large Tap Targets**: All buttons, inputs, and selection cards have minimum 48px–52px touch areas.
- **Sticky Navigation**: Bottom bar stays fixed with 5 core tabs (Today, Tasks, Calendar, Insights, Profile).
- **Thumb Zone Action**: "What should I do now?" floating action is anchored above the bottom bar for comfortable one-handed reach.
- **Fast Load**: Pure Flutter `CustomPainter` renders the circadian curve smoothly with zero lag or bloated external assets.
- **Touch Feedback**: Material ink-splash response on all interactives.

---

## Included Screens

1. **Splash Screen (`lib/screens/splash_screen.dart`)**: Animated breathing Flowstate logo, tagline *"Work with your rhythm."*, sync progress, and *"Private & Local"* privacy badge.
2. **Auth & Sign Up (`lib/screens/auth_screen.dart`)**: Ambient flowing energy visual (top 35%), *"Plan around your energy."*, Google Auth, Email Modal, and Sign In toggle.
3. **7-Step Onboarding (`lib/screens/onboarding_flow_screen.dart`)**:
   - Step 1: Welcome
   - Step 2: Brain dump
   - Step 3: Processing
   - Step 4: First plan
   - Step 5: Why
   - Step 6: Personalization
   - Step 7: Rhythm
4. **Today Dashboard (`lib/screens/today_dashboard_tab.dart`)**: Greeting, Avatar, Today's Readiness Hero Card with dynamic circadian wave, Recommended Next Task card, Today's Schedule timeline, and floating *"What should I do now?"* CTA.
5. **Tasks Inbox (`lib/screens/task_inbox_tab.dart`)**: Category filter pills (All, Work, Personal, Study, Health), High Priority and Later Today sections, complete/reschedule actions, and `+ Add Task` button.
6. **Add Task Modal (`lib/screens/add_task_sheet.dart`)**: AI-assisted task creation modal with real-time attribute inference (Duration, Difficulty, Focus requirement, Deadline, Category), and *"Add & Schedule"* button.
7. **"What Should I Do Now?" (`lib/screens/what_should_i_do_screen.dart`)**: Focused decision screen displaying the best task, reasons why, estimated time, and an interactive focus timer with session feedback logging.
8. **Calendar (`lib/screens/calendar_tab.dart`)**: Day/week strip, scheduled tasks, glowing Focus Windows, and *"Optimize My Day"* intelligent scheduling action.
9. **Insights (`lib/screens/insights_tab.dart`)**: Personal analytics: Best focus window, best task type, average deep work, completion rate, and weekly readiness/completion bar graph.
10. **Profile & Settings (`lib/screens/profile_settings_tab.dart`)**: Rhythm preferences, Calendar & HealthKit connections, Dark/Light theme switcher, and *"Your data belongs to you"* privacy pledge.

---

## Folder Structure

```
c:\FULL STACK WEBDEVLOPMENT\FLowstate\
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
└── lib/
    ├── main.dart
    ├── theme/
    │   ├── flow_colors.dart
    │   ├── flow_typography.dart
    │   ├── flow_radii.dart
    │   └── flow_theme.dart
    ├── models/
    │   ├── personal_data.dart
    │   ├── task_item.dart
    │   ├── readiness_model.dart
    │   ├── schedule_item.dart
    │   └── feedback_log.dart
    ├── engines/
    │   ├── readiness_engine.dart
    │   ├── scheduling_engine.dart
    │   └── personal_learning_engine.dart
    ├── providers/
    │   ├── app_state_provider.dart
    │   └── theme_provider.dart
    ├── components/
    │   ├── flow_logo.dart
    │   ├── primary_button.dart
    │   ├── secondary_button.dart
    │   ├── rounded_card.dart
    │   ├── energy_curve_painter.dart
    │   ├── readiness_hero_card.dart
    │   ├── recommended_task_card.dart
    │   ├── task_card.dart
    │   ├── timeline_item_widget.dart
    │   ├── category_chip.dart
    │   ├── task_difficulty_badge.dart
    │   ├── progress_header.dart
    │   └── flow_bottom_nav.dart
    ├── screens/
    │   ├── splash_screen.dart
    │   ├── auth_screen.dart
    │   ├── onboarding_flow_screen.dart
    │   ├── main_shell.dart
    │   ├── today_dashboard_tab.dart
    │   ├── task_inbox_tab.dart
    │   ├── add_task_sheet.dart
    │   ├── what_should_i_do_screen.dart
    │   ├── calendar_tab.dart
    │   ├── insights_tab.dart
    │   └── profile_settings_tab.dart
    └── utils/
        └── mock_data.dart
```

---

## How to Run

1. Ensure the Flutter SDK is installed and on your PATH:
   ```bash
   flutter --version
   ```
2. Get dependencies:
   ```bash
   flutter pub get
   ```
3. Run on your connected device, Android emulator, iOS simulator, or Chrome:
   ```bash
   flutter run
   ```

---

## Backend & Integration Guide

- **Supabase / FastAPI**:
  - Replace `MockData.initialTasks` in `AppStateProvider` with async repository calls (`supabase.from('tasks').select()`).
  - Send feedback logs to your learning endpoint (`POST /api/v1/feedback`).
- **Google Calendar**:
  - Wire `google_sign_in` and Google Calendar API to populate `schedule` alongside personal tasks.
- **HealthKit / Health Connect**:
  - Read `sleepDuration` and `activityMinutes` using `health` or `flutter_health_connect` package to update `PersonalData` automatically every morning.
