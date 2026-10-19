import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_chat_app/theme_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'app_accent_color';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppThemeNotifier', () {
    test('defaults to blue when nothing is stored', () async {
      final notifier = AppThemeNotifier();
      await pumpEventQueue();

      expect(notifier.value.toARGB32(), Colors.blue.toARGB32());
    });

    test('loads a previously saved accent colour', () async {
      SharedPreferences.setMockInitialValues({key: 0xFF4CAF50});

      final notifier = AppThemeNotifier();
      await pumpEventQueue();

      expect(notifier.value.toARGB32(), 0xFF4CAF50);
    });

    test('setColor updates the value, notifies listeners and persists the ARGB int',
        () async {
      final notifier = AppThemeNotifier();
      await pumpEventQueue();
      var notifications = 0;
      notifier.addListener(() => notifications++);

      await notifier.setColor(const Color(0xFFE91E63));

      expect(notifier.value.toARGB32(), 0xFFE91E63);
      expect(notifications, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(key), 0xFFE91E63);
    });

    test('reset goes back to blue and stores it', () async {
      final notifier = AppThemeNotifier();
      await pumpEventQueue();
      await notifier.setColor(Colors.green);

      await notifier.reset();

      expect(notifier.value.toARGB32(), Colors.blue.toARGB32());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(key), Colors.blue.toARGB32());
    });
  });
}
