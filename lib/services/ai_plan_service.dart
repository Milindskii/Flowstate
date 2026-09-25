import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/ai_plan_models.dart';
import '../models/pricing_config.dart';
import 'api_service.dart';

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
  }) async {
    final cleanInput = rawText.trim();
    if (cleanInput.isEmpty) {
      return const AIPlanResult(tasks: []);
    }

    // Context minimization: only raw brain dump, current date, and local timezone name
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final tzName = now.timeZoneName;

    final key = idempotencyKey ?? 'idemp-${now.millisecondsSinceEpoch}-${cleanInput.hashCode}';

    try {
      final response = await api.post(
        '/api/v1/ai/plan',
        body: {
          'raw_text': cleanInput,
          'user_timezone': tzName,
          'current_date': todayStr,
          'consume_shield': consumeShield,
          'idempotency_key': key,
        },
      );

      if (response is Map<String, dynamic>) {
        return AIPlanResult.fromJson(response);
      }
      throw const ApiException('Invalid plan response from server');
    } on ApiException catch (e) {
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
          message: 'AI planning limit reached for this hour (5 requests/hour max). Please wait a moment.',
          code: 'RATE_LIMITED',
        );
      }
      rethrow;
    }
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
        return response
            .whereType<Map<String, dynamic>>()
            .map<ProPlanConfig>((p) => ProPlanConfig(
                  id: p['id'] as String? ?? 'monthly',
                  title: p['name'] as String? ?? (p['title'] as String? ?? 'Monthly'),
                  displayPrice: p['display_price'] as String? ?? '₹— / month',
                  billingPeriod: p['billing_period'] as String? ?? 'monthly',
                  isBestValue: p['is_best_value'] as bool? ?? false,
                  status: p['pricing_note'] as String? ?? 'pricing_coming_soon',
                ))
            .toList();
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
