import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:country_picker/country_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import 'core/api_service.dart';
import 'core/google_auth_service.dart';
import 'core/models.dart';
import 'core/push_service.dart';
import 'core/update_service.dart';
import 'design/velixeo_design.dart';
import 'social/social_panel.dart';
import 'support/support_page.dart';
import 'virtual_numbers/virtual_number_panel.dart';
import 'premium/premium_panel.dart';
import 'referrals/referral_page.dart';

// FIGMA_ENGLISH_V1 — UI implementation based on the approved English Figma file.

String tr(bool fa, String faText, String enText) => fa ? faText : enText;

class AppController extends ChangeNotifier implements SocialPanelHost, VirtualNumberPanelHost, PremiumPanelHost, SupportPanelHost, ReferralPanelHost {
  AppController(this.api, this.googleAuth);

  final ApiService api;
  final GoogleAuthService googleAuth;
  final PushService pushService = PushService();

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
  VerificationCapabilities verificationCapabilities = const VerificationCapabilities();
  TwoFactorLoginChallenge? pendingTwoFactor;
  bool booting = true;
  bool authenticated = false;
  bool authBusy = false;
  bool refreshing = false;
  bool languageConfirmed = true;
  String? authError;
  Map<String, String>? _pendingNotificationOpen;
  ({String title, String body, Map<String, String> data})? _foregroundPush;

  bool get fa => language == AppLang.fa;
  bool get googleConfigured => googleAuth.configured;
  int get unreadNotificationCount => notifications.where((notice) => !notice.isRead).length;

  Future<void> boot() async {
    language = await api.restoreLanguage();
    currency = await api.restoreCurrency();
    try {
      verificationCapabilities = await api.verificationCapabilities();
    } catch (_) {}
    await api.restoreTokens();
    if (api.hasRefreshToken) {
      try {
        final result = await api.me();
        user = result.$1;
        balanceAfn = result.$2;
        authenticated = true;
        languageConfirmed = true;
        _applyUserPreferences(user!);
        booting = false;
        notifyListeners();
        _warmAuthenticatedData();
        return;
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

  Future<VerificationCapabilities> refreshVerificationCapabilities() async {
    try {
      verificationCapabilities = await api.verificationCapabilities();
      notifyListeners();
    } catch (_) {}
    return verificationCapabilities;
  }

  Future<bool> login(String identifier, String password) async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final attempt = await api.login(identifier: identifier, password: password);
      if (attempt.challenge != null) {
        pendingTwoFactor = attempt.challenge;
        authenticated = false;
        authError = null;
        return false;
      }
      final session = attempt.session!;
      pendingTwoFactor = null;
      user = session.user;
      authenticated = true;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      _warmAuthenticatedData();
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

  Future<bool> register(
    String fullName,
    String identifier,
    String password, {
    String? verificationToken,
    String? referralCode,
  }) async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final session = await api.register(
        fullName: fullName,
        identifier: identifier,
        password: password,
        language: language,
        verificationToken: verificationToken,
        referralCode: referralCode,
      );
      user = session.user;
      authenticated = true;
      balanceAfn = 0;
      _applyUserPreferences(session.user);
      _warmAuthenticatedData();
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


  Future<bool?> pollTwoFactorWhatsAppLogin() async {
    final challenge = pendingTwoFactor;
    if (challenge == null || !challenge.isWhatsAppInbound) {
      authError = 'two_factor_session_missing';
      notifyListeners();
      return false;
    }

    try {
      final session = await api.checkTwoFactorWhatsApp(
        loginToken: challenge.loginToken,
        challengeId: challenge.challengeId,
      );
      if (session == null) return null;

      pendingTwoFactor = null;
      user = session.user;
      authenticated = true;
      authError = null;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      _warmAuthenticatedData();
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      authError = error.code;
      notifyListeners();
      return false;
    } catch (_) {
      authError = 'network_error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> completeTwoFactorLogin(String code) async {
    final challenge = pendingTwoFactor;
    if (challenge == null) {
      authError = 'two_factor_session_missing';
      notifyListeners();
      return false;
    }
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      final session = await api.completeTwoFactorLogin(
        loginToken: challenge.loginToken,
        challengeId: challenge.challengeId,
        code: code,
      );
      pendingTwoFactor = null;
      user = session.user;
      authenticated = true;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      _warmAuthenticatedData();
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
      final attempt = await api.loginWithGoogle(idToken: idToken, language: language);
      if (attempt.challenge != null) {
        pendingTwoFactor = attempt.challenge;
        authenticated = false;
        authError = null;
        return false;
      }
      final session = attempt.session!;
      pendingTwoFactor = null;
      user = session.user;
      authenticated = true;
      _applyUserPreferences(session.user);
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      _warmAuthenticatedData();
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
      if (error.statusCode == 401 || error.statusCode == 403) {
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
    Future<void> loadRates() async {
      try { rates = await api.exchangeRates(); } catch (_) {}
    }
    Future<void> loadWallet() async {
      try { walletEntries = await api.walletEntries(); } catch (_) {}
    }
    Future<void> loadCatalog() async {
      try { catalogServices = (await api.catalogServices()).where((service) => !const ['PROMOTION', 'MOBILE_TOPUP'].contains(service.category)).toList(growable: false); } catch (_) {}
    }
    Future<void> loadBanners() async {
      try { banners = (await api.banners()).where((banner) => !const ['velixeo://promotions', 'velixeo://promotion'].contains(banner.actionUrl?.trim().toLowerCase())).toList(growable: false); } catch (_) {}
    }
    Future<void> loadNotifications() async {
      if (!authenticated) return;
      try { notifications = await api.notifications(); } catch (_) {}
    }
    Future<void> loadOrders() async {
      if (!authenticated) return;
      try { orders = await api.orders(); } catch (_) {}
    }
    // Load the data that paints the home/services screen first so the app feels
    // lighter and remote banners can appear without waiting for order/payment history.
    await Future.wait([
      loadRates(),
      loadWallet(),
      loadCatalog(),
      loadBanners(),
    ]);
    if (authenticated) notifyListeners();

    await Future.wait([
      loadNotifications(),
      loadOrders(),
    ]);
  }

  Future<void> refreshBalanceOnly() async {
    if (!authenticated) return;
    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
      notifyListeners();
    } catch (_) {}
  }

  void _warmAuthenticatedData() {
    unawaited(() async {
      await Future.wait([
        _loadSecondaryData(),
        _configurePush(),
      ]);
      if (authenticated) notifyListeners();
    }());
  }

  Map<String, String>? takePendingNotificationOpen() {
    final value = _pendingNotificationOpen;
    _pendingNotificationOpen = null;
    return value;
  }

  ({String title, String body, Map<String, String> data})? takeForegroundPush() {
    final value = _foregroundPush;
    _foregroundPush = null;
    return value;
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

  Future<void> _configurePush() async {
    if (!authenticated) return;
    try {
      await pushService.configure(
        api,
        onNotification: () async {
          if (!authenticated) return;
          try {
            notifications = await api.notifications();
            notifyListeners();
          } catch (_) {}
        },
        onNotificationOpened: (data) async {
          _pendingNotificationOpen = Map<String, String>.from(data);
          notifyListeners();
        },
        onForegroundNotification: (title, body, data) async {
          _foregroundPush = (title: title, body: body, data: Map<String, String>.from(data));
          notifyListeners();
        },
      );
    } catch (_) {
      // Push is optional at runtime. In-app notifications keep working if
      // Firebase credentials have not been configured yet.
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


  Future<String?> updateProfile({
    required String fullName,
    String? websiteUrl,
    String? countryCode,
    String? avatarPreset,
    String? avatarUrl,
    String? avatarData,
    String? email,
    String? phone,
    String? emailVerificationToken,
    String? phoneVerificationToken,
  }) async {
    final value = fullName.trim();
    if (value.length < 2) return 'invalid_name';
    try {
      user = await api.updateProfile(
        fullName: value,
        websiteUrl: websiteUrl,
        countryCode: countryCode,
        avatarPreset: avatarPreset,
        avatarUrl: avatarUrl,
        avatarData: avatarData,
        email: email,
        phone: phone,
        emailVerificationToken: emailVerificationToken,
        phoneVerificationToken: phoneVerificationToken,
      );
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

  Future<String?> updateFullName(String fullName) => updateProfile(fullName: fullName);

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

  Future<SecurityState?> loadSecurityState() async {
    try {
      return await api.securityState();
    } catch (_) {
      return null;
    }
  }

  Future<VerificationChallenge?> requestContactChangeOtp(String type, String target, String channel) async {
    try {
      return await api.requestContactChangeOtp(type: type, target: target, channel: channel);
    } on ApiException catch (error) {
      authError = error.code;
      notifyListeners();
      return null;
    } catch (_) {
      authError = 'network_error';
      notifyListeners();
      return null;
    }
  }

  Future<VerificationChallenge?> requestAccountOtp(String channel, String purpose) async {
    try {
      return await api.requestAccountOtp(channel: channel, purpose: purpose);
    } on ApiException catch (error) {
      authError = error.code;
      notifyListeners();
      return null;
    } catch (_) {
      authError = 'network_error';
      notifyListeners();
      return null;
    }
  }

  Future<String?> verifyAccountOtp(String challengeId, String code) async {
    try {
      return await api.verifyAccountOtp(challengeId: challengeId, code: code);
    } on ApiException catch (error) {
      authError = error.code;
      notifyListeners();
      return null;
    } catch (_) {
      authError = 'network_error';
      notifyListeners();
      return null;
    }
  }

  Future<String?> verifyContact(String verificationToken) async {
    try {
      user = await api.verifyContact(verificationToken);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> enableTwoFactor(String method, String verificationToken) async {
    try {
      user = await api.enableTwoFactor(method: method, verificationToken: verificationToken);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> disableTwoFactor({String? password}) async {
    try {
      user = await api.disableTwoFactor(password: password);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.code;
    } catch (_) {
      return 'network_error';
    }
  }

  Future<String?> setPassword(String newPassword) async {
    if (newPassword.length < 8) return 'weak_password';
    try {
      await api.setPassword(newPassword: newPassword);
      final result = await api.me();
      user = result.$1;
      notifyListeners();
      return null;
    } on ApiException catch (error) {
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

  Future<String?> deleteAccount({String? password, String? reason}) async {
    authBusy = true;
    authError = null;
    notifyListeners();
    try {
      await pushService.unregister(api);
      await api.deleteAccount(password: password, reason: reason);
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
      pendingTwoFactor = null;
      languageConfirmed = true;
      return null;
    } on ApiException catch (error) {
      authError = error.code;
      return error.code;
    } catch (_) {
      authError = 'network_error';
      return 'network_error';
    } finally {
      authBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await pushService.unregister(api);
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
    pendingTwoFactor = null;
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
        final theme = controller.fa ? VelixeoFaDesign.theme : VelixeoEnDesign.theme;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'VELIXEO',
          theme: theme,
          builder: (context, child) => Directionality(
            textDirection: controller.fa ? TextDirection.rtl : TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
          home: AppUpdateGate(
            fa: controller.fa,
            child: controller.booting
                ? SplashPage(fa: controller.fa)
                : controller.authenticated
                    ? MainShell(controller: controller)
                    : controller.languageConfirmed
                        ? AuthPage(controller: controller)
                        : LanguagePage(controller: controller),
          ),
        );
      },
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key, required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SplashBrandOrb(),
                  const SizedBox(height: 20),
                  const Text(
                    'VELIXEO.',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontFamily: 'Inter',
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: VelixeoDesign.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(fa, 'دنیای دیجیتال، در دسترس تو', 'Your digital world, within reach'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7892A4),
                    ),
                  ),
                  const SizedBox(height: 60),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      backgroundColor: Color(0xFFDCF2FB),
                      color: Color(0xFF36B1E4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(fa, 'در حال آماده‌سازی…', 'Getting everything ready…'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7892A4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SplashBrandOrb extends StatelessWidget {
  const _SplashBrandOrb();

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.14,
        child: Container(
          width: 86,
          height: 86,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(29),
            gradient: const LinearGradient(
              colors: [Color(0xFF78D9F6), Color(0xFF2FB0E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3030B4E5),
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: const Text(
            'V',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontFamily: 'Inter',
              color: Colors.white,
              fontSize: 49,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
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
          SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _LogoPainter()),
          ),
          if (wordmark) ...[
            SizedBox(width: size * .18),
            Text(
              'VELIXEO',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size * .43,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.7,
                color: const Color(0xFF092C56),
              ),
            ),
          ],
        ],
      );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 96;
    final sy = size.height / 96;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final main = Path()
      ..moveTo(19 * sx, 18 * sy)
      ..cubicTo(15 * sx, 18 * sy, 12 * sx, 20 * sy, 10.3 * sx, 23.2 * sy)
      ..cubicTo(8.6 * sx, 26.4 * sy, 8.7 * sx, 30 * sy, 10.6 * sx, 33.2 * sy)
      ..lineTo(37.8 * sx, 80.4 * sy)
      ..cubicTo(40.1 * sx, 84.4 * sy, 43.7 * sx, 86.7 * sy, 47.9 * sx, 86.7 * sy)
      ..cubicTo(51 * sx, 86.7 * sy, 53.8 * sx, 85.5 * sy, 56.1 * sx, 83.2 * sy)
      ..lineTo(74.2 * sx, 65 * sy)
      ..lineTo(61.4 * sx, 46.6 * sy)
      ..lineTo(49.2 * sx, 58.7 * sy)
      ..lineTo(27.8 * sx, 22.5 * sy)
      ..cubicTo(25.8 * sx, 19.5 * sy, 22.9 * sx, 18 * sy, 19 * sx, 18 * sy)
      ..close();
    final mainPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF55D0FF), Color(0xFF168BFF), Color(0xFF0753D9)],
        stops: [0, .50, 1],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawPath(main, mainPaint);

    final fold = Path()
      ..moveTo(21.5 * sx, 18.2 * sy)
      ..lineTo(36.9 * sx, 18.2 * sy)
      ..lineTo(64.3 * sx, 57.8 * sy)
      ..lineTo(49.4 * sx, 72.9 * sy)
      ..lineTo(21.4 * sx, 24.5 * sy)
      ..cubicTo(20.1 * sx, 22.3 * sy, 20.2 * sx, 20.1 * sy, 21.5 * sx, 18.2 * sy)
      ..close();
    canvas.drawPath(fold, Paint()..color = const Color(0xFF176CE5).withValues(alpha: .58));

    final shine = Path()
      ..moveTo(50 * sx, 59 * sy)
      ..lineTo(58.5 * sx, 50.5 * sy)
      ..lineTo(64.3 * sx, 57.8 * sy)
      ..lineTo(54.3 * sx, 67.9 * sy)
      ..close();
    canvas.drawPath(shine, Paint()..color = Colors.white.withValues(alpha: .95));

    final detailShader = const LinearGradient(
      colors: [Color(0xFF5CD4FF), Color(0xFF1269EC)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Offset.zero & size);
    canvas.drawCircle(p(76, 23), 9.4 * sx, Paint()..shader = detailShader);
    final person = Path()
      ..moveTo(67.5 * sx, 43.5 * sy)
      ..cubicTo(67.5 * sx, 38.3 * sy, 71.6 * sx, 34.3 * sy, 76.7 * sx, 34.3 * sy)
      ..cubicTo(81.8 * sx, 34.3 * sy, 85.8 * sx, 38.3 * sy, 85.8 * sx, 43.5 * sy)
      ..cubicTo(85.8 * sx, 46.5 * sy, 84.3 * sx, 48.7 * sy, 82 * sx, 51 * sy)
      ..lineTo(75.1 * sx, 58 * sy)
      ..lineTo(67.5 * sx, 50.1 * sy)
      ..close();
    canvas.drawPath(person, Paint()..shader = detailShader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 52,
    this.onTap,
    this.showEditBadge = false,
  });

  final AppUser? user;
  final double size;
  final VoidCallback? onTap;
  final bool showEditBadge;

  @override
  Widget build(BuildContext context) {
    final avatar = _avatarContent();
    final child = Stack(
      clipBehavior: Clip.none,
      children: [
        ClipOval(
          child: Container(
            width: size,
            height: size,
            color: const Color(0xFFEAF5FF),
            child: avatar,
          ),
        ),
        if (showEditBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * .34,
              height: size * .34,
              decoration: BoxDecoration(
                color: VelixeoDesign.sky,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.edit_rounded, color: Colors.white, size: size * .17),
            ),
          ),
      ],
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, customBorder: const CircleBorder(), child: child);
  }

  Widget _avatarContent() {
    final data = user?.avatarData?.trim();
    if (data?.startsWith('data:image/') == true) {
      final comma = data!.indexOf(',');
      if (comma > 0) {
        try {
          return Image.memory(base64Decode(data.substring(comma + 1)), fit: BoxFit.cover, width: size, height: size);
        } catch (_) {}
      }
    }
    final url = user?.avatarUrl?.trim();
    if (url?.isNotEmpty == true) {
      return Image.network(
        url!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => _PresetAvatar(preset: user?.avatarPreset ?? 'avatar_01'),
      );
    }
    return _PresetAvatar(preset: user?.avatarPreset ?? 'avatar_01');
  }
}

class _PresetAvatar extends StatelessWidget {
  const _PresetAvatar({required this.preset});
  final String preset;

  @override
  Widget build(BuildContext context) {
    final index = (int.tryParse(preset.split('_').last) ?? 1).clamp(1, 16) - 1;
    const backgrounds = [
      Color(0xFFE4F4FF), Color(0xFFF2ECFF), Color(0xFFE9FBF4), Color(0xFFFFF2E2),
      Color(0xFFFFEAF1), Color(0xFFEAF0FF), Color(0xFFE9FAF8), Color(0xFFFFF7D9),
    ];
    return ColoredBox(
      color: backgrounds[index % backgrounds.length],
      child: CustomPaint(painter: _AvatarPainter(index)),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter(this.index);
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    const skins = [
      Color(0xFFF7D7C4), Color(0xFFE9B997), Color(0xFFD99A72), Color(0xFFB97855),
      Color(0xFF8C5A43), Color(0xFFF1C7A8),
    ];
    const hairs = [
      Color(0xFF1D2D42), Color(0xFF4A3126), Color(0xFF6D4C3D), Color(0xFF161A23),
      Color(0xFF874E25), Color(0xFF2C2C2C),
    ];
    const shirts = [
      VelixeoDesign.sky, Color(0xFF7457E8), Color(0xFF14A57A), Color(0xFFF29A2E),
      Color(0xFFE9508B), Color(0xFF4667E8), Color(0xFF0FA7A0), Color(0xFF58708E),
    ];

    final skin = skins[index % skins.length];
    final hair = hairs[(index * 2 + 1) % hairs.length];
    final shirt = shirts[index % shirts.length];
    final center = Offset(size.width / 2, size.height / 2);

    final shoulderRect = Rect.fromCenter(
      center: Offset(center.dx, size.height * .88),
      width: size.width * .82,
      height: size.height * .56,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shoulderRect, Radius.circular(size.width * .28)),
      Paint()..color = shirt,
    );

    final headCenter = Offset(center.dx, size.height * .43);
    final headRadius = size.width * .22;
    canvas.drawCircle(headCenter, headRadius, Paint()..color = skin);

    final hairPath = Path()
      ..moveTo(headCenter.dx - headRadius, headCenter.dy - headRadius * .05)
      ..quadraticBezierTo(
        headCenter.dx - headRadius * .72,
        headCenter.dy - headRadius * 1.25,
        headCenter.dx + headRadius * .15,
        headCenter.dy - headRadius * 1.05,
      )
      ..quadraticBezierTo(
        headCenter.dx + headRadius * .95,
        headCenter.dy - headRadius * .75,
        headCenter.dx + headRadius,
        headCenter.dy - headRadius * .05,
      )
      ..quadraticBezierTo(
        headCenter.dx + headRadius * .45,
        headCenter.dy - headRadius * .45,
        headCenter.dx - headRadius,
        headCenter.dy - headRadius * .05,
      )
      ..close();
    canvas.drawPath(hairPath, Paint()..color = hair);

    final eyeY = headCenter.dy + headRadius * .05;
    final eyeDx = headRadius * .38;
    final eyePaint = Paint()..color = const Color(0xFF263747);
    canvas.drawCircle(Offset(headCenter.dx - eyeDx, eyeY), size.width * .018, eyePaint);
    canvas.drawCircle(Offset(headCenter.dx + eyeDx, eyeY), size.width * .018, eyePaint);

    final mouthPaint = Paint()
      ..color = const Color(0xFF9B5C58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .018
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(headCenter.dx, headCenter.dy + headRadius * .35),
        width: headRadius * .65,
        height: headRadius * .36,
      ),
      .15,
      2.84,
      false,
      mouthPaint,
    );

    if (index % 4 == 1) {
      final glass = Paint()
        ..color = const Color(0xFF3C5871)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .018;
      canvas.drawCircle(Offset(headCenter.dx - eyeDx, eyeY), size.width * .07, glass);
      canvas.drawCircle(Offset(headCenter.dx + eyeDx, eyeY), size.width * .07, glass);
      canvas.drawLine(
        Offset(headCenter.dx - size.width * .055, eyeY),
        Offset(headCenter.dx + size.width * .055, eyeY),
        glass,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) => oldDelegate.index != index;
}

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return controller.fa
        ? _PersianLanguagePage(controller: controller)
        : _EnglishLanguagePage(controller: controller);
  }
}

class _PersianLanguagePage extends StatelessWidget {
  const _PersianLanguagePage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 38, 22, 26),
          children: [
            const Text(
              'به زبان خودت، راحت‌تر',
              style: TextStyle(
                fontSize: 23,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'زبان دلخواهت را انتخاب کن. هر زمان بخواهی می‌توانی آن را تغییر بدهی.',
              style: TextStyle(
                fontSize: 13,
                height: 1.8,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 25),
            _LanguageChoiceCard(
              title: 'فارسی',
              subtitle: 'چیدمان اختصاصی راست‌به‌چپ',
              mark: 'ف',
              selected: true,
              direction: TextDirection.rtl,
              onTap: () => controller.setLanguage(AppLang.fa),
            ),
            const SizedBox(height: 11),
            _LanguageChoiceCard(
              title: 'English',
              subtitle: 'Left-to-right English interface',
              mark: 'EN',
              selected: false,
              direction: TextDirection.ltr,
              onTap: () => controller.setLanguage(AppLang.en),
            ),
            const SizedBox(height: 21),
            const _PersianLanguagePreview(),
            const SizedBox(height: 23),
            FilledButton(
              onPressed: () => controller.chooseLanguage(AppLang.fa),
              child: const Text('ادامه با فارسی'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EnglishLanguagePage extends StatelessWidget {
  const _EnglishLanguagePage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 38, 22, 26),
          children: [
            const Text(
              'Feel right at home',
              style: TextStyle(
                fontSize: 23,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Choose the interface that feels natural to you. You can change it anytime.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 25),
            _LanguageChoiceCard(
              title: 'English',
              subtitle: 'Designed for left-to-right reading',
              mark: 'EN',
              selected: true,
              direction: TextDirection.ltr,
              onTap: () => controller.setLanguage(AppLang.en),
            ),
            const SizedBox(height: 11),
            _LanguageChoiceCard(
              title: 'فارسی',
              subtitle: 'رابط اختصاصی راست‌به‌چپ',
              mark: 'ف',
              selected: false,
              direction: TextDirection.rtl,
              onTap: () => controller.setLanguage(AppLang.fa),
            ),
            const SizedBox(height: 21),
            const _EnglishLanguagePreview(),
            const SizedBox(height: 23),
            FilledButton(
              onPressed: () => controller.chooseLanguage(AppLang.en),
              child: const Text('Continue in English'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LanguageChoiceCard extends StatelessWidget {
  const _LanguageChoiceCard({
    required this.title,
    required this.subtitle,
    required this.mark,
    required this.selected,
    required this.direction,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String mark;
  final bool selected;
  final TextDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEFFAFF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? VelixeoBrand.sky : VelixeoBrand.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7FD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  mark,
                  textDirection: direction,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF39AEE0),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF8294A1),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_rounded
                    : (direction == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded),
                size: 19,
                color: selected
                    ? VelixeoBrand.sky
                    : const Color(0xFF9AAAB4),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PersianLanguagePreview extends StatelessWidget {
  const _PersianLanguagePreview();

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0xFFEEF2F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'پیش‌نمایش رابط فارسی',
                  style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
                ),
              ),
              _PreviewTag(label: 'RTL'),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'سلام، نرگس 👋',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          const Text(
            'همهٔ خدمات دیجیتال، یک‌جا.',
            style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(
                child: Text(
                  'موجودی کیف پول',
                  style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
                ),
              ),
              Text(
                '2,450 AFN',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF287FA7),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _EnglishLanguagePreview extends StatelessWidget {
  const _EnglishLanguagePreview();

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: const Color(0xFFEEF2F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'English interface preview',
                  style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
                ),
              ),
              _PreviewTag(label: 'LTR'),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'Hi, Narges 👋',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          const Text(
            'All your digital services, in one place.',
            style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Wallet balance',
                  style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
                ),
              ),
              Text(
                '2,450 AFN',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF287FA7),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PreviewTag extends StatelessWidget {
  const _PreviewTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF7FE),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: Color(0xFF287495),
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
  final referralCode = TextEditingController();
  bool registerMode = false;
  bool hidden = true;
  bool rememberMe = true;
  bool termsAccepted = false;
  String registerMethod = 'EMAIL';
  String loginMethod = 'EMAIL';
  String countryCode = 'AF';
  String phoneCode = '93';
  String countryFlag = '🇦🇫';

  @override
  void dispose() {
    fullName.dispose();
    identifier.dispose();
    password.dispose();
    confirm.dispose();
    referralCode.dispose();
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
      case 'verification_required':
        return tr(fa, 'ابتدا کد تأیید را وارد کنید.', 'Verification is required before registration.');
      case 'whatsapp_verification_required':
        return tr(
          fa,
          'ثبت‌نام با موبایل فقط پس از تأیید همان شماره از طریق WhatsApp انجام می‌شود.',
          'Mobile registration requires WhatsApp verification from that exact phone number.',
        );
      case 'whatsapp_number_mismatch':
        return tr(
          fa,
          'پیام WhatsApp از شماره دیگری ارسال شده است. باید از همان شماره‌ای که وارد کرده‌اید پیام بفرستید.',
          'The WhatsApp message came from a different number. Send it from the exact number you entered.',
        );
      case 'otp_invalid':
        return tr(fa, 'کد تأیید نادرست است.', 'The verification code is incorrect.');
      case 'otp_expired':
        return tr(fa, 'کد تأیید منقضی شده است.', 'The verification code has expired.');
      case 'otp_resend_too_soon':
        return tr(fa, 'برای ارسال دوباره کمی صبر کنید.', 'Please wait before requesting another code.');
      case 'email_otp_auth_failed':
        return tr(fa, 'اتصال امن به افزونه OTP رد شد. افزونه وردپرس را بروزرسانی کنید.', 'The secure OTP relay was rejected. Update the WordPress relay plugin.');
      case 'email_otp_route_missing':
        return tr(fa, 'مسیر ارسال OTP روی سایت پیدا نشد.', 'The email OTP relay route is missing on the website.');
      case 'email_otp_mail_failed':
        return tr(fa, 'هاست نتوانست ایمیل OTP را ارسال کند.', 'The hosting mailer could not send the OTP email.');
      case 'email_otp_provider_failed':
      case 'email_otp_timeout':
        return tr(fa, 'سرویس ارسال ایمیل OTP موقتاً در دسترس نیست.', 'The email OTP service is temporarily unavailable.');
      case 'invalid_request':
        return tr(fa, 'اطلاعات واردشده معتبر نیست.', 'Please check the entered information.');
      case 'network_error':
        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');
      case 'account_suspended':
      case 'account_temporarily_suspended':
        return tr(fa, 'این حساب موقتاً توسط مدیریت مسدود شده است.', 'This account is temporarily suspended by an administrator.');
      case 'account_permanently_suspended':
        return tr(fa, 'این حساب به‌صورت دائم توسط مدیریت مسدود شده است.', 'This account has been permanently suspended by an administrator.');
      case 'account_deleted':
        return tr(fa, 'این حساب حذف شده است و امکان ورود به آن وجود ندارد.', 'This account has been deleted and can no longer be used.');
      case 'phone_permanently_blocked':
        return tr(fa, 'این شماره توسط مدیریت برای همیشه مسدود شده و امکان ایجاد حساب با آن وجود ندارد.', 'This phone number has been permanently blocked by administration and cannot be used to create an account.');
      case 'invalid_referral_code':
        return tr(fa, 'کد دعوت معتبر نیست.', 'The referral code is invalid.');
      case 'referral_program_disabled':
        return tr(fa, 'برنامه دعوت دوستان فعلاً غیرفعال است.', 'The referral program is currently disabled.');
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

  String _phoneTarget() {
    var local = identifier.text.replaceAll(RegExp(r'\D'), '');
    if (local.startsWith('0')) local = local.substring(1);
    if (local.startsWith(phoneCode)) return '+$local';
    return '+$phoneCode$local';
  }

  String registrationTarget() {
    if (registerMethod == 'EMAIL') return identifier.text.trim().toLowerCase();
    return _phoneTarget();
  }

  String loginTarget() {
    if (loginMethod == 'EMAIL') return identifier.text.trim().toLowerCase();
    return _phoneTarget();
  }

  Future<String?> registrationVerificationToken(String target) async {
    final c = widget.controller;
    final caps = c.verificationCapabilities;
    String? channel;
    if (registerMethod == 'EMAIL') {
      if (caps.email) channel = 'EMAIL';
    } else {
      if (caps.whatsapp && caps.whatsappInbound) channel = 'WHATSAPP';
    }

    if (channel == null) {
      if (caps.registrationVerificationRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(registerMethod == 'EMAIL'
                ? tr(c.fa, 'ارسال OTP ایمیل هنوز تنظیم نشده است.', 'Email OTP is not configured yet.')
                : tr(c.fa, 'تأیید شماره با WhatsApp هنوز روی سرور فعال نیست.', 'WhatsApp phone verification is not active on the server yet.')),
          ),
        );
        return '__cancelled__';
      }
      return null;
    }

    try {
      if (channel == 'WHATSAPP' && caps.whatsappInbound) {
        final challenge = await c.api.requestRegistrationWhatsAppVerification(
          target: target,
        );
        if (!mounted) return '__cancelled__';
        final token = await showWhatsAppInboundVerification(
          context,
          challenge,
          c.fa,
          checkStatus: () => c.api.checkRegistrationWhatsAppVerification(
            challengeId: challenge.challengeId,
          ),
        );
        return token ?? '__cancelled__';
      }

      final challenge = await c.api.requestRegistrationOtp(target: target, channel: channel);
      if (!mounted) return '__cancelled__';
      final code = await showOtpDialog(context, challenge, c.fa);
      if (code == null) return '__cancelled__';
      return await c.api.verifyRegistrationOtp(challengeId: challenge.challengeId, code: code);
    } on ApiException catch (error) {
      if (!mounted) return '__cancelled__';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(error.code))));
      return '__cancelled__';
    } catch (_) {
      if (!mounted) return '__cancelled__';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage('network_error'))));
      return '__cancelled__';
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    final c = widget.controller;
    if (registerMode && fullName.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'نام و نام خانوادگی را وارد کنید.', 'Enter your full name.'))),
      );
      return;
    }

    final rawIdentifier = registerMode ? registrationTarget() : loginTarget();
    final looksLikeEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(rawIdentifier);
    final looksLikePhone = RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(rawIdentifier);
    if ((!looksLikeEmail && !looksLikePhone) || password.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ایمیل یا شماره معتبر و رمز حداقل ۸ کاراکتری وارد کنید.', 'Enter a valid email or phone number and a password of at least 8 characters.'))),
      );
      return;
    }
    if (registerMode && password.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'دو رمز عبور یکسان نیست.', 'Passwords do not match.'))),
      );
      return;
    }

    if (registerMode) {
      final token = await registrationVerificationToken(rawIdentifier);
      if (token == '__cancelled__') return;
      final ok = await c.register(
        fullName.text,
        rawIdentifier,
        password.text,
        verificationToken: token,
        referralCode: referralCode.text.trim().isEmpty ? null : referralCode.text.trim(),
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(c.authError ?? 'unknown'))));
      }
      return;
    }

    final ok = await c.login(rawIdentifier, password.text);
    if (!mounted) return;
    if (!ok && c.pendingTwoFactor != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TwoFactorLoginPage(controller: c)),
      );
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(c.authError ?? 'unknown'))),
      );
    }
  }

  Widget registrationIdentifier(bool fa) {
    if (registerMethod == 'EMAIL') {
      return TextField(
        controller: identifier,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.alternate_email),
          hintText: tr(fa, 'ایمیل شما', 'Email address'),
        ),
      );
    }
    return TextField(
      controller: identifier,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        prefixIcon: InkWell(
          onTap: () => showCountryPicker(
            context: context,
            showPhoneCode: true,
            onSelect: (country) => setState(() {
              countryCode = country.countryCode;
              phoneCode = country.phoneCode;
              countryFlag = country.flagEmoji;
            }),
          ),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: const Color(0xFFF1F6FB), borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(countryFlag),
                const SizedBox(width: 4),
                Text('+$phoneCode', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        hintText: tr(fa, 'شماره موبایل', 'Mobile number'),
      ),
    );
  }

  Widget loginIdentifier(bool fa) {
    if (loginMethod == 'EMAIL') {
      return TextField(
        controller: identifier,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.alternate_email),
          hintText: tr(fa, 'ایمیل شما', 'Email address'),
        ),
      );
    }

    return TextField(
      controller: identifier,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        prefixIcon: InkWell(
          onTap: () => showCountryPicker(
            context: context,
            showPhoneCode: true,
            onSelect: (country) => setState(() {
              countryCode = country.countryCode;
              phoneCode = country.phoneCode;
              countryFlag = country.flagEmoji;
            }),
          ),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(countryFlag),
                const SizedBox(width: 4),
                Text(
                  '+$phoneCode',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        hintText: tr(fa, 'شماره موبایل', 'Mobile number'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.fa
        ? _buildPersianAuth(context)
        : _buildEnglishAuth(context);
  }

  Widget _buildPersianAuth(BuildContext context) {
    final c = widget.controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 36, 22, 28),
            children: [
              Text(
                registerMode ? 'شروع یک تجربهٔ ساده‌تر' : 'سلام، خوش برگشتی',
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                registerMode
                    ? 'حسابت را بساز و خدمات دلخواهت را پیدا کن.'
                    : 'برای ادامه، وارد حساب VELIXEO شو.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 25),
              if (registerMode) ...[
                TextField(
                  controller: fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'نام کامل',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 13),
                DropdownButtonFormField<String>(
                  value: registerMethod,
                  decoration: const InputDecoration(
                    labelText: 'روش ثبت‌نام',
                    prefixIcon: Icon(Icons.how_to_reg_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EMAIL', child: Text('ایمیل')),
                    DropdownMenuItem(value: 'PHONE', child: Text('شماره تماس')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      registerMethod = value;
                      identifier.clear();
                    });
                  },
                ),
                const SizedBox(height: 13),
                registrationIdentifier(true),
                const SizedBox(height: 13),
              ] else ...[
                DropdownButtonFormField<String>(
                  value: loginMethod,
                  decoration: const InputDecoration(
                    labelText: 'روش ورود',
                    prefixIcon: Icon(Icons.login_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EMAIL', child: Text('ایمیل')),
                    DropdownMenuItem(value: 'PHONE', child: Text('شماره تماس')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      loginMethod = value;
                      identifier.clear();
                    });
                  },
                ),
                const SizedBox(height: 13),
                loginIdentifier(true),
                const SizedBox(height: 13),
              ],
              TextField(
                controller: password,
                obscureText: hidden,
                decoration: InputDecoration(
                  labelText: 'رمز عبور',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (registerMode) ...[
                const SizedBox(height: 13),
                TextField(
                  controller: confirm,
                  obscureText: hidden,
                  decoration: const InputDecoration(
                    labelText: 'تکرار رمز عبور',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                const _AuthPasswordHint(
                  text: 'حداقل ۸ نویسه، شامل حرف و عدد',
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: referralCode,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'کد دعوت (اختیاری)',
                    prefixIcon: Icon(Icons.redeem_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: termsAccepted,
                  onChanged: (value) => setState(() => termsAccepted = value == true),
                  title: const Text(
                    'شرایط استفاده و حریم خصوصی را می‌پذیرم.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 4),
                _AuthVerificationNotice(
                  text: registerMethod == 'EMAIL'
                      ? 'کد تأیید به ایمیل ارسال می‌شود.'
                      : 'این شماره باید یک حساب فعال WhatsApp داشته باشد.',
                ),
              ] else ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: rememberMe,
                  onChanged: (value) => setState(() => rememberMe = value == true),
                  title: const Text(
                    'مرا به خاطر بسپار',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: c.authBusy || (registerMode && !termsAccepted)
                    ? null
                    : submit,
                child: Text(
                  c.authBusy
                      ? 'لطفاً صبر کنید…'
                      : registerMode
                          ? 'ساخت حساب'
                          : 'ورود',
                ),
              ),
              if (!registerMode) ...[
                const SizedBox(height: 18),
                const _AuthDivider(label: 'یا ادامه با'),
                const SizedBox(height: 13),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: c.authBusy || !c.googleConfigured
                        ? null
                        : () => _googleLogin(c),
                    icon: const Text(
                      'G',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    label: Text(
                      c.googleConfigured
                          ? 'ورود با Google'
                          : 'Google — در انتظار تنظیم OAuth',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 17),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      registerMode ? 'قبلاً ثبت‌نام کرده‌ای؟ ' : 'حساب نداری؟ ',
                      style: const TextStyle(
                        fontSize: 11,
                        color: VelixeoBrand.muted,
                      ),
                    ),
                    TextButton(
                      onPressed: c.authBusy ? null : _toggleAuthMode,
                      child: Text(registerMode ? 'ورود' : 'ساخت حساب'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => c.setLanguage(AppLang.en),
                  icon: const Icon(Icons.language_rounded, size: 17),
                  label: const Text('English'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnglishAuth(BuildContext context) {
    final c = widget.controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 36, 22, 28),
            children: [
              Text(
                registerMode
                    ? 'A simpler experience starts here'
                    : 'Welcome back',
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                registerMode
                    ? 'Create your account and discover your services.'
                    : 'Sign in to continue your VELIXEO journey.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 25),
              if (registerMode) ...[
                TextField(
                  controller: fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 13),
                DropdownButtonFormField<String>(
                  value: registerMethod,
                  decoration: const InputDecoration(
                    labelText: 'Registration method',
                    prefixIcon: Icon(Icons.how_to_reg_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                    DropdownMenuItem(value: 'PHONE', child: Text('Phone number')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      registerMethod = value;
                      identifier.clear();
                    });
                  },
                ),
                const SizedBox(height: 13),
                registrationIdentifier(false),
                const SizedBox(height: 13),
              ] else ...[
                DropdownButtonFormField<String>(
                  value: loginMethod,
                  decoration: const InputDecoration(
                    labelText: 'Sign-in method',
                    prefixIcon: Icon(Icons.login_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                    DropdownMenuItem(value: 'PHONE', child: Text('Phone number')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      loginMethod = value;
                      identifier.clear();
                    });
                  },
                ),
                const SizedBox(height: 13),
                loginIdentifier(false),
                const SizedBox(height: 13),
              ],
              TextField(
                controller: password,
                obscureText: hidden,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (registerMode) ...[
                const SizedBox(height: 13),
                TextField(
                  controller: confirm,
                  obscureText: hidden,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                const _AuthPasswordHint(
                  text: 'At least 8 characters, including a letter and a number',
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: referralCode,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Referral code (optional)',
                    prefixIcon: Icon(Icons.redeem_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: termsAccepted,
                  onChanged: (value) => setState(() => termsAccepted = value == true),
                  title: const Text(
                    'I agree to the terms of use and privacy policy.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 4),
                _AuthVerificationNotice(
                  text: registerMethod == 'EMAIL'
                      ? 'A verification code will be sent to your email.'
                      : 'This exact phone number must have an active WhatsApp account.',
                ),
              ] else ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: rememberMe,
                  onChanged: (value) => setState(() => rememberMe = value == true),
                  title: const Text(
                    'Remember me',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: c.authBusy || (registerMode && !termsAccepted)
                    ? null
                    : submit,
                child: Text(
                  c.authBusy
                      ? 'Please wait…'
                      : registerMode
                          ? 'Create account'
                          : 'Sign in',
                ),
              ),
              if (!registerMode) ...[
                const SizedBox(height: 18),
                const _AuthDivider(label: 'Or continue with'),
                const SizedBox(height: 13),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: c.authBusy || !c.googleConfigured
                        ? null
                        : () => _googleLogin(c),
                    icon: const Text(
                      'G',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    label: Text(
                      c.googleConfigured
                          ? 'Continue with Google'
                          : 'Google — OAuth setup pending',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 17),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      registerMode
                          ? 'Already have an account? '
                          : 'New to VELIXEO? ',
                      style: const TextStyle(
                        fontSize: 11,
                        color: VelixeoBrand.muted,
                      ),
                    ),
                    TextButton(
                      onPressed: c.authBusy ? null : _toggleAuthMode,
                      child: Text(
                        registerMode ? 'Sign in' : 'Create an account',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => c.setLanguage(AppLang.fa),
                  icon: const Icon(Icons.language_rounded, size: 17),
                  label: const Text('فارسی'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleAuthMode() {
    setState(() {
      registerMode = !registerMode;
      confirm.clear();
      identifier.clear();
      termsAccepted = false;
    });
  }

  Future<void> _googleLogin(AppController c) async {
    final ok = await c.loginWithGoogle();
    if (!mounted) return;
    if (!ok && c.pendingTwoFactor != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TwoFactorLoginPage(controller: c)),
      );
    } else if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage(c.authError ?? 'google_sign_in_failed')),
        ),
      );
    }
  }

}

class _AuthPasswordHint extends StatelessWidget {
  const _AuthPasswordHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF72BAA2)),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            height: 1.55,
            color: Color(0xFF7C919E),
          ),
        ),
      ),
    ],
  );
}

class _AuthVerificationNotice extends StatelessWidget {
  const _AuthVerificationNotice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F8FC),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFE4F0F6)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF65AACA)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.55,
              color: Color(0xFF6E8194),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: Color(0xFF93A3AD),
          ),
        ),
      ),
      const Expanded(child: Divider()),
    ],
  );
}

class TwoFactorLoginPage extends StatefulWidget {
  const TwoFactorLoginPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<TwoFactorLoginPage> createState() => _TwoFactorLoginPageState();
}

class _TwoFactorLoginPageState extends State<TwoFactorLoginPage>
    with WidgetsBindingObserver {
  final code = TextEditingController();
  Timer? whatsappTimer;
  bool whatsappChecking = false;
  bool whatsappOpening = false;
  String? whatsappStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final challenge = widget.controller.pendingTwoFactor;
      if (challenge?.isWhatsAppInbound == true) {
        unawaited(_startWhatsAppVerification());
      }
    });
  }

  @override
  void dispose() {
    whatsappTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    code.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.pendingTwoFactor?.isWhatsAppInbound == true) {
      unawaited(_pollWhatsApp());
    }
  }

  Future<void> verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) return;
    final ok = await widget.controller.completeTwoFactorLogin(code.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.controller.authError ?? 'Verification failed')),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    final link = widget.controller.pendingTwoFactor?.whatsappLink;
    if (link == null || link.isEmpty || whatsappOpening) return;
    whatsappOpening = true;
    try {
      final opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() {
          whatsappStatus = tr(
            widget.controller.fa,
            'واتساپ باز نشد. دوباره تلاش کنید.',
            'WhatsApp could not be opened. Please try again.',
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          whatsappStatus = tr(
            widget.controller.fa,
            'واتساپ باز نشد. دوباره تلاش کنید.',
            'WhatsApp could not be opened. Please try again.',
          );
        });
      }
    } finally {
      whatsappOpening = false;
    }
  }

  Future<void> _startWhatsAppVerification() async {
    await _pollWhatsApp();
    if (!mounted) return;
    whatsappTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollWhatsApp(),
    );
  }

  String _twoFactorWhatsAppError(String? code) {
    switch (code) {
      case 'whatsapp_number_mismatch':
        return tr(
          widget.controller.fa,
          'پیام از شماره دیگری ارسال شده است. برای ورود باید پیام را از همان شماره تأییدشده حساب بفرستید.',
          'The message came from a different WhatsApp number. Send it from the verified number on this account.',
        );
      case 'otp_expired':
        return tr(
          widget.controller.fa,
          'مهلت تأیید تمام شد. دوباره وارد شوید و یک درخواست جدید ایجاد کنید.',
          'The verification request expired. Sign in again to create a new request.',
        );
      default:
        return code ?? 'WhatsApp verification failed';
    }
  }

  Future<void> _copyTwoFactorValue(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label)),
    );
  }

  Widget _twoFactorCopyBox({
    required String title,
    required String value,
    required String buttonLabel,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFDCE6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6E8194),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF17324D),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: value.trim().isEmpty
                  ? null
                  : () => _copyTwoFactorValue(value, buttonLabel),
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pollWhatsApp() async {
    if (whatsappChecking || !mounted) return;
    whatsappChecking = true;
    try {
      final result = await widget.controller.pollTwoFactorWhatsAppLogin();
      if (!mounted) return;
      if (result == true) {
        whatsappTimer?.cancel();
        Navigator.pop(context);
        return;
      }
      if (result == false) {
        setState(() {
          whatsappStatus = _twoFactorWhatsAppError(widget.controller.authError);
        });
      } else if (whatsappStatus != null) {
        setState(() => whatsappStatus = null);
      }
    } finally {
      whatsappChecking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildTwoFactorView(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildTwoFactorView(context),
          );
  }

  Widget _buildTwoFactorView(BuildContext context) {
    final c = widget.controller;
    final challenge = c.pendingTwoFactor;
    final whatsappInbound = challenge?.isWhatsAppInbound == true;

    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'تأیید ورود', 'Verify sign-in'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                whatsappInbound ? Icons.chat_rounded : Icons.phonelink_lock_rounded,
                color: whatsappInbound ? const Color(0xFF20A76F) : VelixeoDesign.sky,
                size: 39,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr(c.fa, 'احراز هویت دو مرحله‌ای', 'Two-step verification'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            challenge == null
                ? tr(c.fa, 'جلسه تأیید در دسترس نیست.', 'Verification session is unavailable.')
                : whatsappInbound
                    ? tr(
                        c.fa,
                        'پیام تأیید را از همان شماره WhatsApp تأییدشده حساب ارسال کنید. اگر WhatsApp روی گوشی دیگری است، لینک وریفای و پیام را از پایین کپی کنید.',
                        'Send the verification message from the verified WhatsApp number on this account. If WhatsApp is on another phone, copy the verification link and message below.',
                      )
                    : tr(
                        c.fa,
                        'کد ۶ رقمی به ${challenge.maskedTarget} ارسال شد.',
                        'A 6-digit code was sent to ${challenge.maskedTarget}.',
                      ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6E8194), height: 1.5),
          ),
          const SizedBox(height: 24),
          if (whatsappInbound) ...[
            PrimaryButton(
              label: tr(c.fa, 'باز کردن واتساپ روی همین گوشی', 'Open WhatsApp on this phone'),
              onPressed: whatsappOpening ? null : _openWhatsApp,
            ),
            const SizedBox(height: 16),
            Text(
              tr(c.fa, 'اگر WhatsApp روی گوشی دیگری است:', 'If WhatsApp is on another phone:'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                c.fa,
                'لینک وریفای را به گوشی دوم منتقل کنید و همان‌جا باز کنید. چت Velixeo با پیام آماده باز می‌شود؛ پیام را بدون تغییر ارسال کنید.',
                'Move the verification link to the other phone and open it there. The Velixeo chat opens with a prepared message; send it without editing.',
              ),
              style: const TextStyle(fontSize: 11.5, color: VelixeoDesign.muted, height: 1.45),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: challenge?.whatsappLink?.isNotEmpty == true
                    ? () => _copyTwoFactorValue(
                          challenge!.whatsappLink!,
                          tr(c.fa, 'لینک وریفای کپی شد.', 'Verification link copied.'),
                        )
                    : null,
                icon: const Icon(Icons.link_rounded),
                label: Text(tr(c.fa, 'کپی لینک وریفای', 'Copy verification link')),
              ),
            ),
            const SizedBox(height: 10),
            _twoFactorCopyBox(
              title: tr(c.fa, 'پیام تأیید', 'Verification message'),
              value: challenge?.verificationMessage ?? '',
              buttonLabel: tr(c.fa, 'کپی پیام تأیید', 'Copy verification message'),
            ),
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              whatsappChecking
                  ? tr(c.fa, 'در حال بررسی پیام واتساپ...', 'Checking your WhatsApp message...')
                  : tr(c.fa, 'منتظر پیام واتساپ شما هستیم...', 'Waiting for your WhatsApp message...'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6E8194),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (whatsappStatus?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                whatsappStatus!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: whatsappChecking ? null : _pollWhatsApp,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(c.fa, 'بررسی وضعیت', 'Check status')),
            ),
          ] else ...[
            TextField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 10,
              ),
              decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              onSubmitted: (_) => verify(),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: c.authBusy
                  ? tr(c.fa, 'درحال بررسی...', 'Verifying...')
                  : tr(c.fa, 'تأیید و ورود', 'Verify and sign in'),
              onPressed: c.authBusy || challenge == null ? null : verify,
            ),
          ],
        ],
      ),
    );
  }
}

Widget _serviceDestination(AppController c, ServiceItem service) {
  if (service.en == 'Social Media') return SocialPanelPage(host: c);
  if (service.en == 'Virtual Numbers') return VirtualNumberPanelPage(host: c);
  if (service.en == 'Premium') return PremiumPanelPage(host: c);
  if (service.en == 'Mobile Top-up') return ComingSoonServicePage(controller: c, service: service);
  if (service.en == 'Digital Accounts') return DigitalAccountsHubPage(controller: c);
  return ServicePreviewPage(controller: c, service: service);
}

Widget _catalogDestination(AppController c, CatalogService service) {
  if (service.category == 'SOCIAL') return SocialPanelPage(host: c);
  if (service.category == 'VIRTUAL_NUMBER') return VirtualNumberPanelPage(host: c);
  if (service.category == 'PREMIUM') return PremiumPanelPage(host: c, initialServiceId: service.id);
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
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerSignals);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleControllerSignals());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerSignals);
    super.dispose();
  }

  void _openPushRoute(Map<String, String> data) {
    if (!mounted) return;
    final route = (data['route'] ?? 'notifications').trim().toLowerCase();
    switch (route) {
      case 'home':
        setState(() => index = 0);
        break;
      case 'services':
        setState(() => index = 1);
        break;
      case 'orders':
        setState(() => index = 2);
        break;
      case 'wallet':
      case 'payments':
        setState(() => index = 3);
        break;
      case 'profile':
        setState(() => index = 4);
        break;
      case 'support':
        Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: widget.controller)));
        break;
      case 'premium':
        Navigator.push(context, MaterialPageRoute(builder: (_) => PremiumPanelPage(host: widget.controller, initialServiceId: data['entityId'])));
        break;
      default:
        Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(controller: widget.controller)));
    }
  }

  void _handleControllerSignals() {
    final opened = widget.controller.takePendingNotificationOpen();
    final foreground = widget.controller.takeForegroundPush();
    if (opened != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPushRoute(opened));
    }
    if (foreground != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const SizedBox.square(dimension: 34, child: CustomPaint(painter: _LogoPainter())),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(foreground.title.isEmpty ? 'VELIXEO' : foreground.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (foreground.body.isNotEmpty) Text(foreground.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(label: widget.controller.fa ? 'باز کردن' : 'Open', onPressed: () => _openPushRoute(foreground.data)),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      HomePage(controller: c, onProfileTap: () => setState(() => index = 4)),
      ServicesPage(controller: c),
      OrdersPage(controller: c),
      WalletPage(controller: c),
      ProfilePage(controller: c),
    ];

    final navigation = c.fa
        ? _FaBottomNavigation(
            index: index,
            onChanged: (value) => setState(() => index = value),
          )
        : _EnBottomNavigation(
            index: index,
            onChanged: (value) => setState(() => index = value),
          );

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: navigation,
    );
  }
}

class _BottomNavItemData {
  const _BottomNavItemData(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _FaBottomNavigation extends StatelessWidget {
  const _FaBottomNavigation({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    _BottomNavItemData(Icons.home_outlined, Icons.home_rounded, 'خانه'),
    _BottomNavItemData(Icons.grid_view_outlined, Icons.grid_view_rounded, 'خدمات'),
    _BottomNavItemData(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'سفارش‌ها'),
    _BottomNavItemData(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'کیف پول'),
    _BottomNavItemData(Icons.person_outline_rounded, Icons.person_rounded, 'پروفایل'),
  ];

  @override
  Widget build(BuildContext context) => _PrototypeBottomNavigation(
        items: items,
        index: index,
        onChanged: onChanged,
        direction: TextDirection.rtl,
      );
}

class _EnBottomNavigation extends StatelessWidget {
  const _EnBottomNavigation({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = [
    _BottomNavItemData(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _BottomNavItemData(Icons.grid_view_outlined, Icons.grid_view_rounded, 'Services'),
    _BottomNavItemData(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
    _BottomNavItemData(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
    _BottomNavItemData(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => _PrototypeBottomNavigation(
        items: items,
        index: index,
        onChanged: onChanged,
        direction: TextDirection.ltr,
      );
}

class _PrototypeBottomNavigation extends StatelessWidget {
  const _PrototypeBottomNavigation({
    required this.items,
    required this.index,
    required this.onChanged,
    required this.direction,
  });
  final List<_BottomNavItemData> items;
  final int index;
  final ValueChanged<int> onChanged;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: direction,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF0F4F7))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
            child: Row(
              children: List.generate(items.length, (i) {
                final item = items[i];
                final selected = i == index;
                return Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 54,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          if (selected)
                            Positioned(
                              top: -12,
                              child: Container(
                                width: 18,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: VelixeoBrand.sky,
                                  borderRadius: BorderRadius.vertical(
                                    bottom: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selected ? item.activeIcon : item.icon,
                                size: 21,
                                color: selected
                                    ? const Color(0xFF329ECA)
                                    : const Color(0xFF97A5AD),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.2,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected
                                      ? const Color(0xFF329ECA)
                                      : const Color(0xFF97A5AD),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, this.onProfileTap});
  final AppController controller;
  final VoidCallback? onProfileTap;

  static const services = [
    ServiceItem('شبکه‌های اجتماعی', 'Social Media', Icons.favorite_rounded, Color(0xFF38BDF8)),
    ServiceItem('شماره مجازی', 'Virtual Numbers', Icons.phone_iphone_rounded, Color(0xFF38BDF8)),
    ServiceItem('اشتراک پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFF9580CA)),
    ServiceItem('شارژ سیم‌کارت', 'Mobile Top-up', Icons.sim_card_rounded, Color(0xFFD19353)),
    ServiceItem('حساب‌های دیجیتال', 'Digital Accounts', Icons.layers_rounded, Color(0xFF68A386)),
  ];

  String _firstName(String value, bool fa) {
    final clean = value.trim();
    if (clean.isEmpty) return fa ? 'دوست' : 'there';
    return clean.split(RegExp(r'\s+')).first;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return VelixeoBrand.green;
      case 'PROCESSING':
      case 'IN_PROGRESS':
      case 'AWAITING_SMS':
        return const Color(0xFF287495);
      case 'FAILED':
        return VelixeoBrand.red;
      case 'CANCELLED':
      case 'REFUNDED':
        return const Color(0xFF6B7984);
      default:
        return VelixeoBrand.orange;
    }
  }

  String _statusLabel(String status, bool fa) {
    if (fa) {
      switch (status) {
        case 'COMPLETED': return 'تکمیل‌شده';
        case 'PROCESSING':
        case 'IN_PROGRESS': return 'در حال انجام';
        case 'AWAITING_SMS': return 'در انتظار پیامک';
        case 'FAILED': return 'ناموفق';
        case 'CANCELLED': return 'لغوشده';
        case 'REFUNDED': return 'بازگشت وجه';
        case 'PARTIAL': return 'نیمه‌کامل';
        default: return 'در انتظار';
      }
    }
    switch (status) {
      case 'COMPLETED': return 'Completed';
      case 'PROCESSING':
      case 'IN_PROGRESS': return 'In progress';
      case 'AWAITING_SMS': return 'Awaiting SMS';
      case 'FAILED': return 'Failed';
      case 'CANCELLED': return 'Cancelled';
      case 'REFUNDED': return 'Refunded';
      case 'PARTIAL': return 'Partial';
      default: return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? 'VELIXEO User';
    final recent = c.orders.take(2).toList(growable: false);
    return c.fa
        ? _buildPersian(context, identity, recent)
        : _buildEnglish(context, identity, recent);
  }

  Widget _buildPersian(
    BuildContext context,
    String identity,
    List<AppOrder> recent,
  ) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoFaDesign.pagePadding,
            children: [
              Row(
                children: [
                  UserAvatar(
                    user: c.user,
                    size: 42,
                    onTap: onProfileTap ?? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfilePage(controller: c)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'خوش اومدی،',
                          style: TextStyle(fontSize: 11, color: Color(0xFF97A3AA)),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'سلام، ' + _firstName(identity, true),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: VelixeoBrand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TopCircleButton(
                    icon: Icons.notifications_none_rounded,
                    badge: c.unreadNotificationCount,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => NotificationsPage(controller: c)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              _PrototypeWalletHero(
                controller: c,
                label: 'موجودی کیف پول',
                buttonLabel: 'افزایش موجودی',
                direction: TextDirection.rtl,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
              ),
              const SizedBox(height: 20),
              _PrototypeSearch(
                hint: 'دنبال چه خدماتی هستی؟',
                direction: TextDirection.rtl,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 23),
              _PrototypeSectionHeader(
                title: 'خدمات، در دسترس تو',
                action: 'مشاهده همه',
                direction: TextDirection.rtl,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 12),
              _PrototypeServiceGrid(
                controller: c,
                labelsFa: true,
                onOpenAll: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 23),
              _PrototypePremiumBanner(
                title: 'یک تجربه فراتر، با پریمیوم',
                subtitle: 'اشتراک‌های محبوبت را اینجا پیدا کن.',
                action: 'دیدن اشتراک‌ها',
                direction: TextDirection.rtl,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PremiumPanelPage(host: c)),
                ),
              ),
              const SizedBox(height: 23),
              _PrototypeSectionHeader(
                title: 'آخرین سفارش‌ها',
                action: 'مشاهده همه',
                direction: TextDirection.rtl,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OrdersPage(controller: c)),
                ),
              ),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                const _PrototypeEmptyRecent(
                  title: 'هنوز سفارشی نداری',
                  subtitle: 'بعد از اولین خرید، سفارش‌هایت اینجا نمایش داده می‌شوند.',
                )
              else
                ...recent.map((order) => _PrototypeRecentOrder(
                  order: order,
                  controller: c,
                  title: order.serviceTitleFa ?? order.serviceSlug ?? order.category,
                  status: _statusLabel(order.status, true),
                  statusColor: _statusColor(order.status),
                  direction: TextDirection.rtl,
                )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnglish(
    BuildContext context,
    String identity,
    List<AppOrder> recent,
  ) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoEnDesign.pagePadding,
            children: [
              Row(
                children: [
                  UserAvatar(
                    user: c.user,
                    size: 42,
                    onTap: onProfileTap ?? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfilePage(controller: c)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back,',
                          style: TextStyle(fontSize: 11, color: Color(0xFF97A3AA)),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Hello, ' + _firstName(identity, false),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: VelixeoBrand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TopCircleButton(
                    icon: Icons.notifications_none_rounded,
                    badge: c.unreadNotificationCount,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => NotificationsPage(controller: c)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              _PrototypeWalletHero(
                controller: c,
                label: 'Available balance',
                buttonLabel: 'Add funds',
                direction: TextDirection.ltr,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
              ),
              const SizedBox(height: 20),
              _PrototypeSearch(
                hint: 'What are you looking for?',
                direction: TextDirection.ltr,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 23),
              _PrototypeSectionHeader(
                title: 'Your digital essentials',
                action: 'View all',
                direction: TextDirection.ltr,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 12),
              _PrototypeServiceGrid(
                controller: c,
                labelsFa: false,
                onOpenAll: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 23),
              _PrototypePremiumBanner(
                title: 'Make more of your membership',
                subtitle: 'Find your favorite premium memberships.',
                action: 'Explore memberships',
                direction: TextDirection.ltr,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PremiumPanelPage(host: c)),
                ),
              ),
              const SizedBox(height: 23),
              _PrototypeSectionHeader(
                title: 'Recent orders',
                action: 'View all',
                direction: TextDirection.ltr,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OrdersPage(controller: c)),
                ),
              ),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                const _PrototypeEmptyRecent(
                  title: 'No orders yet',
                  subtitle: 'Your latest purchases will appear here.',
                )
              else
                ...recent.map((order) => _PrototypeRecentOrder(
                  order: order,
                  controller: c,
                  title: order.serviceTitleEn ?? order.serviceSlug ?? order.category,
                  status: _statusLabel(order.status, false),
                  statusColor: _statusColor(order.status),
                  direction: TextDirection.ltr,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrototypeWalletHero extends StatelessWidget {
  const _PrototypeWalletHero({
    required this.controller,
    required this.label,
    required this.buttonLabel,
    required this.direction,
    required this.onTap,
  });

  final AppController controller;
  final String label;
  final String buttonLabel;
  final TextDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF8ADDFF), Color(0xFFBCEAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            end: -85,
            top: -58,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .27)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF4D7990),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Color(0xFF3A86A5),
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                controller.money(controller.balanceAfn),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Color(0xFF245168),
                  fontSize: 34,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.secondaryBalance(),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFF4D7990),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF245168),
                      elevation: 0,
                      minimumSize: const Size(0, 35),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

}

class _PrototypeSearch extends StatelessWidget {
  const _PrototypeSearch({
    required this.hint,
    required this.direction,
    required this.onTap,
  });
  final String hint;
  final TextDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VelixeoBrand.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF849AA6), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                style: const TextStyle(color: Color(0xFF99A4AB), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PrototypeSectionHeader extends StatelessWidget {
  const _PrototypeSectionHeader({
    required this.title,
    required this.action,
    required this.direction,
    required this.onTap,
  });
  final String title;
  final String action;
  final TextDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: VelixeoBrand.ink,
            ),
          ),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    color: Color(0xFF347996),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  direction == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 14,
                  color: const Color(0xFF347996),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _PrototypeServiceGrid extends StatelessWidget {
  const _PrototypeServiceGrid({
    required this.controller,
    required this.labelsFa,
    required this.onOpenAll,
  });

  final AppController controller;
  final bool labelsFa;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final all = HomePage.services;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: all.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 9,
        mainAxisSpacing: 13,
        childAspectRatio: 1.02,
      ),
      itemBuilder: (context, i) {
        final isAll = i == all.length;
        final service = isAll ? null : all[i];
        final label = isAll
            ? (labelsFa ? 'همه خدمات' : 'All services')
            : (labelsFa ? service!.fa : service!.en);
        final icon = isAll ? Icons.grid_view_rounded : service!.icon;
        final color = isAll ? const Color(0xFF8397A5) : service!.color;
        final soon = !isAll && service!.en == 'Mobile Top-up';
        return InkWell(
          onTap: isAll
              ? onOpenAll
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _serviceDestination(controller, service!),
                    ),
                  ),
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Icon(icon, color: color, size: 25),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF506D7E),
                      fontSize: 11,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (soon)
                PositionedDirectional(
                  end: 2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4DF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      labelsFa ? 'به‌زودی' : 'Soon',
                      style: const TextStyle(
                        color: Color(0xFFB58036),
                        fontSize: 8,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PrototypePremiumBanner extends StatelessWidget {
  const _PrototypePremiumBanner({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.direction,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final TextDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7FC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCEEF8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: VelixeoBrand.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF87A3B3),
                  ),
                ),
                const SizedBox(height: 7),
                InkWell(
                  onTap: onTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action,
                        style: const TextStyle(
                          color: Color(0xFF347996),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        direction == TextDirection.rtl
                            ? Icons.arrow_back_rounded
                            : Icons.arrow_forward_rounded,
                        color: const Color(0xFF347996),
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Transform.rotate(
            angle: -0.16,
            child: const Text(
              '✧',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 64,
                height: 1,
                color: Color(0xFF76C8EB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrototypeRecentOrder extends StatelessWidget {
  const _PrototypeRecentOrder({
    required this.order,
    required this.controller,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.direction,
  });

  final AppOrder order;
  final AppController controller;
  final String title;
  final String status;
  final Color statusColor;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEFF3F6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VelixeoBrand.soft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  catalogIcon(order.category),
                  color: const Color(0xFF369FCA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VelixeoBrand.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.createdAt.toLocal().toString().substring(0, 16),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Color(0xFFA0ADB5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                direction == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: const Color(0xFF94A7B2),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0xFFF3F5F7)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 9,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                controller.money(order.totalAmountAfn),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 12,
                  color: VelixeoBrand.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PrototypeEmptyRecent extends StatelessWidget {
  const _PrototypeEmptyRecent({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEFF3F6)),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.receipt_long_outlined,
          color: Color(0xFF93ADBB),
          size: 28,
        ),
        const SizedBox(height: 9),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, color: VelixeoBrand.muted),
        ),
      ],
    ),
  );
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

class WalletHero extends StatelessWidget {
  const WalletHero({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF8ADDFF), Color(0xFFBCEAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(c.fa, 'موجودی کیف پول', 'Wallet balance'), style: const TextStyle(color: Color(0xFF4D7990), fontSize: 12)),
          const SizedBox(height: 6),
          Text(c.money(c.balanceAfn), style: const TextStyle(color: Color(0xFF245168), fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(c.secondaryBalance(), style: const TextStyle(color: Color(0xFF4D7990), fontSize: 11)),
        ])),
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .70), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF369FCA), size: 24)),
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
                        Text(service.category, style: const TextStyle(fontSize: 10, color: VelixeoDesign.muted)),
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
  Widget build(BuildContext context) => controller.fa
      ? _PersianServicesPage(controller: controller)
      : _EnglishServicesPage(controller: controller);
}

class _PersianServicesPage extends StatelessWidget {
  const _PersianServicesPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoFaDesign.pagePadding,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'خدمات',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: VelixeoBrand.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'هر چیزی که برای دنیای دیجیتال نیاز داری.',
                          style: TextStyle(
                            fontSize: 11,
                            color: VelixeoBrand.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BrandMark(size: 34, wordmark: false),
                ],
              ),
              const SizedBox(height: 17),
              _PrototypeSearch(
                hint: 'جستجو بین خدمات…',
                direction: TextDirection.rtl,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 20),
              _ServicesCategoryStrip(
                fa: true,
                controller: c,
              ),
              const SizedBox(height: 22),
              const Text(
                'همهٔ خدمات',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 11),
              _ServicesLiveList(
                controller: c,
                fa: true,
                direction: TextDirection.rtl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnglishServicesPage extends StatelessWidget {
  const _EnglishServicesPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoEnDesign.pagePadding,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Services',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: VelixeoBrand.ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Everything you need for your digital world.',
                          style: TextStyle(
                            fontSize: 11,
                            color: VelixeoBrand.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BrandMark(size: 34, wordmark: false),
                ],
              ),
              const SizedBox(height: 17),
              _PrototypeSearch(
                hint: 'Search services…',
                direction: TextDirection.ltr,
                onTap: () => _openServiceSearch(context, c),
              ),
              const SizedBox(height: 20),
              _ServicesCategoryStrip(
                fa: false,
                controller: c,
              ),
              const SizedBox(height: 22),
              const Text(
                'All services',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 11),
              _ServicesLiveList(
                controller: c,
                fa: false,
                direction: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicesCategoryStrip extends StatelessWidget {
  const _ServicesCategoryStrip({required this.fa, required this.controller});
  final bool fa;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = HomePage.services;
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          return InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => _serviceDestination(controller, item)),
            ),
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 66,
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF0F4F6)),
                    ),
                    child: Icon(item.icon, color: item.color, size: 23),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fa ? item.fa : item.en,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF6E8390),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ServicesLiveList extends StatelessWidget {
  const _ServicesLiveList({
    required this.controller,
    required this.fa,
    required this.direction,
  });
  final AppController controller;
  final bool fa;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.catalogServices.isEmpty) {
      return Column(
        children: [
          _ServiceListCard(
            icon: Icons.favorite_rounded,
            color: const Color(0xFF38BDF8),
            title: fa ? 'شبکه‌های اجتماعی' : 'Social Media',
            subtitle: fa
                ? 'سفارش، پیگیری، جبران ریزش و سفارش دوره‌ای'
                : 'Order, track, refill and drip-feed',
            direction: direction,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SocialPanelPage(host: c)),
            ),
          ),
          _ServiceListCard(
            icon: Icons.phone_iphone_rounded,
            color: const Color(0xFF38BDF8),
            title: fa ? 'شماره مجازی' : 'Virtual Numbers',
            subtitle: fa
                ? 'خرید شماره، دریافت پیامک و مدیریت شماره‌ها'
                : 'Buy numbers, receive SMS and manage activations',
            direction: direction,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => VirtualNumberPanelPage(host: c)),
            ),
          ),
          _ServiceListCard(
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFF9580CA),
            title: fa ? 'اشتراک‌های پریمیوم' : 'Premium',
            subtitle: fa
                ? 'تلگرام پریمیوم، اسنپ‌چت پلاس و اشتراک‌های مشابه'
                : 'Telegram Premium, Snapchat+ and similar memberships',
            direction: direction,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PremiumPanelPage(host: c)),
            ),
          ),
          _ServiceListCard(
            icon: Icons.layers_rounded,
            color: const Color(0xFF68A386),
            title: fa ? 'حساب‌های دیجیتال' : 'Digital Accounts',
            subtitle: fa
                ? 'VPN، استریم، لایسنس و محصولات دیجیتال'
                : 'VPN, streaming, licenses and digital products',
            direction: direction,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DigitalAccountsHubPage(controller: c)),
            ),
          ),
          _ServiceListCard(
            icon: Icons.sim_card_rounded,
            color: const Color(0xFFD19353),
            title: fa ? 'شارژ سیم‌کارت' : 'Mobile Top-up',
            subtitle: fa
                ? 'به‌زودی · پس از اتصال رسمی API اپراتورها'
                : 'Coming soon · waiting for official telecom APIs',
            direction: direction,
            badge: fa ? 'به‌زودی' : 'Soon',
            onTap: () {
              final item = HomePage.services.firstWhere(
                (service) => service.en == 'Mobile Top-up',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComingSoonServicePage(controller: c, service: item),
                ),
              );
            },
          ),
        ],
      );
    }

    final widgets = <Widget>[];
    if (c.catalogServices.any((service) => service.category == 'SOCIAL')) {
      widgets.add(
        _ServiceListCard(
          icon: Icons.favorite_rounded,
          color: const Color(0xFF38BDF8),
          title: fa ? 'شبکه‌های اجتماعی' : 'Social Media',
          subtitle: fa
              ? 'سفارش جدید، پیگیری، جبران و لغو'
              : 'Order, track, refill and cancel',
          direction: direction,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SocialPanelPage(host: c)),
          ),
        ),
      );
    }

    for (final service in c.catalogServices.where(
      (item) => item.category != 'SOCIAL' && item.category != 'MOBILE_TOPUP',
    )) {
      final color = catalogColor(service.category);
      final price = service.basePriceAfn == null
          ? (fa ? 'قیمت زنده از ارائه‌دهنده' : 'Live provider pricing')
          : (fa ? 'از ' : 'From ') + c.money(service.basePriceAfn!);
      widgets.add(
        _ServiceListCard(
          icon: catalogIcon(service.category),
          color: color,
          title: fa ? service.titleFa : service.titleEn,
          subtitle: price,
          direction: direction,
          featured: service.featured,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => _catalogDestination(c, service)),
          ),
        ),
      );
    }

    widgets.add(
      _ServiceListCard(
        icon: Icons.sim_card_rounded,
        color: const Color(0xFFD19353),
        title: fa ? 'شارژ سیم‌کارت' : 'Mobile Top-up',
        subtitle: fa
            ? 'به‌زودی · پس از اتصال رسمی API اپراتورها'
            : 'Coming soon · waiting for official telecom APIs',
        direction: direction,
        badge: fa ? 'به‌زودی' : 'Soon',
        onTap: () {
          final item = HomePage.services.firstWhere(
            (service) => service.en == 'Mobile Top-up',
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ComingSoonServicePage(controller: c, service: item),
            ),
          );
        },
      ),
    );

    return Column(children: widgets);
  }
}

class _ServiceListCard extends StatelessWidget {
  const _ServiceListCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.direction,
    required this.onTap,
    this.badge,
    this.featured = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final TextDirection direction;
  final VoidCallback onTap;
  final String? badge;
  final bool featured;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEEF2F5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: VelixeoBrand.ink,
                              ),
                            ),
                          ),
                          if (featured) ...[
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFD6A153),
                              size: 15,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: VelixeoBrand.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 7),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4DF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFFB58036),
                      ),
                    ),
                  )
                else
                  Icon(
                    direction == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: const Color(0xFF9AAAB4),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class DigitalAccountsHubPage extends StatelessWidget {
  const DigitalAccountsHubPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => controller.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPage(
          context,
          title: 'حساب‌های دیجیتال',
          heroTitle: 'همهٔ حساب‌ها و ابزارهای دیجیتال',
          heroBody: 'VPN، استریم، لایسنس، ابزارهای آنلاین و حساب‌های دیجیتال را از این بخش تهیه کن.',
          emptyTitle: 'هنوز حساب دیجیتال اضافه نشده',
          emptyBody: 'محصولات این بخش از پنل مدیریت حساب‌های دیجیتال اضافه می‌شوند.',
          priceFallback: 'قیمت و تحویل توسط مدیریت تعیین می‌شود',
          direction: TextDirection.rtl,
        ),
      );

  Widget _buildEnglish(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildPage(
          context,
          title: 'Digital Accounts',
          heroTitle: 'Digital accounts & tools',
          heroBody: 'Get VPN, streaming, licenses, online tools and digital accounts from one place.',
          emptyTitle: 'No digital accounts yet',
          emptyBody: 'Products for this section are created from Digital Accounts in Admin.',
          priceFallback: 'Pricing and delivery are managed from Admin',
          direction: TextDirection.ltr,
        ),
      );

  Widget _buildPage(
    BuildContext context, {
    required String title,
    required String heroTitle,
    required String heroBody,
    required String emptyTitle,
    required String emptyBody,
    required String priceFallback,
    required TextDirection direction,
  }) {
    final c = controller;
    final items = c.catalogServices
        .where((service) => service.category == 'DIGITAL_ACCOUNT')
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(21),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEEFBFA), Color(0xFFE4F4FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFFDCEEF2)),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF8F4),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_rounded,
                      color: Color(0xFF69AE9B),
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heroTitle,
                          style: const TextStyle(
                            color: Color(0xFF2C5366),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          heroBody,
                          style: const TextStyle(
                            color: Color(0xFF7293A5),
                            fontSize: 10.5,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              EmptyCard(
                icon: Icons.manage_accounts_outlined,
                title: emptyTitle,
                subtitle: emptyBody,
              )
            else
              ...items.map((service) {
                final color = catalogColor(service.category);
                final titleText = direction == TextDirection.rtl
                    ? service.titleFa
                    : service.titleEn;
                final subtitle = service.basePriceAfn == null
                    ? priceFallback
                    : (direction == TextDirection.rtl ? 'از ' : 'From ') +
                        c.money(service.basePriceAfn!);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CatalogServicePage(
                          controller: c,
                          service: service,
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFEEF2F5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(Icons.manage_accounts_rounded, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleText,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: VelixeoBrand.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: VelixeoBrand.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            direction == TextDirection.rtl
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            size: 18,
                            color: const Color(0xFF97A8B2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
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
            Text(description!, style: const TextStyle(color: VelixeoDesign.muted, height: 1.55)),
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
            style: const TextStyle(color: VelixeoDesign.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: tr(fa, 'خرید پس از اتصال Provider فعال می‌شود', 'Purchase unlocks after provider integration'), onPressed: null),
        ],
      ),
    );
  }
}

class ComingSoonServicePage extends StatelessWidget {
  const ComingSoonServicePage({super.key, required this.controller, required this.service});

  final AppController controller;
  final ServiceItem service;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? service.fa : service.en)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: service.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(service.icon, size: 52, color: service.color),
              ),
              const SizedBox(height: 24),
              Text(
                tr(fa, 'به‌زودی', 'Coming soon'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  fa,
                  'بخش شارژ موبایل پس از اتصال رسمی به API شرکت‌های مخابراتی فعال خواهد شد.',
                  'Mobile Top-up will become available after official telecom provider APIs are connected.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: VelixeoDesign.muted, height: 1.6),
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
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
            style: const TextStyle(color: VelixeoDesign.muted, height: 1.55),
          ),
          const SizedBox(height: 22),
          SoftCard(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE4F4FF),
                  child: Icon(Icons.api_rounded, color: VelixeoDesign.sky),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(fa, 'اتصال بک‌اند به API ارائه‌دهنده', 'Backend adapter → Provider API'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.lock_outline, color: VelixeoDesign.muted),
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
  Widget build(BuildContext context) => controller.fa
      ? _PersianOrdersPage(controller: controller)
      : _EnglishOrdersPage(controller: controller);
}

String _orderStatusLabel(String status, bool fa) {
  if (fa) {
    switch (status) {
      case 'PROCESSING':
      case 'IN_PROGRESS': return 'در حال انجام';
      case 'COMPLETED': return 'تکمیل‌شده';
      case 'PARTIAL': return 'نیمه‌کامل';
      case 'AWAITING_SMS': return 'در انتظار پیامک';
      case 'CANCELLED': return 'لغوشده';
      case 'FAILED': return 'ناموفق';
      case 'REFUNDED': return 'بازگشت وجه';
      default: return 'در انتظار';
    }
  }
  switch (status) {
    case 'PROCESSING':
    case 'IN_PROGRESS': return 'In progress';
    case 'COMPLETED': return 'Completed';
    case 'PARTIAL': return 'Partial';
    case 'AWAITING_SMS': return 'Awaiting SMS';
    case 'CANCELLED': return 'Cancelled';
    case 'FAILED': return 'Failed';
    case 'REFUNDED': return 'Refunded';
    default: return 'Pending';
  }
}

Color _orderStatusTone(String status) {
  switch (status) {
    case 'COMPLETED': return VelixeoBrand.green;
    case 'PROCESSING':
    case 'IN_PROGRESS':
    case 'AWAITING_SMS': return const Color(0xFF2D8DB4);
    case 'FAILED': return VelixeoBrand.red;
    case 'CANCELLED':
    case 'REFUNDED': return const Color(0xFF6F7E87);
    default: return VelixeoBrand.orange;
  }
}

class _PersianOrdersPage extends StatelessWidget {
  const _PersianOrdersPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoFaDesign.pagePadding,
            children: [
              const Text(
                'سفارش‌ها',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'وضعیت تمام خریدها و خدماتت را یک‌جا ببین.',
                style: TextStyle(
                  fontSize: 11,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 18),
              const _OrdersFilterStrip(
                labels: ['همه', 'در حال انجام', 'تکمیل‌شده'],
                direction: TextDirection.rtl,
              ),
              const SizedBox(height: 16),
              if (c.orders.isEmpty)
                const _OrdersEmptyState(
                  title: 'هنوز سفارشی ثبت نکرده‌ای',
                  subtitle: 'وقتی خریدی انجام بدهی، وضعیت آن اینجا نمایش داده می‌شود.',
                )
              else
                ...c.orders.map(
                  (order) => _OrderPrototypeCard(
                    order: order,
                    controller: c,
                    direction: TextDirection.rtl,
                    title: order.serviceTitleFa ?? order.serviceSlug ?? order.category,
                    status: _orderStatusLabel(order.status, true),
                    statusColor: _orderStatusTone(order.status),
                    idLabel: 'شماره سفارش',
                    amountLabel: 'مبلغ',
                    dateLabel: 'تاریخ',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnglishOrdersPage extends StatelessWidget {
  const _EnglishOrdersPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoEnDesign.pagePadding,
            children: [
              const Text(
                'Orders',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Track every purchase and service in one place.',
                style: TextStyle(
                  fontSize: 11,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 18),
              const _OrdersFilterStrip(
                labels: ['All', 'In progress', 'Completed'],
                direction: TextDirection.ltr,
              ),
              const SizedBox(height: 16),
              if (c.orders.isEmpty)
                const _OrdersEmptyState(
                  title: 'No orders yet',
                  subtitle: 'Your purchases and their live status will appear here.',
                )
              else
                ...c.orders.map(
                  (order) => _OrderPrototypeCard(
                    order: order,
                    controller: c,
                    direction: TextDirection.ltr,
                    title: order.serviceTitleEn ?? order.serviceSlug ?? order.category,
                    status: _orderStatusLabel(order.status, false),
                    statusColor: _orderStatusTone(order.status),
                    idLabel: 'Order ID',
                    amountLabel: 'Amount',
                    dateLabel: 'Date',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersFilterStrip extends StatelessWidget {
  const _OrdersFilterStrip({required this.labels, required this.direction});
  final List<String> labels;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == 0;
          return Expanded(
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                boxShadow: selected
                    ? const [BoxShadow(color: Color(0x0F536D7B), blurRadius: 8)]
                    : null,
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF2E7898)
                      : const Color(0xFF8799A4),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _OrderPrototypeCard extends StatelessWidget {
  const _OrderPrototypeCard({
    required this.order,
    required this.controller,
    required this.direction,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.idLabel,
    required this.amountLabel,
    required this.dateLabel,
  });

  final AppOrder order;
  final AppController controller;
  final TextDirection direction;
  final String title;
  final String status;
  final Color statusColor;
  final String idLabel;
  final String amountLabel;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    final id = order.dripParentOrderId ?? order.id;
    final shortId = id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
    final date = order.createdAt.toLocal().toString().substring(0, 16);
    return Directionality(
      textDirection: direction,
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFEDF2F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: VelixeoBrand.soft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    catalogIcon(order.category),
                    color: const Color(0xFF4AA7CC),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: VelixeoBrand.ink,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFF1F4F6)),
            const SizedBox(height: 11),
            _OrderDetailLine(
              label: idLabel,
              value: '#' + shortId,
              direction: direction,
              ltrValue: true,
            ),
            const SizedBox(height: 7),
            _OrderDetailLine(
              label: amountLabel,
              value: controller.money(order.totalAmountAfn, showBase: true),
              direction: direction,
              ltrValue: true,
            ),
            const SizedBox(height: 7),
            _OrderDetailLine(
              label: dateLabel,
              value: date,
              direction: direction,
              ltrValue: true,
            ),
            if (order.failureReason?.isNotEmpty == true) ...[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  order.failureReason!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: VelixeoBrand.red,
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

class _OrderDetailLine extends StatelessWidget {
  const _OrderDetailLine({
    required this.label,
    required this.value,
    required this.direction,
    this.ltrValue = false,
  });

  final String label;
  final String value;
  final TextDirection direction;
  final bool ltrValue;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: VelixeoBrand.muted,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textDirection: ltrValue ? TextDirection.ltr : direction,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF506D7E),
          ),
        ),
      ],
    ),
  );
}

class _OrdersEmptyState extends StatelessWidget {
  const _OrdersEmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 42),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFEEF2F5)),
    ),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: VelixeoBrand.soft,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.receipt_long_outlined,
            color: Color(0xFF73ACC6),
            size: 27,
          ),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: VelixeoBrand.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.6,
            color: VelixeoBrand.muted,
          ),
        ),
      ],
    ),
  );
}

IconData _notificationIcon(String type) {
  switch (type) {
    case 'ORDER':
    case 'REFILL':
    case 'DRIPFEED':
      return Icons.receipt_long_rounded;
    case 'PAYMENT':
      return Icons.payments_rounded;
    case 'WALLET':
      return Icons.account_balance_wallet_rounded;
    case 'SUPPORT':
      return Icons.support_agent_rounded;
    case 'ACCOUNT':
      return Icons.manage_accounts_rounded;
    default:
      return Icons.notifications_active_rounded;
  }
}

Color _notificationColor(String type) {
  switch (type) {
    case 'ORDER':
    case 'REFILL':
    case 'DRIPFEED':
      return VelixeoDesign.sky;
    case 'PAYMENT':
    case 'WALLET':
      return VelixeoDesign.green;
    case 'SUPPORT':
      return const Color(0xFF7457E8);
    case 'ACCOUNT':
      return const Color(0xFFF29A2E);
    default:
      return const Color(0xFF2E86C9);
  }
}

String _notificationTypeLabel(bool fa, String type) {
  switch (type) {
    case 'ORDER': return tr(fa, 'سفارش', 'Order');
    case 'REFILL': return tr(fa, 'جبران', 'Refill');
    case 'DRIPFEED': return tr(fa, 'دریپ‌فید', 'Drip-feed');
    case 'PAYMENT': return tr(fa, 'پرداخت', 'Payment');
    case 'WALLET': return tr(fa, 'کیف پول', 'Wallet');
    case 'SUPPORT': return tr(fa, 'پشتیبانی', 'Support');
    case 'ACCOUNT': return tr(fa, 'حساب', 'Account');
    default: return tr(fa, 'سیستم', 'System');
  }
}

String _relativeNotificationTime(bool fa, DateTime value) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return tr(fa, 'همین حالا', 'Just now');
  if (diff.inMinutes < 60) return tr(fa, '${diff.inMinutes} دقیقه پیش', '${diff.inMinutes}m ago');
  if (diff.inHours < 24) return tr(fa, '${diff.inHours} ساعت پیش', '${diff.inHours}h ago');
  if (diff.inDays < 7) return tr(fa, '${diff.inDays} روز پیش', '${diff.inDays}d ago');
  return value.toLocal().toString().substring(0, 10);
}

Future<void> _openNotificationAction(BuildContext context, AppController c, AppNotification notice) async {
  await c.markNotificationRead(notice);
  if (!context.mounted || !notice.hasAction) return;
  switch ((notice.actionRoute ?? '').toLowerCase()) {
    case 'orders':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersPage(controller: c)));
      break;
    case 'wallet':
    case 'payments':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => WalletPage(controller: c)));
      break;
    case 'support':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: c)));
      break;
    case 'services':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ServicesPage(controller: c)));
      break;
    case 'profile':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(controller: c)));
      break;
    case 'home':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => HomePage(controller: c)));
      break;
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String filter = 'ALL';

  List<AppNotification> visible(AppController c) {
    if (filter == 'ALL') return c.notifications;
    if (filter == 'ORDER') {
      return c.notifications.where((n) => const ['ORDER', 'REFILL', 'DRIPFEED'].contains(n.type)).toList(growable: false);
    }
    if (filter == 'WALLET') {
      return c.notifications.where((n) => const ['WALLET', 'PAYMENT'].contains(n.type)).toList(growable: false);
    }
    return c.notifications.where((n) => n.type == filter).toList(growable: false);
  }

  int countType(AppController c, String key) {
    if (key == 'ALL') return c.notifications.length;
    if (key == 'ORDER') return c.notifications.where((n) => const ['ORDER', 'REFILL', 'DRIPFEED'].contains(n.type)).length;
    if (key == 'WALLET') return c.notifications.where((n) => const ['WALLET', 'PAYMENT'].contains(n.type)).length;
    return c.notifications.where((n) => n.type == key).length;
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildNotificationsView(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildNotificationsView(context),
          );
  }

  Widget _buildNotificationsView(BuildContext context) {
    final c = widget.controller;
    final filters = <(String, String)>[
      ('ALL', tr(c.fa, 'همه', 'All')),
      ('ORDER', tr(c.fa, 'سفارش‌ها', 'Orders')),
      ('WALLET', tr(c.fa, 'کیف پول', 'Wallet')),
      ('SUPPORT', tr(c.fa, 'پشتیبانی', 'Support')),
      ('SYSTEM', tr(c.fa, 'سیستم', 'System')),
    ];
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final items = visible(c);
        return Scaffold(
          backgroundColor: const Color(0xFFF5F8FC),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: c.refreshAccount,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEEF9FD), Color(0xFFE5F5FB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: const Color(0xFFDDEFF6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF507383)),
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 48,
                                height: 48,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                                child: const BrandMark(size: 40, wordmark: false),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr(c.fa, 'مرکز اعلان‌ها', 'Notification Center'),
                                      style: const TextStyle(color: Color(0xFF2C5366), fontSize: 18, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tr(c.fa, 'سفارش‌ها، کیف پول، پشتیبانی و بروزرسانی‌ها', 'Orders, wallet, support & updates'),
                                      style: const TextStyle(color: Color(0xFF7293A5), fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .78), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3EFF4))),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(tr(c.fa, 'خوانده‌نشده', 'Unread'), style: const TextStyle(color: Color(0xFF7893A2), fontSize: 10)),
                                    const SizedBox(height: 4),
                                    Text('${c.unreadNotificationCount}', style: const TextStyle(color: Color(0xFF2C5366), fontSize: 23, fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .78), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3EFF4))),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(tr(c.fa, 'مجموع', 'Total'), style: const TextStyle(color: Color(0xFF7893A2), fontSize: 10)),
                                    const SizedBox(height: 4),
                                    Text('${c.notifications.length}', style: const TextStyle(color: Color(0xFF2C5366), fontSize: 23, fontWeight: FontWeight.w700)),
                                  ]),
                                ),
                              ),
                              if (c.unreadNotificationCount > 0) ...[
                                const SizedBox(width: 10),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: const Color(0xFF183B4B), minimumSize: const Size(86, 58), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                  onPressed: c.markAllNotificationsRead,
                                  child: Text(tr(c.fa, 'خواندن همه', 'Read all'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 48,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (_, i) {
                          final item = filters[i];
                          final active = filter == item.$1;
                          final count = countType(c, item.$1);
                          return ChoiceChip(
                            selected: active,
                            onSelected: (_) => setState(() => filter = item.$1),
                            label: Text('${item.$2}  $count'),
                            showCheckmark: false,
                            selectedColor: VelixeoDesign.sky,
                            backgroundColor: Colors.white,
                            side: BorderSide(color: active ? VelixeoDesign.sky : const Color(0xFFE0E8F0)),
                            labelStyle: TextStyle(color: active ? Colors.white : const Color(0xFF5D6C7E), fontSize: 11, fontWeight: FontWeight.w800),
                          );
                        },
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: EmptyCard(
                          icon: Icons.notifications_none_rounded,
                          title: 'Nothing here yet',
                          subtitle: filter == 'ALL' ? 'Your important VELIXEO updates will appear here.' : 'No notifications in this category yet.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final notice = items[index];
                          final color = _notificationColor(notice.type);
                          final title = c.fa ? notice.titleFa : notice.titleEn;
                          final body = c.fa ? notice.bodyFa : notice.bodyEn;
                          final action = c.fa ? notice.actionLabelFa : notice.actionLabelEn;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(21),
                              onTap: () => _openNotificationAction(context, c, notice),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                  color: notice.isRead ? Colors.white : color.withValues(alpha: .055),
                                  borderRadius: BorderRadius.circular(21),
                                  border: Border.all(color: notice.isRead ? VelixeoDesign.line : color.withValues(alpha: .24)),
                                  boxShadow: const [BoxShadow(color: Color(0x0D133F69), blurRadius: 20, offset: Offset(0, 8))],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(colors: [color.withValues(alpha: .72), color]),
                                            borderRadius: BorderRadius.circular(15),
                                          ),
                                          child: Icon(_notificationIcon(notice.type), color: Colors.white, size: 23),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)),
                                                  child: Text(_notificationTypeLabel(c.fa, notice.type), style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                                ),
                                                if (notice.priority == 'HIGH') ...[
                                                  const SizedBox(width: 5),
                                                  const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFF29A2E)),
                                                ],
                                                const Spacer(),
                                                Text(_relativeNotificationTime(c.fa, notice.publishAt), style: const TextStyle(color: Color(0xFF8A9AA9), fontSize: 10)),
                                                if (!notice.isRead) ...[
                                                  const SizedBox(width: 7),
                                                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                                ],
                                              ]),
                                              const SizedBox(height: 7),
                                              Text(title, style: TextStyle(fontSize: 14, height: 1.25, fontWeight: notice.isRead ? FontWeight.w800 : FontWeight.w900, color: const Color(0xFF17263A))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 11),
                                    Text(body, style: TextStyle(color: notice.isRead ? const Color(0xFF7C8997) : const Color(0xFF506276), fontSize: 12.2, height: 1.48)),
                                    if (notice.imageUrl?.trim().isNotEmpty == true) ...[
                                      const SizedBox(height: 11),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: AspectRatio(
                                          aspectRatio: 2.3,
                                          child: Image.network(
                                            notice.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (notice.hasAction) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                                        decoration: BoxDecoration(color: color.withValues(alpha: .075), borderRadius: BorderRadius.circular(12)),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text(action?.trim().isNotEmpty == true ? action! : '${tr(c.fa, 'باز کردن', 'Open')} ${_notificationTypeLabel(c.fa, notice.type)}', style: TextStyle(color: color, fontSize: 10.8, fontWeight: FontWeight.w900))),
                                            Icon(Icons.arrow_forward_rounded, color: color, size: 17),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
      } else if (target == 'premium') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => PremiumPanelPage(host: controller)));
      } else if (target == 'digital-accounts' || target == 'accounts') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => DigitalAccountsHubPage(controller: controller)));
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
                cacheWidth: ((MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).clamp(640, 1280)).round(),
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [VelixeoDesign.sky, Color(0xFF31A8FF)]),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [VelixeoDesign.sky, Color(0xFF31A8FF)])),
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

  @override
  Widget build(BuildContext context) => controller.fa
      ? _PersianWalletPage(controller: controller)
      : _EnglishWalletPage(controller: controller);
}

String _walletEntryStatus(WalletEntry entry, bool fa) {
  if (fa) {
    switch (entry.status) {
      case 'PENDING': return 'در انتظار';
      case 'FAILED': return 'ناموفق';
      case 'REVERSED': return 'برگشت‌خورده';
      default: return 'تکمیل‌شده';
    }
  }
  switch (entry.status) {
    case 'PENDING': return 'Pending';
    case 'FAILED': return 'Failed';
    case 'REVERSED': return 'Reversed';
    default: return 'Completed';
  }
}

String _walletEntryTitle(WalletEntry entry, bool fa) {
  if (entry.description.isNotEmpty) return entry.description;
  if (fa) {
    switch (entry.type) {
      case 'MANUAL_CREDIT': return 'افزایش موجودی توسط مدیر';
      case 'MANUAL_DEBIT': return 'کسر موجودی توسط مدیر';
      case 'REFUND': return 'برگشت وجه';
      case 'PURCHASE': return 'خرید';
      default: return 'تراکنش کیف پول';
    }
  }
  switch (entry.type) {
    case 'MANUAL_CREDIT': return 'Manual wallet credit';
    case 'MANUAL_DEBIT': return 'Manual wallet debit';
    case 'REFUND': return 'Refund';
    case 'PURCHASE': return 'Purchase';
    default: return 'Wallet transaction';
  }
}

class _PersianWalletPage extends StatelessWidget {
  const _PersianWalletPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoFaDesign.pagePadding,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'کیف پول',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                  ),
                  if (c.refreshing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'موجودی و تمام تراکنش‌هایت را مدیریت کن.',
                style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
              ),
              const SizedBox(height: 18),
              _PrototypeWalletHero(
                controller: c,
                label: 'موجودی کیف پول',
                buttonLabel: 'افزایش موجودی',
                direction: TextDirection.rtl,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
              ),
              const SizedBox(height: 18),
              _WalletQuickActions(
                fa: true,
                onAddFunds: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
                onHistory: () {},
              ),
              const SizedBox(height: 24),
              const Text(
                'تراکنش‌های اخیر',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 11),
              if (c.walletEntries.isEmpty)
                const _WalletEmptyState(
                  title: 'هنوز تراکنشی نداری',
                  subtitle: 'افزایش موجودی، خرید و بازگشت وجه اینجا ثبت می‌شود.',
                )
              else
                ...c.walletEntries.map(
                  (entry) => _WalletTransactionCard(
                    entry: entry,
                    controller: c,
                    direction: TextDirection.rtl,
                    title: _walletEntryTitle(entry, true),
                    status: _walletEntryStatus(entry, true),
                    balanceLabel: 'موجودی پس از تراکنش',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnglishWalletPage extends StatelessWidget {
  const _EnglishWalletPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAccount,
          child: ListView(
            padding: VelixeoEnDesign.pagePadding,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Wallet',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: VelixeoBrand.ink,
                      ),
                    ),
                  ),
                  if (c.refreshing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'Manage your balance and every wallet transaction.',
                style: TextStyle(fontSize: 11, color: VelixeoBrand.muted),
              ),
              const SizedBox(height: 18),
              _PrototypeWalletHero(
                controller: c,
                label: 'Available balance',
                buttonLabel: 'Add funds',
                direction: TextDirection.ltr,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
              ),
              const SizedBox(height: 18),
              _WalletQuickActions(
                fa: false,
                onAddFunds: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
                ),
                onHistory: () {},
              ),
              const SizedBox(height: 24),
              const Text(
                'Recent transactions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 11),
              if (c.walletEntries.isEmpty)
                const _WalletEmptyState(
                  title: 'No transactions yet',
                  subtitle: 'Top-ups, purchases and refunds will appear here.',
                )
              else
                ...c.walletEntries.map(
                  (entry) => _WalletTransactionCard(
                    entry: entry,
                    controller: c,
                    direction: TextDirection.ltr,
                    title: _walletEntryTitle(entry, false),
                    status: _walletEntryStatus(entry, false),
                    balanceLabel: 'Balance after',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletQuickActions extends StatelessWidget {
  const _WalletQuickActions({
    required this.fa,
    required this.onAddFunds,
    required this.onHistory,
  });
  final bool fa;
  final VoidCallback onAddFunds;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _WalletActionButton(
          icon: Icons.add_rounded,
          label: fa ? 'افزایش موجودی' : 'Add funds',
          onTap: onAddFunds,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _WalletActionButton(
          icon: Icons.history_rounded,
          label: fa ? 'تاریخچه' : 'History',
          onTap: onHistory,
        ),
      ),
    ],
  );
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EEF2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF4C9FC1)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B6D7E),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WalletTransactionCard extends StatelessWidget {
  const _WalletTransactionCard({
    required this.entry,
    required this.controller,
    required this.direction,
    required this.title,
    required this.status,
    required this.balanceLabel,
  });

  final WalletEntry entry;
  final AppController controller;
  final TextDirection direction;
  final String title;
  final String status;
  final String balanceLabel;

  @override
  Widget build(BuildContext context) {
    final positive = entry.amountAfn >= 0;
    final tone = positive ? VelixeoBrand.green : VelixeoBrand.red;
    return Directionality(
      textDirection: direction,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                positive ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: tone,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: VelixeoBrand.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status + ' · ' + entry.createdAt.toLocal().toString().substring(0, 16),
                    textDirection: direction,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Color(0xFF9AA8B1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    balanceLabel + ': ' + entry.balanceAfterAfn.toString() + ' AFN',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFA6B1B8),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              (positive ? '+' : '') + controller.money(entry.amountAfn),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  const _WalletEmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 38),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFEEF2F5)),
    ),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: VelixeoBrand.soft,
            borderRadius: BorderRadius.circular(19),
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: Color(0xFF73ACC6),
            size: 27,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: VelixeoBrand.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.5,
            color: VelixeoBrand.muted,
          ),
        ),
      ],
    ),
  );
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
      unawaited(_handleCheckoutReturn());
    }
  }

  Future<void> _handleCheckoutReturn() async {
    await c.refreshPaymentsAndWallet();
    if (!mounted) return;
    setState(() {});
    final payment = c.payments.isEmpty ? null : c.payments.first;
    if (payment == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentResultPage(
          controller: c,
          payment: payment,
        ),
      ),
    );
    if (mounted) {
      await c.refreshPaymentsAndWallet();
      setState(() {});
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
        return VelixeoDesign.red;
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
    return widget.controller.fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildAddFundsView(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildAddFundsView(context),
          );
  }

  Widget _buildAddFundsView(BuildContext context) {
    final configured = c.paymentCapabilities.hesabPayConfigured;
    final environment = c.paymentCapabilities.hesabPayEnvironment;
    final recent = c.payments.take(8).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.fa ? 'افزایش موجودی' : 'Add Funds'),
        actions: [
          IconButton(
            tooltip: c.fa ? 'تاریخچهٔ پرداخت' : 'Payment history',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentHistoryPage(controller: c),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: c.fa ? 'تازه‌سازی' : 'Refresh',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
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
                          style: const TextStyle(fontSize: 12, color: VelixeoDesign.muted),
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
                  const Icon(Icons.shield_outlined, color: VelixeoDesign.sky),
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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentResultPage(
                          controller: c,
                          payment: payment,
                        ),
                      ),
                    ),
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
                          style: const TextStyle(fontSize: 11, color: VelixeoDesign.muted),
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


class PaymentResultPage extends StatefulWidget {
  const PaymentResultPage({
    super.key,
    required this.controller,
    required this.payment,
  });

  final AppController controller;
  final AppPayment payment;

  @override
  State<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends State<PaymentResultPage> {
  late AppPayment payment = widget.payment;
  bool checking = false;

  AppController get c => widget.controller;

  Color get tone {
    if (payment.status == 'PAID') return VelixeoBrand.green;
    if (payment.status == 'FAILED') return VelixeoBrand.red;
    if (payment.status == 'CANCELLED') return const Color(0xFF6F7E87);
    return VelixeoBrand.orange;
  }

  IconData get resultIcon {
    if (payment.status == 'PAID') return Icons.check_rounded;
    if (payment.status == 'FAILED') return Icons.error_outline_rounded;
    if (payment.status == 'CANCELLED') return Icons.close_rounded;
    return Icons.schedule_rounded;
  }

  String title(bool fa) {
    switch (payment.status) {
      case 'PAID':
        return fa ? 'پرداخت موفق بود' : 'Payment successful';
      case 'FAILED':
        return fa ? 'پرداخت تأیید نشد' : 'Payment could not be verified';
      case 'CANCELLED':
        return fa ? 'پرداخت لغو شد' : 'Payment cancelled';
      case 'REFUNDED':
        return fa ? 'پرداخت برگشت داده شد' : 'Payment refunded';
      default:
        return fa ? 'در حال تأیید پرداخت' : 'Verifying your payment';
    }
  }

  String subtitle(bool fa) {
    switch (payment.status) {
      case 'PAID':
        return fa
            ? 'موجودی کیف پول پس از تأیید سرور افزایش یافته است.'
            : 'Your wallet was credited after server verification.';
      case 'FAILED':
        return fa
            ? 'اگر مبلغ کسر شده، با شمارهٔ پیگیری به پشتیبانی پیام بده.'
            : 'If you were charged, contact support with your reference.';
      case 'CANCELLED':
        return fa
            ? 'موجودی کیف پول تغییر نکرده است.'
            : 'Your wallet balance has not changed.';
      default:
        return fa
            ? 'تأیید نهایی ممکن است کمی زمان ببرد.'
            : 'Final verification may take a moment.';
    }
  }

  Future<void> checkAgain() async {
    setState(() => checking = true);
    await c.refreshPaymentsAndWallet();
    if (!mounted) return;
    final refreshed = c.payments.where((item) => item.id == payment.id);
    if (refreshed.isNotEmpty) payment = refreshed.first;
    setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) => c.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPage(context, true),
      );

  Widget _buildEnglish(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildPage(context, false),
      );

  Widget _buildPage(BuildContext context, bool fa) {
    final ref = payment.externalId?.trim().isNotEmpty == true
        ? payment.externalId!
        : payment.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(fa ? 'وضعیت پرداخت' : 'Payment status'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(resultIcon, size: 34, color: tone),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title(fa),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: VelixeoBrand.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle(fa),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              height: 1.7,
              color: VelixeoBrand.muted,
            ),
          ),
          const SizedBox(height: 24),
          _PaymentDetailCard(
            rows: [
              (
                fa ? 'مبلغ' : 'Amount',
                c.money(payment.amountAfn, showBase: true),
              ),
              (fa ? 'درگاه' : 'Gateway', payment.gateway),
              (fa ? 'شمارهٔ پیگیری' : 'Reference', ref),
              (
                fa ? 'زمان' : 'Time',
                payment.createdAt.toLocal().toString().substring(0, 16),
              ),
            ],
          ),
          if (payment.failureReason?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(
                payment.failureReason!,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.55,
                  color: VelixeoBrand.red,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (!['PAID', 'FAILED', 'CANCELLED', 'REFUNDED']
              .contains(payment.status))
            FilledButton.icon(
              onPressed: checking ? null : checkAgain,
              icon: checking
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(fa ? 'بررسی دوباره' : 'Check again'),
            )
          else if (payment.status == 'PAID')
            FilledButton(
              onPressed: () => Navigator.popUntil(
                context,
                (route) => route.isFirst,
              ),
              child: Text(fa ? 'مشاهدهٔ کیف پول' : 'View wallet'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => AddFundsPage(controller: c)),
              ),
              child: Text(fa ? 'تلاش دوباره' : 'Try again'),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentHistoryPage(controller: c),
              ),
            ),
            child: Text(fa ? 'تاریخچهٔ پرداخت' : 'Payment history'),
          ),
          if (payment.status == 'FAILED') ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SupportPage(host: c)),
              ),
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: Text(fa ? 'تماس با پشتیبانی' : 'Contact support'),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentHistoryPage extends StatelessWidget {
  const PaymentHistoryPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => controller.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPage(
          context,
          title: 'تاریخچهٔ پرداخت‌ها',
          heading: 'پرداخت‌ها، شفاف و مرتب',
          subtitle: 'جزئیات افزایش موجودی را مرور کن.',
          emptyTitle: 'هنوز پرداختی نداری',
          emptyBody: 'بعد از افزایش موجودی، جزئیات اینجا ثبت می‌شود.',
          detailsLabel: 'جزئیات',
          fa: true,
        ),
      );

  Widget _buildEnglish(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildPage(
          context,
          title: 'Payment history',
          heading: 'Your payments, clearly organized',
          subtitle: 'Review your wallet top-ups.',
          emptyTitle: 'No payments yet',
          emptyBody: 'Your top-up history will appear here.',
          detailsLabel: 'Details',
          fa: false,
        ),
      );

  Widget _buildPage(
    BuildContext context, {
    required String title,
    required String heading,
    required String subtitle,
    required String emptyTitle,
    required String emptyBody,
    required String detailsLabel,
    required bool fa,
  }) {
    final payments = controller.payments;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: controller.refreshPaymentsAndWallet,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 20),
            if (payments.isEmpty)
              EmptyCard(
                icon: Icons.payments_outlined,
                title: emptyTitle,
                subtitle: emptyBody,
              )
            else
              ...payments.map(
                (payment) => _PaymentHistoryCard(
                  payment: payment,
                  controller: controller,
                  fa: fa,
                  detailsLabel: detailsLabel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentHistoryCard extends StatelessWidget {
  const _PaymentHistoryCard({
    required this.payment,
    required this.controller,
    required this.fa,
    required this.detailsLabel,
  });

  final AppPayment payment;
  final AppController controller;
  final bool fa;
  final String detailsLabel;

  Color get tone {
    if (payment.status == 'PAID') return VelixeoBrand.green;
    if (payment.status == 'FAILED') return VelixeoBrand.red;
    if (payment.status == 'CANCELLED') return const Color(0xFF6F7E87);
    return VelixeoBrand.orange;
  }

  String get status {
    switch (payment.status) {
      case 'PAID':
        return fa ? 'موفق' : 'Successful';
      case 'FAILED':
        return fa ? 'ناموفق' : 'Failed';
      case 'CANCELLED':
        return fa ? 'لغوشده' : 'Cancelled';
      case 'REFUNDED':
        return fa ? 'بازگشت وجه' : 'Refunded';
      default:
        return fa ? 'در انتظار' : 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEEF2F5)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.money(payment.amountAfn, showBase: true),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: VelixeoBrand.ink,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Container(height: 1, color: const Color(0xFFF2F5F7)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    payment.gateway +
                        ' · ' +
                        payment.createdAt
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentResultPage(
                        controller: controller,
                        payment: payment,
                      ),
                    ),
                  ),
                  icon: Icon(
                    fa
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 15,
                  ),
                  label: Text(detailsLabel),
                ),
              ],
            ),
          ],
        ),
      );
}

class _PaymentDetailCard extends StatelessWidget {
  const _PaymentDetailCard({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFFEEF2F5)),
        ),
        child: Column(
          children: List.generate(rows.length, (index) {
            final row = rows[index];
            return Container(
              constraints: const BoxConstraints(minHeight: 51),
              decoration: BoxDecoration(
                border: index == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF1F4F6)),
                      ),
              ),
              child: Row(
                children: [
                  Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      row.$2,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4E6978),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.controller});
  final AppController controller;

  Future<void> _changeLanguage(BuildContext context, AppLang lang) async {
    Navigator.pop(context);
    await controller.setLanguage(lang);
  }

  void _showLanguageSheet(BuildContext context, bool fa) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  title: const Text('فارسی'),
                  subtitle: const Text('Vazirmatn · RTL'),
                  trailing: controller.fa ? const Icon(Icons.check_rounded, color: VelixeoBrand.sky) : null,
                  onTap: () => _changeLanguage(sheetContext, AppLang.fa),
                ),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  title: const Text('English'),
                  subtitle: const Text('Inter · LTR'),
                  trailing: !controller.fa ? const Icon(Icons.check_rounded, color: VelixeoBrand.sky) : null,
                  onTap: () => _changeLanguage(sheetContext, AppLang.en),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCurrencySheet(BuildContext context, bool fa) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: DisplayCurrency.values.map((value) {
              final title = value == DisplayCurrency.afn
                  ? (fa ? 'افغانی · AFN' : 'AFN · Afghani')
                  : value == DisplayCurrency.usd
                      ? (fa ? 'دالر · USD' : 'USD · Dollar')
                      : (fa ? 'تومان · TOMAN' : 'TOMAN · Toman');
              return ListTile(
                title: Text(title),
                trailing: controller.currency == value
                    ? const Icon(Icons.check_rounded, color: VelixeoBrand.sky)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  controller.setCurrency(value);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }


  void _signOut(BuildContext context, bool fa) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(fa ? 'خروج از حساب؟' : 'Sign out?'),
          content: Text(
            fa
                ? 'برای ورود دوباره باید اطلاعات حسابت را وارد کنی.'
                : 'You will need to sign in again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(fa ? 'لغو' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                controller.logout();
              },
              child: Text(fa ? 'خروج' : 'Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => controller.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) {
    final c = controller;
    final identity = c.user?.email ?? c.user?.phone ?? '—';
    final name = c.user?.fullName?.trim().isNotEmpty == true
        ? c.user!.fullName!
        : 'کاربر VELIXEO';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ListView(
          padding: VelixeoFaDesign.pagePadding,
          children: [
            const Text(
              'پروفایل',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 14),
            _ProfileIdentityHeader(
              controller: c,
              direction: TextDirection.rtl,
              name: name,
              identity: identity,
              verifiedLabel: 'تأیید‌شده',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditProfilePage(controller: c)),
              ),
            ),
            const SizedBox(height: 18),
            _ProfileMenuCard(
              direction: TextDirection.rtl,
              rows: [
                _ProfileMenuData(
                  Icons.manage_accounts_outlined,
                  'ویرایش پروفایل',
                  c.user?.fullName ?? '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(controller: c))),
                ),
                _ProfileMenuData(
                  Icons.security_rounded,
                  'امنیت و ورود',
                  c.user?.twoFactorEnabled == true ? '2FA' : '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => SecurityPage(controller: c))),
                ),
                _ProfileMenuData(
                  Icons.language_rounded,
                  'زبان',
                  'فارسی',
                  () => _showLanguageSheet(context, true),
                ),
                _ProfileMenuData(
                  Icons.currency_exchange_rounded,
                  'واحد نمایش قیمت',
                  c.currency.name.toUpperCase(),
                  () => _showCurrencySheet(context, true),
                ),
                _ProfileMenuData(
                  Icons.group_add_rounded,
                  'دعوت از دوستان',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => InviteFriendsPage(host: c))),
                ),
                _ProfileMenuData(
                  Icons.support_agent_rounded,
                  'پشتیبانی و تیکت',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: c))),
                ),
                _ProfileMenuData(
                  Icons.monitor_heart_outlined,
                  'وضعیت سرورها',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServerStatusPage(controller: c))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProfileMenuCard(
              direction: TextDirection.rtl,
              rows: [
                _ProfileMenuData(
                  Icons.person_remove_alt_1_rounded,
                  'حذف حساب',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeleteAccountPage(controller: c))),
                  danger: true,
                ),
                _ProfileMenuData(
                  Icons.logout_rounded,
                  'خروج از حساب',
                  '',
                  () => _signOut(context, true),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'VELIXEO · نسخه 0.10',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Color(0xFF9AAAB3),
                  fontSize: 9.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnglish(BuildContext context) {
    final c = controller;
    final identity = c.user?.email ?? c.user?.phone ?? '—';
    final name = c.user?.fullName?.trim().isNotEmpty == true
        ? c.user!.fullName!
        : 'VELIXEO User';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SafeArea(
        child: ListView(
          padding: VelixeoEnDesign.pagePadding,
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 14),
            _ProfileIdentityHeader(
              controller: c,
              direction: TextDirection.ltr,
              name: name,
              identity: identity,
              verifiedLabel: 'Verified',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => EditProfilePage(controller: c)),
              ),
            ),
            const SizedBox(height: 18),
            _ProfileMenuCard(
              direction: TextDirection.ltr,
              rows: [
                _ProfileMenuData(
                  Icons.manage_accounts_outlined,
                  'Edit profile',
                  c.user?.fullName ?? '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(controller: c))),
                ),
                _ProfileMenuData(
                  Icons.security_rounded,
                  'Security & login',
                  c.user?.twoFactorEnabled == true ? '2FA' : '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => SecurityPage(controller: c))),
                ),
                _ProfileMenuData(
                  Icons.language_rounded,
                  'Language',
                  'English',
                  () => _showLanguageSheet(context, false),
                ),
                _ProfileMenuData(
                  Icons.currency_exchange_rounded,
                  'Display currency',
                  c.currency.name.toUpperCase(),
                  () => _showCurrencySheet(context, false),
                ),
                _ProfileMenuData(
                  Icons.group_add_rounded,
                  'Invite friends',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => InviteFriendsPage(host: c))),
                ),
                _ProfileMenuData(
                  Icons.support_agent_rounded,
                  'Support & tickets',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: c))),
                ),
                _ProfileMenuData(
                  Icons.monitor_heart_outlined,
                  'Server status',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServerStatusPage(controller: c))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProfileMenuCard(
              direction: TextDirection.ltr,
              rows: [
                _ProfileMenuData(
                  Icons.person_remove_alt_1_rounded,
                  'Delete account',
                  '',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeleteAccountPage(controller: c))),
                  danger: true,
                ),
                _ProfileMenuData(
                  Icons.logout_rounded,
                  'Sign out',
                  '',
                  () => _signOut(context, false),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'VELIXEO · Version 0.10',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF9AAAB3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({
    required this.controller,
    required this.direction,
    required this.name,
    required this.identity,
    required this.verifiedLabel,
    required this.onTap,
  });

  final AppController controller;
  final TextDirection direction;
  final String name;
  final String identity;
  final String verifiedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEEF2F5)),
        ),
        child: Column(
          children: [
            UserAvatar(user: controller.user, size: 74, onTap: onTap),
            const SizedBox(height: 10),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              identity,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded, size: 13, color: VelixeoBrand.green),
                  const SizedBox(width: 4),
                  Text(
                    verifiedLabel,
                    style: const TextStyle(
                      fontSize: 9,
                      color: VelixeoBrand.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileMenuData {
  const _ProfileMenuData(
    this.icon,
    this.title,
    this.value,
    this.onTap, {
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool danger;
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({required this.direction, required this.rows});
  final TextDirection direction;
  final List<_ProfileMenuData> rows;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: direction,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEF2F5)),
      ),
      child: Column(
        children: List.generate(rows.length, (i) {
          final row = rows[i];
          final color = row.danger ? const Color(0xFFCF7880) : const Color(0xFF506D7E);
          return InkWell(
            onTap: row.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 61),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: Color(0xFFF0F4F7)),
                      ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: row.danger
                          ? const Color(0xFFFFF1F2)
                          : const Color(0xFFF1F8FC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      row.icon,
                      size: 17,
                      color: row.danger
                          ? const Color(0xFFD5848A)
                          : const Color(0xFF65AACA),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      row.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (row.value.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 7),
                      child: Text(
                        row.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFF9AAAB4),
                        ),
                      ),
                    ),
                  const SizedBox(width: 5),
                  Icon(
                    direction == TextDirection.rtl
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 15,
                    color: const Color(0xFF99ADBA),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    ),
  );
}


class ServerStatusPage extends StatefulWidget {
  const ServerStatusPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ServerStatusPage> createState() => _ServerStatusPageState();
}

class _ServerStatusPageState extends State<ServerStatusPage> {
  bool checking = true;
  bool online = true;
  DateTime? checkedAt;

  @override
  void initState() {
    super.initState();
    unawaited(check());
  }

  Future<void> check() async {
    if (mounted) setState(() => checking = true);
    final result = await widget.controller.api.health();
    if (!mounted) return;
    setState(() {
      online = result;
      checking = false;
      checkedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) => widget.controller.fa
      ? Directionality(
          textDirection: TextDirection.rtl,
          child: _buildPage(context, true),
        )
      : Directionality(
          textDirection: TextDirection.ltr,
          child: _buildPage(context, false),
        );

  Widget _buildPage(BuildContext context, bool fa) {
    final tone = online ? VelixeoBrand.green : VelixeoBrand.red;
    final services = <String>[
      fa ? 'هستهٔ برنامه' : 'Application core',
      fa ? 'سفارش‌های اجتماعی' : 'Social orders',
      fa ? 'شماره و پیامک' : 'Numbers & SMS',
      fa ? 'پرداخت HesabPay' : 'HesabPay payments',
      fa ? 'پشتیبانی' : 'Support',
    ];
    return Scaffold(
      appBar: AppBar(title: Text(fa ? 'وضعیت سرورها' : 'Server status')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text(
            fa ? 'همه‌چیز، زیر نظر' : 'Keeping an eye on everything',
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: VelixeoBrand.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fa
                ? 'وضعیت خدمات VELIXEO را اینجا ببین.'
                : 'Check the status of VELIXEO services.',
            style: const TextStyle(fontSize: 11, color: VelixeoBrand.muted),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEEF2F5)),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: checking
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          online
                              ? Icons.check_rounded
                              : Icons.wifi_off_rounded,
                          color: tone,
                          size: 30,
                        ),
                ),
                const SizedBox(height: 13),
                Text(
                  checking
                      ? (fa ? 'در حال بررسی…' : 'Checking…')
                      : online
                          ? (fa
                              ? 'خدمات در دسترس هستند'
                              : 'Services are available')
                          : (fa
                              ? 'اتصال برقرار نیست'
                              : 'Services are unavailable'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: VelixeoBrand.ink,
                  ),
                ),
                if (checkedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    (fa ? 'آخرین بررسی: ' : 'Last check: ') +
                        checkedAt!
                            .toLocal()
                            .toString()
                            .substring(0, 16),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...services.map(
            (name) => Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 15,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEEF2F5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF506D7E),
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: checking
                          ? const Color(0xFFACB8BF)
                          : tone,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    checking
                        ? (fa ? 'در حال بررسی' : 'Checking')
                        : online
                            ? (fa ? 'در دسترس' : 'Available')
                            : (fa ? 'نامشخص' : 'Unknown'),
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: VelixeoBrand.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          OutlinedButton.icon(
            onPressed: checking ? null : check,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(fa ? 'بررسی دوباره' : 'Check again'),
          ),
        ],
      ),
    );
  }
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final password = TextEditingController();
  final reason = TextEditingController();
  bool understood = false;
  bool busy = false;

  AppController get c => widget.controller;

  @override
  void dispose() {
    password.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> deleteNow() async {
    setState(() => busy = true);
    final error = await c.deleteAccount(
      password: password.text.trim().isEmpty ? null : password.text,
      reason: reason.text.trim().isEmpty ? null : reason.text,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    final fa = c.fa;
    final message = error == 'incorrect_current_password'
        ? (fa ? 'رمز عبور فعلی نادرست است.' : 'The current password is incorrect.')
        : (fa
            ? 'حذف حساب انجام نشد. دوباره تلاش کنید.'
            : 'Account deletion failed. Please try again.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) => c.fa
      ? Directionality(
          textDirection: TextDirection.rtl,
          child: _buildPage(context, true),
        )
      : Directionality(
          textDirection: TextDirection.ltr,
          child: _buildPage(context, false),
        );

  Widget _buildPage(BuildContext context, bool fa) => Scaffold(
        appBar: AppBar(title: Text(fa ? 'حذف حساب' : 'Delete account')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            Text(
              fa ? 'قبل از خداحافظی…' : 'Before you go…',
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              fa
                  ? 'حذف حساب، نیاز به بررسی دقیق دارد.'
                  : 'Please review the details before deleting your account.',
              style: const TextStyle(
                fontSize: 11,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 17),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFF7DDE0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: VelixeoBrand.red,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fa
                          ? 'حذف حساب دائمی است و امکان بازگردانی آن وجود ندارد.'
                          : 'Account deletion is permanent and cannot be undone.',
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.6,
                        color: VelixeoBrand.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFFEEF2F5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'چه اتفاقی می‌افتد؟' : 'What happens next?',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DeleteInfoRow(
                    text: fa
                        ? 'دسترسی به حساب و خدماتت از بین می‌رود.'
                        : 'You will lose access to your account and services.',
                  ),
                  _DeleteInfoRow(
                    text: fa
                        ? 'پیش از حذف، سفارش‌ها و موجودی کیف پول باید تعیین تکلیف شوند.'
                        : 'Open orders and your wallet balance should be resolved first.',
                  ),
                  _DeleteInfoRow(
                    text: fa
                        ? 'سوابق لازم برای امنیت و حسابداری طبق سیاست سرویس نگهداری می‌شوند.'
                        : 'Records required for security and accounting are retained.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PaymentDetailCard(
              rows: [
                (
                  fa ? 'موجودی فعلی' : 'Current balance',
                  c.money(c.balanceAfn, showBase: true),
                ),
                (
                  fa ? 'سفارش‌های ثبت‌شده' : 'Recorded orders',
                  '${c.orders.length}',
                ),
              ],
            ),
            if (c.user?.hasPassword == true) ...[
              const SizedBox(height: 13),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText:
                      fa ? 'رمز عبور فعلی' : 'Current password',
                ),
              ),
            ],
            const SizedBox(height: 13),
            TextField(
              controller: reason,
              maxLength: 300,
              maxLines: 3,
              decoration: InputDecoration(
                labelText:
                    fa ? 'دلیل (اختیاری)' : 'Reason (optional)',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: understood,
              onChanged: (value) =>
                  setState(() => understood = value == true),
              title: Text(
                fa
                    ? 'می‌دانم این عمل حساب فعلی را به‌صورت دائمی حذف می‌کند.'
                    : 'I understand this permanently deletes my current account.',
                style: const TextStyle(fontSize: 10.5),
              ),
            ),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SupportPage(host: c)),
              ),
              icon: const Icon(Icons.support_agent_rounded, size: 17),
              label: Text(
                fa ? 'گفتگو با پشتیبانی' : 'Contact support',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: VelixeoBrand.red,
                foregroundColor: Colors.white,
              ),
              onPressed: !understood || busy ? null : deleteNow,
              icon: busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                busy
                    ? (fa ? 'در حال حذف…' : 'Deleting…')
                    : (fa ? 'بررسی و حذف حساب' : 'Review and delete account'),
              ),
            ),
          ],
        ),
      );
}

class _DeleteInfoRow extends StatelessWidget {
  const _DeleteInfoRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 14,
                color: Color(0xFF7FA4B4),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.55,
                  color: VelixeoBrand.muted,
                ),
              ),
            ),
          ],
        ),
      );
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController fullName;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController website;
  final emailOtp = TextEditingController();
  final phoneOtp = TextEditingController();

  String? countryCode;
  String avatarPreset = 'avatar_01';
  String? avatarData;
  String? avatarUrl;

  VerificationChallenge? emailChallenge;
  VerificationChallenge? phoneChallenge;
  String? emailVerificationToken;
  String? phoneVerificationToken;

  bool busy = false;
  bool emailSending = false;
  bool emailVerifying = false;
  bool phoneSending = false;
  bool phoneVerifying = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final user = c.user;
    fullName = TextEditingController(text: user?.fullName ?? '');
    email = TextEditingController(text: user?.email ?? '');
    phone = TextEditingController(text: user?.phone ?? '');
    website = TextEditingController(text: user?.websiteUrl ?? '');
    countryCode = user?.countryCode;
    avatarPreset = user?.avatarPreset ?? 'avatar_01';
    avatarData = user?.avatarData;
    avatarUrl = user?.avatarUrl;
    email.addListener(_emailChanged);
    phone.addListener(_phoneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await c.refreshVerificationCapabilities();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    email.removeListener(_emailChanged);
    phone.removeListener(_phoneChanged);
    fullName.dispose();
    email.dispose();
    phone.dispose();
    website.dispose();
    emailOtp.dispose();
    phoneOtp.dispose();
    super.dispose();
  }

  void _emailChanged() {
    emailVerificationToken = null;
    emailChallenge = null;
    emailOtp.clear();
    if (mounted) setState(() {});
  }

  void _phoneChanged() {
    phoneVerificationToken = null;
    phoneChallenge = null;
    phoneOtp.clear();
    if (mounted) setState(() {});
  }

  String get normalizedEmail => email.text.trim().toLowerCase();
  String get normalizedPhone => phone.text.replaceAll(RegExp(r'[\s()-]'), '');

  bool get emailVerifiedNow {
    final current = (c.user?.email ?? '').trim().toLowerCase();
    if (normalizedEmail.isEmpty) return false;
    if (normalizedEmail == current) return c.user?.emailVerified == true;
    return emailVerificationToken?.isNotEmpty == true;
  }

  bool get phoneVerifiedNow {
    final current = (c.user?.phone ?? '').replaceAll(RegExp(r'[\s()-]'), '');
    if (normalizedPhone.isEmpty) return false;
    if (normalizedPhone == current) return c.user?.phoneVerified == true;
    return phoneVerificationToken?.isNotEmpty == true;
  }

  AppUser previewUser() {
    final user = c.user;
    return AppUser(
      id: user?.id ?? 'preview',
      role: user?.role ?? 'USER',
      status: user?.status ?? 'ACTIVE',
      locale: user?.locale ?? 'EN',
      displayCurrency: user?.displayCurrency ?? 'AFN',
      hasPassword: user?.hasPassword ?? true,
      fullName: fullName.text,
      email: email.text,
      phone: phone.text,
      websiteUrl: website.text,
      countryCode: countryCode,
      avatarPreset: avatarPreset,
      avatarData: avatarData,
      avatarUrl: avatarUrl,
      emailVerified: emailVerifiedNow,
      phoneVerified: phoneVerifiedNow,
      twoFactorEnabled: user?.twoFactorEnabled ?? false,
      twoFactorMethod: user?.twoFactorMethod,
    );
  }

  Future<void> pickProfilePhoto() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (file == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        maxWidth: 512,
        maxHeight: 512,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 78,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: tr(c.fa, 'تنظیم تصویر پروفایل', 'Adjust profile photo'),
            toolbarColor: const Color(0xFF0D6FD1),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: VelixeoDesign.sky,
            cropFrameColor: Colors.white,
            cropGridColor: Colors.white70,
            dimmedLayerColor: const Color(0xB3000000),
            showCropGrid: true,
            lockAspectRatio: true,
            initAspectRatio: CropAspectRatioPreset.square,
            cropStyle: CropStyle.circle,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: tr(c.fa, 'تنظیم تصویر پروفایل', 'Adjust profile photo'),
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            doneButtonTitle: tr(c.fa, 'استفاده', 'Use photo'),
            cancelButtonTitle: tr(c.fa, 'لغو', 'Cancel'),
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
        ],
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      if (bytes.length > 360000) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                c.fa,
                'حجم تصویر بعد از برش زیاد است. لطفاً تصویر دیگری انتخاب کنید.',
                'The cropped photo is still too large. Please choose another photo.',
              ),
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        avatarData = 'data:image/jpeg;base64,' + base64Encode(bytes);
        avatarUrl = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'تنظیم تصویر انجام نشد.', 'Could not prepare the profile photo.'))),
      );
    }
  }
  void chooseAvatar() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(c.fa, 'یک آواتار انتخاب کنید', 'Choose an avatar'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 16,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (_, i) {
                  final preset = 'avatar_${(i + 1).toString().padLeft(2, '0')}';
                  final selected = avatarData == null && avatarUrl == null && avatarPreset == preset;
                  return InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() {
                        avatarPreset = preset;
                        avatarData = null;
                        avatarUrl = null;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(child: ClipOval(child: _PresetAvatar(preset: preset))),
                        if (selected)
                          Positioned(
                            right: 1,
                            bottom: 1,
                            child: Container(
                              width: 25,
                              height: 25,
                              decoration: const BoxDecoration(color: VelixeoDesign.sky, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 17),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> sendEmailVerification() async {
    final target = normalizedEmail;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(target)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ابتدا یک ایمیل معتبر وارد کنید.', 'Enter a valid email address first.'))),
      );
      return;
    }

    setState(() => emailSending = true);
    try {
      final caps = await c.refreshVerificationCapabilities();
      if (!caps.email) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'ارسال OTP ایمیل هنوز روی سرور فعال نیست.', 'Email OTP is not active on the server yet.'))),
        );
        return;
      }
      final current = (c.user?.email ?? '').trim().toLowerCase();
      final challenge = target == current
          ? await c.requestAccountOtp('EMAIL', 'VERIFY_EMAIL')
          : await c.requestContactChangeOtp('EMAIL', target, 'EMAIL');
      if (!mounted) return;
      if (challenge == null) {
        final code = c.authError ?? 'email_otp_provider_failed';
        final message = code == 'email_otp_auth_failed'
            ? tr(c.fa, 'اتصال امن افزونه OTP رد شد؛ افزونه وردپرس را بروزرسانی کنید.', 'OTP relay authentication was rejected; update the WordPress relay plugin.')
            : code == 'email_otp_route_missing'
                ? tr(c.fa, 'مسیر OTP روی سایت پیدا نشد.', 'The OTP relay route is missing on the website.')
                : code == 'email_otp_mail_failed'
                    ? tr(c.fa, 'هاست نتوانست ایمیل را ارسال کند.', 'The hosting mailer could not send the email.')
                    : code == 'otp_resend_too_soon'
                        ? tr(c.fa, 'کمی صبر کنید و دوباره تلاش کنید.', 'Please wait a moment before requesting another code.')
                        : tr(c.fa, 'ارسال کد انجام نشد.', 'Could not send the verification code.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      setState(() {
        emailChallenge = challenge;
        emailOtp.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'کد ۶ رقمی به ایمیل ارسال شد.', 'A 6-digit code was sent to your email.'))),
      );
    } finally {
      if (mounted) setState(() => emailSending = false);
    }
  }

  Future<void> verifyEmailCode() async {
    final challenge = emailChallenge;
    final code = emailOtp.text.trim();
    if (challenge == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    setState(() => emailVerifying = true);
    try {
      final token = await c.verifyAccountOtp(challenge.challengeId, code);
      if (token == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(c.fa, 'کد تأیید درست نیست یا منقضی شده است.', 'The code is invalid or expired.'))),
          );
        }
        return;
      }

      final current = (c.user?.email ?? '').trim().toLowerCase();
      if (normalizedEmail == current) {
        final error = await c.verifyContact(token);
        if (!mounted) return;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          return;
        }
        setState(() {
          emailVerificationToken = null;
          emailChallenge = null;
          emailOtp.clear();
        });
      } else {
        setState(() {
          emailVerificationToken = token;
          emailChallenge = null;
          emailOtp.clear();
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            normalizedEmail == current
                ? tr(c.fa, 'ایمیل با موفقیت تأیید شد.', 'Email verified successfully.')
                : tr(c.fa, 'ایمیل تأیید شد؛ برای اعمال تغییرات ذخیره را بزنید.', 'Email verified. Tap Save changes to apply it.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => emailVerifying = false);
    }
  }

  Future<String?> choosePhoneVerificationChannel() async {
    final caps = await c.refreshVerificationCapabilities();
    return caps.whatsapp ? 'WHATSAPP' : null;
  }

  Future<void> sendPhoneVerification() async {
    final target = normalizedPhone;
    if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(target)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'شماره را با کد کشور وارد کنید.', 'Enter the number with country code first.'))),
      );
      return;
    }

    setState(() => phoneSending = true);
    try {
      final channel = await choosePhoneVerificationChannel();
      if (channel == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                c.fa,
                'تأیید شماره با WhatsApp فعلاً در دسترس نیست.',
                'WhatsApp phone verification is currently unavailable.',
              ),
            ),
          ),
        );
        return;
      }

      final current = (c.user?.phone ?? '').replaceAll(RegExp(r'[\s()-]'), '');
      final caps = c.verificationCapabilities;

      if (channel == 'WHATSAPP' && caps.whatsappInbound) {
        try {
          final challenge = await c.api.requestAccountWhatsAppVerification(
            target: target,
            purpose: 'VERIFY_PHONE',
          );
          if (!mounted) return;
          final token = await showWhatsAppInboundVerification(
            context,
            challenge,
            c.fa,
            checkStatus: () => c.api.checkAccountWhatsAppVerification(
              challengeId: challenge.challengeId,
            ),
          );
          if (token == null || !mounted) return;

          if (target == current) {
            final error = await c.verifyContact(token);
            if (!mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error)),
              );
              return;
            }
            setState(() {
              phoneVerificationToken = null;
              phoneChallenge = null;
              phoneOtp.clear();
            });
          } else {
            setState(() {
              phoneVerificationToken = token;
              phoneChallenge = null;
              phoneOtp.clear();
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                target == current
                    ? tr(c.fa, 'شماره موبایل با موفقیت تأیید شد.', 'Mobile number verified successfully.')
                    : tr(c.fa, 'شماره تأیید شد؛ برای اعمال تغییرات ذخیره را بزنید.', 'Number verified. Tap Save changes to apply it.'),
              ),
            ),
          );
          return;
        } on ApiException catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.code)),
          );
          return;
        }
      }

      final challenge = target == current
          ? await c.requestAccountOtp(channel, 'VERIFY_PHONE')
          : await c.requestContactChangeOtp('PHONE', target, channel);
      if (!mounted) return;
      if (challenge == null) {
        final code = c.authError ?? 'otp_provider_failed';
        final message = code == 'whatsapp_test_recipient_not_allowed'
            ? tr(
                c.fa,
                'در حالت تست Meta فقط شماره‌هایی که در Recipient list تأیید شده‌اند می‌توانند کد بگیرند.',
                'In Meta test mode, only phone numbers verified in the Recipient list can receive the code.',
              )
            : code == 'whatsapp_session_required'
                ? tr(
                    c.fa,
                    'ابتدا از همین شماره یک پیام WhatsApp به شماره تست Velixeo بفرستید و دوباره Verify را بزنید.',
                    'First send a WhatsApp message from this number to the Velixeo test number, then tap Verify again.',
                  )
                : code == 'whatsapp_token_invalid'
                    ? tr(
                        c.fa,
                        'توکن WhatsApp Meta نامعتبر یا منقضی شده است.',
                        'The Meta WhatsApp token is invalid or expired.',
                      )
                    : tr(c.fa, 'ارسال کد انجام نشد.', 'Could not send the verification code.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      setState(() {
        phoneChallenge = challenge;
        phoneOtp.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            channel == 'WHATSAPP'
                ? tr(c.fa, 'کد به واتساپ ارسال شد.', 'A verification code was sent to WhatsApp.')
                : tr(c.fa, 'کد پیامکی ارسال شد.', 'A verification code was sent by SMS.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => phoneSending = false);
    }
  }

  Future<void> verifyPhoneCode() async {
    final challenge = phoneChallenge;
    final code = phoneOtp.text.trim();
    if (challenge == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    setState(() => phoneVerifying = true);
    try {
      final token = await c.verifyAccountOtp(challenge.challengeId, code);
      if (token == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(c.fa, 'کد تأیید درست نیست یا منقضی شده است.', 'The code is invalid or expired.'))),
          );
        }
        return;
      }

      final current = (c.user?.phone ?? '').replaceAll(RegExp(r'[\s()-]'), '');
      if (normalizedPhone == current) {
        final error = await c.verifyContact(token);
        if (!mounted) return;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          return;
        }
        setState(() {
          phoneVerificationToken = null;
          phoneChallenge = null;
          phoneOtp.clear();
        });
      } else {
        setState(() {
          phoneVerificationToken = token;
          phoneChallenge = null;
          phoneOtp.clear();
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            normalizedPhone == current
                ? tr(c.fa, 'شماره موبایل با موفقیت تأیید شد.', 'Mobile number verified successfully.')
                : tr(c.fa, 'شماره تأیید شد؛ برای اعمال تغییرات ذخیره را بزنید.', 'Number verified. Tap Save changes to apply it.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => phoneVerifying = false);
    }
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    final name = fullName.text.trim();
    final nextEmail = normalizedEmail;
    final nextPhone = normalizedPhone;
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'نام معتبر وارد کنید.', 'Enter a valid full name.'))),
      );
      return;
    }
    if (nextEmail.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(nextEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ایمیل معتبر وارد کنید.', 'Enter a valid email address.'))),
      );
      return;
    }
    if (nextPhone.isNotEmpty && !RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(nextPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'شماره را با کد کشور وارد کنید.', 'Enter the mobile number with country code.'))),
      );
      return;
    }

    final currentEmail = (c.user?.email ?? '').trim().toLowerCase();
    final currentPhone = (c.user?.phone ?? '').replaceAll(RegExp(r'[\s()-]'), '');
    if (nextEmail != currentEmail && nextEmail.isNotEmpty && emailVerificationToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ابتدا ایمیل جدید را با کد OTP تأیید کنید.', 'Verify the new email with OTP before saving.'))),
      );
      return;
    }
    if (nextPhone != currentPhone && nextPhone.isNotEmpty && phoneVerificationToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ابتدا شماره جدید را با کد OTP تأیید کنید.', 'Verify the new mobile number with OTP before saving.'))),
      );
      return;
    }

    setState(() => busy = true);
    try {
      final error = await c.updateProfile(
        fullName: name,
        websiteUrl: website.text.trim(),
        countryCode: countryCode,
        avatarPreset: avatarPreset,
        avatarData: avatarData,
        avatarUrl: avatarUrl,
        email: nextEmail,
        phone: nextPhone,
        emailVerificationToken: emailVerificationToken,
        phoneVerificationToken: phoneVerificationToken,
      );
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'پروفایل با موفقیت ذخیره شد.', 'Profile updated successfully.'))),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr(c.fa, 'ذخیره پروفایل انجام نشد:', 'Could not update profile:')} $error')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget verificationSuffix({
    required bool verified,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    if (verified) {
      return const Padding(
        padding: EdgeInsets.only(right: 10),
        child: Icon(Icons.verified_rounded, color: Color(0xFF18A875)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                tr(c.fa, 'تأیید', 'Verify'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildEditProfileView(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildEditProfileView(context),
          );
  }

  Widget _buildEditProfileView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'ویرایش پروفایل', 'Edit profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Center(
            child: Column(
              children: [
                UserAvatar(user: previewUser(), size: 96, showEditBadge: true, onTap: pickProfilePhoto),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : pickProfilePhoto,
                      icon: const Icon(Icons.crop_rounded, size: 18),
                      label: Text(tr(c.fa, 'انتخاب و تنظیم تصویر', 'Choose & adjust photo')),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : chooseAvatar,
                      icon: const Icon(Icons.face_retouching_natural_rounded, size: 18),
                      label: Text(tr(c.fa, 'انتخاب آواتار', 'Choose avatar')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    c.fa,
                    'قبل از ذخیره می‌توانید تصویر را جابه‌جا، زوم و دقیقاً وسط کادر تنظیم کنید.',
                    'Before saving, move and zoom the photo to center your face inside the crop.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF8291A1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionTitle(tr(c.fa, 'اطلاعات پایه', 'Basic information')),
          const SizedBox(height: 10),
          TextField(
            controller: fullName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.badge_outlined),
              labelText: tr(c.fa, 'نام و نام خانوادگی', 'Full name'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.alternate_email),
              labelText: tr(c.fa, 'ایمیل', 'Email'),
              suffixIcon: verificationSuffix(
                verified: emailVerifiedNow,
                loading: emailSending,
                onPressed: normalizedEmail.isEmpty ? null : sendEmailVerification,
              ),
              helperText: emailVerifiedNow
                  ? tr(c.fa, 'ایمیل تأیید شده است.', 'Email verified.')
                  : tr(c.fa, 'روی Verify بزنید تا کد ۶ رقمی ارسال شود.', 'Tap Verify to receive a 6-digit code.'),
            ),
          ),
          if (emailChallenge != null) ...[
            const SizedBox(height: 8),
            _InlineOtpPanel(
              controller: emailOtp,
              maskedTarget: emailChallenge!.maskedTarget,
              loading: emailVerifying,
              onVerify: verifyEmailCode,
              fa: c.fa,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.phone_iphone_rounded),
              labelText: tr(c.fa, 'شماره موبایل', 'Mobile number'),
              hintText: '+937XXXXXXXX',
              suffixIcon: verificationSuffix(
                verified: phoneVerifiedNow,
                loading: phoneSending,
                onPressed: normalizedPhone.isEmpty ? null : sendPhoneVerification,
              ),
              helperText: phoneVerifiedNow
                  ? tr(c.fa, 'شماره موبایل تأیید شده است.', 'Mobile number verified.')
                  : tr(c.fa, 'شماره را با کد کشور وارد کنید و Verify را بزنید.', 'Enter the number with country code, then tap Verify.'),
            ),
          ),
          if (phoneChallenge != null) ...[
            const SizedBox(height: 8),
            _InlineOtpPanel(
              controller: phoneOtp,
              maskedTarget: phoneChallenge!.maskedTarget,
              loading: phoneVerifying,
              onVerify: verifyPhoneCode,
              fa: c.fa,
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => showCountryPicker(
              context: context,
              showPhoneCode: true,
              onSelect: (country) => setState(() {
                countryCode = country.countryCode;
                if (phone.text.trim().isEmpty) phone.text = '+${country.phoneCode}';
              }),
            ),
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.public_rounded),
                labelText: tr(c.fa, 'کشور', 'Country'),
              ),
              child: Text(countryCode?.isNotEmpty == true ? countryCode! : tr(c.fa, 'انتخاب کشور', 'Choose country')),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: website,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.language_rounded),
              labelText: tr(c.fa, 'آدرس سایت شما', 'Your website'),
              hintText: 'https://example.com',
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

class _InlineOtpPanel extends StatelessWidget {
  const _InlineOtpPanel({
    required this.controller,
    required this.maskedTarget,
    required this.loading,
    required this.onVerify,
    required this.fa,
  });

  final TextEditingController controller;
  final String maskedTarget;
  final bool loading;
  final VoidCallback onVerify;
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF7FF),
          border: Border.all(color: const Color(0xFFB8DDFC)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(fa, 'کد ارسال شد به ' + maskedTarget, 'Code sent to ' + maskedTarget),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF4D6E8D)),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 5),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    onSubmitted: (_) => onVerify(),
                  ),
                ),
                const SizedBox(width: 9),
                FilledButton(
                  onPressed: loading ? null : onVerify,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(92, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  ),
                  child: loading
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(tr(fa, 'تأیید کد', 'Confirm')),
                ),
              ],
            ),
          ],
        ),
      );
}

Future<String?> showWhatsAppInboundVerification(
  BuildContext context,
  VerificationChallenge challenge,
  bool fa, {
  required Future<String?> Function() checkStatus,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WhatsAppInboundDialog(
      challenge: challenge,
      fa: fa,
      checkStatus: checkStatus,
    ),
  );
}

class _WhatsAppInboundDialog extends StatefulWidget {
  const _WhatsAppInboundDialog({
    required this.challenge,
    required this.fa,
    required this.checkStatus,
  });

  final VerificationChallenge challenge;
  final bool fa;
  final Future<String?> Function() checkStatus;

  @override
  State<_WhatsAppInboundDialog> createState() => _WhatsAppInboundDialogState();
}

class _WhatsAppInboundDialogState extends State<_WhatsAppInboundDialog>
    with WidgetsBindingObserver {
  Timer? timer;
  bool checking = false;
  bool opening = false;
  String? error;
  String? copiedNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNow();
      if (!mounted) return;
      timer = Timer.periodic(const Duration(seconds: 2), (_) => _checkNow());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkNow());
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'whatsapp_number_mismatch':
        return tr(
          widget.fa,
          'پیام از شماره دیگری ارسال شده است. برای تأیید، پیام باید دقیقاً از همان شماره‌ای ارسال شود که در VELIXEO وارد کرده‌اید.',
          'The message came from a different WhatsApp number. Verification must be sent from the exact mobile number entered in VELIXEO.',
        );
      case 'otp_expired':
        return tr(
          widget.fa,
          'هیچ تأیید معتبری از این شماره دریافت نشد. اگر این شماره حساب فعال WhatsApp ندارد، ثبت‌نام با آن امکان‌پذیر نیست.',
          'No valid verification was received from this number. If this number does not have an active WhatsApp account, it cannot be used for mobile registration.',
        );
      case 'otp_attempts_exceeded':
        return tr(
          widget.fa,
          'تلاش‌های نامعتبر زیاد بود. دوباره یک درخواست تأیید جدید ایجاد کنید.',
          'Too many invalid attempts. Start a new verification request.',
        );
      case 'network_error':
        return tr(
          widget.fa,
          'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.',
          'Could not reach the server. Check your internet connection.',
        );
      case 'phone_permanently_blocked':
        return tr(
          widget.fa,
          'این شماره توسط مدیریت برای همیشه مسدود شده و امکان تأیید یا ثبت‌نام با آن وجود ندارد.',
          'This phone number has been permanently blocked by administration and cannot be verified or registered.',
        );
      default:
        return code;
    }
  }

  Future<void> _copy(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() {
      copiedNotice = label;
      error = null;
    });
  }

  Future<void> _openWhatsApp() async {
    final link = widget.challenge.whatsappLink;
    if (link == null || link.isEmpty || opening) return;
    opening = true;
    try {
      final opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() {
          error = tr(
            widget.fa,
            'واتساپ باز نشد. اگر واتساپ روی گوشی دیگری است، لینک وریفای و پیام تأیید را از پایین کپی کنید.',
            'WhatsApp could not be opened. If WhatsApp is on another phone, copy the verification link and message below.',
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = tr(
            widget.fa,
            'واتساپ باز نشد. از روش گوشی دیگر استفاده کنید.',
            'WhatsApp could not be opened. Use the other-phone method below.',
          );
        });
      }
    } finally {
      opening = false;
    }
  }

  Future<void> _checkNow() async {
    if (checking || !mounted) return;
    checking = true;
    try {
      final token = await widget.checkStatus();
      if (!mounted) return;
      if (token?.isNotEmpty == true) {
        timer?.cancel();
        Navigator.of(context).pop(token);
        return;
      }
      if (error != null &&
          !error!.contains('شماره دیگری') &&
          !error!.contains('different WhatsApp number')) {
        setState(() => error = null);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = _friendlyError(e.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => error = _friendlyError('network_error'));
    } finally {
      checking = false;
    }
  }

  Widget _copyBox({
    required String title,
    required String value,
    required String buttonLabel,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6E8194),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF17324D),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: value.trim().isEmpty ? null : () => _copy(value, buttonLabel),
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.challenge.whatsappLink ?? '';
    final message = widget.challenge.verificationMessage ?? '';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.chat_rounded, color: Color(0xFF20A76F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(widget.fa, 'تأیید با واتساپ', 'Verify with WhatsApp'),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                widget.fa,
                'برای ادامه، پیام تأیید باید از همان شماره ${widget.challenge.maskedTarget} ارسال شود. تا زمانی که پیام از همین شماره نرسد، ثبت‌نام یا تأیید انجام نمی‌شود.',
                'The verification message must be sent from the same number ${widget.challenge.maskedTarget}. Registration or verification will not continue until the message arrives from that exact number.',
              ),
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              tr(widget.fa, 'واتساپ روی همین گوشی است', 'WhatsApp is on this phone'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: opening ? null : _openWhatsApp,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(tr(widget.fa, 'باز کردن واتساپ', 'Open WhatsApp')),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    tr(widget.fa, 'واتساپ روی گوشی دیگری است', 'WhatsApp is on another phone'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6E8194)),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                widget.fa,
                'لینک وریفای را کپی کرده و به گوشی‌ای که WhatsApp روی آن فعال است منتقل کنید. لینک را روی گوشی دوم باز کنید؛ چت رسمی Velixeo با پیام آماده باز می‌شود. پیام را بدون تغییر ارسال کنید.',
                'Copy the verification link and move it to the phone that has WhatsApp. Open the link on that phone; the official Velixeo chat opens with the message prepared. Send it without editing.',
              ),
              style: const TextStyle(fontSize: 11.5, height: 1.45, color: VelixeoDesign.muted),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCE6EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(widget.fa, 'لینک امن وریفای', 'Secure verification link'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6E8194),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    tr(
                      widget.fa,
                      'شماره رسمی داخل لینک قرار دارد و در این صفحه نمایش داده نمی‌شود.',
                      'The official number is embedded in the link and is not displayed on this screen.',
                    ),
                    style: const TextStyle(fontSize: 10.5, color: VelixeoDesign.muted),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: link.trim().isEmpty
                          ? null
                          : () => _copy(
                                link,
                                tr(widget.fa, 'لینک وریفای کپی شد.', 'Verification link copied.'),
                              ),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(tr(widget.fa, 'کپی لینک وریفای', 'Copy verification link')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _copyBox(
              title: tr(widget.fa, 'پیام تأیید — بدون تغییر ارسال کنید', 'Verification message — send without editing'),
              value: message,
              buttonLabel: tr(widget.fa, 'کپی پیام تأیید', 'Copy verification message'),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFF3D99B)),
              ),
              child: Text(
                tr(
                  widget.fa,
                  'اگر شماره‌ای که وارد کرده‌اید حساب فعال WhatsApp نداشته باشد، ثبت‌نام با موبایل انجام نمی‌شود. اگر پیام را از شماره دیگری بفرستید نیز تأیید رد می‌شود.',
                  'If the number you entered does not have an active WhatsApp account, mobile registration cannot complete. A message sent from a different number will also be rejected.',
                ),
                style: const TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF8A650F)),
              ),
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Text(
              checking
                  ? tr(widget.fa, 'در حال بررسی...', 'Checking...')
                  : tr(widget.fa, 'منتظر پیام واتساپ شما هستیم...', 'Waiting for your WhatsApp message...'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6E8194),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (copiedNotice?.isNotEmpty == true) ...[
              const SizedBox(height: 7),
              Text(
                copiedNotice!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF18A875),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (error?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(widget.fa, 'لغو', 'Cancel')),
        ),
        OutlinedButton.icon(
          onPressed: checking ? null : _checkNow,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr(widget.fa, 'بررسی وضعیت', 'Check status')),
        ),
      ],
    );
  }
}


Future<String?> showOtpDialog(
  BuildContext context,
  VerificationChallenge challenge,
  bool fa,
) {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _OtpVerificationPage(
        challenge: challenge,
        fa: fa,
      ),
    ),
  );
}

class _OtpVerificationPage extends StatefulWidget {
  const _OtpVerificationPage({
    required this.challenge,
    required this.fa,
  });

  final VerificationChallenge challenge;
  final bool fa;

  @override
  State<_OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<_OtpVerificationPage> {
  final controllers = List.generate(6, (_) => TextEditingController());
  final focuses = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focuses.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    for (final focus in focuses) {
      focus.dispose();
    }
    super.dispose();
  }

  String get code => controllers.map((controller) => controller.text).join();

  void onDigit(int index, String value) {
    final digit = value.replaceAll(RegExp(r'\D'), '');
    if (digit.isEmpty) {
      controllers[index].clear();
      if (index > 0) focuses[index - 1].requestFocus();
      setState(() {});
      return;
    }
    controllers[index].text = digit.substring(digit.length - 1);
    controllers[index].selection = TextSelection.collapsed(
      offset: controllers[index].text.length,
    );
    if (index < focuses.length - 1) {
      focuses[index + 1].requestFocus();
    } else {
      focuses[index].unfocus();
    }
    setState(() {});
  }

  void verify() {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final fa = widget.fa;
    final deliveryMessage = fa
        ? 'کد ۶ رقمی به ' + widget.challenge.maskedTarget + ' ارسال شد.'
        : 'A 6-digit code was sent to ' + widget.challenge.maskedTarget + '.';
    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              fa ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7FD),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    color: Color(0xFF4BA6CB),
                    size: 31,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                fa ? 'حسابت را تأیید کن' : 'Verify your account',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: VelixeoBrand.ink,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                deliveryMessage,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.65,
                  color: VelixeoBrand.muted,
                ),
              ),
              const SizedBox(height: 26),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == 5 ? 0 : 7,
                      ),
                      child: SizedBox(
                        width: 42,
                        height: 52,
                        child: TextField(
                          controller: controllers[index],
                          focusNode: focuses[index],
                          autofocus: index == 0,
                          keyboardType: TextInputType.number,
                          textInputAction: index == 5
                              ? TextInputAction.done
                              : TextInputAction.next,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(1),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: VelixeoBrand.line,
                              ),
                            ),
                          ),
                          onChanged: (value) => onDigit(index, value),
                          onSubmitted: (_) {
                            if (index == 5) verify();
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                fa
                    ? 'این کد تا ۱۰ دقیقه معتبر است.'
                    : 'This code expires in 10 minutes.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8294A1),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    RegExp(r'^\d{6}$').hasMatch(code) ? verify : null,
                child: Text(fa ? 'تأیید و ادامه' : 'Verify and continue'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(fa ? 'بازگشت' : 'Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  SecurityState? state;
  final emailOtp = TextEditingController();
  final phoneOtp = TextEditingController();
  VerificationChallenge? emailChallenge;
  VerificationChallenge? phoneChallenge;
  bool busy = false;
  bool emailSending = false;
  bool emailVerifying = false;
  bool phoneSending = false;
  bool phoneVerifying = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    emailOtp.dispose();
    phoneOtp.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final value = await c.loadSecurityState();
    if (!mounted) return;
    setState(() => state = value);
  }

  String verificationLabel(bool verified) => verified
      ? tr(c.fa, 'تأیید شده', 'Verified')
      : tr(c.fa, 'تأیید نشده', 'Not verified');

  Future<String?> verifyChallenge(VerificationChallenge? challenge) async {
    if (challenge == null || !mounted) return null;
    final code = await showOtpDialog(context, challenge, c.fa);
    if (code == null) return null;
    return c.verifyAccountOtp(challenge.challengeId, code);
  }

  Future<void> sendSecurityEmailCode() async {
    final s = state;
    if (s == null || s.email?.isNotEmpty != true) return;
    setState(() => emailSending = true);
    try {
      final fresh = await c.loadSecurityState();
      if (fresh != null && mounted) setState(() => state = fresh);
      final current = state;
      if (current == null || !current.verification.email) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'ارسال OTP ایمیل هنوز روی سرور فعال نیست.', 'Email OTP is not active on the server yet.'))),
        );
        return;
      }
      final challenge = await c.requestAccountOtp('EMAIL', 'VERIFY_EMAIL');
      if (!mounted) return;
      if (challenge == null) {
        final code = c.authError ?? 'email_otp_provider_failed';
        final message = code == 'email_otp_auth_failed'
            ? tr(c.fa, 'اتصال امن افزونه OTP رد شد؛ افزونه وردپرس را بروزرسانی کنید.', 'OTP relay authentication was rejected; update the WordPress relay plugin.')
            : code == 'email_otp_route_missing'
                ? tr(c.fa, 'مسیر OTP روی سایت پیدا نشد.', 'The OTP relay route is missing on the website.')
                : code == 'email_otp_mail_failed'
                    ? tr(c.fa, 'هاست نتوانست ایمیل را ارسال کند.', 'The hosting mailer could not send the email.')
                    : code == 'otp_resend_too_soon'
                        ? tr(c.fa, 'کمی صبر کنید و دوباره تلاش کنید.', 'Please wait a moment before requesting another code.')
                        : tr(c.fa, 'ارسال کد تأیید انجام نشد.', 'Could not send the verification code.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      setState(() {
        emailChallenge = challenge;
        emailOtp.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'کد ۶ رقمی به ایمیل شما ارسال شد.', 'A 6-digit code was sent to your email.'))),
      );
    } finally {
      if (mounted) setState(() => emailSending = false);
    }
  }

  Future<void> confirmSecurityEmailCode() async {
    final challenge = emailChallenge;
    final code = emailOtp.text.trim();
    if (challenge == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    setState(() => emailVerifying = true);
    try {
      final token = await c.verifyAccountOtp(challenge.challengeId, code);
      if (token == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(c.fa, 'کد نادرست است یا منقضی شده.', 'The code is invalid or expired.'))),
          );
        }
        return;
      }
      final error = await c.verifyContact(token);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      setState(() {
        emailChallenge = null;
        emailOtp.clear();
      });
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'ایمیل با موفقیت تأیید شد.', 'Email verified successfully.'))),
      );
    } finally {
      if (mounted) setState(() => emailVerifying = false);
    }
  }

  Future<String?> choosePhoneChannel() async {
    final s = state;
    if (s == null) return null;
    return s.verification.whatsapp ? 'WHATSAPP' : null;
  }

  Future<void> sendSecurityPhoneCode() async {
    final s = state;
    if (s == null || s.phone?.isNotEmpty != true) return;
    setState(() => phoneSending = true);
    try {
      final channel = await choosePhoneChannel();
      if (channel == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'تأیید شماره با WhatsApp فعلاً در دسترس نیست.', 'WhatsApp phone verification is currently unavailable.'))),
        );
        return;
      }
      if (channel == 'WHATSAPP' && s.verification.whatsappInbound) {
        try {
          final challenge = await c.api.requestAccountWhatsAppVerification(
            purpose: 'VERIFY_PHONE',
          );
          if (!mounted) return;
          final token = await showWhatsAppInboundVerification(
            context,
            challenge,
            c.fa,
            checkStatus: () => c.api.checkAccountWhatsAppVerification(
              challengeId: challenge.challengeId,
            ),
          );
          if (token == null || !mounted) return;

          final error = await c.verifyContact(token);
          if (!mounted) return;
          if (error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
            return;
          }
          await load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(c.fa, 'شماره موبایل با موفقیت تأیید شد.', 'Mobile number verified successfully.'),
              ),
            ),
          );
          return;
        } on ApiException catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.code)),
          );
          return;
        }
      }

      final challenge = await c.requestAccountOtp(channel, 'VERIFY_PHONE');
      if (!mounted) return;
      if (challenge == null) {
        final code = c.authError ?? 'otp_provider_failed';
        final message = code == 'whatsapp_test_recipient_not_allowed'
            ? tr(
                c.fa,
                'این شماره در فهرست شماره‌های تست Meta تأیید نشده است.',
                'This phone number is not verified in the Meta test recipient list.',
              )
            : code == 'whatsapp_session_required'
                ? tr(
                    c.fa,
                    'ابتدا از این شماره به WhatsApp تست Velixeo پیام بدهید و دوباره تلاش کنید.',
                    'Send a message from this number to the Velixeo test WhatsApp first, then try again.',
                  )
                : tr(c.fa, 'ارسال کد تأیید انجام نشد.', 'Could not send the verification code.');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      setState(() {
        phoneChallenge = challenge;
        phoneOtp.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(channel == 'WHATSAPP'
            ? tr(c.fa, 'کد به واتساپ ارسال شد.', 'A code was sent to WhatsApp.')
            : tr(c.fa, 'کد پیامکی ارسال شد.', 'A code was sent by SMS.'))),
      );
    } finally {
      if (mounted) setState(() => phoneSending = false);
    }
  }

  Future<void> confirmSecurityPhoneCode() async {
    final challenge = phoneChallenge;
    final code = phoneOtp.text.trim();
    if (challenge == null || !RegExp(r'^\d{6}$').hasMatch(code)) return;
    setState(() => phoneVerifying = true);
    try {
      final token = await c.verifyAccountOtp(challenge.challengeId, code);
      if (token == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr(c.fa, 'کد نادرست است یا منقضی شده.', 'The code is invalid or expired.'))),
          );
        }
        return;
      }
      final error = await c.verifyContact(token);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      setState(() {
        phoneChallenge = null;
        phoneOtp.clear();
      });
      await load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'شماره موبایل با موفقیت تأیید شد.', 'Mobile number verified successfully.'))),
      );
    } finally {
      if (mounted) setState(() => phoneVerifying = false);
    }
  }

  Future<String?> chooseTwoFactorMethod() async {
    final s = state;
    if (s == null) return null;
    final choices = <String>[];
    if (s.emailVerified && s.verification.email) choices.add('EMAIL');
    if (s.phoneVerified && s.verification.whatsapp) choices.add('WHATSAPP');
    if (choices.isEmpty) return null;
    if (choices.length == 1) return choices.first;
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: choices.map((method) {
            final icon = method == 'EMAIL'
                ? Icons.email_outlined
                : Icons.chat_rounded;
            return ListTile(
              leading: Icon(icon, color: VelixeoDesign.sky),
              title: Text(method == 'EMAIL' ? 'Email' : method == 'WHATSAPP' ? 'WhatsApp' : 'SMS'),
              subtitle: Text(tr(c.fa, 'روش دریافت کد ورود', 'Login verification method')),
              onTap: () => Navigator.pop(context, method),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> enableTwoFactor() async {
    final method = await chooseTwoFactorMethod();
    if (method == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            c.fa,
            'برای فعال‌سازی ابتدا یک ایمیل یا شماره موبایل تأییدشده با کانال OTP فعال لازم است.',
            'Verify at least one email or mobile OTP channel before enabling two-step verification.',
          )),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      String? token;
      if (method == 'WHATSAPP' && state?.verification.whatsappInbound == true) {
        final challenge = await c.api.requestAccountWhatsAppVerification(
          purpose: 'ENABLE_2FA',
        );
        if (!mounted) return;
        token = await showWhatsAppInboundVerification(
          context,
          challenge,
          c.fa,
          checkStatus: () => c.api.checkAccountWhatsAppVerification(
            challengeId: challenge.challengeId,
          ),
        );
      } else {
        token = await verifyChallenge(await c.requestAccountOtp(method, 'ENABLE_2FA'));
      }

      if (token == null) return;
      final error = await c.enableTwoFactor(method, token);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'احراز هویت دو مرحله‌ای فعال شد.', 'Two-step verification is now enabled.'))),
        );
        await load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disableTwoFactor() async {
    final s = state;
    if (s == null) return;
    String? password;
    if (s.hasPassword) {
      final controller = TextEditingController();
      password = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr(c.fa, 'غیرفعال‌سازی 2FA', 'Disable two-step verification')),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: tr(c.fa, 'رمز عبور فعلی', 'Current password')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr(c.fa, 'لغو', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: Text(tr(c.fa, 'ادامه', 'Continue'))),
          ],
        ),
      );
      controller.dispose();
      if (password == null) return;
    }
    setState(() => busy = true);
    try {
      final error = await c.disableTwoFactor(password: password);
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'احراز هویت دو مرحله‌ای غیرفعال شد.', 'Two-step verification has been disabled.'))),
        );
        await load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.fa
        ? Directionality(
            textDirection: TextDirection.rtl,
            child: _buildSecurityView(context),
          )
        : Directionality(
            textDirection: TextDirection.ltr,
            child: _buildSecurityView(context),
          );
  }

  Widget _buildSecurityView(BuildContext context) {
    final s = state;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'امنیت و ورود', 'Security & login'))),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFEEF9FD), Color(0xFFE4F4FC)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(color: const Color(0xFFE6F4FA), borderRadius: BorderRadius.circular(17)),
                        child: const Icon(Icons.shield_rounded, color: Color(0xFF4B9FC1), size: 29),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(c.fa, 'حفاظت از حساب VELIXEO', 'Protect your VELIXEO account'), style: const TextStyle(color: Color(0xFF2C5366), fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              s.twoFactorEnabled
                                  ? tr(c.fa, 'احراز دو مرحله‌ای فعال است.', 'Two-step verification is enabled.')
                                  : tr(c.fa, 'با فعال‌کردن 2FA یک لایه امنیتی دیگر اضافه کنید.', 'Add another layer of protection with 2FA.'),
                              style: const TextStyle(color: Color(0xFF7293A5), fontSize: 11, height: 1.55),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SettingsTile(
                  icon: Icons.password_rounded,
                  title: s.hasPassword ? tr(c.fa, 'رمز عبور', 'Password') : tr(c.fa, 'تنظیم رمز عبور', 'Set password'),
                  value: s.hasPassword ? tr(c.fa, 'فعال', 'Active') : tr(c.fa, 'تنظیم نشده', 'Not set'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => s.hasPassword
                            ? ChangePasswordPage(controller: c)
                            : SetPasswordPage(controller: c),
                      ),
                    );
                    await load();
                  },
                ),
                _SecurityVerificationCard(
                  icon: Icons.alternate_email_rounded,
                  title: tr(c.fa, 'تأیید ایمیل', 'Email verification'),
                  subtitle: s.email ?? tr(c.fa, 'ایمیلی ثبت نشده است', 'No email registered'),
                  verified: s.emailVerified,
                  channelReady: s.verification.email,
                  sending: emailSending,
                  onSend: busy || s.emailVerified || s.email?.isNotEmpty != true ? null : sendSecurityEmailCode,
                  challenge: emailChallenge,
                  otpController: emailOtp,
                  verifying: emailVerifying,
                  onConfirm: confirmSecurityEmailCode,
                  fa: c.fa,
                ),
                const SizedBox(height: 10),
                _SecurityVerificationCard(
                  icon: Icons.phone_iphone_rounded,
                  title: tr(c.fa, 'تأیید شماره موبایل', 'Mobile verification'),
                  subtitle: s.phone ?? tr(c.fa, 'شماره‌ای ثبت نشده است', 'No mobile number registered'),
                  verified: s.phoneVerified,
                  channelReady: s.verification.whatsapp,
                  sending: phoneSending,
                  onSend: busy || s.phoneVerified || s.phone?.isNotEmpty != true ? null : sendSecurityPhoneCode,
                  challenge: phoneChallenge,
                  otpController: phoneOtp,
                  verifying: phoneVerifying,
                  onConfirm: confirmSecurityPhoneCode,
                  fa: c.fa,
                ),
                SettingsTile(
                  icon: Icons.phonelink_lock_rounded,
                  title: tr(c.fa, 'احراز هویت دو مرحله‌ای', 'Two-step verification'),
                  value: s.twoFactorEnabled ? (s.twoFactorMethod ?? 'ON') : 'OFF',
                  onTap: busy ? null : (s.twoFactorEnabled ? disableTwoFactor : enableTwoFactor),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(c.fa, 'کانال‌های OTP', 'OTP channels'), style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      _SecurityChannelRow(label: 'Email', enabled: s.verification.email, free: true),
                      _SecurityChannelRow(label: 'WhatsApp', enabled: s.verification.whatsapp, free: true),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          c.fa,
                          'فقط کانال‌هایی که روی سرور تنظیم شده‌اند قابل انتخاب هستند.',
                          'Only channels configured on the backend can be selected.',
                        ),
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF7D8D9E), height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SecurityVerificationCard extends StatelessWidget {
  const _SecurityVerificationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.verified,
    required this.channelReady,
    required this.sending,
    required this.onSend,
    required this.challenge,
    required this.otpController,
    required this.verifying,
    required this.onConfirm,
    required this.fa,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool verified;
  final bool channelReady;
  final bool sending;
  final VoidCallback? onSend;
  final VerificationChallenge? challenge;
  final TextEditingController otpController;
  final bool verifying;
  final VoidCallback onConfirm;
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: verified ? const Color(0xFFBFECDD) : const Color(0xFFE0E8F0)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: verified ? const Color(0xFFE9F9F2) : const Color(0xFFEAF5FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: verified ? const Color(0xFF18A875) : VelixeoDesign.sky),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(subtitle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFF7A8B9D))),
                    ],
                  ),
                ),
                if (verified)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, color: VelixeoDesign.green, size: 19),
                      const SizedBox(width: 5),
                      Text(
                        tr(fa, 'تأییدشده', 'Verified'),
                        style: const TextStyle(
                          color: VelixeoDesign.green,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  FilledButton(
                    onPressed: sending ? null : onSend,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(84, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                    ),
                    child: sending
                        ? const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(channelReady ? tr(fa, 'ارسال کد', 'Verify') : tr(fa, 'غیرفعال', 'Unavailable'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
            if (!verified && !channelReady) ...[
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(fa, 'کانال OTP این بخش هنوز روی سرور فعال نشده است.', 'The OTP channel for this contact is not active yet.'),
                  style: const TextStyle(fontSize: 10, color: Color(0xFFE09A22)),
                ),
              ),
            ],
            if (challenge != null) ...[
              const SizedBox(height: 11),
              _InlineOtpPanel(
                controller: otpController,
                maskedTarget: challenge!.maskedTarget,
                loading: verifying,
                onVerify: onConfirm,
                fa: fa,
              ),
            ],
          ],
        ),
      );
}

class _SecurityChannelRow extends StatelessWidget {
  const _SecurityChannelRow({required this.label, required this.enabled, required this.free});
  final String label;
  final bool enabled;
  final bool free;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(enabled ? Icons.check_circle_rounded : Icons.schedule_rounded, color: enabled ? const Color(0xFF18A875) : const Color(0xFFEFAF38), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(enabled ? 'READY' : 'PENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: enabled ? const Color(0xFF18A875) : const Color(0xFFEFAF38))),
          ],
        ),
      );
}

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool hidden = true;
  bool busy = false;

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (password.text.length < 8 || password.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز حداقل ۸ کاراکتری و تکرار یکسان وارد کنید.', 'Use at least 8 characters and matching passwords.'))),
      );
      return;
    }
    setState(() => busy = true);
    final error = await widget.controller.setPassword(password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(widget.controller.fa, 'رمز عبور تنظیم شد.', 'Password has been set.'))),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.controller.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPage(
          context,
          appBarTitle: 'تعیین رمز عبور',
          heading: 'یک رمز امن انتخاب کن',
          subtitle: 'از رمزی استفاده کن که در حساب‌های دیگرت استفاده نمی‌کنی.',
          newLabel: 'رمز عبور جدید',
          confirmLabel: 'تکرار رمز عبور جدید',
          showLabel: hidden ? 'نمایش' : 'پنهان',
          actionLabel: busy ? 'در حال ذخیره…' : 'ذخیرهٔ رمز عبور',
          fa: true,
        ),
      );

  Widget _buildEnglish(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildPage(
          context,
          appBarTitle: 'Set password',
          heading: 'Choose a secure password',
          subtitle: 'Use a password you do not use on other accounts.',
          newLabel: 'New password',
          confirmLabel: 'Confirm new password',
          showLabel: hidden ? 'Show' : 'Hide',
          actionLabel: busy ? 'Saving…' : 'Save password',
          fa: false,
        ),
      );

  Widget _buildPage(
    BuildContext context, {
    required String appBarTitle,
    required String heading,
    required String subtitle,
    required String newLabel,
    required String confirmLabel,
    required String showLabel,
    required String actionLabel,
    required bool fa,
  }) =>
      Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                height: 1.65,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: password,
              obscureText: hidden,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: newLabel,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: TextButton(
                  onPressed: () => setState(() => hidden = !hidden),
                  child: Text(showLabel),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: hidden,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: confirmLabel,
                prefixIcon: const Icon(Icons.lock_reset_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _PasswordRulesCard(fa: fa),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ||
                      password.text.length < 8 ||
                      password.text != confirm.text
                  ? null
                  : submit,
              child: Text(actionLabel),
            ),
          ],
        ),
      );

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
  Widget build(BuildContext context) => widget.controller.fa
      ? _buildPersian(context)
      : _buildEnglish(context);

  Widget _buildPersian(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _buildPage(
          context,
          appBarTitle: 'تغییر رمز عبور',
          heading: 'وقت یک رمز تازه است',
          subtitle: 'از رمزی استفاده کن که در حساب‌های دیگرت استفاده نمی‌کنی.',
          currentLabel: 'رمز عبور فعلی',
          nextLabel: 'رمز عبور جدید',
          confirmLabel: 'تکرار رمز عبور جدید',
          showLabel: hidden ? 'نمایش' : 'پنهان',
          actionLabel: busy ? 'در حال ذخیره…' : 'ذخیرهٔ رمز جدید',
          fa: true,
        ),
      );

  Widget _buildEnglish(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _buildPage(
          context,
          appBarTitle: 'Change password',
          heading: 'Time for a fresh password',
          subtitle: 'Use a password you do not use on other accounts.',
          currentLabel: 'Current password',
          nextLabel: 'New password',
          confirmLabel: 'Confirm new password',
          showLabel: hidden ? 'Show' : 'Hide',
          actionLabel: busy ? 'Saving…' : 'Save new password',
          fa: false,
        ),
      );

  Widget _buildPage(
    BuildContext context, {
    required String appBarTitle,
    required String heading,
    required String subtitle,
    required String currentLabel,
    required String nextLabel,
    required String confirmLabel,
    required String showLabel,
    required String actionLabel,
    required bool fa,
  }) =>
      Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: VelixeoBrand.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                height: 1.65,
                color: VelixeoBrand.muted,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: current,
              obscureText: hidden,
              decoration: InputDecoration(
                labelText: currentLabel,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: next,
              obscureText: hidden,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: nextLabel,
                prefixIcon: const Icon(Icons.password_rounded),
                suffixIcon: TextButton(
                  onPressed: () => setState(() => hidden = !hidden),
                  child: Text(showLabel),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: hidden,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: confirmLabel,
                prefixIcon: const Icon(Icons.lock_reset_outlined),
              ),
            ),
            const SizedBox(height: 12),
            _PasswordRulesCard(fa: fa),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ||
                      next.text.length < 8 ||
                      next.text != confirm.text ||
                      current.text.isEmpty
                  ? null
                  : submit,
              child: Text(actionLabel),
            ),
          ],
        ),
      );

}

class _PasswordRulesCard extends StatelessWidget {
  const _PasswordRulesCard({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) {
    final rules = fa
        ? const [
            'حداقل ۸ نویسه',
            'ترکیبی از حرف و عدد',
            'متفاوت از نام و اطلاعات شخصی',
          ]
        : const [
            'At least 8 characters',
            'A mix of letters and numbers',
            'Different from your name and personal details',
          ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F5)),
      ),
      child: Column(
        children: rules
            .map(
              (rule) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Color(0xFF72BAA2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: Color(0xFF7C919E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({super.key, required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SoftCard(
          onTap: onTap,
          child: Row(
            children: [
              Icon(icon, color: VelixeoDesign.sky),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (value.isNotEmpty) Text(value, style: const TextStyle(color: VelixeoDesign.muted)),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 20),
              ],
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
        height: 48,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: VelixeoDesign.sky,
            foregroundColor: const Color(0xFF183B4B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
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
          borderRadius: BorderRadius.circular(21),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(19), child: child),
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
              if (service.en == 'Mobile Top-up') ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: service.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tr(fa, 'به‌زودی', 'Coming soon'),
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: service.color),
                  ),
                ),
              ],
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
              backgroundColor: (positive ? const Color(0xFF18A875) : VelixeoDesign.red).withValues(alpha: .1),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: positive ? const Color(0xFF18A875) : VelixeoDesign.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: VelixeoDesign.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                color: positive ? const Color(0xFF18A875) : VelixeoDesign.red,
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
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: VelixeoDesign.muted, fontSize: 12)),
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
