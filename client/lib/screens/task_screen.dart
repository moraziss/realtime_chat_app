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

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
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
        final tasksRes = await _authService.get(
          '/rooms/${room['id'] ?? room['room_id']}/tasks',
        );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerForeground = isDark ? colorScheme.onSurface : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: headerForeground,
        iconTheme: IconThemeData(color: headerForeground),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [colorScheme.surface, colorScheme.surface]
                  : [colorScheme.primary, colorScheme.primaryContainer],
            ),
          ),
        ),
        title: Text(
          'Моя доска',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: headerForeground,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: headerForeground,
          unselectedLabelColor: headerForeground.withOpacity(0.6),
          indicatorColor: headerForeground,
          indicatorSize: TabBarIndicatorSize.label,
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
                  _buildTaskColumn('todo', colorScheme),
                  _buildTaskColumn('in_progress', colorScheme),
                  _buildTaskColumn('done', colorScheme),
                ],
              ),
      ),
    );
  }

  Widget _buildTaskColumn(String status, ColorScheme colorScheme) {
    final tasks = _allTasks.where((t) => t['status'] == status).toList();
    if (tasks.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 60,
                    color: colorScheme.outline.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Задач пока нет',
                    style: TextStyle(color: colorScheme.outline, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
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
      createdAt:
          DateTime.tryParse(taskData['created_at'] ?? '') ?? DateTime.now(),
      metadata: metadata,
    );

    return TaskCard(
      currentUserId: _currentUserId ?? '',
      message: message,
      onAccept: (id) => _runTaskAction(() async {
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
        await _authService.patch('/tasks/$id', {
          'status': newStatus,
          'accepted_by': acceptedBy,
        });
      }),
      onStatusChange: (id, s) =>
          _runTaskAction(() => _authService.patch('/tasks/$id', {'status': s})),
      onDelete: (id) => _runTaskAction(() => _authService.delete('/tasks/$id')),
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Не удалось сохранить изменения'),
                    ),
                  );
                }
              }
            },
          ),
        );
      },
      onSubtasksUpdated: (taskId, updatedSubtasks) => _runTaskAction(() {
        // Отправляем полный набор полей задачи (как в чате), а не только
        // subtasks: PATCH /tasks/:id трактует такой запрос как полное
        // обновление и иначе перезаписал бы остальные поля (например
        // due_date) пустыми значениями.
        final payload = Map<String, dynamic>.from(metadata);
        payload['subtasks'] = updatedSubtasks;
        return _authService.patch('/tasks/$taskId', payload);
      }),
    );
  }

  /// Выполняет действие над задачей, обновляет список при успехе и
  /// показывает snackbar при ошибке вместо того, чтобы падение запроса
  /// прошло совсем незамеченным.
  Future<void> _runTaskAction(Future<void> Function() action) async {
    try {
      await action();
      _fetchAllTasks();
    } catch (e) {
      debugPrint('Task action error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось выполнить действие с задачей'),
          ),
        );
      }
    }
  }
}
