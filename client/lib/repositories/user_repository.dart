import 'dart:convert';
import '../models/stats.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'api_exception.dart';

class UserRepository {
  final AuthService _auth;
  UserRepository(this._auth);

  // Кэш имени по id пользователя — раньше жил на AuthService (_users),
  // перенесён сюда: это данные о справочнике пользователей, а не о сессии.
  final Map<String, String> _nameCache = {};

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
      _nameCache[u.id] = u.name.isNotEmpty ? u.name : (u.email.isNotEmpty ? u.email : u.id);
    }
    return users;
  }

  Future<String> getUserName(String userId) async {
    if (_nameCache.containsKey(userId)) return _nameCache[userId]!;
    try {
      await getUsers();
    } catch (_) {}
    return _nameCache[userId] ?? userId;
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
