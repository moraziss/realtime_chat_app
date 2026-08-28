import 'dart:convert';
import 'package:http/http.dart' as http;

/// Ошибка ответа сервера с уже извлечённым человекочитаемым сообщением.
/// Разные эндпоинты сериализуют ошибку по-разному (apperr-конверт
/// {"error":{"message":...}} у одних, обычный http.Error(w, err.Error(), ...)
/// с телом как чистый текст у других) — этот же порядок попыток извлечения
/// раньше был скопирован в каждый catch-блок AuthService, здесь он один.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  factory ApiException.from(http.Response res) {
    return ApiException(res.statusCode, _extractMessage(res.body));
  }

  static String _extractMessage(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final error = data['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (error != null) return error.toString();
        if (data['message'] != null) return data['message'].toString();
      }
    } catch (_) {}
    return body.isNotEmpty ? body : 'Ошибка сервера';
  }

  @override
  String toString() => message;
}
