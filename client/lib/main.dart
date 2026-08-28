import 'package:flutter/material.dart';
// package:provider уже занимает имена Provider/ChangeNotifierProvider
// (используются ниже для темы) — riverpod даёт свои одноимённые классы,
// так что отсюда берём явно только то, что реально нужно: ProviderScope.
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'screens/task_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/chat_screen.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'theme_notifier.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      child: ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MessengerApp(),
      ),
    ),
  );
}

final _authService = AuthService();

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    bool loggedIn = false;
    try {
      loggedIn = await _authService.isLoggedIn();
    } catch (e) {
      // Не даём сбою здесь (например, недоступности secure storage) намертво
      // подвесить роутер без единого экрана — по умолчанию считаем, что не
      // авторизованы, и просто отправляем на логин.
      debugPrint('isLoggedIn() error: $e');
    }
    final isLoginRoute = state.uri.path == '/login';
    final isRegisterRoute = state.uri.path == '/register';

    if (!loggedIn && !isLoginRoute && !isRegisterRoute) {
      return '/login';
    }
    if (loggedIn && (isLoginRoute || isRegisterRoute)) {
      return '/rooms';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/rooms', builder: (context, state) => const RoomsScreen()),
    GoRoute(
      path: '/chat/:roomId',
      builder: (context, state) => ChatScreen(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(path: '/tasks', builder: (context, state) => const TasksScreen()),
    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
  ],
);

class MessengerApp extends StatelessWidget {
  const MessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return ValueListenableBuilder<Color>(
      valueListenable: appColorNotifier,
      builder: (context, color, _) {
        return ValueListenableBuilder<double>(
          valueListenable: appFontSizeNotifier,
          builder: (context, fontSizeFactor, _) {
            return MaterialApp.router(
              title: 'Мессенджер',
              debugShowCheckedModeBanner: false,
              themeMode: themeProvider.themeMode,
              theme: AppTheme.build(
                seedColor: color,
                brightness: Brightness.light,
                fontScale: fontSizeFactor,
              ),
              darkTheme: AppTheme.build(
                seedColor: color,
                brightness: Brightness.dark,
                fontScale: fontSizeFactor,
              ),
              routerConfig: _router,
            );
          },
        );
      },
    );
  }
}
