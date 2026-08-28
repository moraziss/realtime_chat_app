/// Статистика по задачам — соответствует entity.TaskStats на бэкенде
/// (GET /users/me/stats).
class TaskStats {
  final int total;
  final int inProgress;
  final int done;

  const TaskStats({
    this.total = 0,
    this.inProgress = 0,
    this.done = 0,
  });

  /// Задачи, которые ещё не взяты в работу и не завершены. Сервер это поле
  /// не считает, клиент всегда выводил его вычитанием — тот же расчёт, что
  /// был в _loadStats у rooms_screen.dart, включая защиту от ухода в минус.
  int get todo {
    final remaining = total - inProgress - done;
    return remaining < 0 ? 0 : remaining;
  }

  factory TaskStats.fromJson(Map<String, dynamic> json) {
    return TaskStats(
      total: (json['total'] as num?)?.toInt() ?? 0,
      inProgress: (json['in_progress'] as num?)?.toInt() ?? 0,
      done: (json['done'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Расширенная статистика профиля (GET /users/me/extended-stats) — на
/// бэкенде это просто map[string]interface{}, типизация есть только здесь.
class ExtendedStats {
  final int messagesSent;
  final int daysInApp;
  final String favoritePriority;
  final List<int> completionHistory;

  const ExtendedStats({
    this.messagesSent = 0,
    this.daysInApp = 0,
    this.favoritePriority = 'Нет данных',
    this.completionHistory = const [0, 0, 0, 0, 0, 0, 0],
  });

  factory ExtendedStats.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['completion_history'];
    return ExtendedStats(
      messagesSent: (json['messages_sent'] as num?)?.toInt() ?? 0,
      daysInApp: (json['days_since_joined'] as num?)?.toInt() ?? 0,
      favoritePriority: json['favorite_priority']?.toString() ?? 'Нет данных',
      completionHistory: rawHistory is List
          ? rawHistory.map((e) => (e as num?)?.toInt() ?? 0).toList()
          : const [0, 0, 0, 0, 0, 0, 0],
    );
  }
}
