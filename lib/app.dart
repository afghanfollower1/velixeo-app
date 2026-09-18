import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/api_service.dart';
import 'core/google_auth_service.dart';
import 'core/models.dart';
import 'social/social_panel.dart';
import 'support/support_page.dart';
import 'virtual_numbers/virtual_number_panel.dart';

// FIGMA_ENGLISH_V1 — UI implementation based on the approved English Figma file.

String tr(bool fa, String faText, String enText) => fa ? faText : enText;

class AppController extends ChangeNotifier implements SocialPanelHost, VirtualNumberPanelHost, SupportPanelHost {
  AppController(this.api, this.googleAuth);

  final ApiService api;
  final GoogleAuthService googleAuth;

  AppLang language = AppLang.en;
  DisplayCurrency currency = DisplayCurrency.afn;
  AppUser? user;
  int balanceAfn = 0;
  ExchangeRates rates = const ExchangeRates();
  List<WalletEntry> walletEntries = const [];
  List<CatalogService> catalogServices = const [];
  List<AppBanner> banners = const [];
  List<AppNotification> notifications = const [];
  List<AppOrder> orders = const [];
  PaymentCapabilities paymentCapabilities = const PaymentCapabilities();
  List<AppPayment> payments = const [];
  bool booting = true;
  bool authenticated = false;
  bool authBusy = false;
  bool refreshing = false;
  bool languageConfirmed = true;
  String? authError;

  bool get fa => false; // English-first release. Persian layout will be enabled in the next design pass.
  bool get googleConfigured => googleAuth.configured;
  int get unreadNotificationCount => notifications.where((notice) => !notice.isRead).length;

  Future<void> boot() async {
    language = await api.restoreLanguage();
    currency = await api.restoreCurrency();
    await api.restoreTokens();
    if (api.hasRefreshToken) {
      try {
        final result = await api.me();
        user = result.$1;
        balanceAfn = result.$2;
        authenticated = true;
        languageConfirmed = true;
        _applyUserPreferences(user!);
        await _loadSecondaryData();
      } catch (_) {
        await api.clearSession();
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> chooseLanguage(AppLang value) async {
    language = value;
    languageConfirmed = true;
    await api.saveLanguage(value);
    notifyListeners();
  }

  Future<bool> login(String identifier, String password) async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final session = await api.login(identifier: identifier, password: password);
      user = session.user;
      authenticated = true;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
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

  Future<bool> register(String fullName, String identifier, String password) async {
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

  Future<void> refreshAccount() async {
    if (!authenticated || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      await _loadSecondaryData();
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        user = null;
        balanceAfn = 0;
        walletEntries = const [];
      }
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _loadSecondaryData() async {
    try {
      rates = await api.exchangeRates();
    } catch (_) {}
    try {
      walletEntries = await api.walletEntries();
    } catch (_) {}
    try {
      catalogServices = await api.catalogServices();
    } catch (_) {}
    try {
      banners = await api.banners();
    } catch (_) {}
    if (authenticated) {
      try {
        notifications = await api.notifications();
      } catch (_) {}
      try {
        orders = await api.orders();
      } catch (_) {}
      try {
        paymentCapabilities = await api.paymentCapabilities();
      } catch (_) {}
      try {
        payments = await api.payments();
      } catch (_) {}
    }
  }

  Future<void> markNotificationRead(AppNotification notice) async {
    if (notice.isRead) return;
    final now = DateTime.now();
    notifications = notifications
        .map((item) => item.id == notice.id ? item.copyWith(isRead: true, readAt: now) : item)
        .toList(growable: false);
    notifyListeners();
    try {
      await api.markNotificationRead(notice.id);
    } catch (_) {
      try {
        notifications = await api.notifications();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> markAllNotificationsRead() async {
    if (unreadNotificationCount == 0) return;
    final now = DateTime.now();
    notifications = notifications
        .map((item) => item.copyWith(isRead: true, readAt: item.readAt ?? now))
        .toList(growable: false);
    notifyListeners();
    try {
      await api.markAllNotificationsRead();
    } catch (_) {
      try {
        notifications = await api.notifications();
      } catch (_) {}
      notifyListeners();
    }
  }

  void _applyUserPreferences(AppUser value) {
    language = value.locale == 'EN' ? AppLang.en : AppLang.fa;
    switch (value.displayCurrency) {
      case 'USD':
        currency = DisplayCurrency.usd;
        break;
      case 'TOMAN':
        currency = DisplayCurrency.toman;
        break;
      default:
        currency = DisplayCurrency.afn;
    }
    api.saveLanguage(language);
    api.saveCurrency(currency);
  }

  Future<void> setLanguage(AppLang value) async {
    language = value;
    await api.saveLanguage(value);
    if (authenticated) {
      try {
        user = await api.updatePreferences(language: value);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setCurrency(DisplayCurrency value) async {
    currency = value;
    await api.saveCurrency(value);
    if (authenticated) {
      try {
        user = await api.updatePreferences(currency: value);
      } catch (_) {}
    }
    notifyListeners();
  }


  Future<String?> updateFullName(String fullName) async {
    final value = fullName.trim();
    if (value.length < 2) return 'invalid_name';
    try {
      user = await api.updateProfile(fullName: value);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        notifyListeners();
      }
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> changePassword(String currentPassword, String newPassword) async {
    if (newPassword.length < 8) return 'weak_password';
    try {
      await api.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      return null;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await api.clearSession();
        authenticated = false;
        notifyListeners();
      }
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<void> refreshPaymentsAndWallet() async {
    if (!authenticated) return;
    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
    } catch (_) {}
    try {
      walletEntries = await api.walletEntries();
    } catch (_) {}
    try {
      paymentCapabilities = await api.paymentCapabilities();
    } catch (_) {}
    try {
      payments = await api.payments();
    } catch (_) {}
    notifyListeners();
  }

  Future<PaymentSessionResult> createHesabPayTopUp(int amountAfn) async {
    final currentUser = user;
    if (!authenticated || currentUser == null) {
      throw const ApiException('unauthorized');
    }
    final result = await api.createHesabPaySession(
      amountAfn: amountAfn,
      idempotencyKey:
          'wallet-${currentUser.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      payments = await api.payments();
    } catch (_) {}
    notifyListeners();
    return result;
  }

  Future<void> logout() async {
    await api.logout();
    await googleAuth.signOut();
    authenticated = false;
    user = null;
    balanceAfn = 0;
    walletEntries = const [];
    catalogServices = const [];
    banners = const [];
    notifications = const [];
    orders = const [];
    paymentCapabilities = const PaymentCapabilities();
    payments = const [];
    authError = null;
    languageConfirmed = true;
    notifyListeners();
  }

  String money(num afn, {bool showBase = false}) {
    String fmt(num value) {
      final isWhole = value == value.roundToDouble();
      final raw = isWhole ? value.round().toString() : value.toStringAsFixed(2);
      final parts = raw.split('.');
      parts[0] = parts[0].replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return parts.join('.');
    }

    switch (currency) {
      case DisplayCurrency.afn:
        return '${fmt(afn)} AFN';
      case DisplayCurrency.usd:
        final rate = rates.afnPerUsd;
        if (rate == null || rate <= 0) return '${fmt(afn)} AFN';
        final converted = afn / rate;
        return showBase
            ? '\$${converted.toStringAsFixed(2)}  ≈  ${fmt(afn)} AFN'
            : '\$${converted.toStringAsFixed(2)}';
      case DisplayCurrency.toman:
        final afnPerToman = rates.afnPerToman;
        if (afnPerToman == null || afnPerToman <= 0) return '${fmt(afn)} AFN';
        final toman = afn / afnPerToman;
        return showBase
            ? '${fmt(toman)} تومان  ≈  ${fmt(afn)} AFN'
            : '${fmt(toman)} تومان';
    }
  }

  String secondaryBalance() {
    final usd = rates.afnPerUsd;
    final toman = rates.afnPerToman;
    final pieces = <String>[];
    if (usd != null && usd > 0) {
      pieces.add('≈ \$${(balanceAfn / usd).toStringAsFixed(2)}');
    }
    if (toman != null && toman > 0) {
      final n = (balanceAfn / toman).round().toString().replaceAllMapped(
            RegExp(r'\B(?=(\d{3})+(?!\d))'),
            (_) => ',',
          );
      pieces.add('≈ $n تومان');
    }
    return pieces.isEmpty
        ? tr(fa, 'نرخ تبدیل هنوز توسط مدیر تعیین نشده', 'Exchange rates are not configured yet')
        : pieces.join('   •   ');
  }
}

class VelixeoApp extends StatefulWidget {
  const VelixeoApp({super.key});

  @override
  State<VelixeoApp> createState() => _VelixeoAppState();
}

class _VelixeoAppState extends State<VelixeoApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(ApiService(), GoogleAuthService());
    controller.boot();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1686FF),
            secondary: Color(0xFF37B6FF),
            surface: Colors.white,
            onSurface: Color(0xFF162235),
            outline: Color(0xFFE3EAF2),
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F9FC),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF162235),
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: TextStyle(
              color: Color(0xFF162235),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE7EDF4)),
            ),
          ),
          dividerTheme: const DividerThemeData(color: Color(0xFFEDF1F6), thickness: 1),
          navigationBarTheme: NavigationBarThemeData(
            height: 68,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE8F3FF),
            elevation: 0,
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? const Color(0xFF1686FF) : const Color(0xFF8995A5),
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            )),
            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? const Color(0xFF1686FF) : const Color(0xFF8995A5),
              size: 23,
            )),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            hintStyle: const TextStyle(color: Color(0xFF9AA6B6), fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3EAF2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3EAF2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1686FF), width: 1.4),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1686FF),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'VELIXEO',
          theme: theme,
          builder: (context, child) => Directionality(
            textDirection: controller.fa ? TextDirection.rtl : TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
          home: controller.booting
              ? const SplashPage()
              : controller.authenticated
                  ? MainShell(controller: controller)
                  : controller.languageConfirmed
                      ? AuthPage(controller: controller)
                      : LanguagePage(controller: controller),
        );
      },
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 86),
              SizedBox(height: 28),
              SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
        ),
      );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 46, this.wordmark = true});
  final double size;
  final bool wordmark;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .28),
              gradient: const LinearGradient(
                colors: [Color(0xFF4DB8FF), Color(0xFF0D78C8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CustomPaint(painter: _LogoPainter()),
          ),
          if (wordmark) ...[
            const SizedBox(width: 10),
            Text(
              'VELIXEO',
              style: TextStyle(
                fontSize: size * .43,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: const Color(0xFF102235),
              ),
            ),
          ],
        ],
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .25, size.height * .29)
      ..lineTo(size.width * .49, size.height * .73)
      ..lineTo(size.width * .72, size.height * .31);
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .77, size.height * .22),
      size.width * .07,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(size: 82),
              const SizedBox(height: 30),
              Text(
                tr(fa, 'زبان خود را انتخاب کنید', 'Choose your language'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                tr(fa, 'هر زبان رابط واقعی خودش را دارد', 'Each language has its own native layout'),
                style: const TextStyle(color: Color(0xFF607487)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              LanguageTile(
                title: 'فارسی',
                subtitle: 'رابط راست‌به‌چپ',
                flag: '🇦🇫',
                selected: fa,
                onTap: () => controller.setLanguage(AppLang.fa),
              ),
              const SizedBox(height: 12),
              LanguageTile(
                title: 'English',
                subtitle: 'Left-to-right interface',
                flag: '🌐',
                selected: !fa,
                onTap: () => controller.setLanguage(AppLang.en),
              ),
              const Spacer(),
              PrimaryButton(
                label: tr(fa, 'ادامه', 'Continue'),
                onPressed: () => controller.chooseLanguage(controller.language),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageTile extends StatelessWidget {
  const LanguageTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.flag,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF0D78C8) : const Color(0xFFDCE8F1),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: const Color(0xFF0D78C8),
              ),
            ],
          ),
        ),
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final fullName = TextEditingController();
  final identifier = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool registerMode = false;
  bool hidden = true;

  @override
  void dispose() {
    fullName.dispose();
    identifier.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  String errorMessage(String code) {
    final fa = widget.controller.fa;
    switch (code) {
      case 'invalid_credentials':
        return tr(fa, 'ایمیل/شماره یا رمز عبور نادرست است.', 'Invalid email/phone or password.');
      case 'email_already_registered':
        return tr(fa, 'این ایمیل قبلاً ثبت شده است.', 'This email is already registered.');
      case 'phone_already_registered':
        return tr(fa, 'این شماره قبلاً ثبت شده است.', 'This phone number is already registered.');
      case 'invalid_request':
        return tr(fa, 'اطلاعات واردشده معتبر نیست.', 'Please check the entered information.');
      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');
      case 'account_suspended':
        return tr(fa, 'این حساب توسط مدیریت موقتاً تعلیق شده است.', 'This account has been suspended by an administrator.');
      case 'google_auth_not_configured':
        return tr(fa, 'ورود با Google هنوز برای این نسخه فعال نشده است.', 'Google Sign-In is not configured for this build yet.');
      case 'google_sign_in_failed':
      case 'invalid_google_token':
      case 'invalid_google_identity':
        return tr(fa, 'ورود با Google انجام نشد. دوباره تلاش کنید.', 'Google Sign-In failed. Please try again.');
      case 'google_account_conflict':
        return tr(fa, 'این ایمیل به حساب Google دیگری متصل است.', 'This email is linked to a different Google account.');
      default:
        return tr(fa, 'خطایی رخ داد. دوباره تلاش کنید.', 'Something went wrong. Please try again.');
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (registerMode && fullName.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'نام و نام خانوادگی را وارد کنید.', 'Enter your full name.'))),
      );
      return;
    }
    final rawIdentifier = identifier.text.trim();
    final looksLikeEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(rawIdentifier);
    final looksLikePhone = RegExp(r'^\+?[0-9][0-9\s-]{6,31}$').hasMatch(rawIdentifier);
    if ((!looksLikeEmail && !looksLikePhone) || password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'ایمیل یا شماره معتبر و رمز حداقل ۸ کاراکتری وارد کنید.', 'Enter a valid email or phone number and a password of at least 8 characters.'))),
      );
      return;
    }
    if (registerMode && password.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'دو رمز عبور یکسان نیست.', 'Passwords do not match.'))),
      );
      return;
    }
    final ok = registerMode
        ? await widget.controller.register(fullName.text, identifier.text, password.text)
        : await widget.controller.login(identifier.text, password.text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(widget.controller.authError ?? 'unknown'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final fa = c.fa;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Center(child: BrandMark(size: 66)),
            const SizedBox(height: 42),
            Text(
              registerMode ? tr(fa, 'ساخت حساب VELIXEO', 'Create your VELIXEO account') : tr(fa, 'ورود به حساب کاربری', 'Welcome back'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              registerMode ? tr(fa, 'حساب واقعی شما روی سرور امن VELIXEO ساخته می‌شود.', 'Your account is created on the secure VELIXEO backend.') : tr(fa, 'برای ادامه وارد حساب خود شوید.', 'Sign in to continue.'),
              style: const TextStyle(color: Color(0xFF607487)),
            ),
            const SizedBox(height: 28),
            if (registerMode) ...[
              TextField(
                controller: fullName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.badge_outlined),
                  hintText: tr(fa, 'نام و نام خانوادگی', 'Full name'),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: identifier,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.alternate_email),
                hintText: tr(fa, 'ایمیل یا شماره موبایل', 'Email or phone number'),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              obscureText: hidden,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline),
                hintText: tr(fa, 'رمز عبور', 'Password'),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (registerMode) ...[
              const SizedBox(height: 14),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  hintText: tr(fa, 'تکرار رمز عبور', 'Confirm password'),
                ),
              ),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: c.authBusy
                  ? tr(fa, 'لطفاً صبر کنید...', 'Please wait...')
                  : registerMode
                      ? tr(fa, 'ساخت حساب', 'Create account')
                      : tr(fa, 'ورود', 'Sign in'),
              onPressed: c.authBusy ? null : submit,
            ),
            if (!registerMode) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(tr(fa, 'یا', 'or')),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
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
            ],
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: c.authBusy
                  ? null
                  : () => setState(() {
                        registerMode = !registerMode;
                        confirm.clear();
                      }),
              child: Text(
                registerMode
                    ? tr(fa, 'حساب دارید؟ وارد شوید', 'Already have an account? Sign in')
                    : tr(fa, 'حساب ندارید؟ ثبت‌نام کنید', 'New here? Create account'),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: () => c.setLanguage(fa ? AppLang.en : AppLang.fa),
                icon: const Icon(Icons.language),
                label: Text(fa ? 'English' : 'فارسی'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _serviceDestination(AppController c, ServiceItem service) {
  if (service.en == 'Social Media') return SocialPanelPage(host: c);
  if (service.en == 'Virtual Numbers') return VirtualNumberPanelPage(host: c);
  return ServicePreviewPage(controller: c, service: service);
}

Widget _catalogDestination(AppController c, CatalogService service) {
  if (service.category == 'SOCIAL') return SocialPanelPage(host: c);
  if (service.category == 'VIRTUAL_NUMBER') return VirtualNumberPanelPage(host: c);
  return CatalogServicePage(controller: c, service: service);
}

Future<void> _openServiceSearch(BuildContext context, AppController c) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceSearchPage(controller: c)));
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      HomePage(controller: c),
      ServicesPage(controller: c),
      OrdersPage(controller: c),
      WalletPage(controller: c),
      ProfilePage(controller: c),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE9EEF5))),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Services'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  static const services = [
    ServiceItem('شبکه‌های اجتماعی', 'Social Media', Icons.favorite_rounded, Color(0xFF7857FF)),
    ServiceItem('شماره مجازی', 'Virtual Numbers', Icons.phone_iphone_rounded, Color(0xFF28A9FF)),
    ServiceItem('پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFFF3A523)),
    ServiceItem('شارژ موبایل', 'Mobile Top-up', Icons.sim_card_rounded, Color(0xFF12B8A6)),
    ServiceItem('اکانت دیجیتال', 'Digital Accounts', Icons.account_circle_rounded, Color(0xFF5B6EF5)),
    ServiceItem('پروموشن', 'Promotions', Icons.campaign_rounded, Color(0xFFE84D93)),
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED': return const Color(0xFF18A875);
      case 'PROCESSING':
      case 'IN_PROGRESS': return const Color(0xFF1686FF);
      case 'FAILED':
      case 'CANCELLED': return const Color(0xFFE65454);
      default: return const Color(0xFFF0A326);
    }
  }

  String _firstName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'there';
    return clean.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? 'VELIXEO User';
    final heroBanners = c.banners.where((b) => b.placement == 'HOME_HERO').toList(growable: false);
    final popular = c.catalogServices.where((s) => s.featured).take(5).toList(growable: false);
    final livePopular = popular.isNotEmpty ? popular : c.catalogServices.take(5).toList(growable: false);
    final recent = c.orders.take(3).toList(growable: false);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, ${_firstName(identity)}!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF172235))),
                      const SizedBox(height: 3),
                      const Text('What would you like to do today?', style: TextStyle(fontSize: 12.5, color: Color(0xFF8793A3))),
                    ],
                  ),
                ),
                _TopCircleButton(
                  icon: Icons.notifications_none_rounded,
                  badge: c.unreadNotificationCount,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(controller: c))),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF51BEFF), Color(0xFF1686FF)])),
                  child: Center(child: Text(_firstName(identity).substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF1265D6), Color(0xFF1895FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: const [BoxShadow(color: Color(0x221686FF), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wallet Balance', style: TextStyle(color: Color(0xFFCDE7FF), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(c.money(c.balanceAfn), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                        const SizedBox(height: 4),
                        Text(c.secondaryBalance(), style: const TextStyle(color: Color(0xFFD9ECFF), fontSize: 11.5)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1686FF), minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WalletPage(controller: c))),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add funds', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            if (heroBanners.isNotEmpty) ...[
              const SizedBox(height: 14),
              RemoteBannerCard(controller: c, banner: heroBanners.first),
            ] else ...[
              const SizedBox(height: 14),
              Container(
                height: 126,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF101F3B), borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Text('Grow your social presence', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 6),
                    Text('Fast, reliable digital services in one place.', style: TextStyle(color: Color(0xFFBFD0E6), fontSize: 12, height: 1.4)),
                  ])),
                  Container(width: 62, height: 62, decoration: BoxDecoration(color: const Color(0xFF1686FF).withValues(alpha: .18), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF51BEFF), size: 32)),
                ]),
              ),
            ],
            const SizedBox(height: 19),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openServiceSearch(context, c),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE4EAF1))),
                child: const Row(children: [Icon(Icons.search_rounded, color: Color(0xFF8D99A9), size: 21), SizedBox(width: 10), Expanded(child: Text('Search services...', style: TextStyle(color: Color(0xFF9AA6B6), fontSize: 13.5))), Icon(Icons.tune_rounded, color: Color(0xFF6B7787), size: 19)]),
              ),
            ),
            const SizedBox(height: 23),
            const _HomeSectionHeader(title: 'Services', action: 'View all'),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .90),
              itemBuilder: (context, i) {
                final service = services[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _serviceDestination(c, service))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE8EDF3))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 43, height: 43, decoration: BoxDecoration(color: service.color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Icon(service.icon, color: service.color, size: 23)),
                      const SizedBox(height: 9),
                      Text(service.en, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF273447))),
                    ]),
                  ),
                );
              },
            ),
            if (livePopular.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _HomeSectionHeader(title: 'Popular services', action: 'See all'),
              const SizedBox(height: 12),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: livePopular.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final service = livePopular[i];
                    final color = catalogColor(service.category);
                    return InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _catalogDestination(c, service))),
                      child: Container(
                        width: 176,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE8EDF3))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)), child: Icon(catalogIcon(service.category), color: color, size: 19)), const Spacer(), if (service.basePriceAfn != null) Text(c.money(service.basePriceAfn!), style: const TextStyle(fontSize: 11, color: Color(0xFF1686FF), fontWeight: FontWeight.w900))]),
                          const SizedBox(height: 10),
                          Text(service.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF253247))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _HomeSectionHeader(title: 'Recent orders', action: 'View all'),
              const SizedBox(height: 10),
              ...recent.map((order) {
                final color = _statusColor(order.status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8EDF3))),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF1686FF).withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Icon(catalogIcon(order.category), color: const Color(0xFF1686FF), size: 20)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${order.serviceTitleEn ?? order.serviceSlug ?? order.category}${order.isDripRun ? ' · Run ${order.dripRunIndex}/${order.dripRunsAll}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(c.money(order.totalAmountAfn), style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C8999)))])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)), child: Text(order.status.replaceAll('_', ' '), style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w800))),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Stack(clipBehavior: Clip.none, children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE5EBF2))), child: Icon(icon, color: const Color(0xFF566274), size: 21)),
      if (badge > 0) Positioned(right: -1, top: -2, child: Container(constraints: const BoxConstraints(minWidth: 17), height: 17, padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: const Color(0xFFFF4D67), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)), child: Center(child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))))),
    ]),
  );
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1A2739)))), Text(action, style: const TextStyle(color: Color(0xFF1686FF), fontSize: 12, fontWeight: FontWeight.w800))]);
}

class WalletHero extends StatelessWidget {
  const WalletHero({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1265D6), Color(0xFF1895FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x201686FF), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Available balance', style: TextStyle(color: Color(0xFFD4E9FF), fontSize: 12)),
          const SizedBox(height: 6),
          Text(c.money(c.balanceAfn), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(c.secondaryBalance(), style: const TextStyle(color: Color(0xFFD8EBFF), fontSize: 11)),
        ])),
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 25)),
      ]),
    );
  }
}

IconData catalogIcon(String category) {
  switch (category) {
    case 'VIRTUAL_NUMBER':
      return Icons.phone_android_rounded;
    case 'PREMIUM':
      return Icons.workspace_premium_rounded;
    case 'DIGITAL_ACCOUNT':
      return Icons.manage_accounts_rounded;
    case 'MOBILE_TOPUP':
      return Icons.sim_card_rounded;
    case 'PROMOTION':
      return Icons.campaign_rounded;
    default:
      return Icons.trending_up_rounded;
  }
}

Color catalogColor(String category) {
  switch (category) {
    case 'VIRTUAL_NUMBER':
      return const Color(0xFF22A8F5);
    case 'PREMIUM':
      return const Color(0xFFFFA928);
    case 'DIGITAL_ACCOUNT':
      return const Color(0xFF6366F1);
    case 'MOBILE_TOPUP':
      return const Color(0xFF14B8A6);
    case 'PROMOTION':
      return const Color(0xFFEC4899);
    default:
      return const Color(0xFF8B5CF6);
  }
}

class ServiceSearchPage extends StatefulWidget {
  const ServiceSearchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ServiceSearchPage> createState() => _ServiceSearchPageState();
}

class _ServiceSearchPageState extends State<ServiceSearchPage> {
  final query = TextEditingController();

  @override
  void initState() {
    super.initState();
    query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  bool matches(String value) => value.toLowerCase().contains(query.text.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = query.text.trim();
    final categories = HomePage.services.where((item) => q.isEmpty || matches(item.fa) || matches(item.en)).toList(growable: false);
    final live = c.catalogServices.where((item) => q.isEmpty || matches(item.titleFa) || matches(item.titleEn) || matches(item.slug) || matches(item.category)).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'جستجوی خدمات', 'Search services'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: query,
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'نام سرویس، شبکه یا دسته...', 'Service, platform or category...'), suffixIcon: q.isEmpty ? null : IconButton(onPressed: query.clear, icon: const Icon(Icons.close))),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty && live.isEmpty)
            EmptyCard(icon: Icons.search_off_rounded, title: tr(c.fa, 'نتیجه‌ای پیدا نشد', 'No results found'), subtitle: tr(c.fa, 'عبارت دیگری جستجو کنید.', 'Try another search.')),
          ...categories.map((service) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SoftCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _serviceDestination(c, service))),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: service.color.withValues(alpha: .10), child: Icon(service.icon, color: service.color)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.fa ? service.fa : service.en, style: const TextStyle(fontWeight: FontWeight.w900))),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              )),
          if (live.isNotEmpty) ...[
            const SizedBox(height: 7),
            SectionTitle(tr(c.fa, 'سرویس‌های فعال', 'Live services')),
            ...live.map((service) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SoftCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _catalogDestination(c, service))),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: catalogColor(service.category).withValues(alpha: .10), child: Icon(catalogIcon(service.category), color: catalogColor(service.category))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text(service.category, style: const TextStyle(fontSize: 10, color: Color(0xFF607487))),
                      ])),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Text(tr(c.fa, 'خدمات', 'Services'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                const BrandMark(size: 34, wordmark: false),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              onTap: () => _openServiceSearch(context, c),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'جستجوی سرویس...', 'Search services...'), suffixIcon: const Icon(Icons.arrow_forward_rounded)),
            ),
            const SizedBox(height: 18),
            if (c.catalogServices.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFE2A5)),
                ),
                child: Text(
                  tr(c.fa, 'کاتالوگ زنده هنوز از پنل ادمین پر نشده؛ فعلاً دسته‌بندی‌های اصلی نمایش داده می‌شوند.', 'The live catalog is still empty in Admin, so the main categories are shown for now.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8D6119)),
                ),
              ),
              ...HomePage.services.map(
                (service) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _serviceDestination(c, service)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: service.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                          child: Icon(service.icon, color: service.color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(c.fa ? service.fa : service.en, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              if (c.catalogServices.any((service) => service.category == 'SOCIAL'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SocialPanelPage(host: c)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.trending_up_rounded, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(c.fa, 'شبکه‌های اجتماعی', 'Social Media'), style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(tr(c.fa, 'سفارش جدید، پیگیری، جبران و لغو', 'Order, track, refill and cancel'), style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ...c.catalogServices.where((service) => service.category != 'SOCIAL').map((service) {
                final color = catalogColor(service.category);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _catalogDestination(c, service)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                          child: Icon(catalogIcon(service.category), color: color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                service.basePriceAfn == null
                                    ? tr(c.fa, 'قیمت از Provider دریافت می‌شود', 'Live provider pricing')
                                    : tr(c.fa, 'از ${c.money(service.basePriceAfn!)}', 'From ${c.money(service.basePriceAfn!)}'),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
                              ),
                            ],
                          ),
                        ),
                        if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928), size: 20),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class CatalogServicePage extends StatelessWidget {
  const CatalogServicePage({super.key, required this.controller, required this.service});
  final AppController controller;
  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    final color = catalogColor(service.category);
    final description = fa ? service.descriptionFa : service.descriptionEn;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? service.titleFa : service.titleEn)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Center(child: Icon(catalogIcon(service.category), size: 72, color: color)),
          ),
          const SizedBox(height: 20),
          if (description?.trim().isNotEmpty == true)
            Text(description!, style: const TextStyle(color: Color(0xFF607487), height: 1.55)),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Text(tr(fa, 'قیمت پایه', 'Base price')),
                    const Spacer(),
                    Text(
                      service.basePriceAfn == null ? tr(fa, 'قیمت زنده', 'Live price') : controller.money(service.basePriceAfn!, showBase: true),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                if (service.minQty != null || service.maxQty != null) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text(tr(fa, 'محدوده سفارش', 'Order range')),
                      const Spacer(),
                      Text('${service.minQty ?? '—'} – ${service.maxQty ?? '—'}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr(
              fa,
              'این خدمت از پنل مدیریت VELIXEO کنترل می‌شود. خرید زمانی فعال می‌شود که Provider واقعی برای همین Service Route متصل و تست شود.',
              'This service is controlled from VELIXEO Admin. Purchasing will activate only after a real provider route is connected and verified.',
            ),
            style: const TextStyle(color: Color(0xFF607487), height: 1.5),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: tr(fa, 'خرید پس از اتصال Provider فعال می‌شود', 'Purchase unlocks after provider integration'), onPressed: null),
        ],
      ),
    );
  }
}

class ServicePreviewPage extends StatelessWidget {
  const ServicePreviewPage({super.key, required this.controller, required this.service});
  final AppController controller;
  final ServiceItem service;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? service.fa : service.en)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            height: 170,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [service.color.withValues(alpha: .82), service.color]),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Center(child: Icon(service.icon, size: 82, color: Colors.white)),
          ),
          const SizedBox(height: 22),
          Text(
            tr(fa, 'زیرساخت این سرویس در مرحله اتصال API است', 'Provider integration is the next step for this service'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              fa,
              'حساب کاربری و کیف پول این نسخه واقعی هستند. برای جلوگیری از سفارش جعلی، خرید این سرویس تا اتصال Provider واقعی غیرفعال نگه داشته شده است.',
              'Accounts and wallet are live in this build. Purchasing stays disabled until a real provider API is connected, so the app never creates fake orders.',
            ),
            style: const TextStyle(color: Color(0xFF607487), height: 1.55),
          ),
          const SizedBox(height: 22),
          const SoftCard(
            child: Row(
              children: [
                CircleAvatar(backgroundColor: Color(0xFFE4F4FF), child: Icon(Icons.api_rounded, color: Color(0xFF0D78C8))),
                SizedBox(width: 12),
                Expanded(child: Text('Backend Adapter → Provider API', style: TextStyle(fontWeight: FontWeight.w800))),
                Icon(Icons.lock_outline, color: Color(0xFF607487)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: tr(fa, 'درحال اتصال', 'Integration pending'), onPressed: null),
        ],
      ),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.controller});
  final AppController controller;

  String statusLabel(bool fa, String status) {
    switch (status) {
      case 'PROCESSING':
        return tr(fa, 'در حال انجام', 'Processing');
      case 'COMPLETED':
        return tr(fa, 'تکمیل', 'Completed');
      case 'PARTIAL':
        return tr(fa, 'نیمه‌کامل', 'Partial');
      case 'AWAITING_SMS':
        return tr(fa, 'در انتظار SMS', 'Awaiting SMS');
      case 'CANCELLED':
        return tr(fa, 'لغو شده', 'Cancelled');
      case 'FAILED':
        return tr(fa, 'ناموفق', 'Failed');
      case 'REFUNDED':
        return tr(fa, 'برگشت وجه', 'Refunded');
      default:
        return tr(fa, 'در انتظار', 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(tr(c.fa, 'سفارش‌های من', 'My Orders'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            if (c.orders.isEmpty) ...[
              const SizedBox(height: 60),
              const Icon(Icons.receipt_long_outlined, size: 74, color: Color(0xFF9BB1C4)),
              const SizedBox(height: 18),
              Text(
                tr(c.fa, 'هنوز سفارش واقعی ثبت نشده است', 'No live orders yet'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                tr(c.fa, 'بعد از اتصال Provider، سفارش‌های واقعی از Backend همین‌جا نمایش داده می‌شوند.', 'Real backend orders will appear here after provider integration.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF607487)),
              ),
            ] else ...[
              ...c.orders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${c.fa ? (order.serviceTitleFa ?? order.category) : (order.serviceTitleEn ?? order.category)}${order.isDripRun ? ' · ${tr(c.fa, 'اجرای', 'Run')} ${order.dripRunIndex}/${order.dripRunsAll}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(999)),
                              child: Text(statusLabel(c.fa, order.status), style: const TextStyle(fontSize: 11, color: Color(0xFF0D78C8), fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(c.money(order.totalAmountAfn, showBase: true), style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          '${order.createdAt.toLocal().toString().substring(0, 16)} • #${order.dripParentOrderId?.substring(0, 8) ?? order.id.substring(0, 8)}${order.isDripRun ? '-R${order.dripRunIndex}' : ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
                        ),
                        if (order.failureReason?.isNotEmpty == true) ...[
                          const SizedBox(height: 7),
                          Text(order.failureReason!, style: const TextStyle(fontSize: 12, color: Color(0xFFE65454))),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr(c.fa, 'اعلان‌ها', 'Notifications')),
          actions: [
            if (c.unreadNotificationCount > 0)
              TextButton(
                onPressed: c.markAllNotificationsRead,
                child: Text(tr(c.fa, 'خواندن همه', 'Read all')),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              if (c.notifications.isEmpty)
                EmptyCard(
                  icon: Icons.notifications_none_rounded,
                  title: tr(c.fa, 'اعلانی ندارید', 'No notifications'),
                  subtitle: tr(c.fa, 'اعلان‌های عمومی یا اختصاصی از پنل مدیریت اینجا نمایش داده می‌شوند.', 'Admin announcements and personal notifications will appear here.'),
                )
              else
                ...c.notifications.map(
                  (notice) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => c.markNotificationRead(notice),
                      child: SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    c.fa ? notice.titleFa : notice.titleEn,
                                    style: TextStyle(
                                      fontWeight: notice.isRead ? FontWeight.w700 : FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (!notice.isRead)
                                  Container(
                                    width: 9,
                                    height: 9,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1686FF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              c.fa ? notice.bodyFa : notice.bodyEn,
                              style: TextStyle(
                                color: notice.isRead ? const Color(0xFF7D8998) : const Color(0xFF4F6073),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    notice.publishAt.toLocal().toString().substring(0, 16),
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF8AA0B3)),
                                  ),
                                ),
                                Text(
                                  notice.isRead ? tr(c.fa, 'خوانده شده', 'Read') : tr(c.fa, 'جدید', 'New'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: notice.isRead ? const Color(0xFF8AA0B3) : const Color(0xFF1686FF),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class RemoteBannerCard extends StatelessWidget {
  const RemoteBannerCard({super.key, required this.controller, required this.banner});
  final AppController controller;
  final AppBanner banner;

  Future<void> openAction(BuildContext context) async {
    final raw = banner.actionUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (uri.scheme == 'velixeo') {
      final target = uri.host.isNotEmpty ? uri.host : uri.path.replaceFirst('/', '');
      if (target == 'social') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SocialPanelPage(host: controller)));
      } else if (target == 'virtual-numbers' || target == 'virtual') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => VirtualNumberPanelPage(host: controller)));
      } else if (target == 'wallet') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AddFundsPage(controller: controller)));
      } else if (target == 'support') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: controller)));
      } else if (target == 'services') {
        await _openServiceSearch(context, controller);
      }
      return;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    final title = fa ? banner.titleFa : banner.titleEn;
    final subtitle = fa ? banner.subtitleFa : banner.subtitleEn;
    final action = fa ? banner.actionLabelFa : banner.actionLabelEn;
    final clickable = banner.actionUrl?.trim().isNotEmpty == true;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: clickable ? () => openAction(context) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0D78C8), Color(0xFF31A8FF)])),
                ),
              ),
              Container(color: Colors.black.withValues(alpha: .24)),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (title?.trim().isNotEmpty == true) Text(title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                    if (action?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(action!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        if (clickable) const Padding(padding: EdgeInsetsDirectional.only(start: 5), child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletPage extends StatelessWidget {
  const WalletPage({super.key, required this.controller});
  final AppController controller;

  String entryStatus(bool fa, WalletEntry entry) {
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
    if (entry.description.isNotEmpty) return entry.description;
    switch (entry.type) {
      case 'MANUAL_CREDIT':
        return tr(fa, 'افزایش موجودی توسط مدیر', 'Manual wallet credit');
      case 'MANUAL_DEBIT':
        return tr(fa, 'کسر موجودی توسط مدیر', 'Manual wallet debit');
      case 'REFUND':
        return tr(fa, 'برگشت وجه', 'Refund');
      case 'PURCHASE':
        return tr(fa, 'خرید', 'Purchase');
      default:
        return tr(fa, 'تراکنش کیف پول', 'Wallet transaction');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Text(tr(c.fa, 'کیف پول', 'Wallet'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                if (c.refreshing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 16),
            WalletHero(controller: c),
            const SizedBox(height: 18),
            PrimaryButton(
              label: tr(c.fa, 'افزایش موجودی', 'Add funds'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddFundsPage(controller: c))),
            ),
            const SizedBox(height: 24),
            SectionTitle(tr(c.fa, 'تراکنش‌های واقعی', 'Live transactions')),
            if (c.walletEntries.isEmpty)
              EmptyCard(
                icon: Icons.history,
                title: tr(c.fa, 'هنوز تراکنشی ندارید', 'No transactions yet'),
                subtitle: tr(c.fa, 'تراکنش‌های کیف پول بعد از ایجاد اینجا ثبت می‌شوند.', 'Wallet ledger entries will appear here.'),
              )
            else
              ...c.walletEntries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransactionTile(
                    title: entryTitle(c.fa, entry),
                    subtitle: '${entryStatus(c.fa, entry)} • ${entry.createdAt.toLocal().toString().substring(0, 16)} • ${tr(c.fa, 'موجودی بعد', 'Balance after')}: ${entry.balanceAfterAfn} AFN',
                    amount: '${entry.amountAfn >= 0 ? '+' : ''}${c.money(entry.amountAfn)}',
                    positive: entry.amountAfn >= 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AddFundsPage extends StatefulWidget {
  const AddFundsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AddFundsPage> createState() => _AddFundsPageState();
}

class _AddFundsPageState extends State<AddFundsPage>
    with WidgetsBindingObserver {
  final TextEditingController amount = TextEditingController(text: '500');
  bool busy = false;
  bool checkoutOpened = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.refreshPaymentsAndWallet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    amount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && checkoutOpened) {
      checkoutOpened = false;
      c.refreshPaymentsAndWallet();
      if (mounted) setState(() {});
    }
  }

  String statusLabel(String status) {
    switch (status) {
      case 'PAID':
        return tr(c.fa, 'پرداخت موفق', 'Paid');
      case 'FAILED':
        return tr(c.fa, 'ناموفق', 'Failed');
      case 'CANCELLED':
        return tr(c.fa, 'لغو شده', 'Cancelled');
      case 'REFUNDED':
        return tr(c.fa, 'برگشت وجه', 'Refunded');
      default:
        return tr(c.fa, 'در انتظار تأیید', 'Pending verification');
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'PAID':
        return const Color(0xFF18A875);
      case 'FAILED':
      case 'CANCELLED':
        return const Color(0xFFE65454);
      default:
        return const Color(0xFFEFAF38);
    }
  }

  String errorLabel(Object error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'hesabpay_not_configured':
        case 'hesabpay_configuration_invalid':
          return tr(c.fa, 'درگاه حساب‌پی هنوز روی سرور فعال نشده است.', 'HesabPay is not configured on the server yet.');
        case 'hesabpay_unavailable':
        case 'hesabpay_session_failed':
          return tr(c.fa, 'ارتباط با حساب‌پی برقرار نشد. دوباره تلاش کنید.', 'Could not reach HesabPay. Please try again.');
        case 'unauthorized':
          return tr(c.fa, 'نشست شما پایان یافته؛ دوباره وارد شوید.', 'Your session has expired. Please sign in again.');
        default:
          return tr(c.fa, 'ایجاد پرداخت انجام نشد. دوباره تلاش کنید.', 'Could not create the payment. Please try again.');
      }
    }
    return tr(c.fa, 'خطای ارتباطی رخ داد.', 'A network error occurred.');
  }

  Future<void> refresh() => c.refreshPaymentsAndWallet();

  Future<void> startPayment() async {
    FocusScope.of(context).unfocus();
    final value = int.tryParse(amount.text.trim());
    if (value == null || value < 1 || value > 100000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'مبلغ معتبر به افغانی وارد کنید.', 'Enter a valid AFN amount.'))),
      );
      return;
    }
    if (!c.paymentCapabilities.hesabPayConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'درگاه حساب‌پی هنوز روی سرور فعال نشده است.', 'HesabPay is not configured on the server yet.'))),
      );
      return;
    }

    setState(() => busy = true);
    try {
      final session = await c.createHesabPayTopUp(value);
      final checkoutUrl = session.checkoutUrl;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'جلسه پرداخت درحال آماده‌سازی است. چند لحظه بعد تازه‌سازی کنید.', 'The payment session is still initializing. Refresh in a moment.'))),
        );
        return;
      }

      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null || !['https', 'http'].contains(uri.scheme)) {
        throw const ApiException('invalid_checkout_url');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw const ApiException('checkout_launch_failed');
      checkoutOpened = true;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorLabel(error))),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = c.paymentCapabilities.hesabPayConfigured;
    final environment = c.paymentCapabilities.hesabPayEnvironment;
    final recent = c.payments.take(8).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(c.fa, 'افزایش موجودی', 'Add Funds')),
        actions: [
          IconButton(
            tooltip: tr(c.fa, 'تازه‌سازی', 'Refresh'),
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: configured
                        ? const Color(0xFFE4F8EF)
                        : const Color(0xFFFFF4DE),
                    child: Icon(
                      configured ? Icons.verified_rounded : Icons.schedule_rounded,
                      color: configured
                          ? const Color(0xFF18A875)
                          : const Color(0xFFEFAF38),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HesabPay • حساب‌پی', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          configured
                              ? tr(c.fa, 'آماده پرداخت • ${environment ?? '—'}', 'Ready • ${environment ?? '—'}')
                              : tr(c.fa, 'منتظر تنظیم امن در سرور', 'Waiting for secure server configuration'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(c.fa, 'مبلغ شارژ کیف پول', 'Wallet top-up amount'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr(c.fa, 'مبلغ به افغانی', 'Amount in AFN'),
                      suffixText: 'AFN',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [100, 500, 1000, 5000]
                        .map(
                          (value) => OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => amount.text = '$value'),
                            child: Text('$value AFN'),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: busy
                        ? tr(c.fa, 'درحال ایجاد پرداخت…', 'Creating payment…')
                        : configured
                            ? tr(c.fa, 'پرداخت با حساب‌پی', 'Pay with HesabPay')
                            : tr(c.fa, 'درگاه هنوز فعال نیست', 'Gateway not active yet'),
                    onPressed: configured && !busy ? startPayment : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4EBFA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF0D78C8)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        c.fa,
                        'بازگشت از صفحه پرداخت به‌تنهایی موجودی را تغییر نمی‌دهد. کیف پول فقط بعد از تأیید امضای Webhook در Backend و تطبیق دقیق مبلغ شارژ می‌شود.',
                        'Returning from checkout never credits the wallet by itself. Balance changes only after the backend verifies the webhook signature and exact amount.',
                      ),
                      style: const TextStyle(color: Color(0xFF49657A), height: 1.5, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionTitle(tr(c.fa, 'پرداخت‌های اخیر', 'Recent payments')),
            if (recent.isEmpty)
              EmptyCard(
                icon: Icons.payments_outlined,
                title: tr(c.fa, 'هنوز پرداختی ثبت نشده', 'No payments yet'),
                subtitle: tr(c.fa, 'تلاش‌های پرداخت و وضعیت تأییدشده آن‌ها اینجا نمایش داده می‌شود.', 'Payment attempts and their verified status will appear here.'),
              )
            else
              ...recent.map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.money(payment.amountAfn, showBase: true),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: statusColor(payment.status).withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel(payment.status),
                                style: TextStyle(
                                  color: statusColor(payment.status),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${payment.gateway} • ${payment.createdAt.toLocal().toString().substring(0, 16)} • #${payment.id.substring(0, 8)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF607487)),
                        ),
                        if (payment.status == 'PAID' && payment.verifiedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr(c.fa, 'تأیید سرور انجام شده و کیف پول شارژ شده است.', 'Server verified; wallet credit completed.'),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF18A875)),
                          ),
                        ],
                        if (payment.failureReason?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            payment.failureReason!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFE65454)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final identity = c.user?.email ?? c.user?.phone ?? '—';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(tr(c.fa, 'پروفایل', 'Profile'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          SoftCard(
            child: Row(
              children: [
                const CircleAvatar(radius: 30, backgroundColor: Color(0xFFE4F4FF), child: Icon(Icons.person_outline, size: 30, color: Color(0xFF0D78C8))),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.user?.fullName?.trim().isNotEmpty == true ? c.user!.fullName! : tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      Text(identity, style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                      const SizedBox(height: 3),
                      Text(c.user?.role ?? 'USER', style: const TextStyle(fontSize: 11, color: Color(0xFF18A875), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Icon(Icons.verified_user_outlined, color: Color(0xFF18A875)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SettingsTile(
            icon: Icons.manage_accounts_outlined,
            title: tr(c.fa, 'ویرایش پروفایل', 'Edit profile'),
            value: c.user?.fullName ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditProfilePage(controller: c)),
            ),
          ),
          if (c.user?.hasPassword == true)
            SettingsTile(
              icon: Icons.password_rounded,
              title: tr(c.fa, 'تغییر رمز عبور', 'Change password'),
              value: '',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChangePasswordPage(controller: c)),
              ),
            ),
          SettingsTile(
            icon: Icons.language,
            title: tr(c.fa, 'زبان', 'Language'),
            value: c.fa ? 'فارسی' : 'English',
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('فارسی'),
                      trailing: c.fa ? const Icon(Icons.check, color: Color(0xFF0D78C8)) : null,
                      onTap: () {
                        Navigator.pop(context);
                        c.setLanguage(AppLang.fa);
                      },
                    ),
                    ListTile(
                      title: const Text('English'),
                      trailing: !c.fa ? const Icon(Icons.check, color: Color(0xFF0D78C8)) : null,
                      onTap: () {
                        Navigator.pop(context);
                        c.setLanguage(AppLang.en);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          SettingsTile(
            icon: Icons.currency_exchange,
            title: tr(c.fa, 'واحد نمایش قیمت', 'Display currency'),
            value: c.currency.name.toUpperCase(),
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: DisplayCurrency.values
                      .map(
                        (value) => ListTile(
                          title: Text(value == DisplayCurrency.afn
                              ? 'AFN • افغانی'
                              : value == DisplayCurrency.usd
                                  ? 'USD • Dollar'
                                  : 'TOMAN • تومان'),
                          trailing: c.currency == value ? const Icon(Icons.check, color: Color(0xFF0D78C8)) : null,
                          onTap: () {
                            Navigator.pop(context);
                            c.setCurrency(value);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
          SettingsTile(
            icon: Icons.support_agent_rounded,
            title: tr(c.fa, 'پشتیبانی و تیکت', 'Support & tickets'),
            value: '',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: c))),
          ),
          SettingsTile(
            icon: Icons.cloud_done_outlined,
            title: tr(c.fa, 'وضعیت سرور', 'Server status'),
            value: 'LIVE',
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.logout_rounded,
            title: tr(c.fa, 'خروج از حساب', 'Sign out'),
            value: '',
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(tr(c.fa, 'خروج از حساب؟', 'Sign out?')),
                content: Text(tr(c.fa, 'برای ورود دوباره باید اطلاعات حساب را وارد کنید.', 'You will need to sign in again.')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(c.fa, 'لغو', 'Cancel'))),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      c.logout();
                    },
                    child: Text(tr(c.fa, 'خروج', 'Sign out')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text('VELIXEO • Milestone 1', style: const TextStyle(color: Color(0xFF8AA0B4), fontSize: 12))),
        ],
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController fullName;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    fullName = TextEditingController(text: widget.controller.user?.fullName ?? '');
  }

  @override
  void dispose() {
    fullName.dispose();
    super.dispose();
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    if (fullName.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'نام معتبر وارد کنید.', 'Enter a valid full name.'))),
      );
      return;
    }
    setState(() => busy = true);
    final error = await widget.controller.updateFullName(fullName.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'پروفایل ذخیره شد.', 'Profile updated.'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'ذخیره پروفایل انجام نشد.', 'Could not update profile.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final identity = c.user?.email ?? c.user?.phone ?? '—';
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'ویرایش پروفایل', 'Edit profile'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: fullName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.badge_outlined),
              labelText: tr(c.fa, 'نام و نام خانوادگی', 'Full name'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            readOnly: true,
            controller: TextEditingController(text: identity),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email),
              labelText: tr(c.fa, 'ایمیل / شماره', 'Email / phone'),
              helperText: tr(c.fa, 'تغییر ایمیل یا شماره بعد از فعال‌شدن تأیید هویت اضافه می‌شود.', 'Email/phone changes will be enabled with identity verification.'),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: busy ? tr(c.fa, 'درحال ذخیره...', 'Saving...') : tr(c.fa, 'ذخیره تغییرات', 'Save changes'),
            onPressed: busy ? null : save,
          ),
        ],
      ),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool hidden = true;
  bool busy = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  String errorText(String code) {
    final fa = widget.controller.fa;
    switch (code) {
      case 'incorrect_current_password':
        return tr(fa, 'رمز فعلی نادرست است.', 'Current password is incorrect.');
      case 'new_password_must_differ':
        return tr(fa, 'رمز جدید باید با رمز فعلی متفاوت باشد.', 'New password must be different.');
      case 'weak_password':
      case 'invalid_request':
        return tr(fa, 'رمز جدید باید حداقل ۸ کاراکتر باشد.', 'New password must be at least 8 characters.');
      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد.', 'Could not reach the server.');
      default:
        return tr(fa, 'تغییر رمز انجام نشد.', 'Password could not be changed.');
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (next.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText('weak_password'))));
      return;
    }
    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز جدید و تکرار آن یکسان نیست.', 'New passwords do not match.'))),
      );
      return;
    }
    setState(() => busy = true);
    final error = await widget.controller.changePassword(current.text, next.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز عبور با موفقیت تغییر کرد.', 'Password changed successfully.'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'تغییر رمز عبور', 'Change password'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: current,
            obscureText: hidden,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.lock_outline), labelText: tr(c.fa, 'رمز فعلی', 'Current password')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: next,
            obscureText: hidden,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.password), labelText: tr(c.fa, 'رمز جدید', 'New password')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            obscureText: hidden,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              labelText: tr(c.fa, 'تکرار رمز جدید', 'Confirm new password'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => hidden = !hidden),
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: busy ? tr(c.fa, 'لطفاً صبر کنید...', 'Please wait...') : tr(c.fa, 'تغییر رمز', 'Change password'),
            onPressed: busy ? null : submit,
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({super.key, required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          onTap: onTap,
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0D78C8)),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (value.isNotEmpty) Text(value, style: const TextStyle(color: Color(0xFF607487))),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0D78C8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      );
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      );
}

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service, required this.fa, required this.onTap});
  final ServiceItem service;
  final bool fa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: service.color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: service.color.withValues(alpha: .14)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(color: service.color, borderRadius: BorderRadius.circular(14)),
                child: Icon(service.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                fa ? service.fa : service.en,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.title, required this.subtitle, required this.amount, required this.positive});
  final String title;
  final String subtitle;
  final String amount;
  final bool positive;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (positive ? const Color(0xFF18A875) : const Color(0xFFE65454)).withValues(alpha: .1),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF607487))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => SoftCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, size: 48, color: const Color(0xFF9BB1C4)),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF607487), fontSize: 12)),
            ],
          ),
        ),
      );
}

class ServiceItem {
  const ServiceItem(this.fa, this.en, this.icon, this.color);
  final String fa;
  final String en;
  final IconData icon;
  final Color color;
}
