import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

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
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    await Future.wait([
      _storage.write(key: _accessKey, value: session.accessToken),
      _storage.write(key: _refreshKey, value: session.refreshToken),
    ]);
  }

  Future<void> clearSession() async {
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
    required String identifier,
    required String password,
    required AppLang language,
  }) async {
    final trimmed = identifier.trim();
    final body = <String, dynamic>{
      if (trimmed.contains('@')) 'email': trimmed.toLowerCase() else 'phone': trimmed,
      'password': password,
      'locale': language == AppLang.fa ? 'FA' : 'EN',
    };
    final response = await _send('POST', '/api/v1/auth/register', body: body);
    if (response.statusCode != 201) _throwResponse(response);
    final session = _sessionFromJson(_decodeObject(response));
    await _saveSession(session);
    return session;
  }

  Future<AppSession> login({required String identifier, required String password}) async {
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

  Future<bool> refreshSession() async {
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

  Future<AppUser> updatePreferences({AppLang? language, DisplayCurrency? currency}) async {
    final body = <String, dynamic>{
      if (language != null) 'locale': language == AppLang.fa ? 'FA' : 'EN',
      if (currency != null) 'displayCurrency': currency.name.toUpperCase(),
    };
    final response = await _send('PATCH', '/api/v1/me/preferences', body: body, auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppUser.fromJson(Map<String, dynamic>.from(_decodeObject(response)['user'] as Map));
  }
}
