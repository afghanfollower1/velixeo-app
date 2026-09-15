import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.code);
  final String code;

  @override
  String toString() => 'GoogleAuthException($code)';
}

class GoogleAuthService {
  GoogleAuthService();

  static const String webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  final GoogleSignIn _google = GoogleSignIn.instance;
  bool _initialized = false;

  bool get configured => webClientId.trim().isNotEmpty;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (!configured) throw const GoogleAuthException('google_auth_not_configured');
    await _google.initialize(serverClientId: webClientId.trim());
    _initialized = true;
  }

  Future<String> authenticateIdToken() async {
    await _ensureInitialized();
    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException('google_token_missing');
      }
      return idToken;
    } on GoogleAuthException {
      rethrow;
    } catch (_) {
      throw const GoogleAuthException('google_sign_in_failed');
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await _google.signOut();
    } catch (_) {}
  }
}
