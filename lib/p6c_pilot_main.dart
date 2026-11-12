import 'dart:io';

import 'package:flutter/material.dart';

import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/core_meanings_pilot/core_meaning_sample.dart';
import 'package:english_learning/features/core_meanings_pilot/core_meanings_pilot_page.dart';

/// Explicitly selected development entry point. Never calls the formal main,
/// path_provider, learning repositories, credentials, or a network service.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('P6C_ENABLE_PILOT');
  const path = String.fromEnvironment('P6C_PILOT_FILE');
  try {
    if (!enabled || path.isEmpty || !File(path).isAbsolute) {
      throw const FormatException('请显式启用试点，并指定隔离 JSON 的绝对路径。');
    }
    final file = File(path);
    if (await file.length() > 4 * 1024 * 1024) {
      throw const FormatException('试点文件超过 4 MB，未加载。');
    }
    final bundle = CoreMeaningPilotBundle.decode(await file.readAsString());
    runApp(CoreMeaningsPilotApp(bundle: bundle));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: Text('隔离试点未加载。请检查启用参数、文件路径和样本校验。')),
        ),
      ),
    );
  }
}
