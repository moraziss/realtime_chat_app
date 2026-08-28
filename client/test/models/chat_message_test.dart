import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/models/chat_message.dart';

void main() {
  group('ChatMessage.fromConversationJson', () {
    test('plain text message', () {
      final msg = ChatMessage.fromConversationJson({
        'id': 'c1',
        'user_id': 'u1',
        'created_at': '2026-08-01T00:00:00Z',
        'text': 'hello',
      });
      expect(msg.kind, ChatMessageKind.text);
      expect(msg.text, 'hello');
      expect(msg.isRead, isFalse);
    });

    test('image message via metadata as a Map', () {
      final msg = ChatMessage.fromConversationJson({
        'id': 'c1',
        'user_id': 'u1',
        'created_at': '2026-08-01T00:00:00Z',
        'text': '',
        'metadata': {'is_image': true, 'url': '/uploads/a.png', 'is_read': true},
      });
      expect(msg.kind, ChatMessageKind.image);
      expect(msg.fileUrl, '/uploads/a.png');
      expect(msg.isRead, isTrue);
    });

    test('file message via metadata as a JSON string', () {
      final msg = ChatMessage.fromConversationJson({
        'id': 'c1',
        'user_id': 'u1',
        'created_at': '2026-08-01T00:00:00Z',
        'text': '',
        'metadata': '{"is_file":true,"url":"/uploads/f.pdf","name":"f.pdf","size":1024}',
      });
      expect(msg.kind, ChatMessageKind.file);
      expect(msg.fileName, 'f.pdf');
      expect(msg.fileSize, 1024);
    });

    test('task message embeds a typed Task parsed from metadata', () {
      final msg = ChatMessage.fromConversationJson({
        'id': 'c1',
        'user_id': 'u1',
        'created_at': '2026-08-01T00:00:00Z',
        'metadata': {
          'task_id': 't1',
          'title': 'Do it',
          'status': 'todo',
          'accepted_by': ['u1'],
        },
      });
      expect(msg.kind, ChatMessageKind.task);
      expect(msg.task, isNotNull);
      expect(msg.task!.id, 't1');
      expect(msg.task!.acceptedBy, ['u1']);
    });
  });

  group('ChatMessage.fromWsJson', () {
    test('text message falls back to the generated id when server sends none', () {
      final msg = ChatMessage.fromWsJson(
        {'type': 'message', 'sender': 'u1', 'data': 'hi'},
        fallbackId: 'local-1',
      );
      expect(msg.id, 'local-1');
      expect(msg.kind, ChatMessageKind.text);
      expect(msg.text, 'hi');
    });

    test('server-provided id wins over the fallback', () {
      final msg = ChatMessage.fromWsJson(
        {'id': 'server-1', 'type': 'message', 'sender': 'u1', 'data': 'hi'},
        fallbackId: 'local-1',
      );
      expect(msg.id, 'server-1');
    });

    test('task_created type is recognized as a task even without task_id in metadata', () {
      final msg = ChatMessage.fromWsJson(
        {
          'type': 'task_created',
          'sender': 'u1',
          'metadata': {'title': 'New task', 'status': 'todo'},
        },
        fallbackId: 'local-2',
      );
      expect(msg.kind, ChatMessageKind.task);
      expect(msg.task!.title, 'New task');
    });

    test('image attachment message', () {
      final msg = ChatMessage.fromWsJson(
        {
          'type': 'message',
          'sender': 'u1',
          'metadata': {'is_image': true, 'url': '/uploads/a.png'},
        },
        fallbackId: 'local-3',
      );
      expect(msg.kind, ChatMessageKind.image);
      expect(msg.fileUrl, '/uploads/a.png');
    });
  });
}
