import 'dart:convert';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import 'api_exception.dart';

class ConversationRepository {
  final AuthService _auth;
  ConversationRepository(this._auth);

  Future<List<ChatMessage>> getHistory(String roomId) async {
    final res = await _auth.get('/conversations/$roomId');
    if (res.statusCode != 200) throw ApiException.from(res);
    final data = (jsonDecode(res.body)['data'] as List?) ?? [];
    return data
        .map((e) => ChatMessage.fromConversationJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
