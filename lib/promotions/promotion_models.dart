import '../core/models.dart';

class PromotionCatalog {
  const PromotionCatalog({this.products = const [], this.banner});
  final List<PromotionProduct> products;
  final AppBanner? banner;

  factory PromotionCatalog.fromJson(Map<String, dynamic> json) {
    final rows = (json['products'] as List<dynamic>?) ?? const [];
    return PromotionCatalog(
      products: rows.whereType<Map>().map((e) => PromotionProduct.fromJson(Map<String, dynamic>.from(e))).toList(growable: false),
      banner: json['banner'] is Map ? AppBanner.fromJson(Map<String, dynamic>.from(json['banner'] as Map)) : null,
    );
  }
}

class PromotionProduct {
  const PromotionProduct({
    required this.id,
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.platform,
    required this.deliveryMinHours,
    required this.deliveryMaxHours,
    required this.requirePartnershipAdCode,
    required this.featured,
    this.descriptionFa,
    this.descriptionEn,
    this.iconUrl,
    this.instructionsFa,
    this.instructionsEn,
    this.minPriceAfn,
    this.supportedObjectives = const [],
    this.packages = const [],
  });

  final String id;
  final String slug;
  final String titleFa;
  final String titleEn;
  final String? descriptionFa;
  final String? descriptionEn;
  final String platform;
  final int deliveryMinHours;
  final int deliveryMaxHours;
  final bool requirePartnershipAdCode;
  final bool featured;
  final String? iconUrl;
  final String? instructionsFa;
  final String? instructionsEn;
  final int? minPriceAfn;
  final List<String> supportedObjectives;
  final List<PromotionPackage> packages;

  factory PromotionProduct.fromJson(Map<String, dynamic> json) => PromotionProduct(
        id: (json['id'] as String?) ?? '',
        slug: (json['slug'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
        platform: (json['platform'] as String?) ?? 'INSTAGRAM',
        deliveryMinHours: (json['deliveryMinHours'] as num?)?.toInt() ?? 1,
        deliveryMaxHours: (json['deliveryMaxHours'] as num?)?.toInt() ?? 12,
        requirePartnershipAdCode: (json['requirePartnershipAdCode'] as bool?) ?? true,
        featured: (json['featured'] as bool?) ?? false,
        iconUrl: json['iconUrl'] as String?,
        instructionsFa: json['instructionsFa'] as String?,
        instructionsEn: json['instructionsEn'] as String?,
        minPriceAfn: json['minPriceAfn'] == null ? null : int.tryParse('${json['minPriceAfn']}'),
        supportedObjectives: ((json['supportedObjectives'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(growable: false),
        packages: ((json['packages'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((e) => PromotionPackage.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );
}

class PromotionPackage {
  const PromotionPackage({
    required this.id,
    required this.titleFa,
    required this.titleEn,
    required this.priceAfn,
    required this.adBudgetAfn,
    required this.serviceFeeAfn,
    required this.durationDays,
    required this.enabled,
    required this.sortOrder,
    this.badgeFa,
    this.badgeEn,
    this.estimateFa,
    this.estimateEn,
  });

  final String id;
  final String titleFa;
  final String titleEn;
  final int priceAfn;
  final int adBudgetAfn;
  final int serviceFeeAfn;
  final int durationDays;
  final bool enabled;
  final int sortOrder;
  final String? badgeFa;
  final String? badgeEn;
  final String? estimateFa;
  final String? estimateEn;

  factory PromotionPackage.fromJson(Map<String, dynamic> json) => PromotionPackage(
        id: (json['id'] as String?) ?? '',
        titleFa: (json['titleFa'] as String?) ?? '',
        titleEn: (json['titleEn'] as String?) ?? '',
        priceAfn: int.tryParse('${json['priceAfn']}') ?? 0,
        adBudgetAfn: int.tryParse('${json['adBudgetAfn']}') ?? 0,
        serviceFeeAfn: int.tryParse('${json['serviceFeeAfn']}') ?? 0,
        durationDays: (json['durationDays'] as num?)?.toInt() ?? 1,
        enabled: (json['enabled'] as bool?) ?? true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,
        badgeFa: json['badgeFa'] as String?,
        badgeEn: json['badgeEn'] as String?,
        estimateFa: json['estimateFa'] as String?,
        estimateEn: json['estimateEn'] as String?,
      );
}

class PromotionOrder {
  const PromotionOrder({
    required this.id,
    required this.status,
    required this.promotionState,
    required this.totalAmountAfn,
    required this.createdAt,
    this.publicOrderNumber,
    this.serviceTitleFa,
    this.serviceTitleEn,
    this.platform,
    this.postUrl,
    this.objective,
    this.packageTitleFa,
    this.packageTitleEn,
    this.adminMessageFa,
    this.adminMessageEn,
    this.metaCampaignId,
    this.metaAdId,
    this.resultSummaryFa,
    this.resultSummaryEn,
  });

  final String id;
  final String status;
  final String promotionState;
  final int totalAmountAfn;
  final DateTime createdAt;
  final String? publicOrderNumber;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
  final String? platform;
  final String? postUrl;
  final String? objective;
  final String? packageTitleFa;
  final String? packageTitleEn;
  final String? adminMessageFa;
  final String? adminMessageEn;
  final String? metaCampaignId;
  final String? metaAdId;
  final String? resultSummaryFa;
  final String? resultSummaryEn;

  factory PromotionOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map ? Map<String, dynamic>.from(json['service'] as Map) : const <String, dynamic>{};
    final package = json['package'] is Map ? Map<String, dynamic>.from(json['package'] as Map) : const <String, dynamic>{};
    return PromotionOrder(
      id: (json['id'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'PENDING',
      promotionState: (json['promotionState'] as String?) ?? 'PENDING_REVIEW',
      totalAmountAfn: int.tryParse('${json['totalAmountAfn']}') ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      publicOrderNumber: json['publicOrderNumber']?.toString(),
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
      platform: json['platform'] as String?,
      postUrl: json['postUrl'] as String?,
      objective: json['objective'] as String?,
      packageTitleFa: package['titleFa'] as String?,
      packageTitleEn: package['titleEn'] as String?,
      adminMessageFa: json['adminMessageFa'] as String?,
      adminMessageEn: json['adminMessageEn'] as String?,
      metaCampaignId: json['metaCampaignId'] as String?,
      metaAdId: json['metaAdId'] as String?,
      resultSummaryFa: json['resultSummaryFa'] as String?,
      resultSummaryEn: json['resultSummaryEn'] as String?,
    );
  }
}

class PromotionOrderResult {
  const PromotionOrderResult({required this.order, required this.balanceAfn, required this.idempotent});
  final PromotionOrder order;
  final int balanceAfn;
  final bool idempotent;

  factory PromotionOrderResult.fromJson(Map<String, dynamic> json) => PromotionOrderResult(
        order: PromotionOrder.fromJson(Map<String, dynamic>.from(json['order'] as Map)),
        balanceAfn: int.tryParse('${json['balanceAfn']}') ?? 0,
        idempotent: (json['idempotent'] as bool?) ?? false,
      );
}


class MetaConnection {
  const MetaConnection({
    required this.id,
    required this.status,
    required this.advertisingReady,
    this.facebookUserName,
    this.pageId,
    this.pageName,
    this.instagramUserId,
    this.instagramUsername,
    this.instagramName,
    this.instagramProfilePictureUrl,
    this.pageTasks = const [],
    this.permissions = const [],
  });

  final String id;
  final String status;
  final bool advertisingReady;
  final String? facebookUserName;
  final String? pageId;
  final String? pageName;
  final String? instagramUserId;
  final String? instagramUsername;
  final String? instagramName;
  final String? instagramProfilePictureUrl;
  final List<String> pageTasks;
  final List<String> permissions;

  factory MetaConnection.fromJson(Map<String, dynamic> json) => MetaConnection(
        id: (json['id'] as String?) ?? '',
        status: (json['status'] as String?) ?? '',
        advertisingReady: (json['advertisingReady'] as bool?) ?? false,
        facebookUserName: json['facebookUserName'] as String?,
        pageId: json['pageId'] as String?,
        pageName: json['pageName'] as String?,
        instagramUserId: json['instagramUserId'] as String?,
        instagramUsername: json['instagramUsername'] as String?,
        instagramName: json['instagramName'] as String?,
        instagramProfilePictureUrl: json['instagramProfilePictureUrl'] as String?,
        pageTasks: ((json['pageTasks'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(growable: false),
        permissions: ((json['permissions'] as List<dynamic>?) ?? const []).map((e) => '$e').toList(growable: false),
      );
}

class MetaMedia {
  const MetaMedia({
    required this.id,
    required this.mediaType,
    required this.permalink,
    required this.thumbnailUrl,
    this.caption = '',
    this.mediaProductType = '',
    this.mediaUrl = '',
  });

  final String id;
  final String mediaType;
  final String mediaProductType;
  final String mediaUrl;
  final String thumbnailUrl;
  final String permalink;
  final String caption;

  factory MetaMedia.fromJson(Map<String, dynamic> json) => MetaMedia(
        id: (json['id'] as String?) ?? '',
        mediaType: (json['mediaType'] as String?) ?? '',
        mediaProductType: (json['mediaProductType'] as String?) ?? '',
        mediaUrl: (json['mediaUrl'] as String?) ?? '',
        thumbnailUrl: (json['thumbnailUrl'] as String?) ?? '',
        permalink: (json['permalink'] as String?) ?? '',
        caption: (json['caption'] as String?) ?? '',
      );
}
