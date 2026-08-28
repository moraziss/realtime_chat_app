import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/stats.dart';
import '../providers/core_providers.dart';
import '../providers/current_user_providers.dart';
import '../providers/extended_stats_provider.dart';
import '../providers/rooms_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();
  bool _isUploading = false;
  bool _dateFormattingReady = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ru_RU', null).then((_) {
      if (mounted) setState(() => _dateFormattingReady = true);
    });
  }

  String _resolveAvatarUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    return '${ref.read(authServiceProvider).currentBaseUrl}$raw';
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final bytes = await image.readAsBytes();
      final uploadedUrl = await ref.read(authServiceProvider).uploadFile(bytes, image.name);

      if (uploadedUrl != null) {
        await ref.read(userRepositoryProvider).updateMe({'avatar_url': uploadedUrl});
        await ref.read(meProvider.notifier).refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Фото профиля обновлено')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error picking/uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при загрузке фото')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _refreshAll() {
    return Future.wait([
      ref.read(meProvider.notifier).refresh(),
      ref.read(taskStatsProvider.notifier).refresh(),
      ref.read(extendedStatsProvider.notifier).refresh(),
    ]);
  }

  void _showAchievementsInfo() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Как получить награды?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _infoItem(Icons.chat_bubble, 'Собеседник', 'Более 50 сообщений', colorScheme.primary, colorScheme),
            _infoItem(Icons.workspace_premium, 'Мастер', 'Выполнено 10+ задач', colorScheme.secondary, colorScheme),
            _infoItem(Icons.calendar_month, 'Ветеран', 'В приложении более 7 дней', colorScheme.tertiary, colorScheme),
            _infoItem(Icons.speed, 'Сверхзвук', 'КПД выше 90%', colorScheme.primary, colorScheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String title, String desc, Color color, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(desc, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final meAsync = ref.watch(meProvider);
    final statsAsync = ref.watch(taskStatsProvider);
    final extAsync = ref.watch(extendedStatsProvider);

    final isLoading = !_dateFormattingReady || (meAsync.isLoading && !meAsync.hasValue);
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = meAsync.valueOrNull;
    final stats = statsAsync.valueOrNull ?? const TaskStats();
    final ext = extAsync.valueOrNull ?? const ExtendedStats();

    final userName = profile?.name ?? 'Без имени';
    final userEmail = profile?.email ?? '';
    final bio = profile?.bio ?? '';
    final avatarUrl = _resolveAvatarUrl(profile?.avatarUrl);
    final efficiency = stats.total > 0 ? (stats.done / stats.total) * 100 : 0.0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 180, pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [colorScheme.primary, colorScheme.tertiary])),
                child: Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _isUploading ? null : _pickAndUploadImage,
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white24,
                          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? Text(
                                  userName.isNotEmpty ? userName.substring(0, 1).toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                                )
                              : null,
                        ),
                      ),
                      if (_isUploading)
                        const Positioned.fill(
                          child: Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.surface,
                          child: Icon(Icons.camera_alt, size: 16, color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Center(
                  child: Column(children: [
                    Text(userName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    Text(userEmail, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
                  ]),
                ),
                const SizedBox(height: 32),
                _buildStatRow(colorScheme, ext),
                const SizedBox(height: 32),
                if (bio.isNotEmpty) ...[
                  const Text('О себе', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(bio, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15)),
                  const SizedBox(height: 32),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Достижения', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: _showAchievementsInfo, icon: const Icon(Icons.info_outline, size: 20)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildAchievementSection(colorScheme, stats, ext, efficiency),
                const SizedBox(height: 32),
                const Text('Прогресс за неделю', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildWeeklyCompletionChart(colorScheme, ext),
                const SizedBox(height: 32),
                _buildActivityChart(colorScheme, stats, efficiency),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildStatRow(ColorScheme colorScheme, ExtendedStats ext) {
    return Row(
      children: [
        Expanded(child: _statCard('Месседжи', ext.messagesSent.toString(), Icons.chat_bubble_outline, colorScheme.primary, colorScheme)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Дни', ext.daysInApp.toString(), Icons.calendar_today, colorScheme.secondary, colorScheme)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Фокус', _translatePriority(ext.favoritePriority), Icons.track_changes, colorScheme.tertiary, colorScheme)),
      ],
    );
  }

  String _translatePriority(String priority) {
    switch (priority) {
      case 'high':
        return 'Высокий';
      case 'medium':
        return 'Средний';
      case 'low':
        return 'Низкий';
      default:
        return priority;
    }
  }

  Widget _statCard(String label, String value, IconData icon, Color color, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
      child: Column(children: [Icon(icon, color: color, size: 20), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))), Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10), textAlign: TextAlign.center)]),
    );
  }

  Widget _buildAchievementSection(ColorScheme colorScheme, TaskStats stats, ExtendedStats ext, double efficiency) {
    final achievements = [
      _badge(Icons.chat_bubble, 'Собеседник', colorScheme.primary, ext.messagesSent >= 50, colorScheme),
      _badge(Icons.workspace_premium, 'Мастер', colorScheme.secondary, stats.done >= 10, colorScheme),
      _badge(Icons.calendar_month, 'Ветеран', colorScheme.tertiary, ext.daysInApp >= 7, colorScheme),
      _badge(Icons.speed, 'Сверхзвук', colorScheme.primary, efficiency >= 90 && stats.done > 5, colorScheme),
    ];

    return SizedBox(
      height: 110,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: achievements,
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color, bool isUnlocked, ColorScheme colorScheme) {
    final lockedColor = colorScheme.onSurfaceVariant;
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: isUnlocked ? color.withOpacity(0.1) : lockedColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnlocked ? color.withOpacity(0.2) : lockedColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isUnlocked ? color : lockedColor.withOpacity(0.4),
            size: 32,
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              label,
              style: TextStyle(
                color: isUnlocked ? color : lockedColor.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.bold
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            isUnlocked ? Icons.check_circle : Icons.lock,
            size: 12,
            color: isUnlocked ? color : lockedColor.withOpacity(0.4)
          ),
        ],
      ),
    );
  }

  Widget _buildActivityChart(ColorScheme colorScheme, TaskStats stats, double efficiency) {
    final double progress = stats.total > 0 ? (stats.done / stats.total).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Общая эффективность', style: TextStyle(fontWeight: FontWeight.bold)), Text('${(progress * 100).toInt()}%', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold))]), const SizedBox(height: 12), LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(10), minHeight: 8), const SizedBox(height: 16), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_chartInfo('Задач', stats.total.toString(), colorScheme), _chartInfo('Готово', stats.done.toString(), colorScheme), _chartInfo('КПД', '${efficiency.toInt()}%', colorScheme)])]),
    );
  }

  Widget _chartInfo(String label, String value, ColorScheme colorScheme) { return Column(children: [Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11))]); }

  Widget _buildWeeklyCompletionChart(ColorScheme colorScheme, ExtendedStats ext) {
    final completionHistory = ext.completionHistory;
    final List<int> history = List<int>.filled(7, 0);
    for (int i = 0; i < 7; i++) {
      int historyIdx = completionHistory.length - 1 - i;
      if (historyIdx >= 0) history[6 - i] = completionHistory[historyIdx];
    }
    final now = DateTime.now();
    final DateFormat formatter = DateFormat('E', 'ru_RU');
    final List<String> labels = List.generate(7, (i) => formatter.format(now.subtract(Duration(days: 6 - i))).replaceAll('.', ''));
    final maxVal = history.isEmpty ? 0 : history.reduce((a, b) => a > b ? a : b);
    return Container(
      height: 160, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(7, (i) {
        final count = history[i];
        final factor = maxVal > 0 ? (count / maxVal) : 0.0;
        return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [if (count > 0) Text(count.toString(), style: TextStyle(fontSize: 9, color: colorScheme.primary, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Container(width: 20, height: (80 * factor).clamp(2, 80).toDouble(), decoration: BoxDecoration(color: colorScheme.primary.withOpacity(factor > 0 ? 1 : 0.2), borderRadius: BorderRadius.circular(4))), const SizedBox(height: 6), Text(labels[i], style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant))]));
      })),
    );
  }
}
