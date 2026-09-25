class AdminMobileOverview {
  const AdminMobileOverview({
    required this.salesTodayAfn,
    required this.ordersToday,
    required this.usersToday,
    required this.openTickets,
    required this.needsAttention,
    required this.attention,
    required this.recentActivity,
    this.updatedAt,
  });

  final int salesTodayAfn;
  final int ordersToday;
  final int usersToday;
  final int openTickets;
  final int needsAttention;
  final AdminAttentionCounts attention;
  final List<AdminActivityItem> recentActivity;
  final DateTime? updatedAt;

  factory AdminMobileOverview.fromJson(Map<String, dynamic> json) {
    final rows = (json['recentActivity'] as List<dynamic>?) ?? const [];
    return AdminMobileOverview(
      salesTodayAfn: int.tryParse('${json['salesTodayAfn'] ?? 0}') ?? 0,
      ordersToday: (json['ordersToday'] as num?)?.toInt() ?? 0,
      usersToday: (json['usersToday'] as num?)?.toInt() ?? 0,
      openTickets: (json['openTickets'] as num?)?.toInt() ?? 0,
      needsAttention: (json['needsAttention'] as num?)?.toInt() ?? 0,
      attention: AdminAttentionCounts.fromJson(
        Map<String, dynamic>.from((json['attention'] as Map?) ?? const {}),
      ),
      recentActivity: rows
          .whereType<Map>()
          .map((row) => AdminActivityItem.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}

class AdminAttentionCounts {
  const AdminAttentionCounts({
    this.social = 0,
    this.virtualNumber = 0,
    this.premium = 0,
    this.support = 0,
  });

  final int social;
  final int virtualNumber;
  final int premium;
  final int support;

  factory AdminAttentionCounts.fromJson(Map<String, dynamic> json) => AdminAttentionCounts(
        social: (json['social'] as num?)?.toInt() ?? 0,
        virtualNumber: (json['virtualNumber'] as num?)?.toInt() ?? 0,
        premium: (json['premium'] as num?)?.toInt() ?? 0,
        support: (json['support'] as num?)?.toInt() ?? 0,
      );
}

class AdminActivityItem {
  const AdminActivityItem({
    required this.id,
    required this.action,
    required this.entityType,
    required this.summary,
    required this.adminName,
    required this.createdAt,
    this.entityId,
  });

  final String id;
  final String action;
  final String entityType;
  final String? entityId;
  final String summary;
  final String adminName;
  final DateTime createdAt;

  factory AdminActivityItem.fromJson(Map<String, dynamic> json) => AdminActivityItem(
        id: '${json['id'] ?? ''}',
        action: '${json['action'] ?? ''}',
        entityType: '${json['entityType'] ?? ''}',
        entityId: json['entityId'] == null ? null : '${json['entityId']}',
        summary: '${json['summary'] ?? ''}',
        adminName: '${json['adminName'] ?? 'Administrator'}',
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      );
}
