import 'dart:convert';
import 'dart:io';

import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/config/config_document.dart';

const configFileNames = <String>['dev.json', 'staging.json', 'prod.json'];

/// Returns 0 when every shipped file passes [ConfigDocument.parse].
///
/// Messages name the file and the rule. They do not include address values or
/// the machine path of [root].
int checkConfiguration(Directory root) {
  var failed = false;
  for (final String name in configFileNames) {
    final file = File('${root.path}/config/$name');
    if (!file.existsSync()) {
      stderr.writeln('Missing configuration file: config/$name');
      failed = true;
      continue;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      ConfigDocument.parse(decoded, fileName: name);
      stdout.writeln('config/$name ok');
    } on ConfigException catch (error) {
      stderr.writeln('config/$name: $error');
      failed = true;
    } on FormatException {
      stderr.writeln('config/$name: Configuration must be valid JSON.');
      failed = true;
    } on FileSystemException {
      stderr.writeln('config/$name: Configuration could not be read.');
      failed = true;
    }
  }
  return failed ? 1 : 0;
}
