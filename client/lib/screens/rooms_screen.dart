import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../models/room.dart';
import '../models/stats.dart';
import '../models/user_profile.dart';
import '../providers/core_providers.dart';
import '../providers/current_user_providers.dart';
import '../providers/rooms_provider.dart';
import '../repositories/api_exception.dart';
import '../services/websocket_service.dart';
import '../widgets/app_drawer.dart';

class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  Future<void> _refreshAll(WidgetRef ref) {
    return Future.wait([
      ref.read(roomsProvider.notifier).refresh(),
      ref.read(taskStatsProvider.notifier).refresh(),
      ref.read(meProvider.notifier).refresh(),
    ]);
  }

  void _showUsersList(BuildContext context, WidgetRef ref) {
    final myEmail = ref.read(meProvider).valueOrNull?.email ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return FutureBuilder<List<UserProfile>>(
                future: ref.read(userRepositoryProvider).getUsers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Center(
                      child: Text('Ошибка загрузки пользователей'),
                    );
                  }

                  final otherUsers = snapshot.data!
                      .where((u) => u.email != myEmail)
                      .toList();

                  if (otherUsers.isEmpty) {
                    return const Center(
                      child: Text('Нет других пользователей'),
                    );
                  }

                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Новый чат',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: otherUsers.length,
                          itemBuilder: (context, index) {
                            final user = otherUsers[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 375),
                              child: FadeInAnimation(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                                    child: Text(
                                      user.name.isNotEmpty
                                          ? user.name.substring(0, 1).toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    user.name.isNotEmpty ? user.name : 'Без имени',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(user.email),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    try {
                                      await ref
                                          .read(roomsProvider.notifier)
                                          .createRoom(user.id);
                                    } on ApiException catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Не удалось создать чат',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('Ошибка создания чата: $e');
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Не удалось создать чат — проверьте соединение',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final roomsAsync = ref.watch(roomsProvider);
    final stats = ref.watch(taskStatsProvider).valueOrNull ?? const TaskStats();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _buildConnectionBanner(ref, colorScheme),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refreshAll(ref),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 320.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: isDark
                        ? colorScheme.surface
                        : colorScheme.primary,
                    elevation: 0,
                    leading: Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(
                          Icons.menu_open_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                      title: const Text(
                        'Чаты',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      background: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isDark
                                    ? [
                                        colorScheme.surfaceVariant,
                                        colorScheme.surface,
                                      ]
                                    : [
                                        colorScheme.primary,
                                        colorScheme.primaryContainer,
                                      ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: -50,
                            right: -50,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.bolt,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        "Статистика задач",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatCard(
                                          context,
                                          "В работе",
                                          stats.inProgress,
                                          Icons.auto_mode_rounded,
                                          Colors.orangeAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          context,
                                          "Готово",
                                          stats.done,
                                          Icons.task_alt_rounded,
                                          Colors.greenAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildStatCard(
                                          context,
                                          "Ожидают",
                                          stats.todo,
                                          Icons.timer_outlined,
                                          Colors.lightBlueAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  ..._buildRoomsSlivers(context, ref, colorScheme, roomsAsync),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUsersList(context, ref),
        backgroundColor: colorScheme.primary,
        elevation: 4,
        highlightElevation: 8,
        icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
        label: const Text(
          "Написать",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  List<Widget> _buildRoomsSlivers(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    AsyncValue<List<Room>> roomsAsync,
  ) {
    if (roomsAsync.isLoading && !roomsAsync.hasValue) {
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }

    final rooms = roomsAsync.valueOrNull ?? const [];
    if (rooms.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 60,
                  color: colorScheme.outline.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  "Нет доступных чатов",
                  style: TextStyle(
                    color: colorScheme.outline,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final room = rooms[index];
            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 400),
              child: SlideAnimation(
                verticalOffset: 30.0,
                child: FadeInAnimation(
                  child: _buildRealChatTile(context, room, ref),
                ),
              ),
            );
          }, childCount: rooms.length),
        ),
      ),
    ];
  }

  Widget _buildConnectionBanner(WidgetRef ref, ColorScheme colorScheme) {
    final ws = ref.watch(webSocketServiceProvider);
    return StreamBuilder<ConnectionStatus>(
      stream: ws.connectionStatus,
      initialData: ws.status,
      builder: (context, snapshot) {
        final isUp = snapshot.data == ConnectionStatus.connected;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: isUp
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  color: colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Переподключение…',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    int count,
    IconData icon,
    Color accentColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isDark ? 0.08 : 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: accentColor, size: 22),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealChatTile(BuildContext context, Room room, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final roomName = room.name.isNotEmpty ? room.name : 'Чат без названия';
    final lastMessage = room.lastMessage.isNotEmpty
        ? room.lastMessage
        : "Нажмите, чтобы начать общение";

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: room.unreadCount > 0
            ? colorScheme.primary.withOpacity(0.03)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () async {
          if (room.id.isNotEmpty) {
            await context.push('/chat/${room.id}');
            ref.read(roomsProvider.notifier).refresh();
          }
        },
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: colorScheme.primaryContainer.withOpacity(0.7),
            child: Text(
              roomName.isNotEmpty
                  ? roomName.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                roomName,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: room.unreadCount > 0
                      ? FontWeight.w900
                      : FontWeight.w700,
                  fontSize: 17,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (room.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  room.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            lastMessage,
            style: TextStyle(
              color: room.unreadCount > 0
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withOpacity(0.7),
              fontWeight: room.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: colorScheme.outline.withOpacity(0.3),
        ),
      ),
    );
  }
}
