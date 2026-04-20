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
    
    final String initial = widget.userName.isNotEmpty ? widget.userName.substring(0, 1).toUpperCase() : '?';

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: (_avatarPath != null && _avatarPath!.isNotEmpty) 
                  ? (_avatarPath!.startsWith('http') 
                      ? NetworkImage(_avatarPath!) 
                      : FileImage(File(_avatarPath!)) as ImageProvider)
                  : null,
              child: (_avatarPath == null || _avatarPath!.isEmpty)
                  ? Text(
                      initial,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    )
                  : null,
            ),
            accountName: Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text(widget.userEmail),
          ),

          _buildItem(context, Icons.chat_bubble_outline, 'Чаты', '/rooms'),
          _buildItem(context, Icons.task_alt, 'Все задачи', '/tasks'),
          _buildItem(context, Icons.person_outline, 'Профиль', '/profile'),
          _buildItem(context, Icons.settings_outlined, 'Настройки', '/settings'),

          const Spacer(),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Выйти', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              await _authService.logout();
              if (context.mounted) context.go('/login');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, String title, String route) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      onTap: () {
        Navigator.pop(context); 
        context.push(route);
      },
    );
  }
}
