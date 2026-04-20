import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import 'auth_service.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;
  String? activeRoomId;
  Stream<Map<String, dynamic>> get stream => _messageController.stream;

  Future<void> connect() async {
    if (_isConnected) return;
    final token = await AuthService().getToken();
    if (token == null) return;

    try {
      final uri = Uri.parse('${AppConfig.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      debugPrint('Глобальный WebSocket подключен');

      _channel!.stream.listen(
            (data) {
          try {
            final msg = jsonDecode(data as String);
            _messageController.add(msg); // Рассылаем сообщение по всему приложению
          } catch (e) {
            debugPrint('Ошибка парсинга WS: $e');
          }
        },
        onDone: _handleDisconnect,
        onError: (e) => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel?.sink.close();
    // Автоматическое переподключение
    Future.delayed(const Duration(seconds: 3), () => connect());
  }

  void send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
  }
}