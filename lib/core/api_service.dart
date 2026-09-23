import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import '../social/social_models.dart';
import '../support/support_models.dart';
import '../virtual_numbers/virtual_number_models.dart';
import '../premium/premium_models.dart';
import '../referrals/referral_models.dart';

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode, this.details});
  final String code;
  final int? statusCode;
  final Object? details;

  @override
  String toString() => 'ApiException($code, status: $statusCode)';
}

class ApiService {
  ApiService({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String baseUrl = 'https://velixeo-api-production.up.railway.app';

  static const _accessKey = 'velixeo_access_token';
  static const _refreshKey = 'velixeo_refresh_token';
  static const _languageKey = 'velixeo_language';
  static const _currencyKey = 'velixeo_display_currency';

  final http.Client _client;
  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;
  int _sessionGeneration = 0;

  Future<void> restoreTokens() async {
    _accessToken ??= await _storage.read(key: _accessKey);
    _refreshToken ??= await _storage.read(key: _refreshKey);
  }

  Future<AppLang> restoreLanguage() async {
    final saved = await _storage.read(key: _languageKey);
    return saved == 'EN' ? AppLang.en : AppLang.fa;
  }

  Future<DisplayCurrency> restoreCurrency() async {
    final saved = await _storage.read(key: _currencyKey);
    switch (saved) {
      case 'USD':
        return DisplayCurrency.usd;
      case 'TOMAN':
        return DisplayCurrency.toman;
      default:
        return DisplayCurrency.afn;
    }
  }

  Future<void> saveLanguage(AppLang language) =>
      _storage.write(key: _languageKey, value: language == AppLang.fa ? 'FA' : 'EN');

  Future<void> saveCurrency(DisplayCurrency currency) =>
      _storage.write(key: _currencyKey, value: currency.name.toUpperCase());

  Future<void> _saveSession(AppSession session) async {
    _sessionGeneration += 1;
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    await Future.wait([
      _storage.write(key: _accessKey, value: session.accessToken),
      _storage.write(key: _refreshKey, value: session.refreshToken),
    ]);
  }

  Future<void> clearSession() async {
    _sessionGeneration += 1;
    _accessToken = null;
    _refreshToken = null;
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }

  bool get hasRefreshToken => _refreshToken?.isNotEmpty == true;

  Map<String, String> _headers({bool auth = false}) => {
        'accept': 'application/json',
        'content-type': 'application/json',
        if (auth && _accessToken != null) 'authorization': 'Bearer $_accessToken',
      };

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return Map<String, dynamic>.from(decoded as Map);
  }

  Never _throwResponse(http.Response response) {
    String code = 'request_failed';
    Object? details;
    try {
      final body = _decodeObject(response);
      code = (body['error'] as String?) ?? code;
      details = body['details'];
    } catch (_) {}
    throw ApiException(code, statusCode: response.statusCode, details: details);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool retry401 = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: _headers(auth: auth)).timeout(const Duration(seconds: 20));
          break;
        case 'POST':
          response = await _client
              .post(uri, headers: _headers(auth: auth), body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(const Duration(seconds: 20));
          break;
        case 'PATCH':
          response = await _client
              .patch(uri, headers: _headers(auth: auth), body: jsonEncode(body ?? <String, dynamic>{}))
              .timeout(const Duration(seconds: 20));
          break;
        default:
          throw const ApiException('unsupported_http_method');
      }
    } catch (error) {
      if (error is ApiException) rethrow;
      throw ApiException('network_error', details: error.toString());
    }

    if (response.statusCode == 401 && auth && retry401 && await refreshSession()) {
      return _send(method, path, body: body, auth: true, retry401: false);
    }
    return response;
  }

  AppSession _sessionFromJson(Map<String, dynamic> json) => AppSession(
        user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );

  Future<AppSession> register({
    String fullName = '',
    required String identifier,
    required String password,
    required AppLang language,
    String? verificationToken,
    String? referralCode,
  }) async {
    final trimmed = identifier.trim();
    final cleanName = fullName.trim();
    final body = <String, dynamic>{
      if (cleanName.isNotEmpty) 'fullName': cleanName,
      if (trimmed.contains('@')) 'email': trimmed.toLowerCase() else 'phone': trimmed,
      'password': password,
      'locale': language == AppLang.fa ? 'FA' : 'EN',
      if (verificationToken?.trim().isNotEmpty == true) 'verificationToken': verificationToken!.trim(),
      if (referralCode?.trim().isNotEmpty == true) 'referralCode': referralCode!.trim().toUpperCase(),
    };
    final response = await _send('POST', '/api/v1/auth/register', body: body);
    if (response.statusCode != 201) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }

  Future<({AppSession? session, TwoFactorLoginChallenge? challenge})> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {
        'identifier': identifier.trim(),
        'password': password,
        'whatsappInbound': true,
      },
    );
    if (response.statusCode == 202) {
      final challenge = TwoFactorLoginChallenge.fromJson(_decodeObject(response));
      return (session: null, challenge: challenge);
    }
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return (session: session, challenge: null);
  }

  Future<AppSession> completeTwoFactorLogin({
    required String loginToken,
    required String challengeId,
    required String code,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login/2fa',
      body: {
        'loginToken': loginToken,
        'challengeId': challengeId,
        'code': code.trim(),
      },
    );
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }


  Future<AppSession?> checkTwoFactorWhatsApp({
    required String loginToken,
    required String challengeId,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login/2fa/whatsapp/status',
      body: {
        'loginToken': loginToken,
        'challengeId': challengeId,
      },
    );
    if (response.statusCode == 202) return null;
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }


  Future<({AppSession? session, TwoFactorLoginChallenge? challenge})> loginWithGoogle({
    required String idToken,
    required AppLang language,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/google',
      body: {
        'idToken': idToken,
        'locale': language == AppLang.fa ? 'FA' : 'EN',
        'whatsappInbound': true,
      },
    );
    if (response.statusCode == 202) {
      return (session: null, challenge: TwoFactorLoginChallenge.fromJson(_decodeObject(response)));
    }
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return (session: session, challenge: null);
  }

  Future<bool> refreshSession() {
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

  Future<void> logout() async {
    await restoreTokens();
    final refresh = _refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await _send(
          'POST',
          '/api/v1/auth/logout',
          body: {'refreshToken': refresh},
          auth: true,
          retry401: false,
        );
      } catch (_) {}
    }
    await clearSession();
  }

  Future<void> deleteAccount({
    String? password,
    String? reason,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/delete-account',
      body: {
        'confirmation': 'DELETE',
        if (password?.isNotEmpty == true) 'password': password,
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
      auth: true,
      retry401: false,
    );
    if (response.statusCode != 200) _throwResponse(response);
    await clearSession();
  }

  Future<(AppUser, int)> me() async {
    await restoreTokens();
    final response = await _send('GET', '/api/v1/me', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final json = _decodeObject(response);
    final user = AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map));
    final wallet = Map<String, dynamic>.from(json['wallet'] as Map);
    return (user, int.tryParse('${wallet['balanceAfn']}') ?? 0);
  }

  Future<int> walletBalance() async {
    final response = await _send('GET', '/api/v1/wallet', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return int.tryParse('${_decodeObject(response)['balanceAfn']}') ?? 0;
  }

  Future<List<WalletEntry>> walletEntries() async {
    final response = await _send('GET', '/api/v1/wallet/entries', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['entries'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => WalletEntry.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<ExchangeRates> exchangeRates() async {
    final response = await _send('GET', '/api/v1/rates');
    if (response.statusCode != 200) _throwResponse(response);
    return ExchangeRates.fromJson(_decodeObject(response));
  }

  Future<List<CatalogService>> catalogServices() async {
    final response = await _send('GET', '/api/v1/catalog/services');
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['services'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => CatalogService.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<AppBanner>> banners() async {
    final response = await _send('GET', '/api/v1/content/banners');
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['banners'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppBanner.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<PushConfig> pushConfig() async {
    final response = await _send('GET', '/api/v1/content/push-config');
    if (response.statusCode != 200) _throwResponse(response);
    return PushConfig.fromJson(_decodeObject(response));
  }

  Future<void> registerPushDevice(String token, {String platform = 'ANDROID'}) async {
    final response = await _send(
      'POST',
      '/api/v1/push/devices',
      body: {'token': token, 'platform': platform},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<void> unregisterPushDevice(String token, {String platform = 'ANDROID'}) async {
    final response = await _send(
      'POST',
      '/api/v1/push/devices/unregister',
      body: {'token': token, 'platform': platform},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<List<AppNotification>> notifications() async {
    final response = await _send('GET', '/api/v1/content/notifications', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['notifications'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppNotification.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> markNotificationRead(String notificationId) async {
    final response = await _send(
      'POST',
      '/api/v1/content/notifications/$notificationId/read',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<void> markAllNotificationsRead() async {
    final response = await _send(
      'POST',
      '/api/v1/content/notifications/read-all',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<List<PromotionOrder>> promotionOrders() async {
    final response = await _send('GET', '/api/v1/promotions/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map>()
        .map((item) => PromotionOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<PromotionOrderResult> createPromotionOrder({
    required String serviceId,
    required String packageId,
    required String postUrl,
    required String partnershipAdCode,
    required String objective,
    required List<String> targetCountries,
    required String audienceNotes,
    required String websiteUrl,
    required String clientRequestId,
    String? metaConnectionId,
    String? instagramMediaId,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/promotions/orders',
      auth: true,
      body: {
        'serviceId': serviceId,
        'packageId': packageId,
        'postUrl': postUrl,
        'partnershipAdCode': partnershipAdCode,
        'objective': objective,
        'targetCountries': targetCountries,
        'audienceNotes': audienceNotes,
        'websiteUrl': websiteUrl,
        if (metaConnectionId?.isNotEmpty == true) 'metaConnectionId': metaConnectionId,
        if (instagramMediaId?.isNotEmpty == true) 'instagramMediaId': instagramMediaId,
        'clientRequestId': clientRequestId,
        'termsAccepted': true,
      },
    );
    if (response.statusCode != 200 && response.statusCode != 201) _throwResponse(response);
    return PromotionOrderResult.fromJson(_decodeObject(response));
  }

  Future<PremiumCatalog> premiumCatalog() async {
    final response = await _send('GET', '/api/v1/premium/catalog');
    if (response.statusCode != 200) _throwResponse(response);
    return PremiumCatalog.fromJson(_decodeObject(response));
  }

  Future<List<PremiumOrder>> premiumOrders() async {
    final response = await _send('GET', '/api/v1/premium/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .whereType<Map>()
        .map((item) => PremiumOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<PremiumOrderResult> createPremiumOrder({
    required String serviceId,
    required String packageId,
    required Map<String, String> fields,
    required String clientRequestId,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/premium/orders',
      body: {
        'serviceId': serviceId,
        'packageId': packageId,
        'fields': fields,
        'clientRequestId': clientRequestId,
        'termsAccepted': true,
      },
      auth: true,
    );
    if (response.statusCode != 200 && response.statusCode != 201) _throwResponse(response);
    return PremiumOrderResult.fromJson(_decodeObject(response));
  }

  Future<List<AppOrder>> orders() async {
    final response = await _send('GET', '/api/v1/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<AppUser> updatePreferences({AppLang? language, DisplayCurrency? currency}) async {
    final body = <String, dynamic>{
      if (language != null) 'locale': language == AppLang.fa ? 'FA' : 'EN',
      if (currency != null) 'displayCurrency': currency.name.toUpperCase(),
    };
    final response = await _send('PATCH', '/api/v1/me/preferences', body: body, auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<AppUser> updateProfile({
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
    final response = await _send(
      'PATCH',
      '/api/v1/me/profile',
      body: {
        'fullName': fullName.trim(),
        'websiteUrl': websiteUrl?.trim().isEmpty == true ? null : websiteUrl?.trim(),
        'countryCode': countryCode?.trim().isEmpty == true ? null : countryCode?.trim().toUpperCase(),
        'avatarPreset': avatarPreset,
        'avatarUrl': avatarUrl?.trim().isEmpty == true ? null : avatarUrl?.trim(),
        'avatarData': avatarData,
        if (email != null) 'email': email.trim().isEmpty ? null : email.trim().toLowerCase(),
        if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.trim(),
        if (emailVerificationToken?.trim().isNotEmpty == true) 'emailVerificationToken': emailVerificationToken!.trim(),
        if (phoneVerificationToken?.trim().isNotEmpty == true) 'phoneVerificationToken': phoneVerificationToken!.trim(),
      },
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<VerificationCapabilities> verificationCapabilities() async {
    final response = await _send('GET', '/api/v1/auth/verification-capabilities');
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationCapabilities.fromJson(_decodeObject(response));
  }

  Future<VerificationChallenge> requestRegistrationWhatsAppVerification({
    required String target,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/whatsapp-verification/request',
      body: {'target': target.trim(), 'purpose': 'REGISTER'},
    );
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationChallenge.fromJson(_decodeObject(response));
  }

  Future<String?> checkRegistrationWhatsAppVerification({
    required String challengeId,
  }) async {
    final query = Uri(queryParameters: {'challengeId': challengeId}).query;
    final response = await _send(
      'GET',
      '/api/v1/auth/whatsapp-verification/status?$query',
    );
    if (response.statusCode != 200) _throwResponse(response);
    final json = _decodeObject(response);
    if (json['status'] != 'VERIFIED') return null;
    return json['verificationToken'] as String?;
  }

  Future<VerificationChallenge> requestAccountWhatsAppVerification({
    String? target,
    required String purpose,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/whatsapp-verification/request',
      body: {
        if (target?.trim().isNotEmpty == true) 'target': target!.trim(),
        'purpose': purpose,
      },
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationChallenge.fromJson(_decodeObject(response));
  }

  Future<String?> checkAccountWhatsAppVerification({
    required String challengeId,
  }) async {
    final query = Uri(queryParameters: {'challengeId': challengeId}).query;
    final response = await _send(
      'GET',
      '/api/v1/me/whatsapp-verification/status?$query',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    final json = _decodeObject(response);
    if (json['status'] != 'VERIFIED') return null;
    return json['verificationToken'] as String?;
  }

  Future<VerificationChallenge> requestRegistrationOtp({
    required String target,
    required String channel,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/verification/request',
      body: {'target': target.trim(), 'channel': channel, 'purpose': 'REGISTER'},
    );
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationChallenge.fromJson(_decodeObject(response));
  }

  Future<String> verifyRegistrationOtp({
    required String challengeId,
    required String code,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/verification/verify',
      body: {'challengeId': challengeId, 'code': code.trim()},
    );
    if (response.statusCode != 200) _throwResponse(response);
    return (_decodeObject(response)['verificationToken'] as String?) ?? '';
  }

  Future<SecurityState> securityState() async {
    final response = await _send('GET', '/api/v1/me/security', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return SecurityState.fromJson(_decodeObject(response));
  }

  Future<VerificationChallenge> requestContactChangeOtp({
    required String type,
    required String target,
    required String channel,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/contact-change/request',
      body: {'type': type, 'target': target.trim(), 'channel': channel},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationChallenge.fromJson(_decodeObject(response));
  }

  Future<VerificationChallenge> requestAccountOtp({
    required String channel,
    required String purpose,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/verification/request',
      body: {'channel': channel, 'purpose': purpose},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return VerificationChallenge.fromJson(_decodeObject(response));
  }

  Future<String> verifyAccountOtp({
    required String challengeId,
    required String code,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/verification/verify',
      body: {'challengeId': challengeId, 'code': code.trim()},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return (_decodeObject(response)['verificationToken'] as String?) ?? '';
  }

  Future<AppUser> verifyContact(String verificationToken) async {
    final response = await _send(
      'POST',
      '/api/v1/me/security/verify-contact',
      body: {'verificationToken': verificationToken},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<AppUser> enableTwoFactor({
    required String method,
    required String verificationToken,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/me/security/2fa/enable',
      body: {'method': method, 'verificationToken': verificationToken},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<AppUser> disableTwoFactor({String? password}) async {
    final response = await _send(
      'POST',
      '/api/v1/me/security/2fa/disable',
      body: {if (password?.isNotEmpty == true) 'password': password},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }

  Future<void> setPassword({required String newPassword}) async {
    final response = await _send(
      'POST',
      '/api/v1/me/set-password',
      body: {'newPassword': newPassword},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
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

  Future<PaymentCapabilities> paymentCapabilities() async {
    final response = await _send('GET', '/api/v1/payments/capabilities', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return PaymentCapabilities.fromJson(_decodeObject(response));
  }

  Future<List<AppPayment>> payments() async {
    final response = await _send('GET', '/api/v1/payments', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['payments'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppPayment.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<AppPayment> payment(String id) async {
    final response = await _send('GET', '/api/v1/payments/$id', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppPayment.fromJson(
      Map<String, dynamic>.from(_decodeObject(response)['payment'] as Map),
    );
  }

  Future<PaymentSessionResult> createHesabPaySession({
    required int amountAfn,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/payments/hesabpay/session',
      body: {
        'amountAfn': amountAfn,
        'idempotencyKey': idempotencyKey,
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return PaymentSessionResult.fromJson(_decodeObject(response));
  }


  Future<SocialOrderConfig> socialOrderConfig() async {
    final response = await _send('GET', '/api/v1/social/order-config');
    if (response.statusCode != 200) _throwResponse(response);
    return SocialOrderConfig.fromJson(_decodeObject(response));
  }

  Future<SocialCatalog> socialCatalog() async {
    final response = await _send('GET', '/api/v1/social/catalog');
    if (response.statusCode != 200) _throwResponse(response);
    return SocialCatalog.fromJson(_decodeObject(response));
  }

  Future<List<SocialOrder>> syncSocialOrders() async {
    final response = await _send('POST', '/api/v1/social/orders/sync', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => SocialOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<SocialOrder>> socialOrders() async {
    final response = await _send('GET', '/api/v1/social/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => SocialOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<SocialQuote> socialQuote({
    required String serviceId,
    required Map<String, dynamic> parameters,
    String? couponCode,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/social/quote',
      body: {
        'serviceId': serviceId,
        'parameters': parameters,
        if (couponCode?.trim().isNotEmpty == true) 'couponCode': couponCode!.trim(),
      },
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return SocialQuote.fromJson(_decodeObject(response));
  }

  Future<SocialCreateOrderResult> createSocialOrder({
    required String serviceId,
    required String clientRequestId,
    required Map<String, dynamic> parameters,
    required bool termsAccepted,
    String? couponCode,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders',
      body: {
        'serviceId': serviceId,
        'clientRequestId': clientRequestId,
        'termsAccepted': termsAccepted,
        'parameters': parameters,
        if (couponCode?.trim().isNotEmpty == true) 'couponCode': couponCode!.trim(),
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return SocialCreateOrderResult.fromJson(_decodeObject(response));
  }

  Future<SocialOrder> refreshSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/refresh',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return SocialOrder.fromJson(
      Map<String, dynamic>.from(_decodeObject(response)['order'] as Map),
    );
  }

  Future<void> refillSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/refill',
      auth: true,
    );
    if (![200, 201].contains(response.statusCode)) _throwResponse(response);
  }

  Future<void> cancelSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/cancel',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<void> refreshSocialAction(String orderId, String actionId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/actions/$actionId/refresh',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }


  Future<ReferralSummary> referralSummary() async {
    final response = await _send('GET', '/api/v1/referrals/me', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return ReferralSummary.fromJson(_decodeObject(response));
  }

  Future<VirtualCatalog> virtualNumberCatalog() async {
    final response = await _send('GET', '/api/v1/virtual-numbers/catalog');
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualCatalog.fromJson(_decodeObject(response));
  }

  Future<List<VirtualCountry>> virtualNumberCountries({required String serviceId}) async {
    final query = Uri(queryParameters: {'serviceId': serviceId}).query;
    final response = await _send('GET', '/api/v1/virtual-numbers/countries?$query');
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['countries'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => VirtualCountry.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<VirtualOffers> virtualNumberOffers({required String serviceId, required String country}) async {
    final query = Uri(queryParameters: {'serviceId': serviceId, 'country': country}).query;
    final response = await _send('GET', '/api/v1/virtual-numbers/offers?$query');
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOffers.fromJson(_decodeObject(response));
  }

  Future<List<VirtualOrder>> virtualNumberOrders() async {
    final response = await _send('GET', '/api/v1/virtual-numbers/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows.map((item) => VirtualOrder.fromJson(Map<String, dynamic>.from(item as Map))).toList(growable: false);
  }

  Future<VirtualOrder> createVirtualNumberOrder({
    required String serviceId,
    required String country,
    required String operatorName,
    required String mode,
    required String clientRequestId,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/virtual-numbers/orders',
      body: {
        'serviceId': serviceId,
        'country': country,
        'operator': operatorName,
        'mode': mode,
        'clientRequestId': clientRequestId,
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> checkVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/check', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> cancelVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/cancel', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> finishVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/finish', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<List<SupportTicket>> supportTickets() async {
    final response = await _send('GET', '/api/v1/support/tickets', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['tickets'] as List<dynamic>?) ?? const [];
    return rows.map((item) => SupportTicket.fromJson(Map<String, dynamic>.from(item as Map))).toList(growable: false);
  }

  Future<SupportTicket> createSupportTicket({required String subject, required String message}) async {
    final response = await _send(
      'POST',
      '/api/v1/support/tickets',
      body: {'subject': subject.trim(), 'message': message.trim()},
      auth: true,
    );
    if (response.statusCode != 201) _throwResponse(response);
    return SupportTicket.fromJson(Map<String, dynamic>.from(_decodeObject(response)['ticket'] as Map));
  }

  Future<SupportMessage> replySupportTicket(String ticketId, String message) async {
    final response = await _send(
      'POST',
      '/api/v1/support/tickets/$ticketId/messages',
      body: {'message': message.trim()},
      auth: true,
    );
    if (response.statusCode != 201) _throwResponse(response);
    return SupportMessage.fromJson(Map<String, dynamic>.from(_decodeObject(response)['message'] as Map));
  }

}
