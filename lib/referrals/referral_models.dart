double _asDouble(Object? value)=>value is num?value.toDouble():double.tryParse('$value')??0;
int _asInt(Object? value)=>value is num?value.round():int.tryParse('$value')??0;

class ReferralInvite {
  const ReferralInvite({
    required this.id,
    required this.name,
    required this.status,
    required this.rewardAfn,
    required this.qualifyingTopupAfn,
    required this.rewardCount,
    required this.createdAt,
    this.lastRewardAt,
  });

  factory ReferralInvite.fromJson(Map<String,dynamic> json)=>ReferralInvite(
    id:'${json['id']??''}',
    name:'${json['name']??'VELIXEO user'}',
    status:'${json['status']??'ACTIVE'}',
    rewardAfn:_asInt(json['rewardAfn']),
    qualifyingTopupAfn:_asInt(json['qualifyingTopupAfn']),
    rewardCount:_asInt(json['rewardCount']),
    createdAt:DateTime.tryParse('${json['createdAt']??''}')??DateTime.now(),
    lastRewardAt:json['lastRewardAt']==null?null:DateTime.tryParse('${json['lastRewardAt']}'),
  );

  final String id;
  final String name;
  final String status;
  final int rewardAfn;
  final int qualifyingTopupAfn;
  final int rewardCount;
  final DateTime createdAt;
  final DateTime? lastRewardAt;
}

class ReferralSummary {
  const ReferralSummary({
    required this.enabled,
    required this.code,
    required this.inviteLink,
    required this.rewardPercent,
    required this.inviteCount,
    required this.totalRewardsAfn,
    required this.totalQualifyingTopupsAfn,
    required this.invites,
  });

  factory ReferralSummary.fromJson(Map<String,dynamic> json)=>ReferralSummary(
    enabled:json['enabled']!=false,
    code:'${json['code']??''}',
    inviteLink:'${json['inviteLink']??''}',
    rewardPercent:_asDouble(json['rewardPercent']),
    inviteCount:_asInt(json['inviteCount']),
    totalRewardsAfn:_asInt(json['totalRewardsAfn']),
    totalQualifyingTopupsAfn:_asInt(json['totalQualifyingTopupsAfn']),
    invites:((json['invites'] as List<dynamic>?)??const[])
      .map((x)=>ReferralInvite.fromJson(Map<String,dynamic>.from(x as Map)))
      .toList(growable:false),
  );

  final bool enabled;
  final String code;
  final String inviteLink;
  final double rewardPercent;
  final int inviteCount;
  final int totalRewardsAfn;
  final int totalQualifyingTopupsAfn;
  final List<ReferralInvite> invites;
}
