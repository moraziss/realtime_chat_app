import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Возвращаем logout, чтобы каждый раз видеть экран входа при перезапуске
  await AuthService().logout();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MessengerApp(),
    ),
  );
}

final _authService = AuthService();

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final loggedIn = await _authService.isLoggedIn();
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
            final lightScheme = ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light);
            final darkScheme = ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark);

            return MaterialApp.router(
              title: 'Мессенджер',
              debugShowCheckedModeBanner: false,
              themeMode: themeProvider.themeMode,
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                textTheme: _applyFontSize(ThemeData.light().textTheme, fontSizeFactor),
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
                textTheme: _applyFontSize(ThemeData.dark().textTheme, fontSizeFactor),
              ),
              routerConfig: _router,
            );
          },
        );
      },
    );
  }

  TextTheme _applyFontSize(TextTheme base, double factor) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontSize: (base.displayLarge?.fontSize ?? 57) * factor),
      displayMedium: base.displayMedium?.copyWith(fontSize: (base.displayMedium?.fontSize ?? 45) * factor),
      displaySmall: base.displaySmall?.copyWith(fontSize: (base.displaySmall?.fontSize ?? 36) * factor),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: (base.headlineLarge?.fontSize ?? 32) * factor),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: (base.headlineMedium?.fontSize ?? 28) * factor),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: (base.headlineSmall?.fontSize ?? 24) * factor),
      titleLarge: base.titleLarge?.copyWith(fontSize: (base.titleLarge?.fontSize ?? 22) * factor),
      titleMedium: base.titleMedium?.copyWith(fontSize: (base.titleMedium?.fontSize ?? 16) * factor),
      titleSmall: base.titleSmall?.copyWith(fontSize: (base.titleSmall?.fontSize ?? 14) * factor),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: (base.bodyLarge?.fontSize ?? 16) * factor),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: (base.bodyMedium?.fontSize ?? 14) * factor),
      bodySmall: base.bodySmall?.copyWith(fontSize: (base.bodySmall?.fontSize ?? 12) * factor),
      labelLarge: base.labelLarge?.copyWith(fontSize: (base.labelLarge?.fontSize ?? 14) * factor),
      labelMedium: base.labelMedium?.copyWith(fontSize: (base.labelMedium?.fontSize ?? 12) * factor),
      labelSmall: base.labelSmall?.copyWith(fontSize: (base.labelSmall?.fontSize ?? 11) * factor),
    );
  }
}
