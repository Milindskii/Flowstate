import '../models/ai_plan_models.dart';
import '../models/pricing_config.dart';
import 'api_service.dart';
import 'timezone_service.dart';

/// Exception thrown when AI economic limit is encountered (e.g. Free AI used up, Shield required)
class AIEconomyException implements Exception {
  final String message;
  final String code; // 'SHIELD_REQUIRED', 'QUOTA_EXHAUSTED', 'RATE_LIMITED'
  final int shieldsAvailable;

  const AIEconomyException({
    required this.message,
    required this.code,
    this.shieldsAvailable = 0,
  });

  @override
  String toString() => message;
}

/// Build My Day AI planning failed. [code] is the server's failure_code (spec 2026-10-03 §7):
/// gemini_error, provider_unavailable, provider_quota, provider_auth, model_not_found, timeout, network,
/// malformed, empty, scheduling_failed, quota_exhausted, privacy_declined, auth_required, plus the AI gateway's
/// ai_busy, rate_limited, request_in_progress, another_request_in_flight, pro_cap_day, pro_cap_month, and two
/// client-side codes: offline (the request never reached Flowstate's server) and server_error (a 5xx with no
/// failure_code). offline/server_error are Flowstate connectivity, never an AI-provider problem.
class AIPlanFailure implements Exception {
  final String code;
  final String message;
  const AIPlanFailure(this.code, this.message);

  @override
  String toString() => 'AIPlanFailure($code): $message';
}

/// Service interfacing with FastAPI Gemini task understanding and AI economy endpoints.
class AIPlanService {
  final ApiService api;

  const AIPlanService({required this.api});

  /// Check server-owned AI usage status and entitlement
  Future<AIUsageStatus> getUsageStatus() async {
    try {
      final response = await api.get('/api/v1/ai/status');
      if (response is Map<String, dynamic>) {
        return AIUsageStatus.fromJson(response);
      }
    } catch (_) {
      // Offline fallback: assume safe initial defaults
    }
    return AIUsageStatus.defaultFreeInitial();
  }

  /// Request Gemini task structuring from raw user notes with strict JSON validation & economy enforcement.
  Future<AIPlanResult> generatePlan({
    required String rawText,
    bool consumeShield = false,
    String? idempotencyKey,
    String? requestId,
  }) async {
    final cleanInput = rawText.trim();
    if (cleanInput.isEmpty) {
      return const AIPlanResult(tasks: []);
    }

    // Context minimization: only the raw brain dump, the client clock, and the IANA timezone.
    // The timezone is omitted (never an abbreviation) when it cannot be determined, so the
    // backend uses the user's stored preference instead of silently falling back to UTC.
    final now = DateTime.now();
    final tzName = await TimezoneService.localIanaName();

    // One stable request id per brain dump: "Retry with AI" reuses it, so the server charges once.
    final key = requestId ?? idempotencyKey ?? 'idemp-${now.millisecondsSinceEpoch}-${cleanInput.hashCode}';

    try {
      final response = await api.post(
        '/api/v1/ai/plan',
        body: {
          'raw_text': cleanInput,
          if (tzName != null) 'timezone': tzName,
          'current_local_time': now.toUtc().toIso8601String(),
          'consume_shield': consumeShield,
          'idempotency_key': key,
        },
      );

      if (response is Map<String, dynamic>) {
        return AIPlanResult.fromJson(response);
      }
      throw const ApiException('Invalid plan response from server');
    } on ApiException catch (e) {
      final data = e.data is Map<String, dynamic> ? e.data as Map<String, dynamic> : const <String, dynamic>{};
      final failureCode = data['failure_code'] as String?;
      final detail = data['detail'];
      final message = detail is String ? detail : e.message;
      if (failureCode != null) {
        throw AIPlanFailure(failureCode, message);
      }
      if (e.statusCode == 401 || e.statusCode == 403) {
        // Not signed in (or the session ended): an account problem, never an AI-provider one.
        throw AIPlanFailure('auth_required', message);
      }
      if (e.isTimeout) {
        throw AIPlanFailure('timeout', message);
      }
      if (e.statusCode == null || e.statusCode == 0) {
        // Connection refused / no network: Flowstate's own server was never reached, so the AI was never involved.
        throw AIPlanFailure('offline', message);
      }
      if (e.statusCode! >= 500) {
        throw AIPlanFailure('server_error', message);
      }
      if (e.statusCode == 402) {
        final data = e.data is Map<String, dynamic> ? e.data as Map<String, dynamic> : {};
        final detail = data['detail'];
        String code = 'QUOTA_EXHAUSTED';
        int shields = 0;
        if (detail is Map<String, dynamic>) {
          code = detail['code'] as String? ?? 'QUOTA_EXHAUSTED';
          shields = detail['shields_available'] as int? ?? 0;
        }
        throw AIEconomyException(
          message: e.message,
          code: code,
          shieldsAvailable: shields,
        );
      } else if (e.statusCode == 429) {
        throw const AIEconomyException(
          message: 'AI planning limit reached for now. Please wait a moment.',
          code: 'RATE_LIMITED',
        );
      }
      rethrow;
    }
  }

  static const _reportableCodes = {'privacy_declined', 'gemini_error', 'input_too_long', 'client_error'};

  /// Diagnostics for failures that never reach the server's Gemini call (privacy declined,
  /// network error). Never blocks the UI and never charges.
  Future<void> reportFailure(String requestId, String code, [String? reason]) async {
    try {
      await api.post('/api/v1/ai/planning-attempts', body: {
        'request_id': requestId,
        // The server accepts a fixed set of codes (a 422 here used to drop the report silently).
        'failure_code': _reportableCodes.contains(code) ? code : 'client_error',
        if (reason != null) 'failure_reason': reason,
      });
    } catch (_) {}
  }

  /// Get Pro subscription status from backend
  Future<SubscriptionStatus> getSubscriptionStatus() async {
    try {
      final response = await api.get('/api/v1/subscription/status');
      if (response is Map<String, dynamic>) {
        return SubscriptionStatus.fromJson(response);
      }
    } catch (_) {}
    return const SubscriptionStatus(
      isPro: false,
      subscriptionTier: 'free',
      status: 'inactive',
    );
  }

  /// Centralized catalog of Pro plans from backend
  Future<List<ProPlanConfig>> getProPlans() async {
    try {
      final response = await api.get('/api/v1/subscription/plans');
      if (response is List) {
        final plans = response.whereType<Map<String, dynamic>>().map<ProPlanConfig>(ProPlanConfig.fromJson).toList();
        if (plans.isNotEmpty) return plans;
      }
    } catch (_) {}
    return ProPlanConfig.defaultPlans;
  }

  /// Authoritative backend verification of Google Play subscription purchase
  Future<bool> verifySubscriptionPurchase({
    required String purchaseToken,
    required String productId,
    required String orderId,
  }) async {
    try {
      final response = await api.post(
        '/api/v1/subscription/verify',
        body: {
          'purchase_token': purchaseToken,
          'product_id': productId,
          'order_id': orderId,
        },
      );
      if (response is Map<String, dynamic>) {
        return response['is_pro'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  /// Authoritative backend verification of streak recovery purchase (₹50)
  Future<bool> verifyStreakRecoveryPurchase({
    required String purchaseToken,
    required String orderId,
  }) async {
    try {
      final response = await api.post(
        '/api/v1/subscription/streak-recover',
        body: {
          'purchase_token': purchaseToken,
          'order_id': orderId,
        },
      );
      if (response is Map<String, dynamic>) {
        return response['streak_recovered'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }
}
