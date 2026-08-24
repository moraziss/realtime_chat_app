import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'; // Нужно для CustomMessage
import '../services/auth_service.dart';
import '../widgets/task_card.dart';
import '../widgets/task_panel.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  late TabController _tabController;
  List<dynamic> _allTasks = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeData();
  }

  Future<void> _initializeData() async {
    _currentUserId = await _authService.getUserId();
    await _fetchAllTasks();
  }

  Future<void> _fetchAllTasks() async {
    try {
      final roomsRes = await _authService.get('/rooms');
      final rooms = jsonDecode(roomsRes.body)['data'] as List? ?? [];

      List<dynamic> aggregatedTasks = [];

      for (var room in rooms) {
        final tasksRes = await _authService.get('/rooms/${room['id'] ?? room['room_id']}/tasks');
        if (tasksRes.statusCode == 200) {
          final tasks = jsonDecode(tasksRes.body)['data'] as List? ?? [];
          aggregatedTasks.addAll(tasks);
        }
      }

      if (mounted) {
        setState(() {
          _allTasks = aggregatedTasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя доска', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Нужно сделать'),
            Tab(text: 'В работе'),
            Tab(text: 'Готово'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAllTasks,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildTaskColumn('todo'),
                  _buildTaskColumn('in_progress'),
                  _buildTaskColumn('done'),
                ],
              ),
      ),
    );
  }

  Widget _buildTaskColumn(String status) {
    final tasks = _allTasks.where((t) => t['status'] == status).toList();
    if (tasks.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
                  const Text('Задач пока нет', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _wrapExistingTaskCard(tasks[index]),
        );
      },
    );
  }

  Widget _wrapExistingTaskCard(dynamic taskData) {
    final metadata = {
      'task_id': taskData['id'].toString(),
      'status': taskData['status'],
      'title': taskData['title'],
      'priority': taskData['priority'] ?? 'medium',
      'description': taskData['description'] ?? '',
      'due_date': taskData['due_date'],
      'subtasks': taskData['subtasks'] ?? [],
      'accepted_by': taskData['accepted_by'] ?? [],
    };

    final message = CustomMessage(
      id: taskData['id'].toString(),
      authorId: taskData['created_by'] ?? '',
      createdAt: DateTime.tryParse(taskData['created_at'] ?? '') ?? DateTime.now(),
      metadata: metadata,
    );

    return TaskCard(
      currentUserId: _currentUserId ?? '',
      message: message,
      onAccept: (id) async {
        // Та же логика "принятия обеими сторонами", что и в чате: статус
        // становится in_progress только когда accepted_by содержит обоих
        // участников, иначе задача остаётся в ожидании напарника.
        final rawAccepted = metadata['accepted_by'];
        List<String> acceptedBy = rawAccepted is List
            ? rawAccepted.map<String>((e) => e.toString()).toList()
            : <String>[];
        if (_currentUserId != null && !acceptedBy.contains(_currentUserId)) {
          acceptedBy.add(_currentUserId!);
        }
        final newStatus = acceptedBy.length >= 2 ? 'in_progress' : 'todo';
        await _authService.patch('/tasks/$id', {'status': newStatus, 'accepted_by': acceptedBy});
        _fetchAllTasks();
      },
      onStatusChange: (id, s) async {
        await _authService.patch('/tasks/$id', {'status': s});
        _fetchAllTasks();
      },
      onDelete: (id) async {
        await _authService.delete('/tasks/$id');
        _fetchAllTasks();
      },
      onEdit: (id) async {
        // Переиспользуем TaskPanel как в чате через шторку
        // Чтобы не ломать API, шлем только измененные поля
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => TaskPanel(
            initialData: metadata,
            onSubmit: (dynamic taskData) async {
              if (taskData is! Map) return;
              final payload = Map<String, dynamic>.from(taskData);
              try {
                await _authService.patch('/tasks/$id', payload);
                if (mounted) Navigator.of(sheetContext).pop();
                _fetchAllTasks();
              } catch (e) {
                debugPrint('edit task in TasksScreen error: $e');
              }
            },
          ),
        );
      },
      onSubtasksUpdated: (taskId, updatedSubtasks) async {
        try {
          await _authService.patch('/tasks/$taskId', {'subtasks': updatedSubtasks});
          _fetchAllTasks();
        } catch (e) {
          debugPrint('Error updating subtasks in task_screen: $e');
        }
      },
    );
  }
}