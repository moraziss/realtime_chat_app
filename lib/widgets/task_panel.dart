import 'dart:convert';
import 'package:flutter/material.dart';

class SubtaskModel {
  String id;
  TextEditingController controller;
  bool isDone;
  SubtaskModel({required this.id, required this.controller, this.isDone = false});
}

class TaskPanel extends StatefulWidget {
  final Function(Map<String, dynamic>) onSubmit;
  final Map<String, dynamic>? initialData;

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
    _titleController = TextEditingController(text: widget.initialData?['title'] ?? '');
    _descController = TextEditingController(text: widget.initialData?['description'] ?? '');
    _priority = widget.initialData?['priority'] ?? 'medium';

    // Пытаемся прочитать due_date (как на сервере) или deadline (для совместимости)
    final rawDueDate = widget.initialData?['due_date'] ?? widget.initialData?['deadline'];
    if (rawDueDate != null) {
      _deadline = DateTime.tryParse(rawDueDate.toString());
    }

    // Normalize subtasks from initialData: may be List or JSON string
    List<dynamic> existingSubtasks = [];
    final raw = widget.initialData?['subtasks'];
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) existingSubtasks = decoded;
      } catch (_) {}
    } else if (raw is List) {
      existingSubtasks = raw;
    }

    for (var st in existingSubtasks) {
      if (st is Map) {
        _subtasks.add(SubtaskModel(
          id: st['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
          controller: TextEditingController(text: st['title']?.toString() ?? ''),
          isDone: st['is_done'] == true,
        ));
      }
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

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Редактировать задачу' : 'Новая задача', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Название задачи', border: OutlineInputBorder()),
              autofocus: !isEditing,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Описание (необязательно)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _priority,
                    decoration: const InputDecoration(labelText: 'Важность', border: OutlineInputBorder()),
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
                    onTap: _pickDeadline,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Дедлайн', border: OutlineInputBorder()),
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