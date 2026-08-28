import 'dart:convert';

/// Подзадача внутри Task.subtasks. У бэкенда своей сущности для этого нет —
/// это просто элемент jsonb-массива в колонке tasks.subtasks.
class Subtask {
  final String id;
  final String title;
  final bool isDone;

  const Subtask({required this.id, required this.title, this.isDone = false});

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      isDone: json['is_done'] == true,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'is_done': isDone};

  Subtask copyWith({String? title, bool? isDone}) {
    return Subtask(
      id: id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }
}

/// task.subtasks и task.accepted_by приходят с сервера то списком, то
/// JSON-строкой (jsonb-колонка, сериализованная по-разному в зависимости от
/// пути — REST-ответ против WS-метаданных), а то и вовсе null. Это раньше
/// парсилось по отдельности в TaskCard, TaskPanel и ChatScreen — теперь
/// единственное место, где эта нормализация происходит.
List<Subtask> _parseSubtasks(dynamic raw) {
  final decoded = raw is String ? _tryDecode(raw) : raw;
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((e) => Subtask.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

List<String> _parseAcceptedBy(dynamic raw) {
  final decoded = raw is String ? _tryDecode(raw) : raw;
  if (decoded is! List) return const [];
  return decoded.map((e) => e.toString()).toList();
}

dynamic _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// Совместная задача — соответствует entity.Task на бэкенде. fromJson
/// одинаково понимает и полный REST-объект (GET /rooms/:id/tasks, id как
/// ключ), и укороченную metadata-карту из WS/CustomMessage (task_id как
/// ключ, без room_id/created_at/updated_at).
class Task {
  final String id;
  final String roomId;
  final String createdBy;
  final String? assignedTo;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final List<Subtask> subtasks;
  final List<String> acceptedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Task({
    required this.id,
    this.roomId = '',
    this.createdBy = '',
    this.assignedTo,
    required this.title,
    this.description = '',
    this.status = 'todo',
    this.priority = 'medium',
    this.dueDate,
    this.subtasks = const [],
    this.acceptedBy = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool acceptedByUser(String userId) => acceptedBy.contains(userId);

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] ?? json['task_id'])?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
      assignedTo: json['assigned_to']?.toString(),
      title: json['title']?.toString() ?? 'Задача',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'todo',
      priority: json['priority']?.toString() ?? 'medium',
      // Сервер отдаёт due_date, но метаданные подзадач в чате исторически
      // иногда приходили под ключом deadline — сохраняем оба.
      dueDate: DateTime.tryParse(
        (json['due_date'] ?? json['deadline'])?.toString() ?? '',
      ),
      subtasks: _parseSubtasks(json['subtasks']),
      acceptedBy: _parseAcceptedBy(json['accepted_by']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  /// Плоская JSON-карта для PATCH/POST-тела запроса и для WS task_update/
  /// CustomMessage.metadata — те же ключи, что сервер и TaskCard ожидают.
  Map<String, dynamic> toJson() {
    return {
      'task_id': id,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      if (assignedTo != null) 'assigned_to': assignedTo,
      'due_date': dueDate?.toIso8601String(),
      'subtasks': subtasks.map((s) => s.toJson()).toList(),
      'accepted_by': acceptedBy,
    };
  }

  Task copyWith({
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueDate,
    List<Subtask>? subtasks,
    List<String>? acceptedBy,
  }) {
    return Task(
      id: id,
      roomId: roomId,
      createdBy: createdBy,
      assignedTo: assignedTo,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      subtasks: subtasks ?? this.subtasks,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
