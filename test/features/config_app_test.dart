import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/app/config_error_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_settings_repository.dart';

void main() {
  for (final config in [
    AppConfig.developmentPreset(),
    AppConfig.stagingPreset(),
    AppConfig.productionPreset(),
  ]) {
    testWidgets(
      '${config.environment.name} keeps home and settings without samples',
      (tester) async {
        await tester.pumpWidget(
          EnglishLearningApp(
            repository: MemorySettingsRepository(),
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
        expect(find.text('Open sample library'), findsNothing);
        expect(find.text('Open status demo'), findsNothing);
        await tester.tap(find.byKey(HomePage.openSettingsKey));
        await tester.pumpAndSettle();
        expect(find.text('Theme'), findsOneWidget);
      },
    );
  }
  testWidgets('startup config error is visible', (tester) async {
    await tester.pumpWidget(
      const ConfigErrorApp(message: 'APP_ENV is required.'),
    );
    expect(find.byKey(ConfigErrorApp.messageKey), findsOneWidget);
    expect(find.text('APP_ENV is required.'), findsOneWidget);
  });
}
