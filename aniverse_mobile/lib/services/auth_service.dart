import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'google_auth.dart';
import 'history_service.dart';

class AuthUser {
  final int id;
  final String? username;
  final String displayName;
  final String? email;
  final String? avatarUrl;

  /// 'password' or 'google'.
  final String provider;

  const AuthUser({
    required this.id,
    required this.displayName,
    required this.provider,
    this.username,
    this.email,
    this.avatarUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String?,
        displayName:
            (j['display_name'] ?? j['username'] ?? 'AniVerse fan').toString(),
        email: j['email'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        provider: (j['provider'] ?? 'password').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'email': email,
        'avatar_url': avatarUrl,
        'provider': provider,
      };

  /// First letter for an avatar placeholder.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();
}

/// What the server offers for signing in.
class AuthConfig {
  final bool googleEnabled;

  /// The Web OAuth client ID Google must issue ID tokens for. It comes from
  /// the server rather than being compiled in, so Google sign-in can be turned
  /// on without shipping a new APK.
  final String? googleServerClientId;

  const AuthConfig({this.googleEnabled = false, this.googleServerClientId});
}

/// Signing in and out, and the session token that goes with it.
///
/// The token is an opaque server session, not a password, so it is kept in
/// the app's private preferences; signing out revokes it on the server too.
class AuthService {
  static const _tokenKey = 'aniverse_auth_token';
  static const _userKey = 'aniverse_auth_user';

  /// The signed-in user, or null. Screens listen to this to switch between the
  /// sign-in form and the profile.
  static final ValueNotifier<AuthUser?> user = ValueNotifier<AuthUser?>(null);

  static String? _token;

  static bool get signedIn => _token != null && user.value != null;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Uri _url(String path) => Uri.parse('${ApiService.baseUrl}$path');

  /// Restore the saved session. The server check runs in the background so a
  /// slow or unreachable server never holds up the first screen.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final raw = prefs.getString(_userKey);
      if (_token != null && raw != null) {
        user.value =
            AuthUser.fromJson(json.decode(raw) as Map<String, dynamic>);
      } else {
        _token = null;
      }
    } catch (_) {
      _token = null;
    }
    if (signedIn) unawaited(_refresh());
  }

  static Future<void> _refresh() async {
    try {
      final r = await http
          .get(_url('/auth/me'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 401) {
        await sessionExpired();
        return;
      }
      if (r.statusCode != 200) return;
      final u = AuthUser.fromJson(
          (json.decode(r.body) as Map)['user'] as Map<String, dynamic>);
      user.value = u;
      await _saveUser(u);
      unawaited(HistoryService.sync());
    } catch (_) {
      // Offline: keep the saved session and try again next launch.
    }
  }

  static Future<AuthConfig> config() async {
    try {
      final r = await http
          .get(_url('/auth/config'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const AuthConfig();
      final g = (json.decode(r.body) as Map)['google'] as Map? ?? const {};
      return AuthConfig(
        googleEnabled: g['enabled'] == true,
        googleServerClientId: g['server_client_id'] as String?,
      );
    } catch (_) {
      return const AuthConfig();
    }
  }

  /// Returns null on success, otherwise a message to show the user.
  static Future<String?> login(String username, String password) =>
      _post('/auth/login', {'username': username.trim(), 'password': password});

  static Future<String?> register(String username, String password,
          {String? displayName}) =>
      _post('/auth/register', {
        'username': username.trim(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      });

  static Future<String?> signInWithGoogle() async {
    final cfg = await config();
    if (!cfg.googleEnabled || cfg.googleServerClientId == null) {
      return 'Google sign-in is not set up on this server yet. '
          'Use a username and password instead.';
    }
    final result = await GoogleAuth.idToken(cfg.googleServerClientId!);
    if (result.error != null) return result.error;
    if (result.idToken == null) return null; // cancelled: nothing to report
    return _post('/auth/google', {'id_token': result.idToken});
  }

  static Future<String?> _post(String path, Map<String, dynamic> body) async {
    http.Response r;
    try {
      r = await http
          .post(_url(path),
              headers: const {'Content-Type': 'application/json'},
              body: json.encode(body))
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      return "Can't reach the AniVerse server. Check your connection and try again.";
    }
    // An older server can still serve anime while lacking the account routes.
    // Its generic "Not Found" is about an endpoint, not the user's account.
    if (r.statusCode == 404 || r.statusCode == 405) {
      return 'Account services are unavailable on this server. Please try again later.';
    }
    if (r.statusCode >= 500) {
      return 'The account server is temporarily unavailable. Please try again later.';
    }
    Map<String, dynamic> data;
    try {
      data = json.decode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return 'The server sent an unexpected reply (HTTP ${r.statusCode}).';
    }
    if (r.statusCode != 200) {
      return _errorText(data['detail']) ??
          'The account request failed (HTTP ${r.statusCode}). Please try again.';
    }

    // Reject incomplete success replies without leaving the form stuck in its
    // loading state or replacing an existing session with invalid data.
    final token = data['token'];
    AuthUser account;
    try {
      if (token is! String || token.isEmpty) {
        throw const FormatException('Missing session token');
      }
      account = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      return 'The server sent an incomplete account reply. Please try again.';
    }
    await _adopt(token, account);
    return null;
  }

  /// FastAPI reports its own validation failures as a list of objects.
  static String? _errorText(dynamic detail) {
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      return (detail.first as Map)['msg']?.toString();
    }
    return null;
  }

  static Future<void> _adopt(String token, AuthUser u) async {
    _token = token;
    user.value = u;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (_) {}
    await _saveUser(u);
    // Whatever was watched on this phone before signing in joins the account.
    unawaited(HistoryService.sync());
  }

  static Future<void> _saveUser(AuthUser u) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, json.encode(u.toJson()));
    } catch (_) {}
  }

  static Future<void> signOut() async {
    // Get the last progress into the account before the device copy goes.
    try {
      await HistoryService.sync().timeout(const Duration(seconds: 6));
    } catch (_) {}
    final token = _token;
    if (token != null) {
      unawaited(http
          .post(_url('/auth/logout'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10))
          .then((_) {}, onError: (_) {}));
    }
    if (user.value?.provider == 'google') unawaited(GoogleAuth.signOut());
    await _clearSession();
    await HistoryService.clearLocal();
  }

  /// The server no longer accepts the token (expired or revoked). The local
  /// history is kept -- it may hold progress the account has not seen yet.
  static Future<void> sessionExpired() => _clearSession();

  static Future<void> _clearSession() async {
    _token = null;
    user.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (_) {}
  }
}
