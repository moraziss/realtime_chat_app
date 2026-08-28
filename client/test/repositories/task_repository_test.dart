import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/repositories/api_exception.dart';
import 'package:realtime_chat_app/repositories/task_repository.dart';
import 'package:realtime_chat_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late TaskRepository repo;

  setUp(() {
    auth = MockAuthService();
    repo = TaskRepository(auth);
  });

  group('getTasksForRoom', () {
    test('parses the data list into typed Tasks', () async {
      when(() => auth.get('/rooms/r1/tasks')).thenAnswer(
        (_) async => http.Response(
          '{"data":[{"id":"t1","title":"A","status":"todo"}]}',
          200,
        ),
      );

      final tasks = await repo.getTasksForRoom('r1');

      expect(tasks, hasLength(1));
      expect(tasks.first.id, 't1');
    });

    test('throws ApiException on a non-200 response', () async {
      when(() => auth.get('/rooms/r1/tasks')).thenAnswer(
        (_) async => http.Response(
          'доступ запрещён',
          400,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        ),
      );

      expect(() => repo.getTasksForRoom('r1'), throwsA(isA<ApiException>()));
    });
  });

  group('createTask', () {
    test('POSTs the payload as-is and parses the created Task', () async {
      when(() => auth.post('/rooms/r1/tasks', any())).thenAnswer(
        (_) async => http.Response('{"data":{"id":"t2","title":"B"}}', 201),
      );

      final task = await repo.createTask('r1', {
        'title': 'B',
        'priority': 'medium',
      });

      expect(task.id, 't2');
      verify(
        () => auth.post('/rooms/r1/tasks', {
          'title': 'B',
          'priority': 'medium',
        }),
      ).called(1);
    });
  });

  group('updateTask', () {
    test('PATCHes the patch map and parses the updated Task', () async {
      when(() => auth.patch('/tasks/t1', any())).thenAnswer(
        (_) async =>
            http.Response('{"data":{"id":"t1","status":"in_progress"}}', 200),
      );

      final task = await repo.updateTask('t1', {
        'status': 'in_progress',
        'accepted_by': ['u1', 'u2'],
      });

      expect(task.status, 'in_progress');
    });
  });

  group('deleteTask', () {
    test('does not throw on 200', () async {
      when(
        () => auth.delete('/tasks/t1'),
      ).thenAnswer((_) async => http.Response('', 200));

      await repo.deleteTask('t1');
    });

    test('throws ApiException on failure', () async {
      when(
        () => auth.delete('/tasks/t1'),
      ).thenAnswer((_) async => http.Response('nope', 500));

      expect(() => repo.deleteTask('t1'), throwsA(isA<ApiException>()));
    });
  });
}
