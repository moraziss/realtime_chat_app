import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme_notifier.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _sectionTitle('Внешний вид'),
          _buildColorPicker(),
          
          const Divider(indent: 16, endIndent: 16),
          
          _buildFontSizePicker(),

          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Темная тема'),
            subtitle: const Text('Переключить оформление приложения'),
            value: themeProvider.isDarkMode,
            onChanged: (_) => themeProvider.toggleTheme(),
          ),

          _sectionTitle('Аккаунт и безопасность'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Профиль'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile'),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Очистить настройки'),
            subtitle: const Text('Сбросить цвет и размер текста'),
            onTap: () => _resetSettings(themeProvider),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('О приложении'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Realtime Chat',
                applicationVersion: '1.3.0',
                applicationIcon: const FlutterLogo(size: 40),
                children: [
                  const Text('Быстрый и удобный мессенджер для командной работы.'),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: const Text('Выйти из системы'),
            onTap: () async {
              await _authService.logout();
              if (mounted) context.go('/login');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Удалить аккаунт', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('Все данные будут стерты безвозвратно'),
            onTap: _confirmAccountDeletion,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = [
      Colors.blue, Colors.red, Colors.green,
      Colors.orange, Colors.purple, Colors.teal,
      Colors.pink, Colors.indigo,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Цветовая схема', style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(
          height: 70,
          child: ValueListenableBuilder<Color>(
            valueListenable: appColorNotifier,
            builder: (context, currentColor, _) {
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                scrollDirection: Axis.horizontal,
                itemCount: colors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final color = colors[index];
                  final isSelected = currentColor.value == color.value;
                  return GestureDetector(
                    onTap: () => appColorNotifier.setColor(color),
                    child: Container(
                      width: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                        ],
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFontSizePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Размер шрифта', style: Theme.of(context).textTheme.bodySmall),
        ),
        ValueListenableBuilder<double>(
          valueListenable: appFontSizeNotifier,
          builder: (context, currentFactor, _) {
            return Slider(
              value: currentFactor,
              min: 0.8,
              max: 1.4,
              divisions: 3,
              label: _getFontLabel(currentFactor),
              onChanged: (value) => appFontSizeNotifier.setFontSize(value),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('A', style: TextStyle(fontSize: 12)),
              Text('A', style: TextStyle(fontSize: 16)),
              Text('A', style: TextStyle(fontSize: 20)),
              Text('A', style: TextStyle(fontSize: 24)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _getFontLabel(double factor) {
    if (factor <= 0.8) return 'Мелкий';
    if (factor <= 1.0) return 'Стандартный';
    if (factor <= 1.2) return 'Крупный';
    return 'Очень крупный';
  }

  Future<void> _resetSettings(ThemeProvider themeProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Сбросить оформление?'),
        content: const Text('Цвет и шрифт вернутся к стандартным. Вы останетесь в своем аккаунте.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сбросить')),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_accent_color');
      await prefs.remove('app_font_size_factor');
      await appColorNotifier.reset();
      await appFontSizeNotifier.reset();
      if (themeProvider.isDarkMode) {
        await themeProvider.toggleTheme();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки оформления сброшены')));
      }
    }
  }

  Future<void> _confirmAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление аккаунта', style: TextStyle(color: Colors.red)),
        content: const Text('Вы уверены? Это действие невозможно отменить. Все ваши данные будут безвозвратно удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ОТМЕНА')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('УДАЛИТЬ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _authService.deleteAccount();
        if (success) {
          await _authService.logout();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Аккаунт успешно удален')),
            );
            context.go('/login');
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ошибка сервера при удалении аккаунта')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка при удалении: $e')),
          );
        }
      }
    }
  }
}
