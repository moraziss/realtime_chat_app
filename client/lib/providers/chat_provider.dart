import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/task.dart';
import 'core_providers.dart';

/// Один чат — это поток дискретных событий, а не снимок списка сообщений:
/// InMemoryChatController (flutter_chat_ui) сам хранит упорядоченный список
/// и ожидает императивные insert/update/remove, а не полную замену списка
/// на каждое изменение. ChatScreen слушает эти события через ref.listen и
/// применяет их к контроллеру — тот же императивный стиль, что раньше был
/// у прямой подписки на WebSocketService().stream, просто с разбором и
/// дедупликацией, вынесенными сюда.
sealed class ChatEvent {
  const ChatEvent();
}

class ChatHistoryLoaded extends ChatEvent {
  final List<ChatMessage> messages;
  final String? roomName;
  const ChatHistoryLoaded(this.messages, this.roomName);
}

class ChatMessageReceived extends ChatEvent {
  final ChatMessage message;
  const ChatMessageReceived(this.message);
}

class ChatReadReceiptReceived extends ChatEvent {
  const ChatReadReceiptReceived();
}

class ChatTaskUpdated extends ChatEvent {
  final String taskId;
  final Map<String, dynamic> data;
  const ChatTaskUpdated(this.taskId, this.data);
}

class ChatTaskDeleted extends ChatEvent {
  final String taskId;
  const ChatTaskDeleted(this.taskId);
}

class ChatNotifier extends AutoDisposeFamilyAsyncNotifier<ChatEvent, String> {
  static const _uuid = Uuid();

  final Set<String> _seenMessageIds = {};
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  String? _currentUserId;

  @override
  Future<ChatEvent> build(String roomId) async {
    final ws = ref.watch(webSocketServiceProvider);
    _currentUserId = await ref.watch(authServiceProvider).getUserId();

    await ws.connect();

    final roomName = await _resolveRoomName(roomId);
    final messages = await ref.read(conversationRepositoryProvider).getHistory(roomId);
    _seenMessageIds
      ..clear()
      ..addAll(messages.map((m) => m.id));

    ws.send({'type': 'join', 'room': roomId, 'sender': _currentUserId});
    _sendReadReceipt(ws, roomId);

    _wsSubscription?.cancel();
    _wsSubscription = ws.stream.listen((msg) => _handleWsMessage(msg, roomId, ws));
    ref.onDispose(() => _wsSubscription?.cancel());

    return ChatHistoryLoaded(messages, roomName);
  }

  Future<String?> _resolveRoomName(String roomId) async {
    try {
      final rooms = await ref.read(roomRepositoryProvider).getRooms();
      for (final r in rooms) {
        if (r.id == roomId) return r.name;
      }
    } catch (_) {}
    return null;
  }

  void _sendReadReceipt(dynamic ws, String roomId) {
    ws.send({'type': 'read', 'room': roomId, 'sender': _currentUserId});
  }

  void _handleWsMessage(Map<String, dynamic> msg, String roomId, dynamic ws) {
    if (msg['type'] == 'read' && msg['room']?.toString() == roomId) {
      if (msg['sender']?.toString() != _currentUserId) {
        state = const AsyncData(ChatReadReceiptReceived());
      }
      return;
    }

    if ((msg['type'] == 'message' || msg['type'] == 'task_created') &&
        msg['room']?.toString() == roomId) {
      final senderId = msg['sender']?.toString();
      if (senderId != _currentUserId) {
        _sendReadReceipt(ws, roomId);
      } else if (msg['type'] == 'message') {
        return; // эхо нашего же оптимистично вставленного сообщения
      }

      final message = ChatMessage.fromWsJson(msg, fallbackId: _uuid.v4());
      if (_seenMessageIds.contains(message.id)) return;
      _seenMessageIds.add(message.id);
      state = AsyncData(ChatMessageReceived(message));
      return;
    }

    if (msg['type'] == 'task_update' && msg['room']?.toString() == roomId) {
      try {
        final data = msg['data'] is String
            ? jsonDecode(msg['data'] as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(msg['data'] as Map);
        final taskId = data['task_id']?.toString();
        if (taskId != null) state = AsyncData(ChatTaskUpdated(taskId, data));
      } catch (_) {}
      return;
    }

    if (msg['type'] == 'task_deleted' && msg['room']?.toString() == roomId) {
      final taskId = msg['task_id']?.toString();
      if (taskId != null) state = AsyncData(ChatTaskDeleted(taskId));
    }
  }

  Future<void> refreshHistory() async {
    final messages = await ref.read(conversationRepositoryProvider).getHistory(arg);
    _seenMessageIds
      ..clear()
      ..addAll(messages.map((m) => m.id));
    state = AsyncData(ChatHistoryLoaded(messages, null));
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    final localId = _uuid.v4();
    _seenMessageIds.add(localId);
    state = AsyncData(
      ChatMessageReceived(
        ChatMessage(
          id: localId,
          authorId: _currentUserId ?? '',
          createdAt: DateTime.now().toUtc(),
          kind: ChatMessageKind.text,
          text: text,
        ),
      ),
    );
    ref.read(webSocketServiceProvider).send({
      'type': 'message',
      'room': arg,
      'sender': _currentUserId,
      'data': text,
    });
  }

  Future<void> sendAttachment(
    Uint8List bytes,
    String fileName, {
    required bool isImage,
  }) async {
    final url = await ref.read(authServiceProvider).uploadFile(bytes, fileName);
    if (url == null) return;

    final localId = _uuid.v4();
    _seenMessageIds.add(localId);
    state = AsyncData(
      ChatMessageReceived(
        ChatMessage(
          id: localId,
          authorId: _currentUserId ?? '',
          createdAt: DateTime.now().toUtc(),
          kind: isImage ? ChatMessageKind.image : ChatMessageKind.file,
          fileUrl: url,
          fileName: fileName,
          fileSize: bytes.length,
        ),
      ),
    );
    ref.read(webSocketServiceProvider).send({
      'type': 'message',
      'room': arg,
      'sender': _currentUserId,
      'metadata': {
        'is_image': isImage,
        'is_file': !isImage,
        'url': url,
        'name': fileName,
        'size': bytes.length,
      },
    });
  }

  /// Сервер рассылает своё обновление задачи под именем 'task_updated', а
  /// не 'task_update' — то, что этот клиент (и другие) слушают, поэтому
  /// клиент рассылает 'task_update' сам. См. heads-up в плане: это
  /// исторический костыль, не то, что стоит менять здесь заодно.
  Future<void> _updateAndBroadcast(
    String taskId,
    Map<String, dynamic> patchBody, {
    Map<String, dynamic>? broadcastData,
  }) async {
    Object? error;
    try {
      await ref.read(taskRepositoryProvider).updateTask(taskId, patchBody);
    } catch (e) {
      error = e;
    }
    ref.read(webSocketServiceProvider).send({
      'type': 'task_update',
      'room': arg,
      'sender': _currentUserId,
      'data': jsonEncode({'task_id': taskId, ...(broadcastData ?? patchBody)}),
    });
    if (error != null) throw error;
  }

  Future<void> acceptTask(Task task) async {
    final me = _currentUserId;
    if (me == null || task.acceptedByUser(me)) return;
    final acceptedBy = [...task.acceptedBy, me];
    final newStatus = acceptedBy.length >= 2 ? 'in_progress' : task.status;
    final patch = {'status': newStatus, 'accepted_by': acceptedBy};
    await _updateAndBroadcast(task.id, patch);
  }

  Future<void> changeTaskStatus(String taskId, String status) async {
    await _updateAndBroadcast(taskId, {'status': status});
  }

  Future<void> updateSubtasks(Task task, List<Subtask> updated) async {
    final subtaskMaps = updated.map((s) => s.toJson()).toList();
    final patchBody = task.toJson()..['subtasks'] = subtaskMaps;
    await _updateAndBroadcast(
      task.id,
      patchBody,
      broadcastData: {'subtasks': subtaskMaps},
    );
  }

  Future<void> editTask(Task current, Map<String, dynamic> payload) async {
    final patchBody = current.toJson()..addAll(payload);
    await _updateAndBroadcast(current.id, patchBody, broadcastData: payload);
  }

  /// В отличие от остальных действий выше, здесь и локальное удаление, и
  /// рассылка происходят только при успехе — так вело себя onDelete в
  /// ChatScreen до рефакторинга.
  Future<void> deleteTask(String taskId) async {
    await ref.read(taskRepositoryProvider).deleteTask(taskId);
    ref.read(webSocketServiceProvider).send({
      'type': 'task_deleted',
      'task_id': taskId,
      'room': arg,
    });
    state = AsyncData(ChatTaskDeleted(taskId));
  }

  Future<void> createTask(Map<String, dynamic> payload) async {
    final fullPayload = Map<String, dynamic>.from(payload)
      ..['status'] = 'todo'
      ..['accepted_by'] = <String>[];
    // Сервер сам рассылает 'task_created' всем в комнате (включая нас) —
    // локальной оптимистичной вставки не нужно, задача появится тем же
    // путём, что и у остальных участников.
    await ref.read(taskRepositoryProvider).createTask(arg, fullPayload);
  }
}

final chatProvider = AsyncNotifierProvider.autoDispose
    .family<ChatNotifier, ChatEvent, String>(ChatNotifier.new);
