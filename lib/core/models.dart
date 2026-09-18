enum AppLang { fa, en }

enum DisplayCurrency { afn, usd, toman }

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.status,
    required this.locale,
    required this.displayCurrency,
    required this.hasPassword,
    this.fullName,
    this.email,
    this.phone,
  });

  final String id;
  final String? fullName;
  final String? email;
  final String? phone;
  final String role;
  final String status;
  final String locale;
  final String displayCurrency;
  final bool hasPassword;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        fullName: json['fullName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        role: (json['role'] as String?) ?? 'USER',
        status: (json['status'] as String?) ?? 'ACTIVE',
        locale: (json['locale'] as String?) ?? 'FA',
        displayCurrency: (json['displayCurrency'] as String?) ?? 'AFN',
        hasPassword: (json['hasPassword'] as bool?) ?? true,
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

class CatalogService {
  const CatalogService({
    required this.id,
    required this.category,
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.featured,
    required this.sortOrder,
    this.descriptionFa,
    this.descriptionEn,
    this.basePriceAfn,
    this.minQty,
    this.maxQty,
  });

  final String id;
  final String category;
  final String slug;
  final String titleFa;
  final String titleEn;
  final String? descriptionFa;
  final String? descriptionEn;
  final bool featured;
  final int sortOrder;
  final int? basePriceAfn;
  final int? minQty;
  final int? maxQty;

  factory CatalogService.fromJson(Map<String, dynamic> json) => CatalogService(
        id: json['id'] as String,
        category: (json['category'] as String?) ?? 'SOCIAL',
        slug: (json['slug'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
        featured: (json['featured'] as bool?) ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        basePriceAfn: json['basePriceAfn'] == null
            ? null
            : int.tryParse('${json['basePriceAfn']}'),
        minQty: (json['minQty'] as num?)?.toInt(),
        maxQty: (json['maxQty'] as num?)?.toInt(),
      );
}

class AppBanner {
  const AppBanner({
    required this.id,
    required this.placement,
    required this.imageUrl,
    required this.sortOrder,
    this.titleFa,
    this.titleEn,
    this.subtitleFa,
    this.subtitleEn,
    this.actionLabelFa,
    this.actionLabelEn,
    this.actionUrl,
  });

  final String id;
  final String placement;
  final String imageUrl;
  final int sortOrder;
  final String? titleFa;
  final String? titleEn;
  final String? subtitleFa;
  final String? subtitleEn;
  final String? actionLabelFa;
  final String? actionLabelEn;
  final String? actionUrl;

  factory AppBanner.fromJson(Map<String, dynamic> json) => AppBanner(
        id: json['id'] as String,
        placement: (json['placement'] as String?) ?? 'HOME_HERO',
        imageUrl: (json['imageUrl'] as String?) ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        titleFa: json['titleFa'] as String?,
        titleEn: json['titleEn'] as String?,
        subtitleFa: json['subtitleFa'] as String?,
        subtitleEn: json['subtitleEn'] as String?,
        actionLabelFa: json['actionLabelFa'] as String?,
        actionLabelEn: json['actionLabelEn'] as String?,
        actionUrl: json['actionUrl'] as String?,
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.titleFa,
    required this.titleEn,
    required this.bodyFa,
    required this.bodyEn,
    required this.publishAt,
    this.isRead = false,
    this.readAt,
  });

  final String id;
  final String titleFa;
  final String titleEn;
  final String bodyFa;
  final String bodyEn;
  final DateTime publishAt;
  final bool isRead;
  final DateTime? readAt;

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        titleFa: titleFa,
        titleEn: titleEn,
        bodyFa: bodyFa,
        bodyEn: bodyEn,
        publishAt: publishAt,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        bodyFa: (json['bodyFa'] as String?) ?? '',
        bodyEn: (json['bodyEn'] as String?) ?? '',
        publishAt: DateTime.tryParse('${json['publishAt']}') ?? DateTime.now(),
        isRead: (json['isRead'] as bool?) ?? false,
        readAt: json['readAt'] == null ? null : DateTime.tryParse('${json['readAt']}'),
      );
}

class AppOrder {
  const AppOrder({
    required this.id,
    required this.category,
    required this.status,
    required this.baseAmountAfn,
    required this.totalAmountAfn,
    required this.createdAt,
    this.quantity,
    this.serviceSlug,
    this.serviceTitleFa,
    this.serviceTitleEn,
    this.failureReason,
    this.dripParentOrderId,
    this.dripRunIndex,
    this.dripRunsAll,
  });

  final String id;
  final String category;
  final String status;
  final int? quantity;
  final int baseAmountAfn;
  final int totalAmountAfn;
  final DateTime createdAt;
  final String? serviceSlug;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
  final String? failureReason;
  final String? dripParentOrderId;
  final int? dripRunIndex;
  final int? dripRunsAll;

  bool get isDripRun => dripRunIndex != null && dripRunsAll != null;

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : const <String, dynamic>{};
    final dripRun = json['dripRun'] is Map
        ? Map<String, dynamic>.from(json['dripRun'] as Map)
        : const <String, dynamic>{};
    return AppOrder(
      id: json['id'] as String,
      category: (json['category'] as String?) ?? 'SOCIAL',
      status: (json['status'] as String?) ?? 'PENDING',
      quantity: (json['quantity'] as num?)?.toInt(),
      baseAmountAfn: int.tryParse('${json['baseAmountAfn']}') ?? 0,
      totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      serviceSlug: service['slug'] as String?,
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
      failureReason: json['failureReason'] as String?,
      dripParentOrderId: dripRun['parentOrderId'] as String?,
      dripRunIndex: (dripRun['runIndex'] as num?)?.toInt(),
      dripRunsAll: (dripRun['runsAll'] as num?)?.toInt(),
    );
  }
}


class AppPayment {
  const AppPayment({
    required this.id,
    required this.gateway,
    required this.status,
    required this.amountAfn,
    required this.createdAt,
    required this.updatedAt,
    this.checkoutUrl,
    this.externalId,
    this.failureReason,
    this.paidAt,
    this.verifiedAt,
  });

  final String id;
  final String gateway;
  final String status;
  final int amountAfn;
  final String? checkoutUrl;
  final String? externalId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? paidAt;
  final DateTime? verifiedAt;

  factory AppPayment.fromJson(Map<String, dynamic> json) => AppPayment(
        id: json['id'] as String,
        gateway: (json['gateway'] as String?) ?? 'UNKNOWN',
        status: (json['status'] as String?) ?? 'PENDING',
        amountAfn: int.tryParse('${json['amountAfn']}') ?? 0,
        checkoutUrl: json['checkoutUrl'] as String?,
        externalId: json['externalId'] as String?,
        failureReason: json['failureReason'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
        paidAt: json['paidAt'] == null ? null : DateTime.tryParse('${json['paidAt']}'),
        verifiedAt: json['verifiedAt'] == null ? null : DateTime.tryParse('${json['verifiedAt']}'),
      );
}

class PaymentCapabilities {
  const PaymentCapabilities({
    this.hesabPayConfigured = false,
    this.hesabPayEnvironment,
    this.webhookUrl,
  });

  final bool hesabPayConfigured;
  final String? hesabPayEnvironment;
  final String? webhookUrl;

  factory PaymentCapabilities.fromJson(Map<String, dynamic> json) {
    final gateways = json['gateways'] is Map
        ? Map<String, dynamic>.from(json['gateways'] as Map)
        : const <String, dynamic>{};
    final hesabPay = gateways['HESABPAY'] is Map
        ? Map<String, dynamic>.from(gateways['HESABPAY'] as Map)
        : const <String, dynamic>{};
    return PaymentCapabilities(
      hesabPayConfigured: (hesabPay['configured'] as bool?) ?? false,
      hesabPayEnvironment: hesabPay['environment'] as String?,
      webhookUrl: json['webhookUrl'] as String?,
    );
  }
}

class PaymentSessionResult {
  const PaymentSessionResult({
    required this.payment,
    required this.idempotent,
    this.checkoutUrl,
  });

  final AppPayment payment;
  final bool idempotent;
  final String? checkoutUrl;

  factory PaymentSessionResult.fromJson(Map<String, dynamic> json) {
    final payment = AppPayment.fromJson(
      Map<String, dynamic>.from(json['payment'] as Map),
    );
    return PaymentSessionResult(
      payment: payment,
      idempotent: (json['idempotent'] as bool?) ?? false,
      checkoutUrl: (json['checkoutUrl'] as String?) ?? payment.checkoutUrl,
    );
  }
}
