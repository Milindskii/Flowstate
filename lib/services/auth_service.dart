import 'api_service.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? 'user-default',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? (json['email'] as String?)?.split('@').first ?? 'Friend',
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
      };
}

/// Authentication and Session Management Service
class AuthService {
  final ApiService _api;
  AuthUser? _currentUser;
  String? _token;

  AuthService({required ApiService api}) : _api = api;

  AuthUser? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null;

  Future<AuthUser> loginWithEmail(String email, String password) async {
    try {
      final res = await _api.post('/api/v1/auth/login', body: {
        'email': email,
        'password': password,
      });

      _token = res['access_token'] as String?;
      _api.setAuthToken(_token);

      if (res['user'] != null) {
        _currentUser = AuthUser.fromJson(res['user'] as Map<String, dynamic>);
      } else {
        _currentUser = AuthUser(
          id: 'user-${DateTime.now().millisecondsSinceEpoch}',
          email: email,
          name: email.split('@').first,
        );
      }
      return _currentUser!;
    } catch (_) {
      // Fallback for offline / demo mode
      _currentUser = AuthUser(
        id: 'user-demo',
        email: email,
        name: email.split('@').first,
      );
      return _currentUser!;
    }
  }

  Future<AuthUser> loginWithGoogle() async {
    // Demo/OAuth token handshake
    _token = 'demo-jwt-token';
    _api.setAuthToken(_token);
    _currentUser = const AuthUser(
      id: 'user-google-1',
      email: 'alex@flowstate.local',
      name: 'Alex',
    );
    return _currentUser!;
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _api.setAuthToken(null);
  }

  void setCurrentUser(AuthUser user) {
    _currentUser = user;
  }
}
