enum AppLang { fa, en }

enum DisplayCurrency { afn, usd, toman }

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.locale,
    required this.displayCurrency,
    this.email,
    this.phone,
  });

  final String id;
  final String? email;
  final String? phone;
  final String role;
  final String locale;
  final String displayCurrency;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        role: (json['role'] as String?) ?? 'USER',
        locale: (json['locale'] as String?) ?? 'FA',
        displayCurrency: (json['displayCurrency'] as String?) ?? 'AFN',
      );
}

class AppSession {
  const AppSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final AppUser user;
  final String accessToken;
  final String refreshToken;
}

class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.amountAfn,
    required this.balanceAfterAfn,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String status;
  final int amountAfn;
  final int balanceAfterAfn;
  final String description;
  final DateTime createdAt;

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
        id: json['id'] as String,
        type: (json['type'] as String?) ?? 'UNKNOWN',
        status: (json['status'] as String?) ?? 'COMPLETED',
        amountAfn: int.tryParse('${json['amountAfn']}') ?? 0,
        balanceAfterAfn: int.tryParse('${json['balanceAfterAfn']}') ?? 0,
        description: (json['description'] as String?) ?? '',
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}

class ExchangeRates {
  const ExchangeRates({this.afnPerUsd, this.afnPerToman});

  final double? afnPerUsd;
  final double? afnPerToman;

  factory ExchangeRates.fromJson(Map<String, dynamic> json) {
    double? usd;
    double? toman;
    final items = (json['rates'] as List<dynamic>?) ?? const [];
    for (final item in items) {
      final row = Map<String, dynamic>.from(item as Map);
      final value = double.tryParse('${row['afnPerUnit']}');
      if (row['code'] == 'USD') usd = value;
      if (row['code'] == 'TOMAN') toman = value;
    }
    return ExchangeRates(afnPerUsd: usd, afnPerToman: toman);
  }
}
