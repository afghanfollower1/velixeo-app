import '../core/models.dart';

class PremiumCatalog {
  const PremiumCatalog({
    this.products = const [],
    this.banner,
  });

  final List<PremiumProduct> products;
  final AppBanner? banner;

  factory PremiumCatalog.fromJson(Map<String, dynamic> json) {
    final rows = (json['products'] as List<dynamic>?) ?? const [];
    return PremiumCatalog(
      products: rows
          .whereType<Map>()
          .map((item) => PremiumProduct.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      banner: json['banner'] is Map
          ? AppBanner.fromJson(Map<String, dynamic>.from(json['banner'] as Map))
          : null,
    );
  }
}

class PremiumProduct {
  const PremiumProduct({
    required this.id,
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.group,
    required this.deliveryType,
    required this.deliveryMinHours,
    required this.deliveryMaxHours,
    required this.featured,
    required this.sortOrder,
    this.descriptionFa,
    this.descriptionEn,
    this.iconUrl,
    this.instructionsFa,
    this.instructionsEn,
    this.minPriceAfn,
    this.packages = const [],
    this.formFields = const [],
  });

  final String id;
  final String slug;
  final String titleFa;
  final String titleEn;
  final String? descriptionFa;
  final String? descriptionEn;
  final String group;
  final String deliveryType;
  final int deliveryMinHours;
  final int deliveryMaxHours;
  final bool featured;
  final int sortOrder;
  final String? iconUrl;
  final String? instructionsFa;
  final String? instructionsEn;
  final int? minPriceAfn;
  final List<PremiumPackage> packages;
  final List<PremiumFormField> formFields;

  factory PremiumProduct.fromJson(Map<String, dynamic> json) => PremiumProduct(
        id: (json['id'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
        group: (json['group'] as String?) ?? 'OTHER',
        deliveryType: (json['deliveryType'] as String?) ?? 'MANUAL_ACTIVATION',
        deliveryMinHours: (json['deliveryMinHours'] as num?)?.toInt() ?? 1,
        deliveryMaxHours: (json['deliveryMaxHours'] as num?)?.toInt() ?? 12,
        featured: (json['featured'] as bool?) ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        iconUrl: json['iconUrl'] as String?,
        instructionsFa: json['instructionsFa'] as String?,
        instructionsEn: json['instructionsEn'] as String?,
        minPriceAfn: json['minPriceAfn'] == null ? null : int.tryParse('${json['minPriceAfn']}'),
        packages: ((json['packages'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((item) => PremiumPackage.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        formFields: ((json['formFields'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((item) => PremiumFormField.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}

class PremiumPackage {
  const PremiumPackage({
    required this.id,
    required this.titleFa,
    required this.titleEn,
    required this.durationFa,
    required this.durationEn,
    required this.priceAfn,
    required this.enabled,
    required this.sortOrder,
    this.stock,
    this.badgeFa,
    this.badgeEn,
  });

  final String id;
  final String titleFa;
  final String titleEn;
  final String durationFa;
  final String durationEn;
  final int priceAfn;
  final bool enabled;
  final int sortOrder;
  final int? stock;
  final String? badgeFa;
  final String? badgeEn;

  bool get available => enabled && (stock == null || stock! > 0);

  factory PremiumPackage.fromJson(Map<String, dynamic> json) => PremiumPackage(
        id: (json['id'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        durationFa: (json['durationFa'] as String?) ?? '',
        durationEn: (json['durationEn'] as String?) ?? '',
        priceAfn: int.tryParse('${json['priceAfn']}') ?? 0,
        enabled: (json['enabled'] as bool?) ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        stock: json['stock'] == null ? null : (json['stock'] as num?)?.toInt(),
        badgeFa: json['badgeFa'] as String?,
        badgeEn: json['badgeEn'] as String?,
      );
}

class PremiumFormField {
  const PremiumFormField({
    required this.key,
    required this.type,
    required this.labelFa,
    required this.labelEn,
    required this.required,
    this.placeholderFa,
    this.placeholderEn,
    this.options = const [],
  });

  final String key;
  final String type;
  final String labelFa;
  final String labelEn;
  final bool required;
  final String? placeholderFa;
  final String? placeholderEn;
  final List<String> options;

  factory PremiumFormField.fromJson(Map<String, dynamic> json) => PremiumFormField(
        key: (json['key'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'TEXT',
        labelFa: (json['labelFa'] as String?) ?? '',
        labelEn: (json['labelEn'] as String?) ?? '',
        required: (json['required'] as bool?) ?? false,
        placeholderFa: json['placeholderFa'] as String?,
        placeholderEn: json['placeholderEn'] as String?,
        options: ((json['options'] as List<dynamic>?) ?? const [])
            .map((item) => '$item')
            .toList(growable: false),
      );
}

class PremiumOrder {
  const PremiumOrder({
    required this.id,
    required this.status,
    required this.premiumState,
    required this.totalAmountAfn,
    required this.createdAt,
    this.publicOrderNumber,
    this.serviceId,
    this.serviceTitleFa,
    this.serviceTitleEn,
    this.packageId,
    this.packageTitleFa,
    this.packageTitleEn,
    this.deliveryMinHours,
    this.deliveryMaxHours,
    this.adminMessageFa,
    this.adminMessageEn,
    this.deliveryText,
    this.submittedFields = const {},
  });

  final String id;
  final String status;
  final String premiumState;
  final int totalAmountAfn;
  final DateTime createdAt;
  final String? publicOrderNumber;
  final String? serviceId;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
  final String? packageId;
  final String? packageTitleFa;
  final String? packageTitleEn;
  final int? deliveryMinHours;
  final int? deliveryMaxHours;
  final String? adminMessageFa;
  final String? adminMessageEn;
  final String? deliveryText;
  final Map<String, String> submittedFields;

  factory PremiumOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : const <String, dynamic>{};
    final package = json['package'] is Map
        ? Map<String, dynamic>.from(json['package'] as Map)
        : const <String, dynamic>{};
    final submitted = json['submittedFields'] is Map
        ? Map<String, dynamic>.from(json['submittedFields'] as Map)
        : const <String, dynamic>{};
    return PremiumOrder(
      id: (json['id'] as String?) ?? '',
      publicOrderNumber: json['publicOrderNumber']?.toString(),
      status: (json['status'] as String?) ?? 'PENDING',
      premiumState: (json['premiumState'] as String?) ?? (json['status'] as String?) ?? 'PENDING',
      totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      serviceId: service['id'] as String?,
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
      packageId: package['id'] as String?,
      packageTitleFa: package['titleFa'] as String?,
      packageTitleEn: package['titleEn'] as String?,
      deliveryMinHours: (json['deliveryMinHours'] as num?)?.toInt(),
      deliveryMaxHours: (json['deliveryMaxHours'] as num?)?.toInt(),
      adminMessageFa: json['adminMessageFa'] as String?,
      adminMessageEn: json['adminMessageEn'] as String?,
      deliveryText: json['deliveryText'] as String?,
      submittedFields: submitted.map((key, value) => MapEntry(key, '$value')),
    );
  }
}

class PremiumOrderResult {
  const PremiumOrderResult({
    required this.order,
    required this.balanceAfn,
    required this.idempotent,
  });

  final PremiumOrder order;
  final int balanceAfn;
  final bool idempotent;

  factory PremiumOrderResult.fromJson(Map<String, dynamic> json) => PremiumOrderResult(
        order: PremiumOrder.fromJson(Map<String, dynamic>.from(json['order'] as Map)),
        balanceAfn: int.tryParse('${json['balanceAfn']}') ?? 0,
        idempotent: (json['idempotent'] as bool?) ?? false,
      );
}
