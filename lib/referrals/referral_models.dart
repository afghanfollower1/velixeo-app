class ReferralInvite {
  const ReferralInvite({
    required this.id,
    required this.name,
    required this.status,
    required this.rewardAfn,
    required this.createdAt,
  });

  factory ReferralInvite.fromJson(Map<String,dynamic> json)=>ReferralInvite(
    id:'${json['id']??''}',
    name:'${json['name']??'VELIXEO user'}',
    status:'${json['status']??'REGISTERED'}',
    rewardAfn:(json['rewardAfn'] as num?)?.round()??int.tryParse('${json['rewardAfn']}')??0,
    createdAt:DateTime.tryParse('${json['createdAt']??''}')??DateTime.now(),
  );

  final String id;
  final String name;
  final String status;
  final int rewardAfn;
  final DateTime createdAt;
}

class ReferralSummary {
  const ReferralSummary({
    required this.enabled,
    required this.code,
    required this.inviteLink,
    required this.rewardAfn,
    required this.inviteCount,
    required this.totalRewardsAfn,
    required this.invites,
  });

  factory ReferralSummary.fromJson(Map<String,dynamic> json)=>ReferralSummary(
    enabled:json['enabled']!=false,
    code:'${json['code']??''}',
    inviteLink:'${json['inviteLink']??''}',
    rewardAfn:(json['rewardAfn'] as num?)?.round()??int.tryParse('${json['rewardAfn']}')??0,
    inviteCount:(json['inviteCount'] as num?)?.round()??int.tryParse('${json['inviteCount']}')??0,
    totalRewardsAfn:(json['totalRewardsAfn'] as num?)?.round()??int.tryParse('${json['totalRewardsAfn']}')??0,
    invites:((json['invites'] as List<dynamic>?)??const[])
      .map((x)=>ReferralInvite.fromJson(Map<String,dynamic>.from(x as Map)))
      .toList(growable:false),
  );

  final bool enabled;
  final String code;
  final String inviteLink;
  final int rewardAfn;
  final int inviteCount;
  final int totalRewardsAfn;
  final List<ReferralInvite> invites;
}
