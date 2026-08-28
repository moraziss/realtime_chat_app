import 'package:flutter/material.dart';
import '../models/task.dart';

class SubtaskModel {
  String id;
  TextEditingController controller;
  bool isDone;
  SubtaskModel({required this.id, required this.controller, this.isDone = false});
}

class TaskPanel extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final Task? initialData;

  const TaskPanel({super.key, required this.onSubmit, this.initialData});

  @override
  State<TaskPanel> createState() => _TaskPanelState();
}

class _TaskPanelState extends State<TaskPanel> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  String _priority = 'medium';

  DateTime? _deadline;
  final List<SubtaskModel> _subtasks = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _descController = TextEditingController(text: initial?.description ?? '');
    _priority = initial?.priority ?? 'medium';
    _deadline = initial?.dueDate;

    for (final st in initial?.subtasks ?? const []) {
      _subtasks.add(SubtaskModel(
        id: st.id.isNotEmpty ? st.id : DateTime.now().microsecondsSinceEpoch.toString(),
        controller: TextEditingController(text: st.title),
        isDone: st.isDone,
      ));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    for (var st in _subtasks) { st.controller.dispose(); }
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() => _deadline = date);
    }
  }

  void _addSubtask() {
    setState(() {
      _subtasks.add(SubtaskModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        controller: TextEditingController(),
      ));
    });
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) return;

    final List<Map<String, dynamic>> subtasksData = _subtasks
        .where((st) => st.controller.text.trim().isNotEmpty)
        .map((st) => {
      'id': st.id,
      'title': st.controller.text.trim(),
      'is_done': st.isDone,
    })
        .toList();

    widget.onSubmit({
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'priority': _priority,
      if (_deadline != null) 'due_date': _deadline!.toIso8601String(),
      if (subtasksData.isNotEmpty) 'subtasks': subtasksData,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialData != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 12,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 5,
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(isEditing ? Icons.edit_rounded : Icons.add_task_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Text(isEditing ? 'Редактировать задачу' : 'Новая задача', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Название задачи', prefixIcon: Icon(Icons.title_rounded)),
              autofocus: !isEditing,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Описание (необязательно)', prefixIcon: Icon(Icons.notes_rounded)),
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(labelText: 'Важность'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Низкий 🟢')),
                      DropdownMenuItem(value: 'medium', child: Text('Средний 🟡')),
                      DropdownMenuItem(value: 'high', child: Text('Высокий 🔴')),
                    ],
                    onChanged: (val) { if (val != null) setState(() => _priority = val); },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickDeadline,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Дедлайн'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_deadline != null ? "${_deadline!.day.toString().padLeft(2,'0')}.${_deadline!.month.toString().padLeft(2,'0')}" : 'Выбрать', style: const TextStyle(fontSize: 15)),
                          const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Text('Подзадачи', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),

            ..._subtasks.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.subdirectory_arrow_right, color: Colors.grey, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: e.value.controller,
                      decoration: const InputDecoration(hintText: 'Что нужно сделать...', isDense: true),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                    onPressed: () => setState(() {
                      e.value.controller.dispose();
                      _subtasks.removeAt(e.key);
                    }),
                  ),
                ],
              ),
            )),

            TextButton.icon(
              onPressed: _addSubtask,
              icon: const Icon(Icons.add),
              label: const Text('Добавить подзадачу'),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _submit,
                child: Text(isEditing ? 'Сохранить изменения' : 'Создать задачу', style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}