import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:realtime_chat_app/repositories/api_exception.dart';

void main() {
  group('ApiException.from', () {
    test('extracts message from the apperr envelope', () {
      final ex = ApiException.from(
        http.Response(
          '{"error":{"message":"не авторизован"}}',
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(ex.message, 'не авторизован');
      expect(ex.statusCode, 401);
    });

    test('extracts message from a bare error string', () {
      final ex = ApiException.from(http.Response('{"error":"bad"}', 400));
      expect(ex.message, 'bad');
    });

    test('falls back to the raw body for plain-text http.Error responses', () {
      final ex = ApiException.from(
        http.Response(
          'доступ запрещён: вы не состоите в этой комнате',
          400,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        ),
      );
      expect(ex.message, 'доступ запрещён: вы не состоите в этой комнате');
    });

    test('falls back to a generic message for an empty body', () {
      final ex = ApiException.from(http.Response('', 500));
      expect(ex.message, isNotEmpty);
    });
  });
}
