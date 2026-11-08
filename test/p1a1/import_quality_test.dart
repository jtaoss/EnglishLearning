import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_import_source.dart';

import '../p1a/fixtures.dart';

class SelectorStub extends FileSelectorPlatform {
  XFile? result;
  List<XTypeGroup>? filters;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    filters = acceptedTypeGroups;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy CSV remains valid and optional POS/notes are retained', () {
    expect(
      VocabularyCsv.parse(encodeEntries([entryFields()])).single.id,
      'test-alpha',
    );
    final fields = {
      ...entryFields(),
      'part_of_speech': '名词',
      'usage_note': '独立说明',
      'lexical_sources': 'https://wordnet.princeton.edu/',
    };
    final csv = Csv().encode([fields.keys.toList(), fields.values.toList()]);
    final entry = VocabularyCsv.parse(csv).single;
    expect(entry.fields['part_of_speech'], '名词');
    expect(entry.fields['usage_note'], '独立说明');
    final reversed = fields.keys.toList().reversed.toList();
    final reordered = Csv().encode([
      reversed,
      [for (final k in reversed) fields[k]],
    ]);
    expect(
      jsonEncode(VocabularyCsv.parse(reordered).single.fields),
      jsonEncode(entry.fields),
    );
  });
  test(
    'empty, whitespace-only, header-only and binary-text inputs are rejected',
    () {
      for (final text in [
        '',
        '  \r\n',
        '\uFEFF',
        VocabularyCsv.columns.join(','),
        '\u0000',
      ]) {
        expect(() => VocabularyCsv.parse(text), throwsFormatException);
      }
    },
  );
  test('the import size limit counts UTF-8 bytes rather than characters', () {
    final text = encodeEntries([entryFields(meaning: '中' * 400000)]);
    expect(text.length, lessThan(1024 * 1024));
    expect(utf8.encode(text).length, greaterThan(1024 * 1024));
    expect(() => VocabularyCsv.parse(text), throwsFormatException);
  });
  test(
    'selector contract on Android covers CSV MIME and cancellation',
    () async {
      final previous = FileSelectorPlatform.instance;
      final selector = SelectorStub();
      FileSelectorPlatform.instance = selector;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        FileSelectorPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
      });
      expect(await pickVocabularyCsv(), isNull);
      expect(selector.filters!.single.extensions, contains('csv'));
      expect(selector.filters!.single.mimeTypes, contains('text/csv'));
      selector.result = XFile.fromData(
        Uint8List.fromList(utf8.encode(encodeEntries([entryFields()]))),
        name: 'sample.csv',
      );
      expect(
        VocabularyCsv.parse((await pickVocabularyCsv())!).single.id,
        'test-alpha',
      );
    },
  );
  test(
    'invalid UTF-8 and oversized selected files return clear errors',
    () async {
      await expectLater(
        readVocabularyCsvFile(
          XFile.fromData(Uint8List.fromList([0xff, 0xfe]), name: 'bad.csv'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
      await expectLater(
        readVocabularyCsvFile(
          XFile.fromData(Uint8List(1024 * 1024 + 1), name: 'large.csv'),
        ),
        throwsFormatException,
      );
    },
  );
}
