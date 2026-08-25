import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockClient extends Mock implements http.Client {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// Собирает синтаксически валидный (но не подписанный) JWT с заданным payload
/// — этого достаточно, так как AuthService только декодирует payload сам,
/// подпись не проверяет (проверка подписи — задача сервера).
String _fakeJwt(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${segment({'alg': 'none'})}.${segment(payload)}.sig';
}

void main() {
  late MockClient client;
  late MockSecureStorage storage;
  late AuthService auth;

  setUp(() {
    AuthService.resetCacheForTesting();
    SharedPreferences.setMockInitialValues({});
    client = MockClient();
    storage = MockSecureStorage();
    auth = AuthService(client: client, secureStorage: storage);

    registerFallbackValue(Uri.parse('https://example.com'));
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  group('login', () {
    test('stores both tokens on success', () async {
      final accessToken = _fakeJwt({
        'sub': 'user-1',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'access_token': accessToken,
            'refresh_token': 'refresh-1',
            'expires_in': 1800,
          }),
          200,
        ),
      );

      final ok = await auth.login('alice@example.com', 'password123');

      expect(ok, isTrue);
      verify(
        () => storage.write(key: 'auth_access_token', value: accessToken),
      ).called(1);
      verify(
        () => storage.write(key: 'auth_refresh_token', value: 'refresh-1'),
      ).called(1);
    });

    test('returns false on non-200 without storing anything', () async {
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response('{"error":{"message":"bad creds"}}', 401),
      );

      final ok = await auth.login('alice@example.com', 'wrong');

      expect(ok, isFalse);
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });
  });

  group('getToken', () {
    test('returns the stored token when not expired', () async {
      final validToken = _fakeJwt({
        'sub': 'user-1',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      when(
        () => storage.read(key: 'auth_access_token'),
      ).thenAnswer((_) async => validToken);

      final token = await auth.getToken();

      expect(token, validToken);
      verifyNever(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
    });

    test(
      'silently refreshes an expired token using the refresh token',
      () async {
        final expiredToken = _fakeJwt({
          'sub': 'user-1',
          'exp':
              DateTime.now()
                  .subtract(const Duration(minutes: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        });
        final freshToken = _fakeJwt({
          'sub': 'user-1',
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        });

        when(
          () => storage.read(key: 'auth_access_token'),
        ).thenAnswer((_) async => expiredToken);
        when(
          () => storage.read(key: 'auth_refresh_token'),
        ).thenAnswer((_) async => 'old-refresh');
        when(
          () => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'access_token': freshToken,
              'refresh_token': 'new-refresh',
              'expires_in': 1800,
            }),
            200,
          ),
        );

        final token = await auth.getToken();

        expect(token, freshToken);
        verify(
          () => storage.write(key: 'auth_access_token', value: freshToken),
        ).called(1);
      },
    );

    test(
      'returns null when the token is expired and there is no refresh token',
      () async {
        final expiredToken = _fakeJwt({
          'sub': 'user-1',
          'exp':
              DateTime.now()
                  .subtract(const Duration(minutes: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        });
        when(
          () => storage.read(key: 'auth_access_token'),
        ).thenAnswer((_) async => expiredToken);
        when(
          () => storage.read(key: 'auth_refresh_token'),
        ).thenAnswer((_) async => null);

        final token = await auth.getToken();

        expect(token, isNull);
      },
    );
  });

  group('request retry on 401', () {
    test(
      'get() refreshes once and retries the request with the new token',
      () async {
        final oldToken = _fakeJwt({
          'sub': 'user-1',
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        });
        final newToken = _fakeJwt({
          'sub': 'user-1',
          'exp':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        });

        when(
          () => storage.read(key: 'auth_access_token'),
        ).thenAnswer((_) async => oldToken);
        when(
          () => storage.read(key: 'auth_refresh_token'),
        ).thenAnswer((_) async => 'refresh-1');

        var getCallCount = 0;
        when(
          () => client.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((_) async {
          getCallCount++;
          // Первый вызов (со старым токеном) получает 401, второй (после
          // обновления) — успех.
          if (getCallCount == 1)
            return http.Response('{"error":{"message":"unauthorized"}}', 401);
          return http.Response('{"data":[]}', 200);
        });
        when(
          () => client.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'access_token': newToken,
              'refresh_token': 'refresh-2',
              'expires_in': 1800,
            }),
            200,
          ),
        );

        final res = await auth.get('/rooms');

        expect(res.statusCode, 200);
        expect(getCallCount, 2);
        final captured = verify(
          () => client.get(captureAny(), headers: captureAny(named: 'headers')),
        ).captured;
        // Второй вызов должен нести уже новый токен в заголовке Authorization.
        final secondCallHeaders = captured[3] as Map<String, String>;
        expect(secondCallHeaders['Authorization'], 'Bearer $newToken');
      },
    );
  });

  group('logout', () {
    test('clears both tokens even if the server call fails', () async {
      when(
        () => storage.read(key: 'auth_refresh_token'),
      ).thenAnswer((_) async => 'refresh-1');
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('network down'));

      await auth.logout();

      verify(() => storage.delete(key: 'auth_access_token')).called(1);
      verify(() => storage.delete(key: 'auth_refresh_token')).called(1);
    });
  });
}
