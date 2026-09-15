from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'[{label}] expected source fragment not found:\n{old[:400]}')
    return text.replace(old, new, 1)


# ---------------- Prisma: support passwordless Google identities ----------------
p = Path('backend/prisma/schema.prisma')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """  email           String?         @unique
  phone           String?         @unique
  passwordHash    String
  role            UserRole        @default(USER)
""",
    """  email           String?         @unique
  phone           String?         @unique
  passwordHash    String?
  googleSubject   String?         @unique
  role            UserRole        @default(USER)
""",
    'prisma-google-identity',
)
p.write_text(s, encoding='utf-8')


# ---------------- Backend package ----------------
p = Path('backend/package.json')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '    "fastify": "^5.6.0",\n    "zod": "^4.1.8"',
    '    "fastify": "^5.6.0",\n    "google-auth-library": "^11.0.2",\n    "zod": "^4.1.8"',
    'backend-google-package',
)
p.write_text(s, encoding='utf-8')


# ---------------- Backend Google token verification ----------------
p = Path('backend/src/index.ts')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import bcrypt from 'bcryptjs';\n",
    "import bcrypt from 'bcryptjs';\nimport { OAuth2Client } from 'google-auth-library';\n",
    'backend-google-import',
)
s = replace_once(
    s,
    """    REFRESH_TOKEN_DAYS: z.coerce.number().int().positive().default(30),
""",
    """    REFRESH_TOKEN_DAYS: z.coerce.number().int().positive().default(30),
    GOOGLE_WEB_CLIENT_ID: z.string().trim().min(1).optional(),
""",
    'backend-google-env',
)
s = replace_once(
    s,
    """const prisma = new PrismaClient();
const app = Fastify({
""",
    """const prisma = new PrismaClient();
const googleOAuth = new OAuth2Client();
const app = Fastify({
""",
    'backend-google-client',
)
s = replace_once(
    s,
    """const refreshSchema = z.object({
  refreshToken: z.string().min(40),
});

""",
    """const refreshSchema = z.object({
  refreshToken: z.string().min(40),
});

const googleAuthSchema = z.object({
  idToken: z.string().min(20),
  locale: z.enum(['FA', 'EN']).default('FA'),
});

""",
    'backend-google-schema',
)
s = replace_once(
    s,
    """  displayCurrency: DisplayCurrency;
  createdAt: Date;
}) {
""",
    """  displayCurrency: DisplayCurrency;
  createdAt: Date;
  passwordHash?: string | null;
}) {
""",
    'public-user-password-type',
)
s = replace_once(
    s,
    """    displayCurrency: user.displayCurrency,
    createdAt: user.createdAt,
""",
    """    displayCurrency: user.displayCurrency,
    hasPassword: Boolean(user.passwordHash),
    createdAt: user.createdAt,
""",
    'public-user-has-password',
)
# Normal and admin password login must safely reject passwordless Google accounts.
s = s.replace(
    "if (!user || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {",
    "if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {",
)
# Change password requires a local password; Google-only accounts can add a password in a later verified flow.
s = replace_once(
    s,
    """    const matches = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
""",
    """    if (!user.passwordHash) return reply.code(400).send({ error: 'password_not_set' });
    const matches = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
""",
    'change-password-null-guard',
)

login_endpoint = """app.post('/api/v1/auth/login', async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  const rawIdentifier = parsed.data.identifier;
  const emailIdentifier = rawIdentifier.includes('@')
    ? rawIdentifier.toLowerCase()
    : '__not_an_email__';
  const phoneIdentifier = normalizePhone(rawIdentifier) ?? rawIdentifier;

  const user = await prisma.user.findFirst({
    where: {
      OR: [{ email: emailIdentifier }, { phone: phoneIdentifier }],
    },
  });

  if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return reply.code(401).send({ error: 'invalid_credentials' });
  }

  const session = await createSession(user);
  return { user: publicUser(user), ...session };
});
"""
google_endpoint = login_endpoint + """

app.post('/api/v1/auth/google', async (request, reply) => {
  if (!env.GOOGLE_WEB_CLIENT_ID) {
    return reply.code(503).send({ error: 'google_auth_not_configured' });
  }

  const parsed = googleAuthSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  try {
    const ticket = await googleOAuth.verifyIdToken({
      idToken: parsed.data.idToken,
      audience: env.GOOGLE_WEB_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    const googleSubject = payload?.sub;
    const email = normalizeEmail(payload?.email);
    if (!googleSubject || !email || payload?.email_verified !== true) {
      return reply.code(401).send({ error: 'invalid_google_identity' });
    }

    let user = await prisma.user.findUnique({ where: { googleSubject } });
    if (!user) {
      const existing = await prisma.user.findUnique({ where: { email } });
      if (existing?.googleSubject && existing.googleSubject !== googleSubject) {
        return reply.code(409).send({ error: 'google_account_conflict' });
      }

      if (existing) {
        user = await prisma.user.update({
          where: { id: existing.id },
          data: {
            googleSubject,
            fullName: existing.fullName?.trim() ? existing.fullName : payload?.name?.trim() || null,
          },
        });
      } else {
        user = await prisma.user.create({
          data: {
            fullName: payload?.name?.trim() || email.split('@')[0],
            email,
            googleSubject,
            passwordHash: null,
            locale: parsed.data.locale as AppLocale,
            wallet: { create: {} },
          },
        });
      }
    }

    const session = await createSession(user);
    return { user: publicUser(user), ...session };
  } catch (error) {
    request.log.warn({ error }, 'google token verification failed');
    return reply.code(401).send({ error: 'invalid_google_token' });
  }
});
"""
s = replace_once(s, login_endpoint, google_endpoint, 'backend-google-endpoint')
p.write_text(s, encoding='utf-8')


# ---------------- Flutter packages ----------------
p = Path('pubspec.yaml')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """  flutter_secure_storage: ^9.2.4
""",
    """  flutter_secure_storage: ^9.2.4
  google_sign_in: ^7.2.0
""",
    'flutter-google-package',
)
p.write_text(s, encoding='utf-8')


# ---------------- Flutter user model ----------------
p = Path('lib/core/models.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """    required this.displayCurrency,
    this.fullName,
""",
    """    required this.displayCurrency,
    required this.hasPassword,
    this.fullName,
""",
    'model-has-password-constructor',
)
s = replace_once(
    s,
    """  final String displayCurrency;

""",
    """  final String displayCurrency;
  final bool hasPassword;

""",
    'model-has-password-field',
)
s = replace_once(
    s,
    """        displayCurrency: (json['displayCurrency'] as String?) ?? 'AFN',
""",
    """        displayCurrency: (json['displayCurrency'] as String?) ?? 'AFN',
        hasPassword: (json['hasPassword'] as bool?) ?? true,
""",
    'model-has-password-json',
)
p.write_text(s, encoding='utf-8')


# ---------------- Flutter Google service ----------------
Path('lib/core/google_auth_service.dart').write_text(r'''import 'package:google_sign_in/google_sign_in.dart';

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
''', encoding='utf-8')


# ---------------- Flutter API Google endpoint ----------------
p = Path('lib/core/api_service.dart')
s = p.read_text(encoding='utf-8')
login_block = """  Future<AppSession> login({required String identifier, required String password}) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'identifier': identifier.trim(), 'password': password},
    );
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }
"""
google_login_block = login_block + """

  Future<AppSession> loginWithGoogle({required String idToken, required AppLang language}) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/google',
      body: {
        'idToken': idToken,
        'locale': language == AppLang.fa ? 'FA' : 'EN',
      },
    );
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }
"""
s = replace_once(s, login_block, google_login_block, 'flutter-google-api')
p.write_text(s, encoding='utf-8')


# ---------------- Flutter controller + real Google button ----------------
p = Path('lib/app.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    """import 'core/api_service.dart';
import 'core/models.dart';
""",
    """import 'core/api_service.dart';
import 'core/google_auth_service.dart';
import 'core/models.dart';
""",
    'flutter-google-import',
)
s = replace_once(
    s,
    """class AppController extends ChangeNotifier {
  AppController(this.api);

  final ApiService api;
""",
    """class AppController extends ChangeNotifier {
  AppController(this.api, this.googleAuth);

  final ApiService api;
  final GoogleAuthService googleAuth;
""",
    'controller-google-service',
)
s = replace_once(
    s,
    """  bool get fa => language == AppLang.fa;
""",
    """  bool get fa => language == AppLang.fa;
  bool get googleConfigured => googleAuth.configured;
""",
    'controller-google-configured',
)
register_end = """  Future<bool> register(String fullName, String identifier, String password) async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final session = await api.register(
        fullName: fullName,
        identifier: identifier,
        password: password,
        language: language,
      );
      user = session.user;
      authenticated = true;
      balanceAfn = 0;
      _applyUserPreferences(session.user);
      await _loadSecondaryData();
      return true;
    } on ApiException catch (error) {
      authError = error.code;
      return false;
    } catch (_) {
      authError = 'network_error';
      return false;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }
"""
google_controller = register_end + """

  Future<bool> loginWithGoogle() async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final idToken = await googleAuth.authenticateIdToken();
      final session = await api.loginWithGoogle(idToken: idToken, language: language);
      user = session.user;
      authenticated = true;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      await _loadSecondaryData();
      return true;
    } on GoogleAuthException catch (error) {
      authError = error.code;
      return false;
    } on ApiException catch (error) {
      authError = error.code;
      return false;
    } catch (_) {
      authError = 'google_sign_in_failed';
      return false;
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }
"""
s = replace_once(s, register_end, google_controller, 'controller-google-login')
s = replace_once(
    s,
    """  Future<void> logout() async {
    await api.logout();
""",
    """  Future<void> logout() async {
    await api.logout();
    await googleAuth.signOut();
""",
    'controller-google-logout',
)
s = replace_once(
    s,
    """    controller = AppController(ApiService());
""",
    """    controller = AppController(ApiService(), GoogleAuthService());
""",
    'app-google-controller-init',
)
# Hide password change for Google-only identities.
s = replace_once(
    s,
    """          SettingsTile(
            icon: Icons.password_rounded,
            title: tr(c.fa, 'تغییر رمز عبور', 'Change password'),
            value: '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChangePasswordPage(controller: c)),
            ),
          ),
""",
    """          if (c.user?.hasPassword == true)
            SettingsTile(
              icon: Icons.password_rounded,
              title: tr(c.fa, 'تغییر رمز عبور', 'Change password'),
              value: '',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChangePasswordPage(controller: c)),
              ),
            ),
""",
    'profile-hide-password-google-only',
)
# Add Google-specific localized errors.
s = replace_once(
    s,
    """      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');
      default:
""",
    """      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');
      case 'google_auth_not_configured':
        return tr(fa, 'ورود با Google هنوز برای این نسخه فعال نشده است.', 'Google Sign-In is not configured for this build yet.');
      case 'google_sign_in_failed':
      case 'invalid_google_token':
      case 'invalid_google_identity':
        return tr(fa, 'ورود با Google انجام نشد. دوباره تلاش کنید.', 'Google Sign-In failed. Please try again.');
      case 'google_account_conflict':
        return tr(fa, 'این ایمیل به حساب Google دیگری متصل است.', 'This email is linked to a different Google account.');
      default:
""",
    'auth-google-error-messages',
)
old_google_button = """              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: c.authBusy
                      ? null
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr(
                                  fa,
                                  'ورود با Google در مرحله اتصال OAuth است و بعد از تنظیم Client ID فعال می‌شود.',
                                  'Google Sign-In is ready for OAuth wiring and will activate after the Client ID is configured.',
                                ),
                              ),
                            ),
                          ),
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  label: Text(tr(fa, 'ادامه با Google', 'Continue with Google')),
                ),
              ),
"""
new_google_button = """              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: c.authBusy || !c.googleConfigured
                      ? null
                      : () async {
                          final ok = await c.loginWithGoogle();
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(errorMessage(c.authError ?? 'google_sign_in_failed'))),
                            );
                          }
                        },
                  icon: const Text(
                    'G',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  label: Text(
                    c.googleConfigured
                        ? tr(fa, 'ادامه با Google', 'Continue with Google')
                        : tr(fa, 'Google — در انتظار تنظیم OAuth', 'Google — OAuth setup pending'),
                  ),
                ),
              ),
"""
s = replace_once(s, old_google_button, new_google_button, 'real-google-button')
p.write_text(s, encoding='utf-8')

print('VELIXEO real Google Sign-In scaffolding applied')
