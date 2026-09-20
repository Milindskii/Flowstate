import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/today_model.dart';
import 'api_service.dart';

/// Single source of truth service for the aggregated Today experience
class TodayService {
  static const String _cacheKey = 'flowstate_today_cache';
  final ApiService _api;

  TodayService({required ApiService api}) : _api = api;

  /// Fetches Today experience from backend, with cached offline fallback
  Future<TodayResponseModel> getTodayExperience() async {
    try {
      final res = await _api.get('/api/v1/today');
      if (res is Map<String, dynamic>) {
        final now = DateTime.now();
        res['cached_at'] = now.toIso8601String();
        // Persist to offline cache
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(res));
        } catch (_) {}

        return TodayResponseModel.fromJson(res, fetchedAt: now);
      }
      throw const ApiException('Invalid today response format');
    } catch (e) {
      // Offline fallback: try reading last-known cached Today payload
      final cached = await getCachedToday();
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  /// Retrieve last-known cached Today state if available
  Future<TodayResponseModel?> getCachedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(_cacheKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(cachedStr);
        DateTime? cachedAt;
        if (data['cached_at'] != null) {
          cachedAt = DateTime.tryParse(data['cached_at'].toString());
        }
        return TodayResponseModel.fromJson(data, fetchedAt: cachedAt ?? DateTime.now());
      }
    } catch (_) {}
    return null;
  }
}
