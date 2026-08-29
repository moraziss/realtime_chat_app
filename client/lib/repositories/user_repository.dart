import 'dart:convert';
import '../models/stats.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'api_exception.dart';

class UserRepository {
  final AuthService _auth;
  UserRepository(this._auth);

  // Кэш профиля по id пользователя (имя + аватар) — раньше на AuthService
  // жил только кэш имени (_users), перенесён сюда и расширен: это данные о
  // справочнике пользователей, а не о сессии. Используется и для чата
  // (имя/аватар собеседника), и для "нового чата" в RoomsScreen.
  final Map<String, UserProfile> _profileCache = {};

  Future<UserProfile> getMe() async {
    final res = await _auth.get('/users/me');
    if (res.statusCode != 200) throw ApiException.from(res);
    return UserProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> updateMe(Map<String, dynamic> patch) async {
    final res = await _auth.put('/users/me', patch);
    if (res.statusCode != 200) throw ApiException.from(res);
  }

  Future<bool> deleteAccount() async {
    final res = await _auth.delete('/users/me');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<List<UserProfile>> getUsers() async {
    final res = await _auth.get('/users');
    if (res.statusCode != 200) throw ApiException.from(res);
    final data = (jsonDecode(res.body)['data'] as List?) ?? [];
    final users = data
        .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    for (final u in users) {
      if (u.id.isEmpty) continue;
      _profileCache[u.id] = u;
    }
    return users;
  }

  Future<UserProfile?> _resolveCachedProfile(String userId) async {
    if (_profileCache.containsKey(userId)) return _profileCache[userId];
    try {
      await getUsers();
    } catch (_) {}
    return _profileCache[userId];
  }

  Future<String> getUserName(String userId) async {
    final profile = await _resolveCachedProfile(userId);
    if (profile == null) return userId;
    if (profile.name.isNotEmpty) return profile.name;
    if (profile.email.isNotEmpty) return profile.email;
    return userId;
  }

  /// Аватар собеседника для чата — тот же кэш, что и getUserName. Значение
  /// приходит с сервера как относительный путь и не резолвится здесь: это
  /// решает вызывающая сторона, которая знает актуальный base URL.
  Future<String?> getAvatarUrl(String userId) async {
    final profile = await _resolveCachedProfile(userId);
    return profile?.avatarUrl;
  }

  Future<TaskStats> getUserStats() async {
    final res = await _auth.get('/users/me/stats');
    if (res.statusCode != 200) throw ApiException.from(res);
    return TaskStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<ExtendedStats> getExtendedStats() async {
    final res = await _auth.get('/users/me/extended-stats');
    if (res.statusCode != 200) throw ApiException.from(res);
    return ExtendedStats.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
