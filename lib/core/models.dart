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
    this.websiteUrl,
    this.countryCode,
    this.avatarPreset = 'avatar_01',
    this.avatarUrl,
    this.avatarData,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.twoFactorEnabled = false,
    this.twoFactorMethod,
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
  final String? websiteUrl;
  final String? countryCode;
  final String avatarPreset;
  final String? avatarUrl;
  final String? avatarData;
  final bool emailVerified;
  final bool phoneVerified;
  final bool twoFactorEnabled;
  final String? twoFactorMethod;

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
        websiteUrl: json['websiteUrl'] as String?,
        countryCode: json['countryCode'] as String?,
        avatarPreset: (json['avatarPreset'] as String?) ?? 'avatar_01',
        avatarUrl: json['avatarUrl'] as String?,
        avatarData: json['avatarData'] as String?,
        emailVerified: (json['emailVerified'] as bool?) ?? false,
        phoneVerified: (json['phoneVerified'] as bool?) ?? false,
        twoFactorEnabled: (json['twoFactorEnabled'] as bool?) ?? false,
        twoFactorMethod: json['twoFactorMethod'] as String?,
      );
}

class VerificationCapabilities {
  const VerificationCapabilities({
    this.email = false,
    this.sms = false,
    this.whatsapp = false,
    this.whatsappInbound = false,
    this.registrationVerificationRequired = false,
    this.resendCooldownSeconds = 60,
    this.expiresInSeconds = 600,
  });

  final bool email;
  final bool sms;
  final bool whatsapp;
  final bool whatsappInbound;
  final bool registrationVerificationRequired;
  final int resendCooldownSeconds;
  final int expiresInSeconds;

  factory VerificationCapabilities.fromJson(Map<String, dynamic> json) => VerificationCapabilities(
        email: (json['email'] as bool?) ?? false,
        sms: (json['sms'] as bool?) ?? false,
        whatsapp: (json['whatsapp'] as bool?) ?? false,
        whatsappInbound: (json['whatsappInbound'] as bool?) ?? false,
        registrationVerificationRequired: (json['registrationVerificationRequired'] as bool?) ?? false,
        resendCooldownSeconds: (json['resendCooldownSeconds'] as num?)?.toInt() ?? 60,
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 600,
      );
}

class VerificationChallenge {
  const VerificationChallenge({
    required this.challengeId,
    required this.maskedTarget,
    required this.channel,
    required this.purpose,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
    this.verificationMode,
    this.whatsappLink,
  });

  final String challengeId;
  final String maskedTarget;
  final String channel;
  final String purpose;
  final int expiresInSeconds;
  final int resendAfterSeconds;
  final String? verificationMode;
  final String? whatsappLink;

  bool get isWhatsAppInbound =>
      verificationMode == 'WHATSAPP_INBOUND' && whatsappLink?.isNotEmpty == true;

  factory VerificationChallenge.fromJson(Map<String, dynamic> json) => VerificationChallenge(
        challengeId: json['challengeId'] as String,
        maskedTarget: (json['maskedTarget'] as String?) ?? '',
        channel: (json['channel'] as String?) ?? 'EMAIL',
        purpose: (json['purpose'] as String?) ?? '',
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 600,
        resendAfterSeconds: (json['resendAfterSeconds'] as num?)?.toInt() ?? 60,
        verificationMode: json['verificationMode'] as String?,
        whatsappLink: json['whatsappLink'] as String?,
      );
}

class SecurityState {
  const SecurityState({
    this.hasPassword = true,
    this.email,
    this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.twoFactorEnabled = false,
    this.twoFactorMethod,
    this.verification = const VerificationCapabilities(),
  });

  final bool hasPassword;
  final String? email;
  final String? phone;
  final bool emailVerified;
  final bool phoneVerified;
  final bool twoFactorEnabled;
  final String? twoFactorMethod;
  final VerificationCapabilities verification;

  factory SecurityState.fromJson(Map<String, dynamic> json) => SecurityState(
        hasPassword: (json['hasPassword'] as bool?) ?? true,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        emailVerified: (json['emailVerified'] as bool?) ?? false,
        phoneVerified: (json['phoneVerified'] as bool?) ?? false,
        twoFactorEnabled: (json['twoFactorEnabled'] as bool?) ?? false,
        twoFactorMethod: json['twoFactorMethod'] as String?,
        verification: VerificationCapabilities.fromJson(
          Map<String, dynamic>.from((json['verification'] as Map?) ?? const {}),
        ),
      );
}

class TwoFactorLoginChallenge {
  const TwoFactorLoginChallenge({
    required this.loginToken,
    required this.challengeId,
    required this.maskedTarget,
    required this.channel,
    required this.expiresInSeconds,
    this.verificationMode,
    this.whatsappLink,
  });

  final String loginToken;
  final String challengeId;
  final String maskedTarget;
  final String channel;
  final int expiresInSeconds;
  final String? verificationMode;
  final String? whatsappLink;

  bool get isWhatsAppInbound =>
      channel == 'WHATSAPP' &&
      verificationMode == 'WHATSAPP_INBOUND' &&
      whatsappLink?.isNotEmpty == true;

  factory TwoFactorLoginChallenge.fromJson(Map<String, dynamic> json) => TwoFactorLoginChallenge(
        loginToken: json['loginToken'] as String,
        challengeId: json['challengeId'] as String,
        maskedTarget: (json['maskedTarget'] as String?) ?? '',
        channel: (json['channel'] as String?) ?? 'EMAIL',
        expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt() ?? 600,
        verificationMode: json['verificationMode'] as String?,
        whatsappLink: json['whatsappLink'] as String?,
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
    this.type = 'SYSTEM',
    this.priority = 'NORMAL',
    this.actionRoute,
    this.actionEntityId,
    this.actionLabelFa,
    this.actionLabelEn,
    this.imageUrl,
    this.isRead = false,
    this.readAt,
  });

  final String id;
  final String type;
  final String priority;
  final String titleFa;
  final String titleEn;
  final String bodyFa;
  final String bodyEn;
  final String? actionRoute;
  final String? actionEntityId;
  final String? actionLabelFa;
  final String? actionLabelEn;
  final String? imageUrl;
  final DateTime publishAt;
  final bool isRead;
  final DateTime? readAt;

  bool get hasAction => actionRoute?.trim().isNotEmpty == true && actionRoute != 'notifications';

  AppNotification copyWith({bool? isRead, DateTime? readAt}) => AppNotification(
        id: id,
        type: type,
        priority: priority,
        titleFa: titleFa,
        titleEn: titleEn,
        bodyFa: bodyFa,
        bodyEn: bodyEn,
        actionRoute: actionRoute,
        actionEntityId: actionEntityId,
        actionLabelFa: actionLabelFa,
        actionLabelEn: actionLabelEn,
        imageUrl: imageUrl,
        publishAt: publishAt,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: (json['type'] as String?) ?? 'SYSTEM',
        priority: (json['priority'] as String?) ?? 'NORMAL',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        bodyFa: (json['bodyFa'] as String?) ?? '',
        bodyEn: (json['bodyEn'] as String?) ?? '',
        actionRoute: json['actionRoute'] as String?,
        actionEntityId: json['actionEntityId'] as String?,
        actionLabelFa: json['actionLabelFa'] as String?,
        actionLabelEn: json['actionLabelEn'] as String?,
        imageUrl: json['imageUrl'] as String?,
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


class PushConfig {
  const PushConfig({
    required this.enabled,
    this.projectId,
    this.apiKey,
    this.appId,
    this.messagingSenderId,
  });

  final bool enabled;
  final String? projectId;
  final String? apiKey;
  final String? appId;
  final String? messagingSenderId;

  bool get complete =>
      enabled &&
      projectId?.isNotEmpty == true &&
      apiKey?.isNotEmpty == true &&
      appId?.isNotEmpty == true &&
      messagingSenderId?.isNotEmpty == true;

  factory PushConfig.fromJson(Map<String, dynamic> json) => PushConfig(
        enabled: (json['enabled'] as bool?) ?? false,
        projectId: json['projectId'] as String?,
        apiKey: json['apiKey'] as String?,
        appId: json['appId'] as String?,
        messagingSenderId: json['messagingSenderId'] as String?,
      );
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
