import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  // Внедряется только тестами (виджет-тесты подставляют фейковый
  // AuthService); в проде всегда null, и state создаёт настоящий.
  final AuthService? authService;

  const LoginScreen({super.key, this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _appeared = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _appeared = true);
    });
  }

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
          _error = e.toString().contains('Exception')
              ? 'Ошибка подключения к серверу'
              : e.toString();
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
        final colorScheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mark_email_read_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Подтверждение Email',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      text: 'Мы отправили 6-значный код на\n',
                      children: [
                        TextSpan(
                          text: email,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      errorText: dialogError,
                      counterText: '',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10,
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                            final success = await _authService.register(
                              name,
                              email,
                              password,
                              code,
                            );
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Подтвердить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _switchMode(bool toLogin) {
    if (_isLogin == toLogin) return;
    setState(() {
      _isLogin = toLogin;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Декоративный градиентный фон
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [colorScheme.surface, colorScheme.surface]
                    : [
                        colorScheme.primary,
                        colorScheme.primaryContainer,
                        colorScheme.surface,
                      ],
                stops: isDark ? null : const [0.0, 0.35, 0.75],
              ),
            ),
          ),
          if (!isDark) ...[
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              top: 80,
              left: -70,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
            ),
          ],

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      size.height - MediaQuery.of(context).padding.vertical,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    AnimatedScale(
                      scale: _appeared ? 1 : 0.6,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      child: AnimatedOpacity(
                        opacity: _appeared ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? colorScheme.primaryContainer
                                : Colors.white.withOpacity(0.18),
                            boxShadow: isDark
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                          ),
                          child: Icon(
                            Icons.forum_rounded,
                            size: 42,
                            color: isDark
                                ? colorScheme.onPrimaryContainer
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedOpacity(
                      opacity: _appeared ? 1 : 0,
                      duration: const Duration(milliseconds: 500),
                      child: AnimatedSlide(
                        offset: _appeared ? Offset.zero : const Offset(0, 0.15),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        child: Column(
                          children: [
                            Text(
                              'Realtime Chat',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: isDark
                                    ? colorScheme.onSurface
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Общение и задачи в одном месте',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark
                                    ? colorScheme.onSurfaceVariant
                                    : Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    AnimatedOpacity(
                      opacity: _appeared ? 1 : 0,
                      duration: const Duration(milliseconds: 600),
                      child: AnimatedSlide(
                        offset: _appeared ? Offset.zero : const Offset(0, 0.2),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isDark ? 0.3 : 0.1,
                                ),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildModeSwitcher(colorScheme),
                              const SizedBox(height: 20),

                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topCenter,
                                child: !_isLogin
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          TextField(
                                            controller: _nameController,
                                            decoration: const InputDecoration(
                                              labelText: 'Имя',
                                              prefixIcon: Icon(
                                                Icons.person_outline_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(
                                    Icons.alternate_email_rounded,
                                  ),
                                ),
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 14),

                              TextField(
                                controller: _passwordController,
                                decoration: InputDecoration(
                                  labelText: 'Пароль',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                onSubmitted: (_) =>
                                    _isLoading ? null : _submit(),
                              ),

                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                alignment: Alignment.topCenter,
                                child: _error != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.errorContainer
                                                .withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.error_outline_rounded,
                                                color: colorScheme.error,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: TextStyle(
                                                    color: colorScheme
                                                        .onErrorContainer,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _submit,
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(_isLogin ? 'Войти' : 'Продолжить'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              'Вход',
              _isLogin,
              colorScheme,
              () => _switchMode(true),
            ),
          ),
          Expanded(
            child: _buildModeTab(
              'Регистрация',
              !_isLogin,
              colorScheme,
              () => _switchMode(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(
    String label,
    bool selected,
    ColorScheme colorScheme,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: selected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
