import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (_isLogin) {
      // --- ЛОГИКА ВХОДА ---
      try {
        final success = await _authService.login(email, password);
        if (success && mounted) {
          context.go('/rooms');
        } else {
          setState(() => _error = 'Неверные данные для входа');
        }
      } catch (e) {
        setState(() => _error = 'Ошибка подключения к серверу');
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      // --- ЛОГИКА РЕГИСТРАЦИИ (ЭТАП 1: ОТПРАВКА КОДА) ---
      if (email.isEmpty || password.isEmpty || name.isEmpty) {
        setState(() {
          _error = 'Заполните все поля';
          _isLoading = false;
        });
        return;
      }

      try {
        final codeSent = await _authService.sendVerificationCode(email);
        setState(() => _isLoading = false);

        if (codeSent) {
          _showCodeDialog(name, email, password);
        }
      } catch (e) {
        setState(() {
          // Если сервер вернул ошибку, выводим её. Иначе стандартное сообщение о сети.
          _error = e.toString().contains('Exception') ? 'Ошибка подключения к серверу' : e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // --- ЭТАП 2: ВВОД КОДА ---
  void _showCodeDialog(String name, String email, String password) {
    final codeController = TextEditingController();
    bool isVerifying = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Подтверждение Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Мы отправили код подтверждения на:\n$email', textAlign: TextAlign.center,),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: '6-значный код',
                      errorText: dialogError,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(ctx),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;

                    setStateDialog(() {
                      isVerifying = true;
                      dialogError = null;
                    });

                    try {
                      final success = await _authService.register(name, email, password, code);
                      if (success) {
                        // Успешная регистрация -> Сразу логинимся
                        await _authService.login(email, password);
                        if (mounted) {
                          Navigator.pop(ctx);
                          context.go('/rooms');
                        }
                      }
                    } catch (e) {
                      setStateDialog(() {
                        isVerifying = false;
                        dialogError = e.toString();
                      });
                    }
                  },
                  child: isVerifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Подтвердить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              Text(
                _isLogin ? 'Вход' : 'Регистрация',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),

              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isLogin ? 'Войти' : 'Продолжить'),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _error = null;
                  });
                },
                child: Text(
                  _isLogin
                      ? 'Нет аккаунта? Зарегистрироваться'
                      : 'Уже есть аккаунт? Войти',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
