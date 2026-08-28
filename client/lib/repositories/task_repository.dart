import 'dart:convert';
import '../models/task.dart';
import '../services/auth_service.dart';
import 'api_exception.dart';

class TaskRepository {
  final AuthService _auth;
  TaskRepository(this._auth);

  Future<List<Task>> getTasksForRoom(String roomId) async {
    final res = await _auth.get('/rooms/$roomId/tasks');
    if (res.statusCode != 200) throw ApiException.from(res);
    final data = (jsonDecode(res.body)['data'] as List?) ?? [];
    return data
        .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// [payload] — тело как ожидает CreateTaskRequest на бэкенде (title,
  /// description, priority, due_date, subtasks, плюс status/accepted_by по
  /// умолчанию для нового чата). Оставлен гибкой картой, а не именованными
  /// параметрами — вызывающая сторона (TaskPanel) уже строит именно такую
  /// карту, а не набор отдельных полей.
  Future<Task> createTask(String roomId, Map<String, dynamic> payload) async {
    final res = await _auth.post('/rooms/$roomId/tasks', payload);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ApiException.from(res);
    }
    return Task.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body)['data'] as Map),
    );
  }

  /// [patch] — гибкая карта, а не типизированный запрос: UpdateTaskRequest
  /// на бэкенде ветвится по тому, какие поля присутствуют (status-only
  /// апдейт против полного редактирования), так что жёсткий тип пришлось
  /// бы всё равно превращать обратно в карту с той же веткой.
  Future<Task> updateTask(String taskId, Map<String, dynamic> patch) async {
    final res = await _auth.patch('/tasks/$taskId', patch);
    if (res.statusCode != 200) throw ApiException.from(res);
    return Task.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body)['data'] as Map),
    );
  }

  Future<void> deleteTask(String taskId) async {
    final res = await _auth.delete('/tasks/$taskId');
    if (res.statusCode != 200) throw ApiException.from(res);
  }
}
