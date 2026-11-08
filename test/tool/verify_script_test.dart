import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verify.ps1 exits non-zero when configuration is missing', () async {
    final result = await Process.run('powershell', <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'scripts/verify.ps1',
      '-Mode',
      'config',
      '-ConfigRoot',
      'test/fixtures/config/missing_prod',
    ]);

    expect(result.exitCode, isNonZero);
    final output = '${result.stdout}\n${result.stderr}';
    expect(output, contains('Missing configuration file: config/prod.json'));
    expect(output, isNot(contains(r'E:\')));
  });
}
