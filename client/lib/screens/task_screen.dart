import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task.dart';
import '../providers/current_user_providers.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_card.dart';
import '../widgets/task_panel.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final headerForeground = isDark ? colorScheme.onSurface : Colors.white;

    final tasksAsync = ref.watch(tasksProvider);
    final currentUserId = ref.watch(currentUserIdProvider).valueOrNull ?? '';

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
        onRefresh: () => ref.read(tasksProvider.notifier).refresh(),
        child: tasksAsync.when(
          data: (tasks) => TabBarView(
            controller: _tabController,
            children: [
              _buildTaskColumn('todo', colorScheme, tasks, currentUserId),
              _buildTaskColumn('in_progress', colorScheme, tasks, currentUserId),
              _buildTaskColumn('done', colorScheme, tasks, currentUserId),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              const Center(child: Text('Не удалось загрузить задачи')),
        ),
      ),
    );
  }

  Widget _buildTaskColumn(
    String status,
    ColorScheme colorScheme,
    List<Task> allTasks,
    String currentUserId,
  ) {
    final tasks = allTasks.where((t) => t.status == status).toList();
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
          child: _buildTaskCard(tasks[index], currentUserId),
        );
      },
    );
  }

  Widget _buildTaskCard(Task task, String currentUserId) {
    return TaskCard(
      currentUserId: currentUserId,
      task: task,
      onAccept: (id) => _runTaskAction(
        () => ref.read(tasksProvider.notifier).accept(id, currentUserId),
      ),
      onStatusChange: (id, s) => _runTaskAction(
        () => ref.read(tasksProvider.notifier).changeStatus(id, s),
      ),
      onDelete: (id) =>
          _runTaskAction(() => ref.read(tasksProvider.notifier).delete(id)),
      onEdit: (id) {
        // Переиспользуем TaskPanel как в чате через шторку.
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => TaskPanel(
            initialData: task,
            onSubmit: (dynamic taskData) async {
              if (taskData is! Map) return;
              final payload = Map<String, dynamic>.from(taskData);
              try {
                await ref.read(tasksProvider.notifier).edit(id, payload);
                if (mounted) Navigator.of(sheetContext).pop();
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
      onSubtasksUpdated: (taskId, updatedSubtasks) => _runTaskAction(
        () => ref
            .read(tasksProvider.notifier)
            .updateSubtasks(taskId, updatedSubtasks),
      ),
    );
  }

  /// Выполняет действие над задачей и показывает snackbar при ошибке —
  /// провайдер уже сам обновляет список после успешного действия.
  Future<void> _runTaskAction(Future<void> Function() action) async {
    try {
      await action();
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
