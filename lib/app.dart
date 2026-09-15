import 'package:flutter/material.dart';

import 'core/api_service.dart';
import 'core/models.dart';

String tr(bool fa, String faText, String enText) => fa ? faText : enText;

class AppController extends ChangeNotifier {
  AppController(this.api);

  final ApiService api;

  AppLang language = AppLang.fa;
  DisplayCurrency currency = DisplayCurrency.afn;
  AppUser? user;
  int balanceAfn = 0;
  ExchangeRates rates = const ExchangeRates();
  List<WalletEntry> walletEntries = const [];
  bool booting = true;
  bool authenticated = false;
  bool authBusy = false;
  bool refreshing = false;
  bool languageConfirmed = false;
  String? authError;

  bool get fa => language == AppLang.fa;

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

  Future<void> logout() async {
    await api.logout();
    authenticated = false;
    user = null;
    balanceAfn = 0;
    walletEntries = const [];
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
    controller = AppController(ApiService());
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF31A8FF),
            primary: const Color(0xFF0D78C8),
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: const Color(0xFFF4FAFF),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFDCE8F1)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFDCE8F1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFDCE8F1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF0D78C8), width: 1.5),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr(c.fa, 'خانه', 'Home')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: tr(c.fa, 'خدمات', 'Services')),
          NavigationDestination(icon: const Icon(Icons.shopping_bag_outlined), selectedIcon: const Icon(Icons.shopping_bag), label: tr(c.fa, 'سفارش‌ها', 'Orders')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: tr(c.fa, 'کیف پول', 'Wallet')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr(c.fa, 'پروفایل', 'Profile')),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  static const services = [
    ServiceItem('شبکه‌های اجتماعی', 'Social Media', Icons.trending_up_rounded, Color(0xFF8B5CF6)),
    ServiceItem('شماره مجازی', 'Virtual Numbers', Icons.phone_android_rounded, Color(0xFF22A8F5)),
    ServiceItem('پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFFFFA928)),
    ServiceItem('اکانت دیجیتال', 'Digital Accounts', Icons.manage_accounts_rounded, Color(0xFF6366F1)),
    ServiceItem('شارژ موبایل', 'Mobile Credit', Icons.sim_card_rounded, Color(0xFF14B8A6)),
    ServiceItem('پروموشن', 'Promotions', Icons.campaign_rounded, Color(0xFFEC4899)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User');
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            Row(
              children: [
                const BrandMark(size: 38),
                const Spacer(),
                IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
                const CircleAvatar(radius: 18, child: Icon(Icons.person_outline)),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              tr(c.fa, 'سلام 👋', 'Hello 👋'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(identity, style: const TextStyle(color: Color(0xFF607487))),
            const SizedBox(height: 14),
            WalletHero(controller: c),
            const SizedBox(height: 18),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(c.fa, 'چه خدمتی نیاز دارید؟', 'What service do you need?'),
              ),
            ),
            const SizedBox(height: 22),
            SectionTitle(tr(c.fa, 'دسته‌بندی خدمات', 'Service categories')),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: .9,
              ),
              itemBuilder: (context, i) => ServiceCard(
                service: services[i],
                fa: c.fa,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServicePreviewPage(controller: c, service: services[i]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 150,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF102B70), Color(0xFF0D78C8), Color(0xFF31A8FF)],
                ),
              ),
              child: Stack(
                children: [
                  PositionedDirectional(
                    end: -14,
                    bottom: -24,
                    child: Icon(Icons.rocket_launch_rounded, size: 130, color: Colors.white.withValues(alpha: .12)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(c.fa, 'VELIXEO در حال واقعی‌شدن است', 'VELIXEO is going live'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(c.fa, 'حساب و کیف پول شما اکنون به سرور واقعی متصل است.', 'Your account and wallet are now connected to the live backend.'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                      const Icon(Icons.verified_rounded, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletHero extends StatelessWidget {
  const WalletHero({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final balance = c.balanceAfn.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF4DB8FF), Color(0xFF0D78C8)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(c.fa, 'موجودی کیف پول', 'Wallet balance'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text('$balance AFN', style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(c.secondaryBalance(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    tr(c.fa, 'موجودی زنده از سرور VELIXEO', 'Live balance from VELIXEO server'),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
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
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'جستجوی سرویس...', 'Search services...')),
          ),
          const SizedBox(height: 18),
          ...HomePage.services.map(
            (service) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: SoftCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ServicePreviewPage(controller: c, service: service)),
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

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(tr(c.fa, 'سفارش‌های من', 'My Orders'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 80),
          const Icon(Icons.receipt_long_outlined, size: 74, color: Color(0xFF9BB1C4)),
          const SizedBox(height: 18),
          Text(
            tr(c.fa, 'هنوز سفارش واقعی ثبت نشده است', 'No live orders yet'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            tr(c.fa, 'با اتصال اولین Provider، سفارش‌ها از همین بخش نمایش داده می‌شوند.', 'Orders will appear here once the first provider is connected.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF607487)),
          ),
        ],
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

class AddFundsPage extends StatelessWidget {
  const AddFundsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'افزایش موجودی', 'Add Funds'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SizedBox(height: 8),
          const SoftCard(
            child: Row(
              children: [
                CircleAvatar(backgroundColor: Color(0xFFE4F8EF), child: Icon(Icons.bolt_rounded, color: Color(0xFF18A875))),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HesabPay • حساب‌پی', style: TextStyle(fontWeight: FontWeight.w900)),
                      SizedBox(height: 3),
                      Text('Payment gateway integration', style: TextStyle(fontSize: 12, color: Color(0xFF607487))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            tr(c.fa, 'مرحله بعد: اتصال پرداخت واقعی حساب‌پی', 'Next: live HesabPay integration'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              c.fa,
              'این دکمه عمداً تا تأیید Webhook و Session API حساب‌پی فعال نمی‌شود. بعد از اتصال، فقط پرداخت تأییدشده در Backend کیف پول را شارژ خواهد کرد.',
              'This button intentionally remains disabled until HesabPay session creation and webhook verification are connected. Only backend-verified payments will credit the wallet.',
            ),
            style: const TextStyle(color: Color(0xFF607487), height: 1.55),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: tr(c.fa, 'درگاه درحال اتصال', 'Gateway integration pending'), onPressed: null),
        ],
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
