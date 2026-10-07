import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/providers/flow_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow Hub & ApiService Auth Wiring Tests', () {
    test('1. ApiService activeToken falls back to _authToken when Supabase is not active', () {
      final api = ApiService();
      expect(api.isAuthenticated, isFalse);
      expect(api.activeToken, isNull);

      api.setAuthToken('test-jwt-token-123');
      expect(api.isAuthenticated, isTrue);
      expect(api.activeToken, 'test-jwt-token-123');

      api.setAuthToken(null);
      expect(api.isAuthenticated, isFalse);
      expect(api.activeToken, isNull);
    });

    test('2. FlowProvider does NOT fire eager network requests from its constructor', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'error': 'should not be called'}), 500);
      });

      final api = ApiService(client: mockClient);
      final provider = FlowProvider(api: api);

      // Verify that no network calls were made synchronously during constructor
      expect(requestCount, 0);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.apiService, same(api));
    });

    test('3. FlowProvider.loadOverview() visibly sets error when wired with unauthenticated ApiService', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'detail': 'Not authenticated'}), 401);
      });

      final unauthApi = ApiService(client: mockClient);
      expect(unauthApi.isAuthenticated, isFalse);

      final provider = FlowProvider(api: unauthApi);
      await provider.loadOverview();

      // Because unauthApi is not authenticated, loadOverview immediately flags authentication error
      // without silently fabricating data
      expect(provider.errorMessage, 'Authentication required. Please sign in.');
      expect(provider.isLoading, isFalse);
      expect(requestCount, 0);
    });

    test('4. FlowProvider.loadOverview() sends Bearer token and updates overview when authenticated', () async {
      String? sentAuthHeader;
      final mockClient = MockClient((request) async {
        sentAuthHeader = request.headers['Authorization'];
        if (request.url.path == '/api/v1/flow') {
          return http.Response(
            jsonEncode({
              'companion': {
                'id': 'comp-1',
                'user_id': 'user-1',
                'name': 'NOYA',
                'species': 'fox',
                'stage': 'adult',
                'level': 5,
                'current_xp': 500,
                'target_xp': 1000,
                'mood': 'happy',
                'energy': 100,
                'is_evolution_ready': false,
              },
              'profile': {
                'id': 'prof-1',
                'user_id': 'user-1',
                'flow_balance': 120,
                'streak_shield_count': 2,
                'max_streak_shields': 3,
                'current_streak': 7,
                'longest_streak': 14,
              },
              'daily_quests': [],
              'achievements': [],
              'league_tier': 'Gold',
              'weekly_flow_points': 340,
              'personal_best_focus_minutes': 60,
              'weekly_focus_sessions': 8,
              'weekly_focus_minutes': 240,
              'total_focus_minutes': 1200,
              'total_sessions_completed': 42,
              'best_focus_day_minutes': 180,
              'consistency_score': 88,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/flow/shop/catalog') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('Not found', 404);
      });

      final authApi = ApiService(client: mockClient);
      authApi.setAuthToken('valid-session-jwt-token');
      expect(authApi.isAuthenticated, isTrue);

      final provider = FlowProvider(api: authApi);
      await provider.loadOverview();

      expect(sentAuthHeader, 'Bearer valid-session-jwt-token');
      expect(provider.errorMessage, isNull);
      expect(provider.companion.name, 'NOYA');
      expect(provider.companion.level, 5);
      expect(provider.profile.flowBalance, 120);
    });
  });
}
