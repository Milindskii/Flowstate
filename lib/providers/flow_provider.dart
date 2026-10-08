import '../components/noya_notice.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/single_flight.dart';
import '../models/flow_companion.dart';
import '../models/flow_profile.dart';
import '../models/flow_challenge.dart';
import '../models/flow_daily_quest.dart';
import '../models/flow_achievement.dart';
import '../models/flow_overview.dart';
import '../services/flow_service.dart';
import '../services/api_service.dart';
import '../components/companion/flow_companion_animation_controller.dart';
import '../utils/friendly_error.dart';

/// Central state provider for the Flow Companion Simulator & Progression Economy.
/// Coordinates UI state, the server-owned focus session lifecycle, and the
/// decoupled animation controller.
class FlowProvider extends ChangeNotifier {
  /// Rapid repeated taps on the same action become ONE request (a second call shares the first one's result).
  final SingleFlight _flight = SingleFlight();

  final FlowService flowService;
  final ApiService? apiService;
  final FlowCompanionAnimationController animController = FlowCompanionAnimationController();

  FlowOverview _overview = FlowOverview.defaultInitial();
  bool _isLoading = false;
  String? _errorMessage;

  String? _activeSessionId;
  String? _activeTaskId;
  String? _activeTaskTitle;
  int _sessionElapsedSeconds = 0;
  Timer? _sessionTimer;

  List<Map<String, dynamic>> _shopCatalog = [];
  String? _latestNotification;

  FlowProvider({FlowService? service, ApiService? api})
      : apiService = api,
        flowService = service ?? FlowService(api: api ?? ApiService()) {
    // Eager constructor network calls removed to ensure authenticated
    // dependency wiring is ready before firing network requests.
    // UI lifecycle (FlowScreen.initState) initiates loading when auth is ready.
  }

  FlowOverview get overview => _overview;
  FlowCompanion get companion => _overview.companion;
  FlowProfile get profile => _overview.profile;
  FlowChallenge? get activeChallenge => _overview.activeChallenge;
  List<FlowDailyQuest> get dailyQuests => _overview.dailyQuests;
  List<FlowAchievement> get achievements => _overview.achievements;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  static const String authRequiredMessage = 'Authentication required. Please sign in.';

  /// The Hub can't sync because nobody is signed in (not a failure to show as an error).
  bool get isAuthRequired => _errorMessage == authRequiredMessage;

  String? get activeSessionId => _activeSessionId;
  String? get activeTaskId => _activeTaskId;
  String? get activeTaskTitle => _activeTaskTitle;
  bool get isFocusing => _activeSessionId != null;
  int get sessionElapsedSeconds => _sessionElapsedSeconds;
  List<Map<String, dynamic>> get shopCatalog => List.unmodifiable(_shopCatalog);
  String? get latestNotification => _latestNotification;

  bool _mockMode = false;

  void setMockMode(bool enabled) {
    _mockMode = enabled;
  }

  /// Optimistically increments daily quest and weekly challenge progress on local task completion
  void recordTaskCompletionLocally({bool isPriority = false}) {
    final updatedQuests = _overview.dailyQuests.map((q) {
      if (q.questKey == 'finish_2_tasks' && !q.isCompleted) {
        final newCount = (q.currentCount + 1).clamp(0, q.targetCount);
        return FlowDailyQuest(
          id: q.id,
          questDate: q.questDate,
          questKey: q.questKey,
          title: q.title,
          description: q.description,
          targetCount: q.targetCount,
          currentCount: newCount,
          rewardFlow: q.rewardFlow,
          isCompleted: newCount >= q.targetCount,
          isClaimed: q.isClaimed,
        );
      }
      return q;
    }).toList();

    _overview = _overview.copyWith(
      dailyQuests: updatedQuests,
      totalSessionsCompleted: _overview.totalSessionsCompleted + 1,
      weeklyQuests: _overview.weeklyQuests.map((w) {
        if (isPriority && w.challengeType == 'priority_tasks' && !w.isCompleted) {
          final n = (w.currentCount + 1).clamp(0, w.targetCount);
          return w.copyWith(currentCount: n, isCompleted: n >= w.targetCount);
        }
        return w;
      }).toList(),
      activeChallenge: (isPriority &&
              _overview.activeChallenge != null &&
              !_overview.activeChallenge!.isCompleted)
          ? FlowChallenge(
              id: _overview.activeChallenge!.id,
              weekIdentifier: _overview.activeChallenge!.weekIdentifier,
              title: _overview.activeChallenge!.title,
              targetCount: _overview.activeChallenge!.targetCount,
              currentCount: (_overview.activeChallenge!.currentCount + 1)
                  .clamp(0, _overview.activeChallenge!.targetCount),
              isCompleted: (_overview.activeChallenge!.currentCount + 1) >=
                  _overview.activeChallenge!.targetCount,
              rewardFlow: _overview.activeChallenge!.rewardFlow,
              challengeType: _overview.activeChallenge!.challengeType,
            )
          : _overview.activeChallenge,
    );

    // Save to SharedPreferences cache for offline & restart resilience
    try {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('flowstate_flow_overview_cache', jsonEncode(_overview.toJson()));
      }).catchError((_) {});
    } catch (_) {}

    notifyListeners();
  }

  /// Quests that are finished but not yet claimed (daily + weekly).
  int _claimableQuestCount() =>
      _overview.dailyQuests.where((q) => q.isCompleted && !q.isClaimed).length +
      _overview.weeklyQuests.where((q) => q.isCompleted && !q.isClaimed).length;

  Future<void> loadOverview() async {
    if (_mockMode) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // If an authenticated ApiService was wired and is not authenticated,
      // fail visibly rather than silently fabricating default progression data.
      if (apiService != null && !apiService!.isAuthenticated) {
        _errorMessage = 'Authentication required. Please sign in.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final res = await flowService.getOverview();
      if (_mockMode) return;
      _overview = res;
      _activeSessionId = res.activeSessionId;
      _latestNotification = res.notification;

      if (_activeSessionId != null) {
        animController.setFocusing();
      } else if (res.companion.isEvolutionReady) {
        animController.triggerEvolution();
      } else {
        animController.setIdle();
      }
      _isLoading = false;
      // Lazily load shop catalog on first overview sync if empty
      if (_shopCatalog.isEmpty) {
        unawaited(loadShopCatalog());
      }
      notifyListeners();
    } on ApiException catch (e) {
      _errorMessage = e.statusCode == 401
          ? 'Authentication required. Please sign in.'
          : friendlyActionError(e, fallback: "Your progress couldn't sync right now. Pull down to try again.");
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to sync progression state.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadShopCatalog() async {
    if (_mockMode) return;
    if (apiService != null && !apiService!.isAuthenticated) return;
    try {
      final items = await flowService.getShopCatalog();
      if (items.isNotEmpty) {
        _shopCatalog = items;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Initiates server-owned focus session
  Future<void> startSession({String? taskId, String? taskTitle}) =>
      _flight.run('start-session', () => _startSession(taskId: taskId, taskTitle: taskTitle));

  Future<void> _startSession({String? taskId, String? taskTitle}) async {
    try {
      final sessionId = await flowService.startFocusSession(taskId: taskId);
      _activeSessionId = sessionId;
      _activeTaskId = taskId;
      _activeTaskTitle = taskTitle;
      _sessionElapsedSeconds = 0;

      animController.setFocusing(taskTitle: taskTitle);

      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _sessionElapsedSeconds++;
        // Listeners (Flow hub, shield dialog) show minutes: notify once a minute, not every second.
        if (_sessionElapsedSeconds % 60 == 0) {
          final mins = _sessionElapsedSeconds ~/ 60;
          animController.setFocusing(taskTitle: _activeTaskTitle, elapsedMinutes: mins);
          notifyListeners();
        }
      });
      notifyListeners();
    } catch (e) {
      // If server unreachable or error, timer does not start
      rethrow;
    }
  }

  /// Completes focus session with server-calculated duration and atomic rewards
  Future<Map<String, dynamic>> completeSession({
    bool taskCompleted = true,
    int? feelingScore,
    String? idempotencyKey,
  }) =>
      _flight.run(
        'complete-session',
        () => _completeSession(taskCompleted: taskCompleted, feelingScore: feelingScore, idempotencyKey: idempotencyKey),
      );

  Future<Map<String, dynamic>> _completeSession({
    bool taskCompleted = true,
    int? feelingScore,
    String? idempotencyKey,
  }) async {
    if (_activeSessionId == null) {
      throw Exception('No active focus session to complete');
    }

    _sessionTimer?.cancel();
    final sid = _activeSessionId!;

    try {
      final res = await flowService.completeFocusSession(
        sessionId: sid,
        taskCompleted: taskCompleted,
        feelingScore: feelingScore,
        idempotencyKey: idempotencyKey,
      );

      _activeSessionId = null;
      _activeTaskId = null;
      _activeTaskTitle = null;
      _sessionElapsedSeconds = 0;

      if (res['notification'] != null) {
        _latestNotification = res['notification'] as String?;
      }

      animController.triggerSuccess(
        message: 'Session Complete! +${res['xp_awarded']} XP · +${res['flow_awarded']} Flow',
      );

      final before = _claimableQuestCount();
      await loadOverview();
      final milestone = milestoneFromSession(res);
      if (milestone != null) {
        NoyaNoticeCenter.instance.show(milestone);
      } else if (_claimableQuestCount() > before) {
        NoyaNoticeCenter.instance.show(const NoyaNotice(NoticeKind.questComplete, 'A quest is ready to claim.',
            title: 'Quest complete'));
      }
      return res;
    } catch (e) {
      _activeSessionId = null;
      _sessionTimer?.cancel();
      animController.setIdle();
      notifyListeners();
      rethrow;
    }
  }

  /// Recoverable abandonment
  Future<void> abandonSession() async {
    if (_activeSessionId == null) return;
    _sessionTimer?.cancel();
    final sid = _activeSessionId!;
    _activeSessionId = null;
    _activeTaskId = null;
    _activeTaskTitle = null;
    _sessionElapsedSeconds = 0;

    animController.setTired(message: 'Resting. Protect your progress tomorrow.');
    notifyListeners();

    await flowService.abandonFocusSession(sid);
  }

  /// Triggers companion stage evolution
  Future<bool> evolveCompanion() => _flight.run('evolve', _evolveCompanion);

  Future<bool> _evolveCompanion() async {
    try {
      final updated = await flowService.evolveCompanion();
      _overview = FlowOverview(
        companion: updated,
        profile: _overview.profile,
        activeChallenge: _overview.activeChallenge,
        weeklyQuests: _overview.weeklyQuests,
        dailyQuests: _overview.dailyQuests,
        achievements: _overview.achievements,
        leagueTier: _overview.leagueTier,
        weeklyFlowPoints: _overview.weeklyFlowPoints,
        leagueStatusMessage: _overview.leagueStatusMessage,
        personalBestFocusMinutes: _overview.personalBestFocusMinutes,
        weeklyFocusSessions: _overview.weeklyFocusSessions,
        weeklyFocusMinutes: _overview.weeklyFocusMinutes,
        totalFocusMinutes: _overview.totalFocusMinutes,
        totalSessionsCompleted: _overview.totalSessionsCompleted,
        bestFocusDayMinutes: _overview.bestFocusDayMinutes,
        consistencyScore: _overview.consistencyScore,
        rhythmAcknowledgement: _overview.rhythmAcknowledgement,
      );
      animController.triggerSuccess(message: 'Evolution complete! Noya reached ${updated.stage} stage.');
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Claims weekly challenge reward
  Future<bool> claimChallenge(String challengeId) =>
      _flight.run('claim-weekly-$challengeId', () => _claimChallenge(challengeId));

  Future<bool> _claimChallenge(String challengeId) async {
    try {
      await flowService.claimChallenge(challengeId);
      await loadOverview();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Claims daily quest reward
  Future<bool> claimDailyQuest(String questId) =>
      _flight.run('claim-daily-$questId', () => _claimDailyQuest(questId));

  Future<bool> _claimDailyQuest(String questId) async {
    try {
      await flowService.claimDailyQuest(questId);
      await loadOverview();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Select active animal companion (Fox Noya, Otter Ludo, Owl Aria, Capybara Boba)
  Future<bool> selectCompanion(String species, {String? name}) async {
    try {
      final updated = await flowService.selectCompanion(species, name: name);
      _overview = FlowOverview(
        companion: updated,
        profile: _overview.profile,
        activeChallenge: _overview.activeChallenge,
        weeklyQuests: _overview.weeklyQuests,
        dailyQuests: _overview.dailyQuests,
        achievements: _overview.achievements,
        weeklyProgress: _overview.weeklyProgress,
        leagueTier: _overview.leagueTier,
        weeklyFlowPoints: _overview.weeklyFlowPoints,
        leagueStatusMessage: _overview.leagueStatusMessage,
        personalBestFocusMinutes: _overview.personalBestFocusMinutes,
        weeklyFocusSessions: _overview.weeklyFocusSessions,
        weeklyFocusMinutes: _overview.weeklyFocusMinutes,
        totalFocusMinutes: _overview.totalFocusMinutes,
        totalSessionsCompleted: _overview.totalSessionsCompleted,
        bestFocusDayMinutes: _overview.bestFocusDayMinutes,
        consistencyScore: _overview.consistencyScore,
        rhythmAcknowledgement: _overview.rhythmAcknowledgement,
      );
      animController.triggerSuccess(message: '${updated.name} is now your active companion!');
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Purchase a companion from the Flow Shop using Flow Points.
  /// Returns a result map with keys: species, name, flow_spent, new_balance, message.
  /// Throws on error so the UI can display the specific reason.
  Future<Map<String, dynamic>> purchaseCompanion(String species) =>
      _flight.run('purchase-$species', () => _purchaseCompanion(species));

  Future<Map<String, dynamic>> _purchaseCompanion(String species) async {
    final result = await flowService.purchaseCompanion(species);
    // Reload overview so balance and shop ownership update atomically
    await loadOverview();
    // Reload shop catalog with updated ownership
    await loadShopCatalog();
    animController.triggerSuccess(message: result['message'] as String? ?? 'Companion unlocked!');
    return result;
  }

  /// User-confirmed streak shield activation
  Future<bool> useStreakShield() => _flight.run('use-shield', _useStreakShield);

  Future<bool> _useStreakShield() async {
    try {
      final res = await flowService.useStreakShield();
      if (res['success'] == true) {
        await loadOverview();
        animController.triggerSuccess(message: 'Shield activated! Streak protected.');
        return true;
      }
    } catch (_) {}
    return false;
  }

  void clearNotification() {
    _latestNotification = null;
    notifyListeners();
  }

  /// Wipes in-memory companion progression state on user logout or account switch
  void reset() {
    _overview = FlowOverview.defaultInitial();
    _activeSessionId = null;
    _activeTaskId = null;
    _activeTaskTitle = null;
    _sessionElapsedSeconds = 0;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _errorMessage = null;
    _shopCatalog = [];
    _latestNotification = null;
    animController.setIdle();
    notifyListeners();
  }

  @visibleForTesting
  void setOverviewForTesting(FlowOverview overview) {
    _mockMode = true;
    _overview = overview;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    animController.dispose();
    super.dispose();
  }
}
