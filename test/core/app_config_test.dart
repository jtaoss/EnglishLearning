import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads all three environments without a backend or account', () {
    expect(
      AppConfig.developmentPreset().environment,
      AppEnvironment.development,
    );
    expect(AppConfig.stagingPreset().logLevel, LogLevel.info);
    expect(AppConfig.productionPreset().logLevel, LogLevel.warning);
  });
  test('startup does not silently use development when config is missing', () {
    expect(
      AppConfig.fromEnvironment,
      throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          'APP_ENV is required.',
        ),
      ),
    );
  });
  test('rejects missing and unknown environment or log levels', () {
    for (final env in ['', 'local']) {
      expect(
        () => AppConfig.parse(appEnv: env, logLevel: 'info'),
        throwsA(isA<ConfigException>()),
      );
    }
    for (final level in ['', 'verbose']) {
      expect(
        () => AppConfig.parse(appEnv: 'production', logLevel: level),
        throwsA(isA<ConfigException>()),
      );
    }
  });
  test('release has no environment label', () {
    expect(
      AppConfig.debugLabel(AppEnvironment.staging, debugMode: true),
      'Environment: Staging',
    );
    expect(
      AppConfig.debugLabel(AppEnvironment.production, debugMode: false),
      isNull,
    );
  });
}
