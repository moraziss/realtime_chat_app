import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatefulWidget {
  final String userName;
  final String userEmail;

  const AppDrawer({super.key, required this.userName, required this.userEmail});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _authService = AuthService();
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final profile = await _authService.getLocalProfile();
    if (mounted) {
      setState(() {
        _avatarPath = profile['avatar'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentPath = GoRouterState.of(context).uri.path;

    final String initial = widget.userName.isNotEmpty ? widget.userName.substring(0, 1).toUpperCase() : '?';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -30,
                    right: -30,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white,
                        backgroundImage: (_avatarPath != null && _avatarPath!.isNotEmpty)
                            ? (_avatarPath!.startsWith('http')
                                ? NetworkImage(_avatarPath!)
                                : FileImage(File(_avatarPath!)) as ImageProvider)
                            : null,
                        child: (_avatarPath == null || _avatarPath!.isEmpty)
                            ? Text(
                                initial,
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colorScheme.primary),
                              )
                            : null,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.userName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.userEmail,
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildItem(context, Icons.chat_bubble_rounded, 'Чаты', '/rooms', currentPath, colorScheme),
            _buildItem(context, Icons.task_alt_rounded, 'Все задачи', '/tasks', currentPath, colorScheme),
            _buildItem(context, Icons.person_rounded, 'Профиль', '/profile', currentPath, colorScheme),
            _buildItem(context, Icons.settings_rounded, 'Настройки', '/settings', currentPath, colorScheme),

            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: colorScheme.outlineVariant.withOpacity(0.4)),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                title: const Text('Выйти', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
                onTap: () async {
                  await _authService.logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                'Realtime Chat · v1.3.0',
                style: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, String title, String route, String currentPath, ColorScheme colorScheme) {
    final bool isActive = currentPath == route;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: isActive ? colorScheme.primary.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(context);
            if (!isActive) context.push(route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 22),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
