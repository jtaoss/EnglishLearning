import 'dart:convert';
import 'dart:io';

import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/config/config_check.dart';
import 'package:english_learning/core/config/config_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipped configs match presets', () {
    for (final pair in <String, AppConfig>{
      'dev.json': AppConfig.developmentPreset(),
      'staging.json': AppConfig.stagingPreset(),
      'prod.json': AppConfig.productionPreset(),
    }.entries) {
      final config = ConfigDocument.parse(
        jsonDecode(File('config/${pair.key}').readAsStringSync()),
        fileName: pair.key,
      );
      expect(config.environment, pair.value.environment);
      expect(config.logLevel, pair.value.logLevel);
    }
  });
  test('missing production config makes preflight fail', () {
    expect(
      checkConfiguration(Directory('test/fixtures/config/missing_prod')),
      1,
    );
  });
  test(
    'rejects non-object, missing, non-string, unknown and mismatched fields',
    () {
      for (final Object? value in [
        null,
        <Object?>[],
        <String, Object?>{},
        {'APP_ENV': 'production', 'LOG_LEVEL': true},
        {
          'APP_ENV': 'production',
          'LOG_LEVEL': 'warning',
          'NOTION_TOKEN': 'must-not-be-a-compile-time-secret',
        },
        {'APP_ENV': 'development', 'LOG_LEVEL': 'debug'},
      ]) {
        expect(
          () => ConfigDocument.parse(value, fileName: 'prod.json'),
          throwsA(isA<ConfigException>()),
        );
      }
    },
  );
}
