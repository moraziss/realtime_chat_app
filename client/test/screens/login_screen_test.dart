import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realtime_chat_app/screens/login_screen.dart';
import 'package:realtime_chat_app/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

Widget _hostWithRouter(AuthService authService) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(authService: authService),
      ),
      GoRoute(
        path: '/rooms',
        builder: (context, state) => const Scaffold(body: Text('ROOMS_SCREEN')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  late MockAuthService authService;

  setUp(() {
    authService = MockAuthService();
  });

  testWidgets('successful login navigates to /rooms', (tester) async {
    when(() => authService.login(any(), any())).thenAnswer((_) async => true);

    await tester.pumpWidget(_hostWithRouter(authService));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alice@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Пароль'),
      'password123',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Войти'));
    await tester.pumpAndSettle();

    verify(
      () => authService.login('alice@example.com', 'password123'),
    ).called(1);
    expect(find.text('ROOMS_SCREEN'), findsOneWidget);
  });

  testWidgets('failed login shows an error banner and does not navigate', (
    tester,
  ) async {
    when(() => authService.login(any(), any())).thenAnswer((_) async => false);

    await tester.pumpWidget(_hostWithRouter(authService));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alice@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Пароль'),
      'wrong-password',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Войти'));
    await tester.pumpAndSettle();

    expect(find.text('Неверные данные для входа'), findsOneWidget);
    expect(find.text('ROOMS_SCREEN'), findsNothing);
  });

  testWidgets('switching to register mode reveals the name field', (
    tester,
  ) async {
    await tester.pumpWidget(_hostWithRouter(authService));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Имя'), findsNothing);

    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Имя'), findsOneWidget);
  });
}
