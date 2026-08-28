import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/repositories/user_repository.dart';
import 'package:realtime_chat_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late UserRepository repo;

  setUp(() {
    auth = MockAuthService();
    repo = UserRepository(auth);
  });

  test('getMe parses the plain (non-enveloped) profile response', () async {
    when(() => auth.get('/users/me')).thenAnswer(
      (_) async =>
          http.Response('{"id":"u1","name":"Bob","email":"b@x.com"}', 200),
    );

    final me = await repo.getMe();

    expect(me.id, 'u1');
    expect(me.name, 'Bob');
  });

  test('getUserName caches names from getUsers and reuses them', () async {
    when(() => auth.get('/users')).thenAnswer(
      (_) async => http.Response(
        '{"data":[{"id":"u2","name":"Alice","email":"a@x.com"}]}',
        200,
      ),
    );

    final first = await repo.getUserName('u2');
    final second = await repo.getUserName('u2');

    expect(first, 'Alice');
    expect(second, 'Alice');
    // getUsers should only have been hit once — the second lookup was
    // served from the cache, same as AuthService's old _users map.
    verify(() => auth.get('/users')).called(1);
  });

  test('getUserName falls back to the raw id when the user is unknown', () async {
    when(
      () => auth.get('/users'),
    ).thenAnswer((_) async => http.Response('{"data":[]}', 200));

    final name = await repo.getUserName('unknown-id');

    expect(name, 'unknown-id');
  });
}
