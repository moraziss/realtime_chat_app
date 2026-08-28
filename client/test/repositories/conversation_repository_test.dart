import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/models/chat_message.dart';
import 'package:realtime_chat_app/repositories/conversation_repository.dart';
import 'package:realtime_chat_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late ConversationRepository repo;

  setUp(() {
    auth = MockAuthService();
    repo = ConversationRepository(auth);
  });

  test('parses conversation rows into typed ChatMessages', () async {
    when(() => auth.get('/conversations/r1')).thenAnswer(
      (_) async => http.Response(
        '{"data":[{"id":"c1","user_id":"u1","created_at":"2026-08-01T00:00:00Z","text":"hi"}]}',
        200,
      ),
    );

    final messages = await repo.getHistory('r1');

    expect(messages, hasLength(1));
    expect(messages.first.kind, ChatMessageKind.text);
    expect(messages.first.text, 'hi');
  });

  test('an empty data list yields an empty result, not a crash', () async {
    when(
      () => auth.get('/conversations/r1'),
    ).thenAnswer((_) async => http.Response('{"data":[]}', 200));

    final messages = await repo.getHistory('r1');

    expect(messages, isEmpty);
  });
}
