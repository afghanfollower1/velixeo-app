class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.content,
    required this.isAdmin,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        id: '${json['id'] ?? ''}',
        content: '${json['content'] ?? ''}',
        isAdmin: json['isAdmin'] == true,
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      );

  final String id;
  final String content;
  final bool isAdmin;
  final DateTime createdAt;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.lastMessageAt,
    required this.messages,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: '${json['id'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        status: '${json['status'] ?? 'OPEN'}',
        createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
        lastMessageAt: DateTime.tryParse('${json['lastMessageAt'] ?? json['updatedAt'] ?? ''}') ?? DateTime.now(),
        messages: ((json['messages'] as List<dynamic>?) ?? const [])
            .map((item) => SupportMessage.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );

  final String id;
  final String subject;
  final String status;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final List<SupportMessage> messages;

  SupportTicket copyWith({List<SupportMessage>? messages, String? status}) => SupportTicket(
        id: id,
        subject: subject,
        status: status ?? this.status,
        createdAt: createdAt,
        lastMessageAt: DateTime.now(),
        messages: messages ?? this.messages,
      );
}
