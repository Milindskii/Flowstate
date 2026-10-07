import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Custom Exception for Flowstate API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  /// True when the client gave up waiting (as opposed to a refused connection or a server error).
  final bool isTimeout;

  const ApiException(this.message, {this.statusCode, this.data, this.isTimeout = false});

  @override
  String toString() => 'ApiException(status: $statusCode, message: $message)';
}

/// Centralized API Service
/// Handles dynamic device URL routing, authorization headers, timeouts, and JSON serialization.
class ApiService {
  static const String _defaultLanIp = '192.168.1.9';
  static const String _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  final http.Client _client;
  String? _authToken;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Determine the appropriate backend URL depending on the runtime platform
  String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    try {
      if (Platform.isAndroid) {
        // Android emulator connects to host computer on 10.0.2.2
        return 'http://10.0.2.2:8000';
      }
      if (Platform.isIOS) {
        return 'http://$_defaultLanIp:8000';
      }
    } catch (_) {
      // Platform check unavailable (e.g. web fallback)
    }
    return 'http://127.0.0.1:8000';
  }

  void setAuthToken(String? token) {
    _authToken = token;
  }

  /// Returns the current active token.
  /// Prefers the live Supabase session access token when available so that
  /// token refreshes are immediately respected and stale cached tokens
  /// cannot override the live session.
  /// Falls back to cached [_authToken] for manual tokens, mock clients, or testing.
  String? get activeToken {
    String? token;
    try {
      token = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      // Supabase uninitialized or platform error
    }
    if (token == null || token.isEmpty) {
      token = _authToken;
    }
    return (token != null && token.isNotEmpty) ? token : null;
  }

  /// Whether a valid authentication token is currently available
  bool get isAuthenticated => activeToken != null;

  Map<String, String> _headers({Map<String, String>? extra}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = activeToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) async {
    Uri uri = Uri.parse('$baseUrl$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected network error: $e');
    }
  }

  /// Endpoints that legitimately outlast the default: /ai/plan walks Gemini's fallback chain server-side
  /// (up to 3 models x 12s), so the client must wait longer than that or it reports a timeout for a call
  /// the server is still completing.
  static const Duration _defaultPostTimeout = Duration(seconds: 12);
  static const Duration _aiPlanPostTimeout = Duration(seconds: 45);
  /// Replan may read the message with the language model (server deadline 25 s) before planning.
  static const Duration _replanPostTimeout = Duration(seconds: 30);

  @visibleForTesting
  static Duration postTimeoutFor(String endpoint) {
    if (endpoint.startsWith('/api/v1/ai/plan')) return _aiPlanPostTimeout;
    if (endpoint.startsWith('/api/v1/ai/replan') || endpoint.startsWith('/api/v1/calendar/replan')) {
      return _replanPostTimeout;
    }
    return _defaultPostTimeout;
  }

  Future<dynamic> post(String endpoint, {dynamic body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .post(
            uri,
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(postTimeoutFor(endpoint));
      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out. Please try again.', isTimeout: true);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected network error: $e');
    }
  }

  Future<dynamic> put(String endpoint, {dynamic body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .put(
            uri,
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected network error: $e');
    }
  }

  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .patch(
            uri,
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 12));
      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected network error: $e');
    }
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .delete(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network connection failed: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected network error: $e');
    }
  }

  dynamic _handleResponse(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    String message = 'Request failed with status ${response.statusCode}';
    if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
      message = decoded['detail'].toString();
    }
    throw ApiException(message, statusCode: response.statusCode, data: decoded);
  }
}
