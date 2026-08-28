import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static const _legacyTokenKey =
      'auth_token'; // старое место хранения (SharedPreferences), только для миграции
  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _userIdKey = 'user_id';
  static const _userEmailKey = 'user_email';

  static const _timeout = Duration(seconds: 10);

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;

  // http.Client/FlutterSecureStorage внедряются через конструктор
  // исключительно ради тестов (mocktail может подменить обе зависимости);
  // в проде оба параметра всегда опускаются и используются реальные
  // реализации, как и раньше.
  AuthService({http.Client? client, FlutterSecureStorage? secureStorage})
    : _client = client ?? http.Client(),
      _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // Кэш текущей личности в памяти процесса. На desktop (Windows/Linux/macOS)
  // shared_preferences хранится в одном файле на диске, привязанном к
  // приложению, а не к процессу — если запустить два окна одного и того же
  // .exe и залогиниться в них под разными аккаунтами, второй логин
  // перезапишет файл, и первое окно при следующем чтении с диска (getToken/
  // getUserId читали с диска на каждый вызов) внезапно получит чужую
  // личность прямо посреди уже открытой сессии. Кэш фиксирует личность этого
  // конкретного запущенного процесса один раз и больше не позволяет её тихо
  // подменить извне.
  static String? _cachedToken;
  static String? _cachedUserId;
  static String? _cachedUserEmail;

  // Не даёт нескольким одновременным 401 запустить параллельно несколько
  // обменов refresh-токена — все они дожидаются одного и того же Future.
  static Future<bool>? _refreshInFlight;

  /// Сбрасывает статический in-memory кэш между тестами — без этого кэш,
  /// намеренно живущий на уровне процесса в проде (см. комментарий выше),
  /// протекал бы из одного теста в другой.
  @visibleForTesting
  static void resetCacheForTesting() {
    _cachedToken = null;
    _cachedUserId = null;
    _cachedUserEmail = null;
    _refreshInFlight = null;
  }

  // Вспомогательная функция для генерации уникального ключа для каждого пользователя
  Future<String> _getPrefKey(String baseKey) async {
    final uid = await getUserId() ?? 'guest';
    return 'user_${uid}_$baseKey';
  }

  // Сохранение данных профиля в локальный кеш (индивидуально для юзера)
  Future<void> saveProfileLocally({
    String? name,
    String? bio,
    String? avatar,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(await _getPrefKey('name'), name);
    if (bio != null) await prefs.setString(await _getPrefKey('bio'), bio);
    if (avatar != null)
      await prefs.setString(await _getPrefKey('avatar'), avatar);
  }

  // Получение данных профиля из локального кеша
  Future<Map<String, String?>> getLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(await _getPrefKey('name')),
      'bio': prefs.getString(await _getPrefKey('bio')),
      'avatar': prefs.getString(await _getPrefKey('avatar')),
    };
  }

  Future<bool> sendVerificationCode(String email) async {
    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.apiUrl}/register/send-code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(_timeout);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      } else {
        String errorMsg = 'Ошибка сервера';
        try {
          final data = jsonDecode(res.body);
          errorMsg =
              data['error']?['message'] ??
              data['error'] ??
              data['message'] ??
              res.body;
        } catch (_) {
          errorMsg = res.body;
        }
        throw errorMsg;
      }
    } catch (e) {
      debugPrint("Error in sendVerificationCode: $e");
      rethrow;
    }
  }

  Future<bool> register(
    String name,
    String email,
    String password,
    String code,
  ) async {
    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.apiUrl}/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': email,
              'confirm_email': email,
              'password': password,
              'code': code,
            }),
          )
          .timeout(_timeout);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        await _storeTokens(data['access_token'], data['refresh_token']);
        return true;
      } else {
        String errorMsg = 'Ошибка регистрации';
        try {
          final data = jsonDecode(res.body);
          errorMsg =
              data['error']?['message'] ??
              data['error'] ??
              data['message'] ??
              res.body;
        } catch (_) {
          errorMsg = res.body;
        }
        throw errorMsg;
      }
    } catch (e) {
      debugPrint("Error in register: $e");
      rethrow;
    }
  }

  Future<bool> login(String email, String password) async {
    final res = await _client
        .post(
          Uri.parse('${AppConfig.apiUrl}/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await _storeTokens(data['access_token'], data['refresh_token']);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userEmailKey, email);
      _cachedUserEmail = email;
      return true;
    }
    return false;
  }

  /// Сохраняет пару токенов в secure storage и кэширует access-токен + id
  /// пользователя, извлечённый из его payload.
  Future<void> _storeTokens(String accessToken, String? refreshToken) async {
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    }
    _cachedToken = accessToken;

    final parts = accessToken.split('.');
    if (parts.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        final userId = payload['sub']?.toString();
        if (userId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_userIdKey, userId);
          _cachedUserId = userId;
        }
      } catch (_) {}
    }
  }

  bool _isExpired(String accessToken) {
    final parts = accessToken.split('.');
    if (parts.length != 3) return true;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload['exp'];
      if (exp is! int) return false;
      return DateTime.now().isAfter(
        DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      );
    } catch (_) {
      return true;
    }
  }

  /// Обменивает сохранённый refresh-токен на новую пару access+refresh.
  /// Параллельные вызовы (несколько одновременных 401) переиспользуют один
  /// и тот же в процессе идущий обмен вместо того, чтобы гонять несколько
  /// одновременных /auth/refresh (что привело бы к лишним ротациям и гонке).
  Future<bool> _refreshTokens() {
    return _refreshInFlight ??= _doRefresh().whenComplete(
      () => _refreshInFlight = null,
    );
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;

    try {
      final res = await _client
          .post(
            Uri.parse('${AppConfig.apiUrl}/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(_timeout);

      if (res.statusCode != 200) return false;

      final data = jsonDecode(res.body);
      await _storeTokens(data['access_token'], data['refresh_token']);
      return true;
    } catch (e) {
      debugPrint('Token refresh error: $e');
      return false;
    }
  }

  /// Оборачивает один HTTP-запрос: подставляет текущий access-токен, и если
  /// сервер ответил 401 (токен истёк), один раз пробует обновить пару токенов
  /// и повторяет запрос уже с новым access-токеном. Если обновить не
  /// удалось — пользователь молча остаётся разлогиненным на следующем
  /// обращении к isLoggedIn(), без явного форс-логаута посреди случайного
  /// запроса.
  Future<http.Response> _withAuthRetry(
    Future<http.Response> Function(String token) send,
  ) async {
    final token = await getToken() ?? '';
    final res = await send(token);
    if (res.statusCode != 401) return res;

    if (await _refreshTokens()) {
      final newToken = await getToken() ?? '';
      return send(newToken);
    }
    return res;
  }

  Future<http.Response> get(String path) {
    return _withAuthRetry(
      (token) => _client
          .get(
            Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) {
    return _withAuthRetry(
      (token) => _client
          .post(
            Uri.parse('${AppConfig.apiUrl}$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> patch(String path, Map<String, dynamic> body) {
    return _withAuthRetry(
      (token) => _client
          .patch(
            Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> put(String path, Map<String, dynamic> body) {
    return _withAuthRetry(
      (token) => _client
          .put(
            Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> delete(String path) {
    return _withAuthRetry(
      (token) => _client
          .delete(
            Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout),
    );
  }

  String get currentBaseUrl => AppConfig.apiUrl;

  // Принимает байты, а не путь к файлу: MultipartFile.fromPath использует
  // dart:io и не работает на web, а на web путь от image_picker/file_picker
  // и не является настоящим путём в файловой системе (blob URL).
  Future<String?> uploadFile(Uint8List bytes, String fileName) async {
    try {
      final res = await _withAuthRetry((token) async {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.apiUrl}/upload'),
        );
        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
        final streamedResponse = await _client.send(request).timeout(_timeout);
        return http.Response.fromStream(streamedResponse);
      });
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body)['url'];
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  /// Возвращает действующий (не просроченный) access-токен, при
  /// необходимости молча обновляя его через refresh-токен. Все вызовы,
  /// включая долгоживущее WebSocket-соединение, должны получать токен именно
  /// отсюда, а не читать его напрямую — иначе короткое время жизни
  /// access-токена (30 минут на сервере) означало бы, что подключение по WS
  /// начинает получать "не авторизован" на каждый reconnect после первых
  /// получаса сессии.
  Future<String?> getToken() async {
    String? token = _cachedToken;
    if (token == null) {
      token = await _secureStorage.read(key: _accessTokenKey);
      if (token == null) {
        // Одноразовая миграция со старого хранения в SharedPreferences.
        final prefs = await SharedPreferences.getInstance();
        final legacy = prefs.getString(_legacyTokenKey);
        if (legacy != null) {
          token = legacy;
          await _secureStorage.write(key: _accessTokenKey, value: legacy);
          await prefs.remove(_legacyTokenKey);
        }
      }
      _cachedToken = token;
    }

    if (token == null) return null;
    if (!_isExpired(token)) return token;

    final refreshed = await _refreshTokens();
    return refreshed ? _cachedToken : null;
  }

  /// true, если есть действующий access-токен, либо его удалось молча
  /// обновить через refresh-токен.
  Future<bool> isLoggedIn() async => (await getToken()) != null;

  Future<void> logout() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _client
            .post(
              Uri.parse('${AppConfig.apiUrl}/auth/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': refreshToken}),
            )
            .timeout(_timeout);
      } catch (e) {
        debugPrint(
          'Logout request error (ignoring, logging out locally anyway): $e',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();

    // Очищаем пользовательский кэш перед удалением user_id
    final uid = _cachedUserId ?? prefs.getString(_userIdKey) ?? 'guest';
    await prefs.remove('user_${uid}_name');
    await prefs.remove('user_${uid}_bio');
    await prefs.remove('user_${uid}_avatar');

    // Потом удаляем основные ключи
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);

    _cachedToken = null;
    _cachedUserId = null;
    _cachedUserEmail = null;
  }

  // Метод для удаления аккаунта
  Future<bool> deleteAccount() async {
    try {
      final res = await delete('/users/me');
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint("Error deleting account: $e");
      return false;
    }
  }

  Future<String?> getUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString(_userIdKey);
    return _cachedUserId;
  }

  Future<String?> getUserEmail() async {
    if (_cachedUserEmail != null) return _cachedUserEmail;
    final prefs = await SharedPreferences.getInstance();
    _cachedUserEmail = prefs.getString(_userEmailKey);
    return _cachedUserEmail;
  }
}
