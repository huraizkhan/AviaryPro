import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AviaryThemePreset { classic, olive, ocean, plum }

class ThemeProvider extends ChangeNotifier {
  static const _modeKey = 'appearance_mode';
  static const _presetKey = 'appearance_preset';

  ThemeMode _mode = ThemeMode.system;
  AviaryThemePreset _preset = AviaryThemePreset.classic;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  AviaryThemePreset get preset => _preset;
  bool get loaded => _loaded;

  Color get seedColor => switch (_preset) {
        AviaryThemePreset.classic => const Color(0xFF2E8B78),
        AviaryThemePreset.olive => const Color(0xFF687A42),
        AviaryThemePreset.ocean => const Color(0xFF356F9F),
        AviaryThemePreset.plum => const Color(0xFF7A537D),
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_modeKey);
    final presetName = prefs.getString(_presetKey);
    _mode = ThemeMode.values.where((item) => item.name == modeName).firstOrNull ??
        ThemeMode.system;
    _preset = AviaryThemePreset.values
            .where((item) => item.name == presetName)
            .firstOrNull ??
        AviaryThemePreset.classic;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, value.name);
  }

  Future<void> setPreset(AviaryThemePreset value) async {
    if (_preset == value) return;
    _preset = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, value.name);
  }
}
