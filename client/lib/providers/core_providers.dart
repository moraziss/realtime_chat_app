import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/room_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';

/// AuthService/WebSocketService остаются как есть (в т.ч. WebSocketService —
/// синглтон-фабрика) — эти провайдеры просто дают до них доступ через ref
/// вместо прямого статического обращения, без изменения их внутреннего
/// поведения.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final webSocketServiceProvider = Provider<WebSocketService>(
  (ref) => WebSocketService(),
);

final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(ref.watch(authServiceProvider)),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(authServiceProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(authServiceProvider)),
);

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => ConversationRepository(ref.watch(authServiceProvider)),
);
