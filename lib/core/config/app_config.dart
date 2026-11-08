import 'package:english_learning/core/logging/app_logger.dart';

enum AppEnvironment {
  development,
  staging,
  production;

  String get label => switch (this) {
    AppEnvironment.development => 'Development',
    AppEnvironment.staging => 'Staging',
    AppEnvironment.production => 'Production',
  };
}

final class ConfigException implements Exception {
  const ConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Non-secret compile-time configuration; no backend or account is required.
final class AppConfig {
  const AppConfig._({required this.environment, required this.logLevel});
  final AppEnvironment environment;
  final LogLevel logLevel;
  factory AppConfig.fromEnvironment() => AppConfig.parse(
    appEnv: const String.fromEnvironment('APP_ENV'),
    logLevel: const String.fromEnvironment('LOG_LEVEL'),
  );
  factory AppConfig.developmentPreset() =>
      AppConfig.parse(appEnv: 'development', logLevel: 'debug');
  factory AppConfig.stagingPreset() =>
      AppConfig.parse(appEnv: 'staging', logLevel: 'info');
  factory AppConfig.productionPreset() =>
      AppConfig.parse(appEnv: 'production', logLevel: 'warning');
  factory AppConfig.parse({required String appEnv, required String logLevel}) {
    final environment = switch (appEnv.trim()) {
      'development' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      'production' => AppEnvironment.production,
      '' => throw const ConfigException('APP_ENV is required.'),
      _ => throw const ConfigException(
        'APP_ENV must be development, staging, or production.',
      ),
    };
    final level = switch (logLevel.trim()) {
      'debug' => LogLevel.debug,
      'info' => LogLevel.info,
      'warning' => LogLevel.warning,
      'error' => LogLevel.error,
      '' => throw const ConfigException('LOG_LEVEL is required.'),
      _ => throw const ConfigException(
        'LOG_LEVEL must be debug, info, warning, or error.',
      ),
    };
    return AppConfig._(environment: environment, logLevel: level);
  }
  static String? debugLabel(
    AppEnvironment environment, {
    required bool debugMode,
  }) => debugMode ? 'Environment: ${environment.label}' : null;
}
