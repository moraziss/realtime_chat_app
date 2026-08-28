import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final String currentUserId;
  final Function(String) onAccept;
  final Function(String, String) onStatusChange;
  final Function(String) onDelete;
  final Function(String) onEdit;
  final Function(String, List<Subtask>) onSubtasksUpdated;

  const TaskCard({
    super.key,
    required this.task,
    required this.currentUserId,
    required this.onAccept,
    required this.onStatusChange,
    required this.onDelete,
    required this.onEdit,
    required this.onSubtasksUpdated,
  });

  String _formatDate(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isMeAccepted = task.acceptedByUser(currentUserId);
    final hasPartnerAccepted = task.acceptedBy.isNotEmpty && !isMeAccepted;

    return Container(
      width: 280, // Сделали чуть уже для чата
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14), // Чуть меньше отступы
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.assignment_turned_in_rounded, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.2)),
                    const SizedBox(height: 6),
                    Wrap( // Wrap позволяет тегам переноситься на новую строку, если не влезают
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildPriorityBadge(task.priority),
                        if (task.dueDate != null) _buildDeadlineBadge(task.dueDate!),
                      ],
                    ),
                  ],
                ),
              ),
              _buildMenu(task.id),
            ],
          ),

          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              maxLines: 2, // Ограничиваем описание 2 строками!
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (task.subtasks.isNotEmpty) _buildSubtasksArea(context, task.subtasks, task.id),

          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          const SizedBox(height: 12),
          _buildActionArea(task.status, isMeAccepted, hasPartnerAccepted, task.id),
        ],
      ),
    );
  }

  Widget _buildSubtasksArea(BuildContext context, List<Subtask> subtasks, String taskId) {
    int completed = subtasks.where((s) => s.isDone).length;
    double progress = subtasks.isEmpty ? 0 : completed / subtasks.length;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Подзадачи', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text('$completed из ${subtasks.length}', style: TextStyle(color: colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              color: progress == 1.0 ? Colors.green : colorScheme.primary,
              minHeight: 4, // Тонкий прогресс-бар
            ),
          ),
          const SizedBox(height: 8),
          ...subtasks.asMap().entries.map((entry) {
            final idx = entry.key;
            final st = entry.value;
            return InkWell(
              onTap: () {
                final updated = List<Subtask>.from(subtasks);
                updated[idx] = st.copyWith(isDone: !st.isDone);
                onSubtasksUpdated(taskId, updated);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4), // Компактные отступы
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(st.isDone ? Icons.check_box : Icons.check_box_outline_blank,
                        color: st.isDone ? Colors.green : Colors.grey.shade400, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        st.title,
                        style: TextStyle(
                          fontSize: 12, // Уменьшенный шрифт
                          color: st.isDone
                              ? Colors.grey
                              : (isDark ? Colors.white : Colors.black87),
                          decoration: st.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDeadlineBadge(DateTime deadline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 10, color: Colors.red.shade700),
          const SizedBox(width: 4),
          Text(_formatDate(deadline), style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color; String text;
    switch (priority) {
      case 'high': color = Colors.redAccent; text = '🔥 Высокий'; break;
      case 'low': color = Colors.grey.shade600; text = '💤 Низкий'; break;
      case 'medium': default: color = Colors.orange; text = '⚡ Средний'; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildMenu(String taskId) {
    return SizedBox(
      width: 24, height: 24,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          if (value == 'edit') onEdit(taskId);
          if (value == 'delete') onDelete(taskId);
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 12), Text('Редактировать')])),
          const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), SizedBox(width: 12), Text('Удалить', style: TextStyle(color: Colors.redAccent))])),
        ],
      ),
    );
  }

  Widget _buildActionArea(String status, bool isMeAccepted, bool hasPartnerAccepted, String taskId) {
    if (status == 'todo') {
      if (isMeAccepted) return _buildStatusBadge("Ожидание напарника...", Colors.orange.shade50, Colors.orange.shade800, Icons.sync);
      if (hasPartnerAccepted) return _buildAnimatedButton(taskId, "Начать работу", Colors.green, Icons.handshake, onAccept);
      return _buildAnimatedButton(taskId, "Взять в работу", Colors.blue, Icons.play_arrow_rounded, onAccept);
    } else if (status == 'in_progress') {
      return _buildAnimatedButton(taskId, "Завершить", Colors.green.shade600, Icons.check_circle_outline, (id) => onStatusChange(id, 'done'));
    } else {
      return _buildStatusBadge("Выполнено", Colors.grey.shade100, Colors.grey.shade600, Icons.done_all);
    }
  }

  Widget _buildAnimatedButton(String taskId, String label, Color color, IconData icon, Function(String) action) {
    return SizedBox(
      width: double.infinity, height: 40, // Чуть ниже
      child: ElevatedButton.icon(
        onPressed: () => action(taskId),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color bgColor, Color textColor, IconData icon) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: textColor), const SizedBox(width: 8), Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13))]),
    );
  }
}
