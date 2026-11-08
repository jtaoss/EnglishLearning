import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';

Future<SqliteLearningRepository> openLearningRepository() async {
  final directory = await getApplicationSupportDirectory();
  await Directory(directory.path).create(recursive: true);
  return SqliteLearningRepository.open(
    p.join(directory.path, 'english_learning_v1.sqlite3'),
  );
}
