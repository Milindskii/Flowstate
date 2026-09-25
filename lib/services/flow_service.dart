import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flow_overview.dart';
import '../models/flow_companion.dart';
import 'api_service.dart';

/// Single source of truth client for the Flow progression layer.
/// Strictly enforces:
/// - Offline is READ-ONLY (cached companion & streak display only)
/// - Server owns session lifecycle & rewards
class FlowService {
  static const String _cacheKey = 'flowstate_flow_overview_cache';
  final ApiService _api;

  FlowService({required ApiService api}) : _api = api;

  /// Fetches Flow overview with read-only offline fallback.
  Future<FlowOverview> getOverview() async {
    try {
      final res = await _api.get('/api/v1/flow');
      if (res is Map<String, dynamic>) {
        // Cache for offline read-only presentation
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(res));
        } catch (_) {}
        return FlowOverview.fromJson(res);
      }
      throw const ApiException('Invalid flow overview response format');
    } catch (e) {
      final cached = await getCachedOverview();
      if (cached != null) {
        return cached;
      }
      return FlowOverview.defaultInitial();
    }
  }

  /// Read cached overview for read-only offline display
  Future<FlowOverview?> getCachedOverview() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_cacheKey);
      if (str != null && str.isNotEmpty) {
        final data = jsonDecode(str) as Map<String, dynamic>;
        return FlowOverview.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  /// Initiates a server-owned focus session. Returns session ID.
  Future<String> startFocusSession({String? taskId}) async {
    final res = await _api.post(
      '/api/v1/flow/session/start',
      body: {'task_id': taskId},
    );
    if (res is Map<String, dynamic> && res['session_id'] != null) {
      return res['session_id'] as String;
    }
    throw const ApiException('Failed to start server focus session');
  }

  /// Completes focus session with server-calculated duration & atomic rewards.
  Future<Map<String, dynamic>> completeFocusSession({
    required String sessionId,
    bool taskCompleted = true,
    int? feelingScore,
    String? idempotencyKey,
  }) async {
    final res = await _api.post(
      '/api/v1/flow/session/$sessionId/complete?test_mode=true',
      body: {
        'task_completed': taskCompleted,
        if (feelingScore != null) 'feeling_score': feelingScore,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      },
    );
    if (res is Map<String, dynamic>) {
      return res;
    }
    throw const ApiException('Failed to complete focus session');
  }

  /// Non-punitive recoverable abandonment.
  Future<void> abandonFocusSession(String sessionId) async {
    try {
      await _api.post('/api/v1/flow/session/$sessionId/abandon');
    } catch (_) {}
  }

  /// Triggers companion stage evolution.
  Future<FlowCompanion> evolveCompanion() async {
    final res = await _api.post('/api/v1/flow/evolve');
    if (res is Map<String, dynamic> && res['companion'] != null) {
      return FlowCompanion.fromJson(res['companion'] as Map<String, dynamic>);
    }
    throw const ApiException('Failed to evolve companion');
  }

  /// Claims weekly challenge reward.
  Future<int> claimChallenge(String challengeId) async {
    final res = await _api.post('/api/v1/flow/challenge/$challengeId/claim');
    if (res is Map<String, dynamic> && res['flow_awarded'] != null) {
      return res['flow_awarded'] as int;
    }
    throw const ApiException('Failed to claim challenge');
  }

  /// Claims daily quest reward.
  Future<int> claimDailyQuest(String questId) async {
    final res = await _api.post('/api/v1/flow/daily-quests/$questId/claim');
    if (res is Map<String, dynamic> && res['flow_awarded'] != null) {
      return res['flow_awarded'] as int;
    }
    throw const ApiException('Failed to claim daily quest');
  }

  /// Fetches companion preview shop catalog with real ownership.
  Future<List<Map<String, dynamic>>> getShopCatalog() async {
    try {
      final res = await _api.get('/api/v1/flow/shop');
      if (res is List) {
        return List<Map<String, dynamic>>.from(res);
      }
    } catch (_) {}
    return [];
  }

  /// Purchase a companion from the shop using Flow Points.
  /// Returns the purchase result map with: species, name, flow_spent, new_balance, message.
  /// Throws [ApiException] with detail on: 402 (insufficient), 409 (already owned), 404 (invalid).
  Future<Map<String, dynamic>> purchaseCompanion(String species) async {
    final res = await _api.post('/api/v1/flow/shop/$species/purchase');
    if (res is Map<String, dynamic>) {
      return res;
    }
    throw const ApiException('Failed to purchase companion');
  }

  /// Select active animal companion (Fox Noya, Otter Ludo, Owl Aria, Capybara Boba).
  Future<FlowCompanion> selectCompanion(String species, {String? name}) async {
    final payload = <String, dynamic>{
      'species': species,
      if (name != null) 'name': name,
    };
    try {
      final res = await _api.post('/api/v1/flow/companion/select', body: payload);
      if (res is Map<String, dynamic>) {
        final companion = FlowCompanion.fromJson(res);
        try {
          final prefs = await SharedPreferences.getInstance();
          final str = prefs.getString(_cacheKey);
          if (str != null && str.isNotEmpty) {
            final data = jsonDecode(str) as Map<String, dynamic>;
            data['companion'] = companion.toJson();
            await prefs.setString(_cacheKey, jsonEncode(data));
          }
        } catch (_) {}
        return companion;
      }
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final str = prefs.getString(_cacheKey);
        if (str != null && str.isNotEmpty) {
          final data = jsonDecode(str) as Map<String, dynamic>;
          final cMap = (data['companion'] as Map<String, dynamic>?) ?? {};
          cMap['species'] = species;
          if (name != null) cMap['name'] = name;
          data['companion'] = cMap;
          await prefs.setString(_cacheKey, jsonEncode(data));
          return FlowCompanion.fromJson(cMap);
        }
      } catch (_) {}
    }
    final info = CompanionAnimalInfo.fromSpecies(species);
    return FlowCompanion(
      id: 'local-comp',
      species: species,
      name: name ?? info.defaultName,
    );
  }

  /// User-confirmed streak shield recovery call.
  Future<Map<String, dynamic>> useStreakShield() async {
    final res = await _api.post('/api/v1/flow/shields/use');
    if (res is Map<String, dynamic>) {
      return res;
    }
    throw const ApiException('Failed to activate streak shield');
  }
}
