import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import 'core_providers.dart';

/// Доска задач сразу по всем комнатам — соответствует
/// _TasksScreenState._fetchAllTasks (список комнат, затем задачи каждой,
/// собранные в один список).
///
/// accept() по-прежнему сам считает handshake (accepted_by.length >= 2 ->
/// in_progress) и шлёт готовый status/accepted_by, воспроизводя логику
/// _wrapExistingTaskCard — но это чисто оптимистичное UI-решение, не
/// граница доверия: сервер (PATCH /tasks/:id -> repo.AcceptTask) сам
/// пересчитывает оба поля из текущего состояния и id авторизованного
/// пользователя, игнорируя присланные значения, а refresh() ниже подтягивает
/// то, что реально сохранилось.
class TasksNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() => _fetchAll();

  Future<List<Task>> _fetchAll() async {
    final rooms = await ref.read(roomRepositoryProvider).getRooms();
    final taskRepo = ref.read(taskRepositoryProvider);
    final all = <Task>[];
    for (final room in rooms) {
      try {
        all.addAll(await taskRepo.getTasksForRoom(room.id));
      } catch (_) {
        // Одна недоступная комната не должна валить всю доску целиком.
      }
    }
    return all;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetchAll);
  }

  Task? _find(String taskId) {
    final tasks = state.valueOrNull ?? const [];
    for (final t in tasks) {
      if (t.id == taskId) return t;
    }
    return null;
  }

  Future<void> accept(String taskId, String userId) async {
    final task = _find(taskId);
    if (task == null) return;
    final acceptedBy = List<String>.from(task.acceptedBy);
    if (!acceptedBy.contains(userId)) acceptedBy.add(userId);
    final newStatus = acceptedBy.length >= 2 ? 'in_progress' : 'todo';
    await ref.read(taskRepositoryProvider).updateTask(taskId, {
      'status': newStatus,
      'accepted_by': acceptedBy,
    });
    await refresh();
  }

  Future<void> changeStatus(String taskId, String status) async {
    await ref
        .read(taskRepositoryProvider)
        .updateTask(taskId, {'status': status});
    await refresh();
  }

  Future<void> delete(String taskId) async {
    await ref.read(taskRepositoryProvider).deleteTask(taskId);
    await refresh();
  }

  Future<void> edit(String taskId, Map<String, dynamic> payload) async {
    await ref.read(taskRepositoryProvider).updateTask(taskId, payload);
    await refresh();
  }

  /// Шлём полный набор полей задачи, а не только subtasks: PATCH /tasks/:id
  /// трактует запрос с непустым title как полное обновление и иначе
  /// перезаписал бы остальные поля (например due_date) пустыми значениями.
  Future<void> updateSubtasks(String taskId, List<Subtask> updated) async {
    final task = _find(taskId);
    if (task == null) return;
    final payload = task.toJson();
    payload['subtasks'] = updated.map((s) => s.toJson()).toList();
    await ref.read(taskRepositoryProvider).updateTask(taskId, payload);
    await refresh();
  }
}

final tasksProvider = AsyncNotifierProvider<TasksNotifier, List<Task>>(
  TasksNotifier.new,
);
