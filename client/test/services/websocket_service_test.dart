import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/services/websocket_service.dart';

void main() {
  test('WebSocketService is a singleton', () {
    expect(WebSocketService(), same(WebSocketService()));
  });

  test(
    'disconnect() reports ConnectionStatus.disconnected on the status stream',
    () async {
      final service = WebSocketService();
      final statuses = <ConnectionStatus>[];
      final sub = service.connectionStatus.listen(statuses.add);

      service.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, contains(ConnectionStatus.disconnected));
      expect(service.status, ConnectionStatus.disconnected);

      await sub.cancel();
    },
  );

  test('send() is a no-op when not connected (does not throw)', () {
    final service = WebSocketService();
    service.disconnect();
    expect(() => service.send({'type': 'status'}), returnsNormally);
  });
}
