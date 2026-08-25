import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import 'auth_service.dart';

enum ConnectionStatus { connecting, connected, disconnected }

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  static const _baseDelay = Duration(seconds: 2);
  static const _maxDelay = Duration(seconds: 30);

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  bool _isConnected = false;
  String? activeRoomId;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  ConnectionStatus _status = ConnectionStatus.disconnected;

  Stream<Map<String, dynamic>> get stream => _messageController.stream;

  /// Поток состояния соединения — UI может показать индикатор
  /// "переподключение" вместо того, чтобы молча зависать при обрыве связи.
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;
  ConnectionStatus get status => _status;

  Future<void> connect() async {
    if (_isConnected) return;
    final token = await AuthService().getToken();
    if (token == null) return;

    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse('${AppConfig.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _reconnectAttempts = 0;
      _setStatus(ConnectionStatus.connected);
      debugPrint('Глобальный WebSocket подключен');

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String);
            _messageController.add(
              msg,
            ); // Рассылаем сообщение по всему приложению
          } catch (e) {
            debugPrint('Ошибка парсинга WS: $e');
          }
        },
        onDone: _handleDisconnect,
        onError: (e) {
          debugPrint('WS error: $e');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WS connect error: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!_isConnected && _reconnectTimer != null)
      return; // переподключение уже запланировано
    _isConnected = false;
    _channel?.sink.close();
    _setStatus(ConnectionStatus.disconnected);

    _reconnectAttempts++;
    final delay = _nextReconnectDelay();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  /// Экспоненциальная задержка с ограничением и джиттером: 2с, 4с, 8с... до
  /// потолка в 30с. Раньше был фиксированный интервал в 3с без потолка,
  /// который при недоступном сервере долбил его переподключением каждые 3
  /// секунды бесконечно.
  Duration _nextReconnectDelay() {
    final shift = (_reconnectAttempts - 1).clamp(0, 5);
    final exponentialMs = _baseDelay.inMilliseconds * (1 << shift);
    final cappedMs = min(exponentialMs, _maxDelay.inMilliseconds);
    final jitterMs = Random().nextInt(500);
    return Duration(milliseconds: cappedMs + jitterMs);
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }
}
