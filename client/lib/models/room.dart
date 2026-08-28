/// Комната (1:1 чат) — соответствует entity.UserRoom на бэкенде.
class Room {
  final String id;
  final String userId;
  final String name;
  final String lastMessage;
  final int unreadCount;

  const Room({
    required this.id,
    required this.userId,
    required this.name,
    required this.lastMessage,
    required this.unreadCount,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      // Бэкенд отдаёт только room_id (entity.UserRoom), но старый клиентский
      // код везде подстраховывался на случай id — оставляем тот же fallback.
      id: (json['id'] ?? json['room_id'])?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lastMessage: json['last_message']?.toString() ?? '',
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  Room copyWith({
    String? id,
    String? userId,
    String? name,
    String? lastMessage,
    int? unreadCount,
  }) {
    return Room(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
