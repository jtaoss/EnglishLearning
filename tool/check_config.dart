import 'dart:io';

import 'package:english_learning/core/config/config_check.dart';

/// Checks config/dev.json, config/staging.json, and config/prod.json.
///
/// Exit code 1 means the configuration is not safe to build.
void main(List<String> args) {
  exit(checkConfiguration(_root(args)));
}

Directory _root(List<String> args) {
  var root = Directory.current;
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--root') {
      if (index + 1 >= args.length) {
        stderr.writeln('Missing value for --root.');
        exit(1);
      }
      root = Directory(args[index + 1]);
      index++;
      continue;
    }
    stderr.writeln('Unknown argument.');
    exit(1);
  }
  return root;
}
