import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import 'core_providers.dart';

/// Просто "кто я" по id — читается из кэшированного/декодированного JWT без
/// сетевого запроса (AuthService.getUserId), для мест, которым не нужен
/// весь профиль (TasksScreen, ChatScreen).
final currentUserIdProvider = FutureProvider<String?>((ref) {
  return ref.watch(authServiceProvider).getUserId();
});

/// Полный профиль текущего пользователя (GET /users/me) — используется и
/// шапкой RoomsScreen/AppDrawer, и ProfileScreen как основа для identity.
class MeNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() {
    return ref.watch(userRepositoryProvider).getMe();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(userRepositoryProvider).getMe(),
    );
  }
}

final meProvider = AsyncNotifierProvider<MeNotifier, UserProfile>(
  MeNotifier.new,
);
