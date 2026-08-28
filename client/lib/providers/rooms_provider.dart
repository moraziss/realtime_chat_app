import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/stats.dart';
import 'core_providers.dart';

const _kRoomRefreshEvents = {'message', 'read', 'task_created'};

/// Список чатов — соответствует _RoomsScreenState._loadRooms +
/// её WS-слушателю (message/read/task_created -> перезагрузить и,
/// для 'message', поднять задетую комнату наверх списка).
class RoomsNotifier extends AsyncNotifier<List<Room>> {
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  @override
  Future<List<Room>> build() async {
    final ws = ref.watch(webSocketServiceProvider);
    ws.connect();

    _wsSubscription?.cancel();
    _wsSubscription = ws.stream.listen((message) {
      final type = message['type'];
      if (!_kRoomRefreshEvents.contains(type)) return;
      refresh();
      if (type == 'message' && message['room'] != null) {
        _bumpRoomToTop(message['room'].toString());
      }
    });
    ref.onDispose(() => _wsSubscription?.cancel());

    return ref.read(roomRepositoryProvider).getRooms();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(roomRepositoryProvider).getRooms(),
    );
  }

  void _bumpRoomToTop(String roomId) {
    final rooms = state.valueOrNull;
    if (rooms == null) return;
    final index = rooms.indexWhere((r) => r.id == roomId);
    if (index > 0) {
      final updated = List<Room>.from(rooms);
      final room = updated.removeAt(index);
      updated.insert(0, room);
      state = AsyncData(updated);
    }
  }

  Future<Room> createRoom(String friendId) async {
    final room = await ref.read(roomRepositoryProvider).createOrGetRoom(friendId);
    await refresh();
    return room;
  }
}

final roomsProvider = AsyncNotifierProvider<RoomsNotifier, List<Room>>(
  RoomsNotifier.new,
);

/// Статистика задач для карточек в шапке RoomsScreen — обновляется по тем
/// же WS-событиям, что и список комнат (были одним _loadAllData раньше).
class TaskStatsNotifier extends AsyncNotifier<TaskStats> {
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  @override
  Future<TaskStats> build() async {
    final ws = ref.watch(webSocketServiceProvider);

    _wsSubscription?.cancel();
    _wsSubscription = ws.stream.listen((message) {
      if (_kRoomRefreshEvents.contains(message['type'])) refresh();
    });
    ref.onDispose(() => _wsSubscription?.cancel());

    return ref.read(userRepositoryProvider).getUserStats();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(userRepositoryProvider).getUserStats(),
    );
  }
}

final taskStatsProvider = AsyncNotifierProvider<TaskStatsNotifier, TaskStats>(
  TaskStatsNotifier.new,
);
