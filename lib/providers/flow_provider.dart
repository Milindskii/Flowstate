import 'dart:async';
import 'package:flutter/material.dart';
import '../models/flow_companion.dart';
import '../models/flow_profile.dart';
import '../models/flow_challenge.dart';
import '../models/flow_daily_quest.dart';
import '../models/flow_achievement.dart';
import '../models/flow_overview.dart';
import '../services/flow_service.dart';
import '../services/api_service.dart';
import '../components/companion/flow_companion_animation_controller.dart';

/// Central state provider for the Flow Companion Simulator & Progression Economy.
/// Coordinates UI state, the server-owned focus session lifecycle, and the
/// decoupled animation controller.
class FlowProvider extends ChangeNotifier {
  final FlowService flowService;
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
      : flowService = service ?? FlowService(api: api ?? ApiService()) {
    loadOverview();
    loadShopCatalog();
  }

  FlowOverview get overview => _overview;
  FlowCompanion get companion => _overview.companion;
  FlowProfile get profile => _overview.profile;
  FlowChallenge? get activeChallenge => _overview.activeChallenge;
  List<FlowDailyQuest> get dailyQuests => _overview.dailyQuests;
  List<FlowAchievement> get achievements => _overview.achievements;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String? get activeSessionId => _activeSessionId;
  String? get activeTaskId => _activeTaskId;
  String? get activeTaskTitle => _activeTaskTitle;
  bool get isFocusing => _activeSessionId != null;
  int get sessionElapsedSeconds => _sessionElapsedSeconds;
  List<Map<String, dynamic>> get shopCatalog => List.unmodifiable(_shopCatalog);
  String? get latestNotification => _latestNotification;

  bool _mockMode = false;

  Future<void> loadOverview() async {
    if (_mockMode) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
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
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to sync progression state.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadShopCatalog() async {
    try {
      final items = await flowService.getShopCatalog();
      if (items.isNotEmpty) {
        _shopCatalog = items;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Initiates server-owned focus session
  Future<void> startSession({String? taskId, String? taskTitle}) async {
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
        final mins = _sessionElapsedSeconds ~/ 60;
        animController.setFocusing(taskTitle: _activeTaskTitle, elapsedMinutes: mins);
        notifyListeners();
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

      await loadOverview();
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
  Future<bool> evolveCompanion() async {
    try {
      final updated = await flowService.evolveCompanion();
      _overview = FlowOverview(
        companion: updated,
        profile: _overview.profile,
        activeChallenge: _overview.activeChallenge,
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
  Future<bool> claimChallenge(String challengeId) async {
    try {
      await flowService.claimChallenge(challengeId);
      await loadOverview();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Claims daily quest reward
  Future<bool> claimDailyQuest(String questId) async {
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
  Future<Map<String, dynamic>> purchaseCompanion(String species) async {
    final result = await flowService.purchaseCompanion(species);
    // Reload overview so balance and shop ownership update atomically
    await loadOverview();
    // Reload shop catalog with updated ownership
    await loadShopCatalog();
    animController.triggerSuccess(message: result['message'] as String? ?? 'Companion unlocked!');
    return result;
  }

  /// User-confirmed streak shield activation
  Future<bool> useStreakShield() async {
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
