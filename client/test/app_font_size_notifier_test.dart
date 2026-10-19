import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/theme_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'app_font_size_factor';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppFontSizeNotifier', () {
    test('defaults to a factor of 1.0', () async {
      final notifier = AppFontSizeNotifier();
      await pumpEventQueue();

      expect(notifier.value, 1.0);
    });

    test('loads a previously saved factor', () async {
      SharedPreferences.setMockInitialValues({key: 1.25});

      final notifier = AppFontSizeNotifier();
      await pumpEventQueue();

      expect(notifier.value, 1.25);
    });

    test('setFontSize updates the value, notifies listeners and persists it',
        () async {
      final notifier = AppFontSizeNotifier();
      await pumpEventQueue();
      var notifications = 0;
      notifier.addListener(() => notifications++);

      await notifier.setFontSize(1.4);

      expect(notifier.value, 1.4);
      expect(notifications, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(key), 1.4);
    });

    test('reset goes back to 1.0 and stores it', () async {
      final notifier = AppFontSizeNotifier();
      await pumpEventQueue();
      await notifier.setFontSize(0.8);

      await notifier.reset();

      expect(notifier.value, 1.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(key), 1.0);
    });
  });
}
