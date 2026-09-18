class SocialBrand {
  const SocialBrand({
    required this.key,
    required this.titleFa,
    required this.titleEn,
    required this.iconType,
    required this.iconValue,
    required this.sortOrder,
  });

  final String key;
  final String titleFa;
  final String titleEn;
  final String iconType;
  final String iconValue;
  final int sortOrder;

  factory SocialBrand.fromJson(Map<String, dynamic> json) => SocialBrand(
        key: (json['key'] as String?) ?? 'OTHER',
        titleFa: (json['titleFa'] as String?) ?? (json['titleEn'] as String? ?? 'Other'),
        titleEn: (json['titleEn'] as String?) ?? (json['key'] as String? ?? 'Other'),
        iconType: (json['iconType'] as String?) ?? 'DEFAULT',
        iconValue: (json['iconValue'] as String?) ?? 'generic',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
      );
}

class SocialOrderField {
  const SocialOrderField({
    required this.key,
    required this.type,
    required this.required,
    required this.labelFa,
    required this.labelEn,
    this.hintFa,
    this.hintEn,
    this.options = const [],
  });

  final String key;
  final String type;
  final bool required;
  final String labelFa;
  final String labelEn;
  final String? hintFa;
  final String? hintEn;
  final List<SocialFieldOption> options;

  factory SocialOrderField.fromJson(Map<String, dynamic> json) => SocialOrderField(
        key: (json['key'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'text',
        required: (json['required'] as bool?) ?? false,
        labelFa: (json['labelFa'] as String?) ?? '',
        labelEn: (json['labelEn'] as String?) ?? '',
        hintFa: json['hintFa'] as String?,
        hintEn: json['hintEn'] as String?,
        options: ((json['options'] as List<dynamic>?) ?? const [])
            .map((item) => SocialFieldOption.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );
}

class SocialFieldOption {
  const SocialFieldOption({
    required this.value,
    required this.labelFa,
    required this.labelEn,
  });

  final String value;
  final String labelFa;
  final String labelEn;

  factory SocialFieldOption.fromJson(Map<String, dynamic> json) => SocialFieldOption(
        value: '${json['value'] ?? ''}',
        labelFa: (json['labelFa'] as String?) ?? '${json['value'] ?? ''}',
        labelEn: (json['labelEn'] as String?) ?? '${json['value'] ?? ''}',
      );
}

class SocialService {
  const SocialService({
    required this.id,
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.platform,
    required this.group,
    required this.priceRateAfn,
    required this.priceUnit,
    required this.featured,
    required this.refillSupported,
    required this.cancelSupported,
    required this.providerType,
    required this.orderFields,
    this.descriptionFa,
    this.descriptionEn,
    this.minQty,
    this.maxQty,
    this.estimatedMinMinutes,
    this.estimatedMaxMinutes,
    this.refillDays,
    this.providerEta,
  });

  final String id;
  final String slug;
  final String titleFa;
  final String titleEn;
  final String? descriptionFa;
  final String? descriptionEn;
  final String platform;
  final String group;
  final int priceRateAfn;
  final int priceUnit;
  final int? minQty;
  final int? maxQty;
  final int? estimatedMinMinutes;
  final int? estimatedMaxMinutes;
  final bool featured;
  final bool refillSupported;
  final bool cancelSupported;
  final int? refillDays;
  final String? providerEta;
  final String providerType;
  final List<SocialOrderField> orderFields;

  factory SocialService.fromJson(Map<String, dynamic> json) => SocialService(
        id: json['id'] as String,
        slug: (json['slug'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
        platform: (json['platform'] as String?) ?? 'OTHER',
        group: (json['group'] as String?) ?? 'OTHER',
        priceRateAfn: int.tryParse('${json['priceRateAfn']}') ?? 0,
        priceUnit: (json['priceUnit'] as num?)?.toInt() ?? 1000,
        minQty: (json['minQty'] as num?)?.toInt(),
        maxQty: (json['maxQty'] as num?)?.toInt(),
        estimatedMinMinutes: (json['estimatedMinMinutes'] as num?)?.toInt(),
        estimatedMaxMinutes: (json['estimatedMaxMinutes'] as num?)?.toInt(),
        featured: (json['featured'] as bool?) ?? false,
        refillSupported: (json['refillSupported'] as bool?) ?? false,
        cancelSupported: (json['cancelSupported'] as bool?) ?? false,
        refillDays: (json['refillDays'] as num?)?.toInt(),
        providerEta: json['providerEta']?.toString(),
        providerType: (json['providerType'] as String?) ?? 'Default',
        orderFields: ((json['orderFields'] as List<dynamic>?) ?? const [])
            .map((item) => SocialOrderField.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );
}

class SocialCategory {
  const SocialCategory({
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.platform,
    required this.sortOrder,
    this.descriptionFa,
    this.descriptionEn,
  });

  final String slug;
  final String titleFa;
  final String titleEn;
  final String platform;
  final int sortOrder;
  final String? descriptionFa;
  final String? descriptionEn;

  factory SocialCategory.fromJson(Map<String, dynamic> json) => SocialCategory(
        slug: (json['slug'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? (json['slug'] as String? ?? ''),
        titleEn: (json['titleEn'] as String?) ?? (json['slug'] as String? ?? ''),
        platform: (json['platform'] as String?) ?? 'OTHER',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
      );
}

class SocialCatalog {
  const SocialCatalog({
    this.brands = const [],
    this.services = const [],
    this.categories = const [],
  });

  final List<SocialBrand> brands;
  final List<SocialService> services;
  final List<SocialCategory> categories;

  factory SocialCatalog.fromJson(Map<String, dynamic> json) => SocialCatalog(
        brands: ((json['brands'] as List<dynamic>?) ?? const [])
            .map((item) => SocialBrand.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((item) => item.key.isNotEmpty)
            .toList(growable: false),
        services: ((json['services'] as List<dynamic>?) ?? const [])
            .map((item) => SocialService.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
        categories: ((json['categories'] as List<dynamic>?) ?? const [])
            .map((item) => SocialCategory.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((item) => item.slug.isNotEmpty)
            .toList(growable: false),
      );
}

class SocialOrderConfig {
  const SocialOrderConfig({
    this.orderIdMode = 'PROVIDER',
    this.termsFa = '',
    this.termsEn = '',
    this.refillWindowHours = 24,
  });

  final String orderIdMode;
  final String termsFa;
  final String termsEn;
  final int refillWindowHours;

  factory SocialOrderConfig.fromJson(Map<String, dynamic> json) => SocialOrderConfig(
        orderIdMode: (json['orderIdMode'] as String?) ?? 'PROVIDER',
        termsFa: (json['termsFa'] as String?) ?? '',
        termsEn: (json['termsEn'] as String?) ?? '',
        refillWindowHours: (json['refillWindowHours'] as num?)?.toInt() ?? 24,
      );
}

class SocialQuote {
  const SocialQuote({
    required this.quantity,
    required this.rateAfn,
    required this.priceUnit,
    required this.totalAmountAfn,
    required this.subtotalAmountAfn,
    required this.runs,
    required this.totalQuantity,
    required this.discountAmountAfn,
    this.couponCode,
  });

  final int quantity;
  final int rateAfn;
  final int priceUnit;
  final int subtotalAmountAfn;
  final int runs;
  final int totalQuantity;
  final int discountAmountAfn;
  final int totalAmountAfn;
  final String? couponCode;

  factory SocialQuote.fromJson(Map<String, dynamic> json) => SocialQuote(
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        rateAfn: int.tryParse('${json['rateAfn']}') ?? 0,
        priceUnit: (json['priceUnit'] as num?)?.toInt() ?? 1000,
        subtotalAmountAfn: int.tryParse('${json['subtotalAmountAfn'] ?? json['totalAmountAfn']}') ?? 0,
        runs: (json['runs'] as num?)?.toInt() ?? 1,
        totalQuantity: (json['totalQuantity'] as num?)?.toInt() ?? ((json['quantity'] as num?)?.toInt() ?? 0),
        discountAmountAfn: int.tryParse('${json['discountAmountAfn']}') ?? 0,
        totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
        couponCode: json['couponCode'] as String?,
      );
}

class SocialOrderAction {
  const SocialOrderAction({
    required this.id,
    required this.action,
    required this.status,
    required this.createdAt,
    this.providerReference,
    this.updatedAt,
  });

  final String id;
  final String action;
  final String status;
  final String? providerReference;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory SocialOrderAction.fromJson(Map<String, dynamic> json) => SocialOrderAction(
        id: json['id'] as String,
        action: (json['action'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'PENDING',
        providerReference: json['providerReference'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        updatedAt: json['updatedAt'] == null ? null : DateTime.tryParse('${json['updatedAt']}'),
      );
}

class SocialDripRun {
  const SocialDripRun({
    required this.id,
    required this.runIndex,
    required this.runsAll,
    required this.quantity,
    required this.status,
    required this.scheduledAt,
  });

  final String id;
  final int runIndex;
  final int runsAll;
  final int quantity;
  final String status;
  final DateTime scheduledAt;

  factory SocialDripRun.fromJson(Map<String, dynamic> json) => SocialDripRun(
        id: (json['id'] as String?) ?? '',
        runIndex: (json['runIndex'] as num?)?.toInt() ?? 1,
        runsAll: (json['runsAll'] as num?)?.toInt() ?? 1,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        status: (json['status'] as String?) ?? 'PENDING',
        scheduledAt: DateTime.tryParse('${json['scheduledAt']}') ?? DateTime.now(),
      );
}

class SocialOrder {
  const SocialOrder({
    required this.id,
    required this.displayOrderId,
    required this.status,
    required this.totalAmountAfn,
    required this.baseAmountAfn,
    required this.createdAt,
    required this.updatedAt,
    required this.output,
    required this.input,
    required this.dripFeed,
    required this.dripRuns,
    required this.actions,
    this.quantity,
    this.failureReason,
    this.completedAt,
    this.refillAvailableAt,
    this.refillAvailabilityMessage,
    this.refillCheckable = false,
    this.canRefill = false,
    this.canCancel = false,
    this.serviceTitleFa,
    this.serviceTitleEn,
    this.platform,
    this.group,
    this.refillDays,
  });

  final String id;
  final String displayOrderId;
  final String status;
  final int? quantity;
  final int totalAmountAfn;
  final int baseAmountAfn;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? refillAvailableAt;
  final String? refillAvailabilityMessage;
  final bool refillCheckable;
  final bool canRefill;
  final bool canCancel;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
  final String? platform;
  final String? group;
  final int? refillDays;
  final Map<String, dynamic> output;
  final Map<String, dynamic> input;
  final Map<String, dynamic> dripFeed;
  final List<SocialDripRun> dripRuns;
  final List<SocialOrderAction> actions;

  bool get refillSupported => output['refillSupported'] == true;
  bool get cancelSupported => output['cancelSupported'] == true;
  String? get providerStatus => output['providerStatus'] as String?;
  String? get remains => output['remains']?.toString();
  String? get startCount => output['startCount']?.toString();
  String? get providerEta => output['providerEta']?.toString();
  int get runs {
    final v = input['runs'];
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 1;
  }
  int? get intervalMinutes {
    final v = input['intervalMinutes'] ?? (input['parameters'] is Map ? (input['parameters'] as Map)['interval'] : null);
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  }
  int get totalQuantity => (input['totalQuantity'] as num?)?.toInt() ?? quantity ?? 0;
  int get unitQuantity => (input['unitQuantity'] as num?)?.toInt() ?? (runs > 1 && totalQuantity > 0 ? (totalQuantity ~/ runs) : (quantity ?? 0));
  bool get isDripFeed => input['dripFeed'] == true || runs > 1;
  String get dripFeedStatus => (dripFeed['status']?.toString().trim().isNotEmpty == true)
      ? dripFeed['status'].toString()
      : status;
  int get dripFeedRunsCurrent => (dripFeed['runsCurrent'] as num?)?.toInt() ?? 0;
  int get dripFeedRunsAll => (dripFeed['runsAll'] as num?)?.toInt() ?? runs;
  int get dripFeedInterval => (dripFeed['interval'] as num?)?.toInt() ?? (intervalMinutes ?? 0);
  int get dripFeedTotalQuantity => (dripFeed['totalQuantity'] as num?)?.toInt() ?? totalQuantity;
  int get dripFeedUnitQuantity => (dripFeed['unitQuantity'] as num?)?.toInt() ?? unitQuantity;
  String? get orderLink {
    final parameters = input['parameters'];
    if (parameters is Map) {
      for (final key in const ['link', 'username', 'url', 'media']) {
        final value = parameters[key];
        if (value != null && value.toString().trim().isNotEmpty) return value.toString().trim();
      }
    }
    return null;
  }

  factory SocialOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : const <String, dynamic>{};
    final output = json['output'] is Map
        ? Map<String, dynamic>.from(json['output'] as Map)
        : <String, dynamic>{};
    final input = json['input'] is Map
        ? Map<String, dynamic>.from(json['input'] as Map)
        : <String, dynamic>{};
    final dripFeed = json['dripFeed'] is Map
        ? Map<String, dynamic>.from(json['dripFeed'] as Map)
        : <String, dynamic>{};
    return SocialOrder(
      id: json['id'] as String,
      displayOrderId: (json['displayOrderId'] as String?) ?? (json['id'] as String).substring(0, 8),
      status: (json['status'] as String?) ?? 'PENDING',
      quantity: (json['quantity'] as num?)?.toInt(),
      totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
      baseAmountAfn: int.tryParse('${json['baseAmountAfn']}') ?? 0,
      failureReason: json['failureReason'] as String?,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      completedAt: json['completedAt'] == null ? null : DateTime.tryParse('${json['completedAt']}'),
      refillAvailableAt: json['refillAvailableAt'] == null ? null : DateTime.tryParse('${json['refillAvailableAt']}'),
      refillAvailabilityMessage: json['refillAvailabilityMessage']?.toString(),
      refillCheckable: (json['refillCheckable'] as bool?) ?? false,
      canRefill: (json['canRefill'] as bool?) ?? false,
      canCancel: (json['canCancel'] as bool?) ?? false,
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
      platform: service['socialPlatform'] as String?,
      group: service['socialGroup'] as String?,
      refillDays: (service['refillDays'] as num?)?.toInt(),
      output: output,
      input: input,
      dripFeed: dripFeed,
      dripRuns: ((json['dripRuns'] as List<dynamic>?) ?? const [])
          .map((item) => SocialDripRun.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      actions: ((json['actions'] as List<dynamic>?) ?? const [])
          .map((item) => SocialOrderAction.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }
}

class SocialCreateOrderResult {
  const SocialCreateOrderResult({required this.order, this.warning, this.idempotent = false});
  final SocialOrder order;
  final String? warning;
  final bool idempotent;

  factory SocialCreateOrderResult.fromJson(Map<String, dynamic> json) => SocialCreateOrderResult(
        order: SocialOrder.fromJson(Map<String, dynamic>.from(json['order'] as Map)),
        warning: json['warning'] as String?,
        idempotent: (json['idempotent'] as bool?) ?? false,
      );
}
