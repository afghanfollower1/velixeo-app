int _asInt(Object? value) => value is num ? value.round() : int.tryParse('$value') ?? 0;
double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

class VirtualCountry {
  const VirtualCountry({
    required this.code,
    required this.name,
    required this.iso,
    required this.flag,
    required this.minPriceAfn,
    required this.availableCount,
    this.maxRate,
  });

  factory VirtualCountry.fromJson(Map<String, dynamic> json) => VirtualCountry(
        code: '${json['code'] ?? ''}',
        name: '${json['name'] ?? json['code'] ?? ''}',
        iso: '${json['iso'] ?? ''}',
        flag: '${json['flag'] ?? '🌐'}',
        minPriceAfn: _asInt(json['minPriceAfn']),
        availableCount: _asInt(json['availableCount']),
        maxRate: _asDoubleOrNull(json['maxRate']),
      );

  final String code;
  final String name;
  final String iso;
  final String flag;
  final int minPriceAfn;
  final int availableCount;
  final double? maxRate;
}

class VirtualService {
  const VirtualService({
    required this.id,
    required this.slug,
    required this.titleFa,
    required this.titleEn,
    required this.featured,
    required this.sortOrder,
    required this.countries,
    this.iconUrl,
    this.descriptionFa,
    this.descriptionEn,
  });

  factory VirtualService.fromJson(Map<String, dynamic> json) => VirtualService(
        id: '${json['id'] ?? ''}',
        slug: '${json['slug'] ?? ''}',
        titleFa: '${json['titleFa'] ?? ''}',
        titleEn: '${json['titleEn'] ?? ''}',
        descriptionFa: json['descriptionFa'] as String?,
        descriptionEn: json['descriptionEn'] as String?,
        featured: json['featured'] == true,
        sortOrder: _asInt(json['sortOrder']),
        iconUrl: json['iconUrl'] as String?,
        countries: ((json['countries'] as List<dynamic>?) ?? const [])
            .map((item) => VirtualCountry.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );

  final String id;
  final String slug;
  final String titleFa;
  final String titleEn;
  final String? descriptionFa;
  final String? descriptionEn;
  final bool featured;
  final int sortOrder;
  final String? iconUrl;
  final List<VirtualCountry> countries;

  VirtualService copyWithCountries(List<VirtualCountry> value) => VirtualService(
        id: id,
        slug: slug,
        titleFa: titleFa,
        titleEn: titleEn,
        featured: featured,
        sortOrder: sortOrder,
        iconUrl: iconUrl,
        countries: value,
        descriptionFa: descriptionFa,
        descriptionEn: descriptionEn,
      );
}

class VirtualCatalog {
  const VirtualCatalog({this.services = const []});

  factory VirtualCatalog.fromJson(Map<String, dynamic> json) => VirtualCatalog(
        services: ((json['services'] as List<dynamic>?) ?? const [])
            .map((item) => VirtualService.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );

  final List<VirtualService> services;
}

class VirtualOffer {
  const VirtualOffer({
    required this.country,
    required this.operatorName,
    required this.count,
    required this.priceAfn,
    this.deliveryPercent,
  });

  factory VirtualOffer.fromJson(Map<String, dynamic> json) => VirtualOffer(
        country: '${json['country'] ?? ''}',
        operatorName: '${json['operator'] ?? 'any'}',
        count: _asInt(json['count']),
        priceAfn: _asInt(json['priceAfn']),
        deliveryPercent: _asDoubleOrNull(json['deliveryPercent']),
      );

  final String country;
  final String operatorName;
  final int count;
  final int priceAfn;
  final double? deliveryPercent;
}

class VirtualOffers {
  const VirtualOffers({
    required this.country,
    this.bestRate,
    this.lowPrice,
    this.highPrice,
    this.anyOperator,
    this.minPriceAfn = 0,
    this.maxPriceAfn = 0,
    this.bestDeliveryPercent,
    this.totalAvailable = 0,
    this.operators = const [],
  });

  factory VirtualOffers.fromJson(Map<String, dynamic> json) {
    VirtualOffer? read(String key) {
      final value = json[key];
      return value is Map ? VirtualOffer.fromJson(Map<String, dynamic>.from(value)) : null;
    }

    return VirtualOffers(
      country: '${json['country'] ?? ''}',
      bestRate: read('bestRate'),
      lowPrice: read('lowPrice'),
      highPrice: read('highPrice'),
      anyOperator: read('anyOperator'),
      minPriceAfn: _asInt(json['minPriceAfn']),
      maxPriceAfn: _asInt(json['maxPriceAfn']),
      bestDeliveryPercent: _asDoubleOrNull(json['bestDeliveryPercent']),
      totalAvailable: _asInt(json['totalAvailable']),
      operators: ((json['operators'] as List<dynamic>?) ?? const [])
          .map((item) => VirtualOffer.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }

  final String country;
  final VirtualOffer? bestRate;
  final VirtualOffer? lowPrice;
  final VirtualOffer? highPrice;
  final VirtualOffer? anyOperator;
  final int minPriceAfn;
  final int maxPriceAfn;
  final double? bestDeliveryPercent;
  final int totalAvailable;
  final List<VirtualOffer> operators;
}

class VirtualSms {
  const VirtualSms({this.sender, this.text, this.code, this.date});

  factory VirtualSms.fromJson(Map<String, dynamic> json) => VirtualSms(
        sender: json['sender'] as String?,
        text: json['text'] as String?,
        code: json['code'] == null ? null : '${json['code']}',
        date: json['date'] as String? ?? json['createdAt'] as String?,
      );

  final String? sender;
  final String? text;
  final String? code;
  final String? date;
}

class VirtualOrder {
  const VirtualOrder({
    required this.id,
    required this.status,
    required this.totalAmountAfn,
    required this.createdAt,
    required this.updatedAt,
    required this.sms,
    required this.canCancel,
    required this.canFinish,
    this.phone,
    this.product,
    this.country,
    this.operatorName,
    this.expires,
    this.providerStatus,
    this.failureReason,
    this.serviceTitleFa,
    this.serviceTitleEn,
  });

  factory VirtualOrder.fromJson(Map<String, dynamic> json) {
    final service = json['service'] is Map
        ? Map<String, dynamic>.from(json['service'] as Map)
        : const <String, dynamic>{};
    return VirtualOrder(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? 'PENDING'}',
      totalAmountAfn: _asInt(json['totalAmountAfn']),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      phone: json['phone'] as String?,
      product: json['product'] as String?,
      country: json['country'] as String?,
      operatorName: json['operator'] as String?,
      expires: DateTime.tryParse('${json['expires'] ?? ''}'),
      providerStatus: json['providerStatus'] as String?,
      failureReason: json['failureReason'] as String?,
      sms: ((json['sms'] as List<dynamic>?) ?? const [])
          .map((item) => VirtualSms.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
      canCancel: json['canCancel'] == true,
      canFinish: json['canFinish'] == true,
      serviceTitleFa: service['titleFa'] as String?,
      serviceTitleEn: service['titleEn'] as String?,
    );
  }

  final String id;
  final String status;
  final int totalAmountAfn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? phone;
  final String? product;
  final String? country;
  final String? operatorName;
  final DateTime? expires;
  final String? providerStatus;
  final String? failureReason;
  final List<VirtualSms> sms;
  final bool canCancel;
  final bool canFinish;
  final String? serviceTitleFa;
  final String? serviceTitleEn;
}
