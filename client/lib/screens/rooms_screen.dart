import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../widgets/app_drawer.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _authService = AuthService();
  List<dynamic> _rooms = [];
  bool _isLoading = true;

  String _userName = "Загрузка...";
  String _userEmail = "...";

  int _tasksInProgress = 0;
  int _tasksDone = 0;
  int _tasksTodo = 0;

  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _loadAllData();

    WebSocketService().connect();

    _wsSubscription = WebSocketService().stream.listen((message) {
      if (!mounted) return;

      if (message['type'] == 'message' || message['type'] == 'read' || message['type'] == 'task_created') {
        _loadRooms();
        _loadStats();

        if (message['type'] == 'message' && message['room'] != null) {
          final roomId = message['room'].toString();
          final index = _rooms.indexWhere((r) => r['id']?.toString() == roomId || r['room_id']?.toString() == roomId);

          if (index > 0) {
            setState(() {
              final room = _rooms.removeAt(index);
              _rooms.insert(0, room);
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadUserProfile(),
      _loadRooms(),
      _loadStats(),
    ]);
  }

  Future<void> _loadUserProfile() async {
    final savedEmail = await _authService.getUserEmail();
    if (mounted && savedEmail != null) {
      setState(() => _userEmail = savedEmail);
    }

    try {
      final res = await _authService.get('/users/me');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _userName = data['name'] ?? "Без имени";
            if (data['email'] != null) _userEmail = data['email'];
          });
        }
      }
    } catch (e) {
      debugPrint("Ошибка профиля: $e");
    }
  }

  Future<void> _loadRooms() async {
    try {
      final res = await _authService.get('/rooms');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _rooms = data['data'] ?? [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки комнат: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final res = await _authService.get('/users/me/stats');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            final int total = data['total'] ?? 0;
            _tasksInProgress = data['in_progress'] ?? 0;
            _tasksDone = data['done'] ?? 0;
            _tasksTodo = total - _tasksInProgress - _tasksDone;
            if (_tasksTodo < 0) _tasksTodo = 0;
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статистики: $e');
    }
  }

  void _showUsersList() {
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
              return FutureBuilder<dynamic>(
                future: _authService.get('/users'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.statusCode != 200) {
                    return const Center(child: Text('Ошибка загрузки пользователей'));
                  }

                  final data = jsonDecode(snapshot.data!.body);
                  final users = (data['data'] as List?) ?? [];
                  final otherUsers = users.where((u) => u['email'] != _userEmail).toList();

                  if (otherUsers.isEmpty) {
                    return const Center(child: Text('Нет других пользователей'));
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
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                  leading: CircleAvatar(
                                    radius: 25,
                                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    child: Text(
                                      user['name']?.toString().substring(0, 1).toUpperCase() ?? '?',
                                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(user['name'] ?? 'Без имени', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(user['email'] ?? ''),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    try {
                                      final targetId = user['id'].toString();
                                      final res = await _authService.post('/rooms', {
                                        'target_user_id': targetId,
                                        'friend_id': targetId,
                                      });
                                      if (res.statusCode == 200 || res.statusCode == 201) {
                                        _loadRooms();
                                      }
                                    } catch (e) {
                                      debugPrint('Ошибка: $e');
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: AppDrawer(
        userName: _userName,
        userEmail: _userEmail,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 320.0,
              floating: false,
              pinned: true,
              backgroundColor: isDark ? colorScheme.surface : colorScheme.primary,
              elevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_open_rounded, color: Colors.white, size: 28),
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
                              ? [colorScheme.surfaceVariant, colorScheme.surface]
                              : [colorScheme.primary, colorScheme.primaryContainer],
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
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.bolt, color: Colors.white, size: 20),
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
                                Expanded(child: _buildStatCard(context, "В работе", _tasksInProgress, Icons.auto_mode_rounded, Colors.orangeAccent)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStatCard(context, "Готово", _tasksDone, Icons.task_alt_rounded, Colors.greenAccent)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildStatCard(context, "Ожидают", _tasksTodo, Icons.timer_outlined, Colors.lightBlueAccent)),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
              ),
            ),
            _isLoading
                ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                : _rooms.isEmpty
                ? SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline_rounded, size: 60, color: colorScheme.outline.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      "Нет доступных чатов",
                      style: TextStyle(color: colorScheme.outline, fontSize: 16),
                    ),
                  ],
                ),
              ),
            )
                : SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final room = _rooms[index];
                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 400),
                      child: SlideAnimation(
                        verticalOffset: 30.0,
                        child: FadeInAnimation(
                          child: _buildRealChatTile(context, room),
                        ),
                      ),
                    );
                  },
                  childCount: _rooms.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUsersList,
        backgroundColor: colorScheme.primary,
        elevation: 4,
        highlightElevation: 8,
        icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
        label: const Text("Написать", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, int count, IconData icon, Color accentColor) {
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor.withOpacity(0.5)),
              )
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

  Widget _buildRealChatTile(BuildContext context, dynamic room) {
    final colorScheme = Theme.of(context).colorScheme;
    final String roomId = room['id']?.toString() ?? room['room_id']?.toString() ?? '';
    final String roomName = room['name'] ?? 'Чат без названия';
    final int unreadCount = room['unread_count'] ?? 0;
    final String lastMessage = room['last_message']?.toString().isNotEmpty == true
        ? room['last_message'].toString()
        : "Нажмите, чтобы начать общение";

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: unreadCount > 0 ? colorScheme.primary.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () async {
          if (roomId.isNotEmpty) {
            await context.push('/chat/$roomId');
            _loadRooms();
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
              roomName.isNotEmpty ? roomName.substring(0, 1).toUpperCase() : '?',
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
                  fontWeight: unreadCount > 0 ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 17,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            lastMessage,
            style: TextStyle(
              color: unreadCount > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withOpacity(0.7),
              fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colorScheme.outline.withOpacity(0.3)),
      ),
    );
  }
}
