import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Глобальный уведомитель для акцентного цвета приложения
final AppThemeNotifier appColorNotifier = AppThemeNotifier();

// Глобальный уведомитель для размера шрифта
final AppFontSizeNotifier appFontSizeNotifier = AppFontSizeNotifier();

class AppThemeNotifier extends ValueNotifier<Color> {
  static const String _colorKey = 'app_accent_color';

  AppThemeNotifier() : super(Colors.blue) {
    _loadColor();
  }

  Future<void> _loadColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_colorKey);
    if (colorValue != null) {
      value = Color(colorValue);
    }
  }

  Future<void> setColor(Color newColor) async {
    value = newColor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, newColor.value);
  }

  Future<void> reset() async {
    await setColor(Colors.blue);
  }
}

class AppFontSizeNotifier extends ValueNotifier<double> {
  static const String _fontSizeKey = 'app_font_size_factor';

  AppFontSizeNotifier() : super(1.0) {
    _loadFontSize();
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble(_fontSizeKey);
    if (size != null) {
      value = size;
    }
  }

  Future<void> setFontSize(double factor) async {
    value = factor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, factor);
  }

  Future<void> reset() async {
    await setFontSize(1.0);
  }
}
