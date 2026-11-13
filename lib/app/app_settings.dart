import 'package:flutter/material.dart';
import 'package:english_learning/core/settings/settings_repository.dart';

enum AppLanguage {
  english('English / 英语'),
  japanese('日本語 / 日语');

  const AppLanguage(this.label);
  final String label;
}

/// Theme and language selection for this process.
///
/// The repository is the durable copy. A read or write failure leaves the
/// in-memory selection on the system theme or on the last choice the user made.
final class AppSettings extends ChangeNotifier {
  AppSettings({required this.repository});

  final SettingsRepository repository;
  ThemeMode _themeMode = ThemeMode.system;
  AppLanguage _language = AppLanguage.english;
  var _userChanged = false;
  var _disposed = false;

  ThemeMode get themeMode => _themeMode;
  AppLanguage get language => _language;

  void setLanguage(AppLanguage language) {
    if (_language != language) {
      _language = language;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> restore() async {
    ThemeMode mode = ThemeMode.system;
    try {
      mode = await repository.readThemeMode();
    } catch (_) {
      mode = ThemeMode.system;
    }
    if (_disposed || _userChanged) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _userChanged = true;
    if (_themeMode != mode) {
      _themeMode = mode;
      if (!_disposed) {
        notifyListeners();
      }
    }
    try {
      await repository.writeThemeMode(mode);
    } catch (_) {
      // The screen keeps the selection even when storage is unavailable.
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    super.dispose();
  }
}
