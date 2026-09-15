from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'[{label}] expected source fragment not found:\n{old[:260]}')
    return text.replace(old, new, 1)


# Backend: rotate every session after a password change and invalidate other devices.
p = Path('backend/src/index.ts')
s = p.read_text(encoding='utf-8')
old = """    const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
    await prisma.user.update({
      where: { id: claims.sub },
      data: { passwordHash },
    });
    return { ok: true };
"""
new = """    const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
    const revokedAt = new Date();
    const updated = await prisma.$transaction(async (tx) => {
      const nextUser = await tx.user.update({
        where: { id: claims.sub },
        data: { passwordHash },
      });
      await tx.refreshToken.updateMany({
        where: { userId: claims.sub, revokedAt: null },
        data: { revokedAt },
      });
      return nextUser;
    });
    const session = await createSession(updated);
    return { ok: true, user: publicUser(updated), ...session };
"""
s = replace_once(s, old, new, 'backend-password-session-rotation')
p.write_text(s, encoding='utf-8')


# Flutter API: single-flight refresh, logout/refresh race protection, and accept rotated password session.
p = Path('lib/core/api_service.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """  String? _accessToken;
  String? _refreshToken;
""",
    """  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;
  int _sessionGeneration = 0;
""",
    'api-refresh-fields',
)
s = replace_once(
    s,
    """  Future<void> _saveSession(AppSession session) async {
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
""",
    """  Future<void> _saveSession(AppSession session) async {
    _sessionGeneration += 1;
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
""",
    'api-session-generation-save',
)
s = replace_once(
    s,
    """  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
""",
    """  Future<void> clearSession() async {
    _sessionGeneration += 1;
    _accessToken = null;
    _refreshToken = null;
""",
    'api-session-generation-clear',
)
old_refresh = """  Future<bool> refreshSession() async {
    await restoreTokens();
    final token = _refreshToken;
    if (token == null || token.isEmpty) return false;

    try {
      final response = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refreshToken': token},
        retry401: false,
      );
      if (response.statusCode != 200) {
        await clearSession();
        return false;
      }
      final json = _decodeObject(response);
      _accessToken = json['accessToken'] as String?;
      _refreshToken = json['refreshToken'] as String?;
      if (_accessToken == null || _refreshToken == null) {
        await clearSession();
        return false;
      }
      await Future.wait([
        _storage.write(key: _accessKey, value: _accessToken),
        _storage.write(key: _refreshKey, value: _refreshToken),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
"""
new_refresh = """  Future<bool> refreshSession() {
    final active = _refreshInFlight;
    if (active != null) return active;
    final operation = _refreshSessionOnce();
    _refreshInFlight = operation;
    operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    });
    return operation;
  }

  Future<bool> _refreshSessionOnce() async {
    await restoreTokens();
    final token = _refreshToken;
    if (token == null || token.isEmpty) return false;
    final generation = _sessionGeneration;

    try {
      final response = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refreshToken': token},
        retry401: false,
      );
      if (generation != _sessionGeneration) return false;
      if (response.statusCode != 200) {
        await clearSession();
        return false;
      }
      final json = _decodeObject(response);
      final nextAccess = json['accessToken'] as String?;
      final nextRefresh = json['refreshToken'] as String?;
      if (nextAccess == null || nextRefresh == null) {
        await clearSession();
        return false;
      }
      if (generation != _sessionGeneration) return false;
      _accessToken = nextAccess;
      _refreshToken = nextRefresh;
      await Future.wait([
        _storage.write(key: _accessKey, value: nextAccess),
        _storage.write(key: _refreshKey, value: nextRefresh),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }
"""
s = replace_once(s, old_refresh, new_refresh, 'api-single-flight-refresh')
old_change = """  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final response = await _send(
      'POST',
      '/api/v1/me/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }
"""
new_change = """  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final response = await _send(
      'POST',
      '/api/v1/me/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
  }
"""
s = replace_once(s, old_change, new_change, 'api-password-rotation-save')
p.write_text(s, encoding='utf-8')


# Flutter UX: validate identifiers locally and localize wallet status labels.
p = Path('lib/app.dart')
s = p.read_text(encoding='utf-8')
old_validation = """    if (identifier.text.trim().isEmpty || password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'ایمیل/شماره و رمز حداقل ۸ کاراکتری وارد کنید.', 'Enter your email/phone and a password of at least 8 characters.'))),
      );
      return;
    }
"""
new_validation = """    final rawIdentifier = identifier.text.trim();
    final looksLikeEmail = RegExp(r'^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').hasMatch(rawIdentifier);
    final looksLikePhone = RegExp(r'^\\+?[0-9][0-9\\s-]{6,31}$').hasMatch(rawIdentifier);
    if ((!looksLikeEmail && !looksLikePhone) || password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'ایمیل یا شماره معتبر و رمز حداقل ۸ کاراکتری وارد کنید.', 'Enter a valid email or phone number and a password of at least 8 characters.'))),
      );
      return;
    }
"""
s = replace_once(s, old_validation, new_validation, 'auth-local-validation')
wallet_title_anchor = """  String entryTitle(bool fa, WalletEntry entry) {
"""
wallet_helpers = """  String entryStatus(bool fa, WalletEntry entry) {
    switch (entry.status) {
      case 'PENDING':
        return tr(fa, 'در انتظار', 'Pending');
      case 'FAILED':
        return tr(fa, 'ناموفق', 'Failed');
      case 'REVERSED':
        return tr(fa, 'برگشت خورده', 'Reversed');
      default:
        return tr(fa, 'تکمیل', 'Completed');
    }
  }

  String entryTitle(bool fa, WalletEntry entry) {
"""
s = replace_once(s, wallet_title_anchor, wallet_helpers, 'wallet-localized-status-helper')
s = replace_once(
    s,
    "subtitle: '${entry.status} • ${entry.createdAt.toLocal().toString().substring(0, 16)} • ${tr(c.fa, 'موجودی بعد', 'Balance after')}: ${entry.balanceAfterAfn} AFN',",
    "subtitle: '${entryStatus(c.fa, entry)} • ${entry.createdAt.toLocal().toString().substring(0, 16)} • ${tr(c.fa, 'موجودی بعد', 'Balance after')}: ${entry.balanceAfterAfn} AFN',",
    'wallet-localized-status-use',
)
p.write_text(s, encoding='utf-8')

print('VELIXEO Milestone 1 session hardening applied')
