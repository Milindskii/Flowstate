# FLOWSTATE: QUESTIONNAIRE → PERSONAL PLANNING PROFILE → SCHEDULER AUDIT

**Audit Date**: September 27, 2026  
**System**: Flowstate Cognitive Architecture & Deterministic Scheduler  
**Auditor**: Antigravity Pair-Programming Agent

---

## 1. Executive Summary & Verification Matrix

Every single onboarding questionnaire field was traced end-to-end through the complete data pipeline:
$$\text{Questionnaire UI} \longrightarrow \text{Saved State} \longrightarrow \text{Database} \longrightarrow \text{Backend Model} \longrightarrow \text{Planning Profile} \longrightarrow \text{Scheduler} \longrightarrow \text{Slot Generation} \longrightarrow \text{Slot Scoring} \longrightarrow \text{Final Recommended Time}$$

### Complete Questionnaire Field Tracking

| Questionnaire Field | Stored? | Used by Scheduler? | How It Affects Scheduling |
|---|---|---|---|
| **weekday_wake_time** (`wake_weekday`) | **Yes** (`readiness_profiles.weekday_wake_time`) | **Yes** | Sets daily start anchor for weekdays; enforces that no candidate slots begin before wake time. |
| **weekend_wake_time** (`wake_weekend`) | **Yes** (`readiness_profiles.weekend_wake_time`) | **Yes** | Sets day start anchor on weekend days (Sat/Sun); calculates schedule variability (`wake_variability`). |
| **bedtime** (`sleep_time`) | **Yes** (`readiness_profiles.bedtime`) | **Yes** | Enforces hard cutoff for daily slots and triggers **Sleep Protection**: non-deadline tasks near bedtime receive severe penalty (`-1.00`) and roll over to tomorrow. |
| **wake-up warmup duration** (`sleep_inertia`) | **Yes** (`readiness_profiles.sleep_inertia_minutes`) | **Yes** | Enforces **Cognitive Warmup Protection**: demanding work (coding, deep work) is blocked/penalized (`-0.85`) between wake time and `wake_time + warmup_minutes`. |
| **strongest work window** (`peak_window`) | **Yes** (`readiness_profiles.preferred_peak_start`, `preferred_peak_end`) | **Yes** | Allocates strong fit bonus (`+0.45`) to cognitively demanding tasks inside this window; guides next-day morning recommendations. |
| **cognitively demanding task types** (`draining_work`) | **Yes** (`readiness_profiles.draining_work_types`) | **Yes** | Tasks matching user's declared draining types (e.g. coding, problem solving) receive cognitive treatment: peak window preference, warmup protection, and late fatigue avoidance. |
| **behavior when tired** (`tired_reaction`) | **Yes** (`readiness_profiles.fatigue_symptom`) | **Yes** | Stored in `PlanningProfile.tired_behavior`; tightens late-evening fatigue penalties and post-session focus buffers. |
| **routine adaptation preference** (`schedule_shift_adaptation`) | **Yes** (`readiness_profiles.routine_shift_preference`) | **Yes** | Stored in `PlanningProfile.routine_shift_preference`; adjusts weekend/shifted schedule scoring (e.g. `slower_tempo` shifts peak window later; `lighter_work` penalizes heavy cognitive work). |
| **focus duration** (`focus_duration`) | **Yes** (`readiness_profiles.preferred_session_minutes`) | **Yes** (indirect) | Calibrates default task session duration and focus timer interval. |
| **energy predictability** (`energy_predictability`) | **Yes** (`readiness_profiles.energy_predictability`) | **Yes** (indirect) | Regulates Bayesian confidence calibration in the readiness engine and starting rhythm confidence. |
| **primary goal** (`primary_goal`) | **Yes** (`readiness_profiles.optimization_goal`) | **Yes** (indirect) | Informs starting rhythm summary and focus recommendations. |
| **work session disruptor** (`session_disruptor`) | **Yes** (onboarding payload) | **Unused by scheduler** | Used for companion nudges and ambient reflection insights; not an active constraint for time slots. |
| **schedule disruptors** (`schedule_disruptors`) | **Yes** (onboarding payload) | **Unused by scheduler** | Retained for user context and future adaptive triggers. |

---

## 2. Planning Profile Architecture

The scheduler accesses a unified, authoritative `PlanningProfile` combining baseline questionnaire responses with empirical performance data.

### Fields and Accessors in `PlanningProfile`
- `wake_time` / `weekday_wake_time`: Float hours (e.g., `7.0`)
- `weekend_wake_time`: Float hours (e.g., `8.5`)
- `bedtime`: Float hours (e.g., `23.0`)
- `peak_window_start` / `preferred_peak_start`: Float hours (e.g., `8.5`)
- `peak_window_end` / `preferred_peak_end`: Float hours (e.g., `12.0`)
- `warmup_minutes`: Integer minutes (e.g., `30`, `60`)
- `high_energy_task_types`: List of strings (e.g., `["coding", "problem_solving", "deep_work", "study"]`)
- `tired_behavior`: String (e.g., `"distracted"`, `"procrastinate"`, `"slower"`, `"mistakes"`)
- `routine_shift_preference`: String (e.g., `"quick_recovery"`, `"slower_tempo"`, `"lighter_work"`)
- `avg_duration_ratio`: Recency-weighted actual vs. estimated duration ratio
- `learned_afternoon_focus`: Boolean indicating empirical circadian shift

---

## 3. Scheduler Rules & Constraint Implementation

### A. Sleep Protection
- Stated bedtime is a strict constraint.
- When `now_local` is within 1 hour 15 minutes of bedtime (e.g., 10:15 PM when bedtime is 11:00 PM), non-deadline tasks receive a severe score penalty (`-1.00`, reason: `sleep_protection`).
- The scheduler automatically moves non-urgent tasks to tomorrow.

### B. Deadline Safety Override
- Imminent deadlines (e.g. tomorrow at 8:00 AM) override bedtime preference when finishing tonight is necessary.
- Evaluated as `requires_tonight_for_deadline`: tasks due before morning peak receive an urgent bonus (`+0.70`, reason: `deadline_imminent`, secondary: `deadline_safety_overrides_sleep`) and schedule tonight before bedtime.

### C. Cognitive Warmup Protection
- Wake time + warmup duration defines the warmup window (e.g., Wake 7:00 AM + Warmup 60m = 8:00 AM).
- Cognitively demanding tasks (coding, problem solving, study) scheduled during warmup receive a penalty (`-0.85`, reason: `during_cognitive_warmup`).
- The scheduler waits until the warmup concludes, preferring the user's peak window (e.g., 8:30 AM).

### D. Peak Window Matching
- Demanding tasks receive a strong personal-fit bonus (`+0.45`, reason: `peak_window`) inside `[preferred_peak_start, preferred_peak_end]`.
- Light/routine work (cleaning, emails) prefers afternoon dip windows (`14:00 - 15:30`, `+0.35`).
- Physical tasks (gym, workout) prefer morning (`7:00 - 9:30`) or late afternoon (`16:00 - 19:30`, `+0.40`).

### E. Current Time Influence vs. Fixed Anchoring
- Current time is an availability boundary, never a fake fixed time.
- Tasks without an explicit user-specified time remain flexible and are scheduled at the highest-scoring candidate slot.

### F. Priority Decoupling
- User priority is strictly preserved.
- When priority is omitted by the user, the UI displays `"Priority not specified"` (never silently defaulted to Medium).

---

## 4. Test Case Verification Results

All 6 required benchmark test cases were automated and verified via pytest:

### Case 1: Sleep Protection (Low Priority Cleaning)
- **Profile**: Wake 7:00 AM, Peak 8:30 AM–12:00 PM, Bed 11:00 PM
- **Current Time**: 10:15 PM
- **Task**: "clean desk", Priority: low, Duration: 20 min, No deadline
- **Result**: **PASSED**. Scheduler rejected tonight (day offset 0) and scheduled tomorrow (`day_offset = 1`). Explanation: *"Tomorrow at 2:00 PM — Moved to tomorrow to protect your sleep schedule and wind-down window."*

### Case 2: Demanding Work Future Window (Important Coding)
- **Profile**: Wake 7:00 AM, Peak 8:30 AM–12:00 PM, Bed 11:00 PM
- **Current Time**: 10:15 PM
- **Task**: "Important coding work", Priority: high, No deadline
- **Result**: **PASSED**. Scheduler scheduled tomorrow at 8:30 AM inside the peak window (`day_offset = 1`, `start_time = 8:30 AM`). Explanation: *"Tomorrow at 8:30 AM — That's one of your strongest focus windows with a clear uninterrupted block."*

### Case 3: Deadline Safety Overrides Sleep (Urgent Assignment)
- **Profile**: Wake 7:00 AM, Peak 8:30 AM–12:00 PM, Bed 11:00 PM
- **Current Time**: 10:15 PM
- **Task**: "Important assignment", Priority: high, Deadline: Tomorrow 8:00 AM
- **Result**: **PASSED**. Deadline safety overrode sleep wind-down. Task was scheduled tonight at 10:15 PM (`day_offset = 0`, finishing before 11:00 PM). Reason: `deadline_imminent` with `deadline_safety_overrides_sleep`.

### Case 4: Cognitive Warmup Protection (Coding at 7 AM)
- **Profile**: Wake 7:00 AM, Warmup 60 min, Peak 8:30 AM–12:00 PM
- **Current Time**: 6:45 AM
- **Task**: "Coding"
- **Result**: **PASSED**. Scheduler did not schedule at 7:00 AM during warmup. Scheduled at 8:30 AM in the post-warmup peak window.

### Case 5: Independent Tasks Around Meetings
- **Tasks**: Gym, Important coding work, Emails, Three meetings (10:00, 13:00, 15:30)
- **Result**: **PASSED**. Meetings were treated as hard obstacles. Coding was placed in the morning peak block (8:30 - 9:30 AM), Gym in physical window, Emails in admin opening. Zero collisions.

### Case 6: Brain Dump Clause Splitting ("gym work assignment")
- **Input**: `"gym work assignment"`
- **Result**: **PASSED**. Extracted exactly 3 independent tasks: `["Gym", "Work", "Assignment"]`. Not one combined task.

---

## 5. Exact Code & Service Modifications

| File | Subsystem | Modifications |
|---|---|---|
| `backend/app/models/readiness_profile.py` | Database Model | Added persistent columns: `bedtime` (String), `draining_work_types` (String), `fatigue_symptom` (String), `routine_shift_preference` (String). |
| `backend/app/main.py` | Startup Sync | Added automated SQLite schema synchronizer to safely migrate existing databases with missing profile columns. |
| `backend/app/repositories/readiness_repository.py` | Data Access | Added `get_by_user_id = get_profile` method alias to resolve unhandled attribute error in AI planning route. |
| `backend/app/schemas/readiness.py` | API Contracts | Added `bedtime`, `draining_work_types`, `fatigue_symptom`, `routine_shift_preference` to `ReadinessProfileSchema` and `ReadinessOnboardingRequest`. |
| `backend/app/services/readiness_service.py` | Profile Service | Updated `create_or_update_profile` and `submit_onboarding_answers` to persist `bedtime`, `draining_work_types`, `fatigue_symptom`, and `routine_shift_preference`. |
| `backend/app/engines/scheduling_engine.py` | Backend Optimizer | 1. Implemented complete `PlanningProfile` with requested property aliases (`wake_time`, `peak_window_start`, `peak_window_end`).<br>2. Implemented recency-weighted historical learning from `TaskPerformance`.<br>3. Implemented Cognitive Warmup Protection (`-0.85` penalty during warmup).<br>4. Implemented Sleep Protection (`-1.00` penalty near bedtime for non-deadline tasks).<br>5. Implemented Deadline Safety Override (`+0.70` bonus tonight when deadline is tomorrow morning). |
| `lib/screens/onboarding_flow_screen.dart` | Flutter Client | Corrected payload mapping: mapped `sleep_inertia` and `focus_duration` into exact minutes; included `fatigue_symptom` and `routine_shift_preference`. |
| `lib/engines/scheduling_engine.dart` | Flutter Offline Scheduler | Added `PlanningProfile` mirror class and enhanced client-side candidate evaluation with sleep protection and warmup awareness. |
| `backend/tests/test_questionnaire_scheduler_audit.py` | Automated Tests | Created 8 comprehensive automated tests covering all 6 cases and the full questionnaire data path. |

---

## 6. Verification Status

- **Automated Backend Tests**: 100/100 tests passed (`pytest`).
- **Audit Specific Tests**: 8/8 tests passed.
- **Flutter Analyzer**: 0 errors, 0 warnings.
- **Remaining Bugs**: None.
- **Conclusion**: The entire questionnaire-to-scheduler data path is fully verified, wired, and enforced.
