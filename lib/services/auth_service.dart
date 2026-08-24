import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _userEmailKey = 'user_email';

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

  // Вспомогательная функция для генерации уникального ключа для каждого пользователя
  Future<String> _getPrefKey(String baseKey) async {
    final uid = await getUserId() ?? 'guest';
    return 'user_${uid}_$baseKey';
  }

  // Сохранение данных профиля в локальный кеш (индивидуально для юзера)
  Future<void> saveProfileLocally({String? name, String? bio, String? avatar}) async {
    final prefs = await SharedPreferences.getInstance();
    if (name != null) await prefs.setString(await _getPrefKey('name'), name);
    if (bio != null) await prefs.setString(await _getPrefKey('bio'), bio);
    if (avatar != null) await prefs.setString(await _getPrefKey('avatar'), avatar);
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
      final res = await http.post(
        Uri.parse('${AppConfig.apiUrl}/register/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      } else {
        // Пытаемся достать сообщение об ошибке от сервера
        String errorMsg = 'Ошибка сервера';
        try {
          final data = jsonDecode(res.body);
          errorMsg = data['error'] ?? data['message'] ?? res.body;
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

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final token = await getToken();
    return await http.post(
      Uri.parse('${AppConfig.apiUrl}$endpoint'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String path) async {
    final token = await getToken();
    return await http.delete(
      Uri.parse('${AppConfig.apiUrl}$path'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<bool> register(String name, String email, String password, String code) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.apiUrl}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'confirm_email': email,
          'password': password,
          'code': code,
        }),
      );
      
      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      } else {
        String errorMsg = 'Ошибка регистрации';
        try {
          final data = jsonDecode(res.body);
          errorMsg = data['error'] ?? data['message'] ?? res.body;
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
    final res = await http.post(
      Uri.parse('${AppConfig.apiUrl}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final prefs = await SharedPreferences.getInstance();
      final token = data['access_token'] as String;
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userEmailKey, email);
      _cachedToken = token;
      _cachedUserEmail = email;

      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = parts[1];
        final normalized = base64Url.normalize(payload);
        final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
        final userId = decoded['sub']?.toString();
        if (userId != null) {
          await prefs.setString(_userIdKey, userId);
          _cachedUserId = userId;
        }
      }
      return true;
    }
    return false;
  }

  String get currentBaseUrl => AppConfig.apiUrl;

  // Принимает байты, а не путь к файлу: MultipartFile.fromPath использует
  // dart:io и не работает на web, а на web путь от image_picker/file_picker
  // и не является настоящим путём в файловой системе (blob URL).
  Future<String?> uploadFile(Uint8List bytes, String fileName) async {
    try {
      final token = await getToken();
      if (token == null) return null;
      var request = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiUrl}/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['url'];
      }
    } catch (e) {
      debugPrint('Upload error: $e');
    }
    return null;
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    return _cachedToken;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // Очищаем пользовательский кэш перед удалением user_id
    final uid = _cachedUserId ?? prefs.getString(_userIdKey) ?? 'guest';
    await prefs.remove('user_${uid}_name');
    await prefs.remove('user_${uid}_bio');
    await prefs.remove('user_${uid}_avatar');

    // Потом удаляем основные ключи
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);

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

  Future<http.Response> get(String path) async {
    final token = await getToken();
    return http.get(Uri.parse('${AppConfig.apiUrl}$path'), headers: {'Authorization': 'Bearer $token'});
  }

  Future<http.Response> patch(String path, Map<String, dynamic> body) async {
    final token = await getToken();
    return await http.patch(
      Uri.parse('${AppConfig.apiUrl}$path'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode(body),
    );
  }

  // Метод PUT для обновления данных
  Future<http.Response> put(String path, Map<String, dynamic> body) async {
    final token = await getToken();
    return await http.put(
      Uri.parse('${AppConfig.apiUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
  }

  final Map<String, String> _users = {};
  Future<String> getUserName(String userId) async {
    if (_users.containsKey(userId)) return _users[userId]!;
    final token = await getToken();
    try {
      final res = await http.get(Uri.parse('${AppConfig.apiUrl}/users'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode == 200) {
        final users = jsonDecode(res.body)['data'] as List? ?? [];
        for (final u in users) {
          _users[u['id'].toString()] = u['name'] ?? u['email'] ?? u['id'].toString();
        }
      }
    } catch (_) {}
    return _users[userId] ?? userId;
  }
}
