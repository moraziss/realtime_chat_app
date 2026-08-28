import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/models/room.dart';
import 'package:realtime_chat_app/models/stats.dart';

void main() {
  group('Room.fromJson', () {
    test('reads room_id (the only key the backend actually sends)', () {
      final room = Room.fromJson({
        'room_id': 'r1',
        'user_id': 'u2',
        'name': 'Alice',
        'last_message': 'hi',
        'unread_count': 3,
      });
      expect(room.id, 'r1');
      expect(room.unreadCount, 3);
    });

    test('falls back to id if room_id is absent', () {
      final room = Room.fromJson({'id': 'r2', 'user_id': 'u3'});
      expect(room.id, 'r2');
    });
  });

  group('TaskStats', () {
    test('todo is computed and clamped at zero', () {
      expect(TaskStats.fromJson({'total': 5, 'in_progress': 2, 'done': 1}).todo, 2);
      expect(TaskStats.fromJson({'total': 0, 'in_progress': 3, 'done': 3}).todo, 0);
    });
  });

  group('ExtendedStats.fromJson', () {
    test('parses a full response', () {
      final stats = ExtendedStats.fromJson({
        'messages_sent': 42,
        'days_since_joined': 7,
        'favorite_priority': 'high',
        'completion_history': [1, 2, 3],
      });
      expect(stats.messagesSent, 42);
      expect(stats.completionHistory, [1, 2, 3]);
    });

    test('defaults completion_history when missing', () {
      final stats = ExtendedStats.fromJson({});
      expect(stats.completionHistory, [0, 0, 0, 0, 0, 0, 0]);
    });
  });
}
