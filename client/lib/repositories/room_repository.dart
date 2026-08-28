import 'dart:convert';
import '../models/room.dart';
import '../services/auth_service.dart';
import 'api_exception.dart';

class RoomRepository {
  final AuthService _auth;
  RoomRepository(this._auth);

  Future<List<Room>> getRooms() async {
    final res = await _auth.get('/rooms');
    if (res.statusCode != 200) throw ApiException.from(res);
    final data = (jsonDecode(res.body)['data'] as List?) ?? [];
    return data
        .map((e) => Room.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Создаёт чат с [friendId], либо возвращает уже существующий — сервер
  /// сам решает (см. NewPostRoomsService на бэкенде).
  Future<Room> createOrGetRoom(String friendId) async {
    final res = await _auth.post('/rooms', {'friend_id': friendId});
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ApiException.from(res);
    }
    final data = jsonDecode(res.body)['data'];
    return Room.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
