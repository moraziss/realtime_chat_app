import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/repositories/room_repository.dart';
import 'package:realtime_chat_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late RoomRepository repo;

  setUp(() {
    auth = MockAuthService();
    repo = RoomRepository(auth);
  });

  test('getRooms parses the data list', () async {
    when(() => auth.get('/rooms')).thenAnswer(
      (_) async => http.Response(
        '{"data":[{"room_id":"r1","user_id":"u2","name":"Alice"}]}',
        200,
      ),
    );

    final rooms = await repo.getRooms();

    expect(rooms, hasLength(1));
    expect(rooms.first.id, 'r1');
  });

  test('createOrGetRoom sends only friend_id, not target_user_id', () async {
    when(() => auth.post('/rooms', any())).thenAnswer(
      (_) async => http.Response('{"data":{"room_id":"r1","user_id":"u2"}}', 201),
    );

    final room = await repo.createOrGetRoom('u2');

    expect(room.id, 'r1');
    verify(() => auth.post('/rooms', {'friend_id': 'u2'})).called(1);
  });
}
