import 'dart:convert';
import 'task.dart';

enum ChatMessageKind { text, image, file, task }

/// Одно сообщение в чате — приходит либо строкой из истории
/// (GET /conversations/:roomId, entity.Conversation), либо живым событием
/// по WebSocket ('message'/'task_created'). Оба формата раньше разбирались
/// инлайн в ChatScreen (_loadHistory и _connectWebSocket) почти
/// одинаковой, но не общей логикой — теперь это единственное место.
class ChatMessage {
  final String id;
  final String authorId;
  final DateTime createdAt;
  final ChatMessageKind kind;
  final bool isRead;
  final String? text;
  final String? fileUrl; // относительный путь с сервера, без base URL
  final String? fileName;
  final int? fileSize;
  final Task? task;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.createdAt,
    required this.kind,
    this.isRead = false,
    this.text,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.task,
  });

  static Map<String, dynamic>? _parseMetadata(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      }
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  /// Строка истории из GET /conversations/:roomId.
  factory ChatMessage.fromConversationJson(Map<String, dynamic> conv) {
    final meta = _parseMetadata(conv['metadata']);
    final id = conv['id'].toString();
    final authorId = conv['user_id'].toString();
    final createdAt = DateTime.parse(conv['created_at'].toString()).toUtc();
    final isRead = meta != null && meta['is_read'] == true;

    if (meta != null && meta['task_id'] != null) {
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.task,
        isRead: isRead,
        task: Task.fromJson(meta),
      );
    }
    if (meta != null && meta['is_image'] == true) {
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.image,
        isRead: isRead,
        fileUrl: meta['url']?.toString(),
      );
    }
    if (meta != null && meta['is_file'] == true) {
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.file,
        isRead: isRead,
        fileUrl: meta['url']?.toString(),
        fileName: meta['name']?.toString() ?? 'file',
        fileSize: (meta['size'] as num?)?.toInt() ?? 0,
      );
    }
    return ChatMessage(
      id: id,
      authorId: authorId,
      createdAt: createdAt,
      kind: ChatMessageKind.text,
      isRead: isRead,
      text: (conv['text'] ?? conv['data'])?.toString() ?? '',
    );
  }

  /// Живое событие 'message'/'task_created' с WebSocket. [fallbackId]
  /// используется, если сервер не прислал свой id (генерируется вызывающей
  /// стороной, у модели нет доступа к Uuid).
  factory ChatMessage.fromWsJson(
    Map<String, dynamic> msg, {
    required String fallbackId,
  }) {
    final id = msg['id']?.toString() ?? fallbackId;
    final authorId = msg['sender']?.toString() ?? '';
    final createdAt = DateTime.now().toUtc();
    final meta = _parseMetadata(msg['metadata']);

    final isTask =
        (meta != null && meta.containsKey('task_id')) ||
        msg['type'] == 'task_created';

    if (isTask) {
      final taskJson = meta ??
          (msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : <String, dynamic>{});
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.task,
        task: Task.fromJson(taskJson),
      );
    }
    if (meta != null && meta['is_image'] == true) {
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.image,
        fileUrl: meta['url']?.toString(),
      );
    }
    if (meta != null && meta['is_file'] == true) {
      return ChatMessage(
        id: id,
        authorId: authorId,
        createdAt: createdAt,
        kind: ChatMessageKind.file,
        fileUrl: meta['url']?.toString(),
        fileName: meta['name']?.toString() ?? 'file',
        fileSize: (meta['size'] as num?)?.toInt() ?? 0,
      );
    }
    return ChatMessage(
      id: id,
      authorId: authorId,
      createdAt: createdAt,
      kind: ChatMessageKind.text,
      text: (msg['data'] ?? msg['text'])?.toString() ?? '',
    );
  }

  ChatMessage copyWith({bool? isRead, Task? task}) {
    return ChatMessage(
      id: id,
      authorId: authorId,
      createdAt: createdAt,
      kind: kind,
      isRead: isRead ?? this.isRead,
      text: text,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      task: task ?? this.task,
    );
  }
}
