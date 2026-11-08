import 'package:english_learning/core/config/app_config.dart';

/// JSON document rules for the three shipped configuration files.
///
/// Semantic checks go through [AppConfig.parse]. This type only adds the file
/// shape: required names, string values, and the environment each file owns.
final class ConfigDocument {
  static const List<String> fieldNames = <String>['APP_ENV', 'LOG_LEVEL'];

  static const Map<String, String> environmentForFile = <String, String>{
    'dev.json': 'development',
    'staging.json': 'staging',
    'prod.json': 'production',
  };

  static AppConfig parse(Object? decoded, {required String fileName}) {
    if (decoded is! Map<Object?, Object?>) {
      throw const ConfigException('Configuration must be a JSON object.');
    }
    final keys = <String>{
      for (final Object? key in decoded.keys) key.toString(),
    };
    for (final String name in fieldNames) {
      if (!keys.contains(name)) {
        throw ConfigException('$name is required.');
      }
    }
    for (final String key in keys) {
      if (!fieldNames.contains(key)) {
        throw ConfigException('$key is not a configuration field.');
      }
    }
    final values = <String, String>{};
    for (final String name in fieldNames) {
      final Object? value = decoded[name];
      if (value is! String) {
        throw ConfigException('$name must be a string.');
      }
      values[name] = value;
    }
    final expected = environmentForFile[fileName];
    if (expected != null && values['APP_ENV'] != expected) {
      throw ConfigException('$fileName must set APP_ENV to $expected.');
    }
    return AppConfig.parse(
      appEnv: values['APP_ENV']!,
      logLevel: values['LOG_LEVEL']!,
    );
  }
}
