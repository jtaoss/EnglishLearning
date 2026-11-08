import 'package:flutter/material.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native shell starts with each valid environment', (
    tester,
  ) async {
    for (final config in [
      AppConfig.developmentPreset(),
      AppConfig.stagingPreset(),
      AppConfig.productionPreset(),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: SharedPreferencesSettingsRepository(),
          logger: AppLogger(),
          config: config,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有学习词库'), findsOneWidget);
      expect(
        find.text('Environment: ${config.environment.label}'),
        findsOneWidget,
      );
    }
  });
}
