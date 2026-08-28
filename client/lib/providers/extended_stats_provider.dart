import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stats.dart';
import 'core_providers.dart';

/// Расширенная статистика для ProfileScreen (сообщения, дни в приложении,
/// любимый приоритет, история выполнения по дням) — единственный экран,
/// которому она нужна, в отличие от TaskStats (там же на RoomsScreen).
class ExtendedStatsNotifier extends AsyncNotifier<ExtendedStats> {
  @override
  Future<ExtendedStats> build() {
    return ref.watch(userRepositoryProvider).getExtendedStats();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(userRepositoryProvider).getExtendedStats(),
    );
  }
}

final extendedStatsProvider =
    AsyncNotifierProvider<ExtendedStatsNotifier, ExtendedStats>(
      ExtendedStatsNotifier.new,
    );
