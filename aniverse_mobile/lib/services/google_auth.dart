import 'package:google_sign_in/google_sign_in.dart';

/// Outcome of a Google sign-in attempt.
class GoogleIdResult {
  /// Present on success. The server verifies it with Google before trusting it.
  final String? idToken;

  /// A message for the user when something went wrong; null when the user
  /// simply backed out of the account picker.
  final String? error;

  const GoogleIdResult({this.idToken, this.error});
}

/// Thin wrapper over google_sign_in, kept separate so the rest of the app
/// never touches the plugin directly.
class GoogleAuth {
  static String? _initializedFor;

  /// Show Google's account picker and return an ID token issued for
  /// [serverClientId] (the server's Web OAuth client).
  static Future<GoogleIdResult> idToken(String serverClientId) async {
    final signIn = GoogleSignIn.instance;
    try {
      // initialize() may only run once per process.
      if (_initializedFor == null) {
        await signIn.initialize(serverClientId: serverClientId);
        _initializedFor = serverClientId;
      }
      if (!signIn.supportsAuthenticate()) {
        return const GoogleIdResult(
            error: 'Google sign-in is not available on this device.');
      }
      final account = await signIn.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        return const GoogleIdResult(error: 'Google did not return a sign-in token.');
      }
      return GoogleIdResult(idToken: token);
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return const GoogleIdResult();
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          // Almost always the Android OAuth client: its package name or SHA-1
          // does not match this APK. See SETUP.md.
          return const GoogleIdResult(
              error: "Google sign-in isn't configured for this build of the app yet. "
                  'Use a username and password for now.');
        case GoogleSignInExceptionCode.uiUnavailable:
          return const GoogleIdResult(
              error: 'Google sign-in could not open. Is Google Play Services installed?');
        default:
          return GoogleIdResult(
              error: 'Google sign-in failed${e.description == null ? '' : ': ${e.description}'}');
      }
    } catch (e) {
      return GoogleIdResult(error: 'Google sign-in failed: $e');
    }
  }

  static Future<void> signOut() async {
    if (_initializedFor == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signing out of AniVerse must not depend on Google answering.
    }
  }
}
