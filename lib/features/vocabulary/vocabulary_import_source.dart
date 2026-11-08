import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

Future<String> loadVerifiedSample() =>
    rootBundle.loadString('assets/vocabulary/verified100.csv');

Future<String?> pickVocabularyCsv() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'CSV',
        extensions: ['csv'],
        mimeTypes: ['text/csv', 'text/comma-separated-values', 'text/plain'],
        uniformTypeIdentifiers: ['public.comma-separated-values-text'],
      ),
    ],
  );
  if (file == null) return null;
  return readVocabularyCsvFile(file);
}

/// Shared by native selectors and tests using their returned XFile payloads.
Future<String> readVocabularyCsvFile(XFile file) async {
  if (await file.length() > 1024 * 1024) {
    throw const FormatException('CSV 超过 1 MB，未导入。');
  }
  try {
    return utf8.decode(await file.readAsBytes());
  } on FormatException {
    throw const FormatException('CSV 不是有效的 UTF-8 文件，请另存为 UTF-8 后重试。');
  }
}
