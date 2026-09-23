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

  bool get fa => false; // English-first release. Persian layout will be enabled in the next design pass.
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
    Future<void> loadPaymentCapabilities() async {
      if (!authenticated) return;
      try { paymentCapabilities = await api.paymentCapabilities(); } catch (_) {}
    }
    Future<void> loadPayments() async {
      if (!authenticated) return;
      try { payments = await api.payments(); } catch (_) {}
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
      loadPaymentCapabilities(),
      loadPayments(),
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
          home: AppUpdateGate(
            child: controller.booting
                ? const SplashPage()
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
          SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _LogoPainter()),
          ),
          if (wordmark) ...[
            SizedBox(width: size * .18),
            Text(
              'VELIXEO',
              style: TextStyle(
                fontSize: size * .43,
                fontWeight: FontWeight.w900,
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
                color: const Color(0xFF1686FF),
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
      Color(0xFF1686FF), Color(0xFF7457E8), Color(0xFF14A57A), Color(0xFFF29A2E),
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
  final referralCode = TextEditingController();
  bool registerMode = false;
  bool hidden = true;
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
              registerMode
                  ? tr(fa, 'با ایمیل یا شماره موبایل ثبت‌نام کنید.', 'Register with email or mobile number.')
                  : tr(fa, 'برای ادامه وارد حساب خود شوید.', 'Sign in to continue.'),
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
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFFF0F5FA), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: _AuthMethodButton(
                        selected: registerMethod == 'EMAIL',
                        icon: Icons.alternate_email_rounded,
                        label: tr(fa, 'ایمیل', 'Email'),
                        onTap: () => setState(() {
                          registerMethod = 'EMAIL';
                          identifier.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _AuthMethodButton(
                        selected: registerMethod == 'PHONE',
                        icon: Icons.phone_iphone_rounded,
                        label: tr(fa, 'موبایل', 'Mobile'),
                        onTap: () => setState(() {
                          registerMethod = 'PHONE';
                          identifier.clear();
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              registrationIdentifier(fa),
              const SizedBox(height: 14),
              TextField(
                controller: referralCode,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.redeem_rounded),
                  hintText: tr(fa, 'کد دعوت (اختیاری)', 'Referral code (optional)'),
                  helperText: tr(
                    fa,
                    'اگر دوستی شما را دعوت کرده، کد VXL او را اینجا وارد کنید.',
                    'If a friend invited you, enter their VXL code here.',
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _AuthMethodButton(
                        selected: loginMethod == 'EMAIL',
                        icon: Icons.alternate_email_rounded,
                        label: tr(fa, 'ورود با ایمیل', 'Email'),
                        onTap: () => setState(() {
                          loginMethod = 'EMAIL';
                          identifier.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _AuthMethodButton(
                        selected: loginMethod == 'PHONE',
                        icon: Icons.phone_iphone_rounded,
                        label: tr(fa, 'ورود با موبایل', 'Mobile'),
                        onTap: () => setState(() {
                          loginMethod = 'PHONE';
                          identifier.clear();
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              loginIdentifier(fa),
            ],
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
                obscureText: hidden,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  hintText: tr(fa, 'تکرار رمز عبور', 'Confirm password'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    registerMethod == 'EMAIL'
                        ? (c.verificationCapabilities.email ? Icons.verified_user_rounded : Icons.info_outline_rounded)
                        : ((c.verificationCapabilities.sms || c.verificationCapabilities.whatsapp) ? Icons.verified_user_rounded : Icons.info_outline_rounded),
                    size: 17,
                    color: const Color(0xFF1686FF),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      registerMethod == 'EMAIL'
                          ? tr(fa, 'در صورت فعال بودن SMTP، کد OTP به ایمیل ارسال می‌شود.', 'OTP will be sent by email when SMTP is configured.')
                          : tr(fa, 'برای ثبت‌نام با موبایل، همین شماره باید یک حساب فعال WhatsApp داشته باشد.', 'To register with mobile, this exact number must have an active WhatsApp account.'),
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E8194)),
                    ),
                  ),
                ],
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
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr(fa, 'یا', 'or'))),
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
                          if (!mounted) return;
                          if (!ok && c.pendingTwoFactor != null) {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => TwoFactorLoginPage(controller: c)));
                          } else if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(errorMessage(c.authError ?? 'google_sign_in_failed'))),
                            );
                          }
                        },
                  icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
                  label: Text(c.googleConfigured ? tr(fa, 'ادامه با Google', 'Continue with Google') : tr(fa, 'Google — در انتظار تنظیم OAuth', 'Google — OAuth setup pending')),
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
                        identifier.clear();
                      }),
              child: Text(registerMode ? tr(fa, 'حساب دارید؟ وارد شوید', 'Already have an account? Sign in') : tr(fa, 'حساب ندارید؟ ثبت‌نام کنید', 'New here? Create account')),
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

class _AuthMethodButton extends StatelessWidget {
  const _AuthMethodButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: const [BoxShadow(color: Color(0x0D153F68), blurRadius: 12)],
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? const Color(0xFF1686FF) : const Color(0xFF7B8B9C)),
                const SizedBox(width: 7),
                Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: selected ? const Color(0xFF1686FF) : const Color(0xFF7B8B9C))),
              ],
            ),
          ),
        ),
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
                color: whatsappInbound ? const Color(0xFF20A76F) : const Color(0xFF1686FF),
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
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF607487), height: 1.45),
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
            action: SnackBarAction(label: 'OPEN', onPressed: () => _openPushRoute(foreground.data)),
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
  const HomePage({super.key, required this.controller, this.onProfileTap});
  final AppController controller;
  final VoidCallback? onProfileTap;

  static const services = [
    ServiceItem('شبکه‌های اجتماعی', 'Social Media', Icons.favorite_rounded, Color(0xFF7857FF)),
    ServiceItem('شماره مجازی', 'Virtual Numbers', Icons.phone_iphone_rounded, Color(0xFF28A9FF)),
    ServiceItem('پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFFF3A523)),
    ServiceItem('شارژ موبایل', 'Mobile Top-up', Icons.sim_card_rounded, Color(0xFF12B8A6)),
    ServiceItem('اکانت دیجیتال', 'Digital Accounts', Icons.account_circle_rounded, Color(0xFF5B6EF5)),
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
                UserAvatar(
                  user: c.user,
                  size: 42,
                  onTap: onProfileTap ?? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(controller: c))),
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
                      if (service.en == 'Mobile Top-up') ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: service.color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)),
                          child: Text(tr(c.fa, 'به‌زودی', 'Coming soon'), style: TextStyle(fontSize: 8, color: service.color, fontWeight: FontWeight.w900)),
                        ),
                      ],
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
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: SoftCard(
                  onTap: () {
                    final service = HomePage.services.firstWhere((item) => item.en == 'Mobile Top-up');
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ComingSoonServicePage(controller: c, service: service)));
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: const Color(0xFF12B8A6).withValues(alpha: .10), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.sim_card_rounded, color: Color(0xFF12B8A6)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(c.fa, 'شارژ موبایل', 'Mobile Top-up'), style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(tr(c.fa, 'به‌زودی · پس از اتصال API شرکت‌های مخابراتی', 'Coming soon · waiting for telecom APIs'), style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF12B8A6).withValues(alpha: .10), borderRadius: BorderRadius.circular(999)),
                        child: Text(tr(c.fa, 'به‌زودی', 'Soon'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF0D8E81))),
                      ),
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

class DigitalAccountsHubPage extends StatelessWidget {
  const DigitalAccountsHubPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final items = c.catalogServices
        .where((service) => service.category == 'DIGITAL_ACCOUNT')
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'اکانت‌های دیجیتال', 'Digital Accounts'))),
      body: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3F51D7), Color(0xFF6D63FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(c.fa, 'اکانت‌ها و خدمات دیجیتال', 'Digital accounts & services'),
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          tr(
                            c.fa,
                            'نتفلیکس، VPN، سرویس‌های استریم، ابزارهای آنلاین، لایسنس‌ها و اکانت‌های دیجیتال از این بخش مدیریت می‌شوند.',
                            'Netflix, VPN, streaming services, online tools, licenses and other digital accounts belong here.',
                          ),
                          style: const TextStyle(color: Color(0xFFE9E9FF), fontSize: 11.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              EmptyCard(
                icon: Icons.manage_accounts_outlined,
                title: tr(c.fa, 'هنوز اکانت دیجیتال اضافه نشده', 'No digital accounts yet'),
                subtitle: tr(
                  c.fa,
                  'محصولات این بخش از پنل ادمین Digital Accounts اضافه می‌شوند.',
                  'Products for this section are created from Digital Accounts in Admin.',
                ),
              )
            else
              ...items.map((service) {
                final color = catalogColor(service.category);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CatalogServicePage(controller: c, service: service)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
                          child: Icon(Icons.manage_accounts_rounded, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(
                                service.basePriceAfn == null
                                    ? tr(c.fa, 'قیمت و تحویل از پنل ادمین مدیریت می‌شود', 'Pricing and delivery are managed from Admin')
                                    : tr(c.fa, 'از ${c.money(service.basePriceAfn!)}', 'From ${c.money(service.basePriceAfn!)}'),
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF607487)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
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
                style: const TextStyle(color: Color(0xFF607487), height: 1.6),
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
      return const Color(0xFF1686FF);
    case 'PAYMENT':
    case 'WALLET':
      return const Color(0xFF16A873);
    case 'SUPPORT':
      return const Color(0xFF7457E8);
    case 'ACCOUNT':
      return const Color(0xFFF29A2E);
    default:
      return const Color(0xFF2E86C9);
  }
}

String _notificationTypeLabel(String type) {
  switch (type) {
    case 'ORDER': return 'Order';
    case 'REFILL': return 'Refill';
    case 'DRIPFEED': return 'Drip-feed';
    case 'PAYMENT': return 'Payment';
    case 'WALLET': return 'Wallet';
    case 'SUPPORT': return 'Support';
    case 'ACCOUNT': return 'Account';
    default: return 'System';
  }
}

String _relativeNotificationTime(DateTime value) {
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
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
    final c = widget.controller;
    const filters = <(String, String)>[
      ('ALL', 'All'),
      ('ORDER', 'Orders'),
      ('WALLET', 'Wallet'),
      ('SUPPORT', 'Support'),
      ('SYSTEM', 'System'),
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
                      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF082D58), Color(0xFF0F70D9), Color(0xFF28B2FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: const [BoxShadow(color: Color(0x261686FF), blurRadius: 28, offset: Offset(0, 12))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .14), foregroundColor: Colors.white),
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
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Notification Center', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                                    SizedBox(height: 2),
                                    Text('Orders, wallet, support & updates', style: TextStyle(color: Color(0xFFD7EDFF), fontSize: 11.5)),
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
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .11), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .13))),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('Unread', style: TextStyle(color: Color(0xFFD6ECFF), fontSize: 10.5)),
                                    const SizedBox(height: 4),
                                    Text('${c.unreadNotificationCount}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .11), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .13))),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('Total', style: TextStyle(color: Color(0xFFD6ECFF), fontSize: 10.5)),
                                    const SizedBox(height: 4),
                                    Text('${c.notifications.length}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                                  ]),
                                ),
                              ),
                              if (c.unreadNotificationCount > 0) ...[
                                const SizedBox(width: 10),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1268C7), minimumSize: const Size(86, 58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                  onPressed: c.markAllNotificationsRead,
                                  child: const Text('Read all', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14),
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
                            selectedColor: const Color(0xFF1686FF),
                            backgroundColor: Colors.white,
                            side: BorderSide(color: active ? const Color(0xFF1686FF) : const Color(0xFFE0E8F0)),
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
                                  border: Border.all(color: notice.isRead ? const Color(0xFFE3EAF2) : color.withValues(alpha: .24)),
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
                                                  child: Text(_notificationTypeLabel(notice.type), style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900)),
                                                ),
                                                if (notice.priority == 'HIGH') ...[
                                                  const SizedBox(width: 5),
                                                  const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFF29A2E)),
                                                ],
                                                const Spacer(),
                                                Text(_relativeNotificationTime(notice.publishAt), style: const TextStyle(color: Color(0xFF8A9AA9), fontSize: 10)),
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
                                            Expanded(child: Text(action?.trim().isNotEmpty == true ? action! : 'Open ${_notificationTypeLabel(notice.type)}', style: TextStyle(color: color, fontSize: 10.8, fontWeight: FontWeight.w900))),
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
                          gradient: LinearGradient(colors: [Color(0xFF0D78C8), Color(0xFF31A8FF)]),
                        ),
                      ),
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
                UserAvatar(
                  user: c.user,
                  size: 60,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(controller: c))),
                ),
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
            icon: Icons.security_rounded,
            title: tr(c.fa, 'امنیت و ورود', 'Security & login'),
            value: c.user?.twoFactorEnabled == true ? '2FA ON' : '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SecurityPage(controller: c)),
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
            icon: Icons.group_add_rounded,
            title: tr(c.fa, 'دعوت از دوستان', 'Invite friends'),
            value: '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => InviteFriendsPage(host: c)),
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
            icon: Icons.person_remove_alt_1_rounded,
            title: tr(c.fa, 'حذف حساب', 'Delete account'),
            value: '',
            onTap: () async {
              final passwordController = TextEditingController();
              final reasonController = TextEditingController();
              var confirmDelete = false;
              final confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => StatefulBuilder(
                  builder: (context, setDialogState) => AlertDialog(
                    title: Text(tr(c.fa, 'حذف حساب VELIXEO', 'Delete VELIXEO account')),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(
                              c.fa,
                              'حساب شما غیرفعال و اطلاعات شخصی پروفایل حذف می‌شود. سوابق مالی و سفارش‌ها برای امنیت و حسابداری نگهداری می‌شوند. حذف حساب به‌تنهایی شماره شما را بلاک نمی‌کند و در آینده می‌توانید دوباره ثبت‌نام کنید.',
                              'Your account will be disabled and personal profile data removed. Financial and order records are retained for security and accounting. Deleting your account does not blacklist your phone number, so you may register again later.',
                            ),
                            style: const TextStyle(height: 1.5),
                          ),
                          if (c.user?.hasPassword == true) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: tr(c.fa, 'رمز عبور فعلی', 'Current password'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: reasonController,
                            maxLength: 300,
                            decoration: InputDecoration(
                              labelText: tr(c.fa, 'دلیل (اختیاری)', 'Reason (optional)'),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: confirmDelete,
                            onChanged: (value) => setDialogState(() => confirmDelete = value == true),
                            title: Text(
                              tr(
                                c.fa,
                                'می‌دانم این عمل حساب فعلی را حذف می‌کند.',
                                'I understand this deletes my current account.',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(tr(c.fa, 'لغو', 'Cancel')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65454)),
                        onPressed: !confirmDelete ||
                                (c.user?.hasPassword == true && passwordController.text.isEmpty)
                            ? null
                            : () => Navigator.pop(dialogContext, true),
                        child: Text(tr(c.fa, 'حذف حساب', 'Delete account')),
                      ),
                    ],
                  ),
                ),
              );
              final password = passwordController.text;
              final reason = reasonController.text;
              passwordController.dispose();
              reasonController.dispose();
              if (confirmed != true || !context.mounted) return;
              final error = await c.deleteAccount(
                password: password.isEmpty ? null : password,
                reason: reason,
              );
              if (!context.mounted || error == null) return;
              final message = error == 'incorrect_current_password'
                  ? tr(c.fa, 'رمز عبور فعلی نادرست است.', 'The current password is incorrect.')
                  : tr(c.fa, 'حذف حساب انجام نشد. دوباره تلاش کنید.', 'Account deletion failed. Please try again.');
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
            },
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
            activeControlsWidgetColor: const Color(0xFF1686FF),
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
                              decoration: const BoxDecoration(color: Color(0xFF1686FF), shape: BoxShape.circle),
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
          SnackBar(content: Text('Could not update profile: ' + error)),
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
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'ویرایش پروفایل', 'Edit profile'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
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
          const SectionTitle('Basic information'),
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
              style: const TextStyle(fontSize: 11.5, height: 1.45, color: Color(0xFF607487)),
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
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF607487)),
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
) async {
  final code = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(tr(fa, 'کد تأیید', 'Verification code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(
            fa,
            'کد ۶ رقمی به ${challenge.maskedTarget} ارسال شد.',
            'A 6-digit code was sent to ${challenge.maskedTarget}.',
          )),
          const SizedBox(height: 16),
          TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onSubmitted: (value) {
              if (RegExp(r'^\d{6}$').hasMatch(value.trim())) Navigator.pop(dialogContext, value.trim());
            },
          ),
          const SizedBox(height: 8),
          Text(
            tr(fa, 'این کد تا ۱۰ دقیقه معتبر است.', 'This code expires in 10 minutes.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF7A8B9D)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr(fa, 'لغو', 'Cancel'))),
        FilledButton(
          onPressed: () {
            if (RegExp(r'^\d{6}$').hasMatch(code.text.trim())) Navigator.pop(dialogContext, code.text.trim());
          },
          child: Text(tr(fa, 'تأیید', 'Verify')),
        ),
      ],
    ),
  );
  code.dispose();
  return result;
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
              leading: Icon(icon, color: const Color(0xFF1686FF)),
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
    final s = state;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'امنیت و ورود', 'Security & login'))),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF082D58), Color(0xFF1686FF)]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(17)),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 29),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(c.fa, 'حفاظت از حساب VELIXEO', 'Protect your VELIXEO account'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              s.twoFactorEnabled
                                  ? tr(c.fa, 'احراز دو مرحله‌ای فعال است.', 'Two-step verification is enabled.')
                                  : tr(c.fa, 'با فعال‌کردن 2FA یک لایه امنیتی دیگر اضافه کنید.', 'Add another layer of protection with 2FA.'),
                              style: const TextStyle(color: Color(0xFFD8ECFF), fontSize: 11.5, height: 1.4),
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
                  child: Icon(icon, color: verified ? const Color(0xFF18A875) : const Color(0xFF1686FF)),
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
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, color: Color(0xFF18A875), size: 19),
                      SizedBox(width: 5),
                      Text('VERIFIED', style: TextStyle(color: Color(0xFF18A875), fontSize: 9.5, fontWeight: FontWeight.w900)),
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
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'تنظیم رمز عبور', 'Set password'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: password,
            obscureText: hidden,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              labelText: tr(c.fa, 'رمز عبور جدید', 'New password'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            obscureText: hidden,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_reset_rounded),
              labelText: tr(c.fa, 'تکرار رمز عبور', 'Confirm password'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => hidden = !hidden),
                icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(label: busy ? 'Saving...' : tr(c.fa, 'تنظیم رمز عبور', 'Set password'), onPressed: busy ? null : submit),
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
  final VoidCallback? onTap;

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
