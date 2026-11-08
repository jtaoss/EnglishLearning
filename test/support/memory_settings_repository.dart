import 'dart:async';

import 'package:flutter/material.dart';
import 'package:english_learning/core/settings/settings_repository.dart';

/// In-memory settings store for tests.
final class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository({
    this.stored,
    this.throwOnRead = false,
    this.throwOnWrite = false,
    this.readGate,
  });

  String? stored;
  bool throwOnRead;
  bool throwOnWrite;
  Completer<void>? readGate;

  @override
  Future<ThemeMode> readThemeMode() async {
    final gate = readGate;
    if (gate != null) {
      await gate.future;
    }
    if (throwOnRead) {
      throw StateError('read');
    }
    return themeModeFromStorage(stored);
  }

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {
    if (throwOnWrite) {
      throw StateError('write');
    }
    stored = themeModeToStorage(mode);
  }
}
