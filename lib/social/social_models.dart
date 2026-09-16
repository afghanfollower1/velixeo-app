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
        providerType: (json['providerType'] as String?) ?? 'Default',
        orderFields: ((json['orderFields'] as List<dynamic>?) ?? const [])
            .map((item) => SocialOrderField.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );
}

class SocialCatalog {
  const SocialCatalog({this.services = const []});
  final List<SocialService> services;

  factory SocialCatalog.fromJson(Map<String, dynamic> json) => SocialCatalog(
        services: ((json['services'] as List<dynamic>?) ?? const [])
            .map((item) => SocialService.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );
}

class SocialQuote {
  const SocialQuote({
    required this.quantity,
    required this.rateAfn,
    required this.priceUnit,
    required this.totalAmountAfn,
  });

  final int quantity;
  final int rateAfn;
  final int priceUnit;
  final int totalAmountAfn;

  factory SocialQuote.fromJson(Map<String, dynamic> json) => SocialQuote(
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        rateAfn: int.tryParse('${json['rateAfn']}') ?? 0,
        priceUnit: (json['priceUnit'] as num?)?.toInt() ?? 1000,
        totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
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

class SocialOrder {
  const SocialOrder({
    required this.id,
    required this.status,
    required this.totalAmountAfn,
    required this.baseAmountAfn,
    required this.createdAt,
    required this.updatedAt,
    required this.output,
    required this.actions,
    this.quantity,
    this.failureReason,
    this.completedAt,
    this.serviceTitleFa,
    this.serviceTitleEn,
    this.platform,
    this.group,
    this.refillDays,
  });

  final String id;
  final String status;
  final int? quantity;
  final int totalAmountAfn;
  final int baseAmountAfn;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
  final String? platform;
  final String? group;
  final int? refillDays;
  final Map<String, dynamic> output;
  final List<SocialOrderAction> actions;

  bool get refillSupported => output['refillSupported'] == true;
  bool get cancelSupported => output['cancelSupported'] == true;
  String? get providerStatus => output['providerStatus'] as String?;
  String? get remains => output['remains']?.toString();
  String? get startCount => output['startCount']?.toString();

  factory SocialOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : const <String, dynamic>{};
    final output = json['output'] is Map
        ? Map<String, dynamic>.from(json['output'] as Map)
        : <String, dynamic>{};
    return SocialOrder(
      id: json['id'] as String,
      status: (json['status'] as String?) ?? 'PENDING',
      quantity: (json['quantity'] as num?)?.toInt(),
      totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
      baseAmountAfn: int.tryParse('${json['baseAmountAfn']}') ?? 0,
      failureReason: json['failureReason'] as String?,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      completedAt: json['completedAt'] == null ? null : DateTime.tryParse('${json['completedAt']}'),
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
      platform: service['socialPlatform'] as String?,
      group: service['socialGroup'] as String?,
      refillDays: (service['refillDays'] as num?)?.toInt(),
      output: output,
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
