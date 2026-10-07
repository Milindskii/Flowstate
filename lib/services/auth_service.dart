import 'dart:async';
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
        final event = data.event;
        final newSession = data.session;

        if (event == AuthChangeEvent.signedOut) {
          _token = null;
          _api.setAuthToken(null);
          _currentUser = null;
          return;
        }

        if (newSession != null) {
          _token = newSession.accessToken;
          _api.setAuthToken(_token);
          _currentUser = AuthUser.fromSupabase(newSession.user);
        } else {
          // If event has null session, only clear if Supabase client also confirms no session
          final liveSession = Supabase.instance.client.auth.currentSession;
          if (liveSession == null) {
            _token = null;
            _api.setAuthToken(null);
            _currentUser = null;
          }
        }
      });
    } catch (_) {
      // Offline / initialization safety
    }
  }

  AuthUser? get currentUser {
    if (_currentUser != null && !_currentUser!.id.startsWith('guest_')) {
      return _currentUser;
    }
    try {
      final supaUser = Supabase.instance.client.auth.currentUser;
      if (supaUser != null) {
        _currentUser = AuthUser.fromSupabase(supaUser);
        return _currentUser;
      }
    } catch (_) {}
    return _currentUser;
  }

  String? get token {
    if (_token != null && _token!.isNotEmpty) return _token;
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  bool get isAuthenticated {
    try {
      final liveSession = Supabase.instance.client.auth.currentSession;
      if (liveSession != null && !liveSession.isExpired) {
        return true;
      }
    } catch (_) {}
    return ((_token != null && _token!.isNotEmpty) || _api.isAuthenticated) &&
        _currentUser != null &&
        !_currentUser!.id.startsWith('guest_');
  }

  Future<AuthUser?> restoreSession() async {
    try {
      var session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        // Brief window for Supabase on web or storage to finish loading
        await Future.delayed(const Duration(milliseconds: 150));
        session = Supabase.instance.client.auth.currentSession;
      }
      if (session != null) {
        if (session.isExpired) {
          try {
            final refreshRes = await Supabase.instance.client.auth.refreshSession();
            session = refreshRes.session ?? session;
          } catch (_) {}
        }
        _token = session?.accessToken;
        _api.setAuthToken(_token);
        final user = Supabase.instance.client.auth.currentUser ?? session?.user;
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
    final session = res.session;
    if (session == null || session.accessToken.isEmpty) {
      throw const AuthException('Login succeeded but no valid session was returned. Please verify your email.');
    }
    _token = session.accessToken;
    _api.setAuthToken(_token);
    final user = res.user ?? session.user;
    _currentUser = AuthUser.fromSupabase(user);
    return _currentUser!;
  }

  Future<AuthUser> signUpWithEmail(String email, String password) async {
    final res = await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    var session = res.session;
    if (session == null) {
      // Attempt immediate sign in in case user is confirmed or auto-login is supported
      try {
        final signInRes = await Supabase.instance.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        session = signInRes.session;
      } catch (_) {
        // If signInWithPassword fails, session remains null
      }
    }

    if (session != null && session.accessToken.isNotEmpty) {
      _token = session.accessToken;
      _api.setAuthToken(_token);
      final user = res.user ?? session.user;
      _currentUser = AuthUser.fromSupabase(user);
      return _currentUser!;
    }

    // When email verification is required by Supabase, no session is issued yet.
    // Throw actionable AuthException so the user is informed to verify their email
    // instead of silently entering the app without an authenticated session.
    throw const AuthException(
      'Account created! Please check your email to verify your account before logging in.',
    );
  }

  /// Resolves the OAuth redirect URL dynamically based on the current platform and environment.
  /// On Flutter Web: returns the dynamic browser origin (e.g. 'http://localhost:64823') derived
  /// from [Uri.base.origin] so Supabase redirects back to the active port.
  /// On Mobile/Native: returns the custom deep link scheme ('io.flowstate://login-callback').
  static String? getOAuthRedirectUrl({bool isWeb = kIsWeb, Uri? baseUri}) {
    if (isWeb) {
      try {
        final uri = baseUri ?? Uri.base;
        final origin = uri.origin;
        if (origin.isNotEmpty && origin != 'null') {
          return origin;
        }
      } catch (_) {}
      return null;
    }
    return 'io.flowstate://login-callback';
  }

  Future<AuthUser> loginWithGoogle({Duration timeout = const Duration(minutes: 2)}) async {
    try {
      final existingSession = Supabase.instance.client.auth.currentSession;
      if (existingSession?.user != null) {
        _token = existingSession!.accessToken;
        _api.setAuthToken(_token);
        _currentUser = AuthUser.fromSupabase(existingSession.user);
        return _currentUser!;
      }

      final completer = Completer<AuthUser>();
      late final StreamSubscription<AuthState> authSub;

      authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.session?.user != null && !completer.isCompleted) {
          final user = AuthUser.fromSupabase(data.session!.user);
          _currentUser = user;
          _token = data.session!.accessToken;
          _api.setAuthToken(_token);
          completer.complete(user);
        }
      }, onError: (err) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
      });

      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: getOAuthRedirectUrl(),
      );

      if (!launched) {
        authSub.cancel();
        throw Exception('Could not launch Google Sign-In browser.');
      }

      // Check if session became available immediately
      final immediateSession = Supabase.instance.client.auth.currentSession;
      if (immediateSession?.user != null && !completer.isCompleted) {
        final user = AuthUser.fromSupabase(immediateSession!.user);
        _currentUser = user;
        _token = immediateSession.accessToken;
        _api.setAuthToken(_token);
        authSub.cancel();
        return user;
      }

      // Wait for deep link OAuth redirect event
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          authSub.cancel();
          final fallbackSession = Supabase.instance.client.auth.currentSession;
          if (fallbackSession?.user != null) {
            final user = AuthUser.fromSupabase(fallbackSession!.user);
            _currentUser = user;
            _token = fallbackSession.accessToken;
            _api.setAuthToken(_token);
            return user;
          }
          throw Exception('Google Sign-In completed without session or was cancelled.');
        },
      ).whenComplete(() {
        authSub.cancel();
      });
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
