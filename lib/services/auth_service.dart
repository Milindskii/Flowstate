import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String? avatarUrl;
  final bool onboardingCompleted;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
    this.onboardingCompleted = false,
  });

  factory AuthUser.fromSupabase(User user, {bool onboardingCompleted = false}) {
    final meta = user.userMetadata ?? {};
    final name = meta['name'] as String? ??
        meta['full_name'] as String? ??
        (user.email?.split('@').first ?? 'Friend');
    return AuthUser(
      id: user.id,
      email: user.email ?? '',
      name: name,
      avatarUrl: meta['avatar_url'] as String?,
      onboardingCompleted: onboardingCompleted,
    );
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? 'user-default',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? (json['email'] as String?)?.split('@').first ?? 'Friend',
      avatarUrl: json['avatar_url'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_url': avatarUrl,
        'onboarding_completed': onboardingCompleted,
      };

  AuthUser copyWith({
    String? id,
    String? email,
    String? name,
    String? avatarUrl,
    bool? onboardingCompleted,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }
}

/// Authentication and Session Management Service
/// Powered by Supabase Auth with seamless JWT propagation to FastAPI backend
class AuthService {
  final ApiService _api;
  AuthUser? _currentUser;
  String? _token;

  AuthService({required ApiService api}) : _api = api {
    _initSupabaseSession();
  }

  void _initSupabaseSession() {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        _token = session.accessToken;
        _api.setAuthToken(_token);
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          _currentUser = AuthUser.fromSupabase(user);
        }
      }

      // Listen to real-time auth state changes
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final newSession = data.session;
        _token = newSession?.accessToken;
        _api.setAuthToken(_token);
        if (newSession?.user != null) {
          _currentUser = AuthUser.fromSupabase(newSession!.user);
        } else {
          _currentUser = null;
        }
      });
    } catch (_) {
      // Offline / initialization safety
    }
  }

  AuthUser? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => (_token != null && _token!.isNotEmpty) && _currentUser != null;

  Future<AuthUser?> restoreSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        _token = session.accessToken;
        _api.setAuthToken(_token);
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          _currentUser = AuthUser.fromSupabase(user);
          return _currentUser;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AuthUser?> fetchUserProfile() async {
    try {
      final res = await _api.get('/api/v1/auth/me');
      if (res is Map<String, dynamic>) {
        final profile = AuthUser.fromJson(res);
        _currentUser = profile;
        return profile;
      }
    } catch (_) {}
    return _currentUser;
  }

  Future<AuthUser> loginWithEmail(String email, String password) async {
    final res = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    _token = res.session?.accessToken;
    _api.setAuthToken(_token);
    if (res.user != null) {
      _currentUser = AuthUser.fromSupabase(res.user!);
      return _currentUser!;
    }
    throw Exception('Login succeeded but user profile was not returned.');
  }

  Future<AuthUser> signUpWithEmail(String email, String password) async {
    final res = await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    _token = res.session?.accessToken;
    _api.setAuthToken(_token);
    if (res.user != null) {
      _currentUser = AuthUser.fromSupabase(res.user!);
      return _currentUser!;
    }
    throw Exception('Sign up succeeded but user profile was not returned.');
  }

  Future<AuthUser> loginWithGoogle() async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.flowstate://login-callback',
      );
      final session = Supabase.instance.client.auth.currentSession;
      _token = session?.accessToken;
      _api.setAuthToken(_token);
      if (session?.user != null) {
        _currentUser = AuthUser.fromSupabase(session!.user);
        return _currentUser!;
      }
      throw Exception('Google sign-in completed but active session was not returned.');
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('unsupported provider') ||
          e.message.toLowerCase().contains('not enabled')) {
        throw Exception(
          'Google Sign-In is not enabled in your Supabase project. '
          'Please enable Google in Supabase Dashboard > Authentication > Providers, '
          'or use Email / Guest access.',
        );
      }
      rethrow;
    }
  }

  Future<AuthUser> loginAsGuest() async {
    final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final guest = AuthUser(
      id: guestId,
      email: '$guestId@flowstate.local',
      name: 'Guest',
      onboardingCompleted: false,
    );
    _currentUser = guest;
    _token = null;
    _api.setAuthToken(null);
    return guest;
  }


  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _token = null;
    _currentUser = null;
    _api.setAuthToken(null);
  }

  void setCurrentUser(AuthUser user) {
    _currentUser = user;
  }
}
