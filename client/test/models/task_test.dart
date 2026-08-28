import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/models/task.dart';

void main() {
  group('Task.fromJson', () {
    test('parses a full REST task (subtasks/accepted_by as real lists)', () {
      final task = Task.fromJson({
        'id': 't1',
        'room_id': 'r1',
        'created_by': 'u1',
        'title': 'Fix bug',
        'description': 'desc',
        'status': 'todo',
        'priority': 'high',
        'due_date': '2026-09-01T00:00:00Z',
        'subtasks': [
          {'id': 's1', 'title': 'step 1', 'is_done': true},
          {'id': 's2', 'title': 'step 2', 'is_done': false},
        ],
        'accepted_by': ['u1'],
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-01T00:00:00Z',
      });

      expect(task.id, 't1');
      expect(task.roomId, 'r1');
      expect(task.subtasks, hasLength(2));
      expect(task.subtasks.first.isDone, isTrue);
      expect(task.acceptedBy, ['u1']);
      expect(task.dueDate, isNotNull);
    });

    test('parses subtasks and accepted_by when sent as JSON strings', () {
      final task = Task.fromJson({
        'id': 't1',
        'title': 'x',
        'subtasks': '[{"id":"s1","title":"a","is_done":false}]',
        'accepted_by': '["u1","u2"]',
      });

      expect(task.subtasks, hasLength(1));
      expect(task.subtasks.first.title, 'a');
      expect(task.acceptedBy, ['u1', 'u2']);
    });

    test('treats null/missing subtasks and accepted_by as empty lists', () {
      final task = Task.fromJson({'id': 't1', 'title': 'x'});
      expect(task.subtasks, isEmpty);
      expect(task.acceptedBy, isEmpty);
    });

    test('a malformed subtasks JSON string does not throw', () {
      final task = Task.fromJson({
        'id': 't1',
        'title': 'x',
        'subtasks': 'not json',
      });
      expect(task.subtasks, isEmpty);
    });

    test('falls back to task_id for the WS/metadata-map shape', () {
      final task = Task.fromJson({
        'task_id': 't1',
        'status': 'in_progress',
        'title': 'from ws',
      });
      expect(task.id, 't1');
      expect(task.status, 'in_progress');
    });

    test('acceptedByUser reflects membership in accepted_by', () {
      final task = Task.fromJson({
        'id': 't1',
        'title': 'x',
        'accepted_by': ['u1'],
      });
      expect(task.acceptedByUser('u1'), isTrue);
      expect(task.acceptedByUser('u2'), isFalse);
    });
  });
}
