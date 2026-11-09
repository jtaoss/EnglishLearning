import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

import 'fixtures.dart';

void main() {
  test(
    'the reviewed asset retains 100 verified IDs and explicit AI review status',
    () {
      final rows = VocabularyCsv.parse(
        File('assets/vocabulary/verified100.csv').readAsStringSync(),
      );
      expect(rows.length, 100);
      expect(rows.map((e) => e.id).toSet().length, 100);
      expect(rows.every((e) => e.fields['book_verification'] == '已核验'), isTrue);
      expect(
        rows.every(
          (e) => e.fields['meaning_review_status'] == '来源对照复核（AI）；待个人确认',
        ),
        isTrue,
      );
      expect(rows.every((e) => e.fields['pets2025_status'] == '待核实'), isTrue);
      expect(rows.where((e) => e.libraryClass == '主学习').length, 86);
      expect(rows.every((e) => e.fields['part_of_speech']!.isNotEmpty), isTrue);
      final baselineIds = (jsonDecode(
        File('test/fixtures/vocabulary/verified100_baseline_ids.json')
            .readAsStringSync(),
      ) as List).cast<String>();
      expect(rows.map((e) => e.id).toSet(), baselineIds.toSet());
    },
  );
  test('BOM, quoted commas, escaped quotes and multiline meanings survive', () {
    final input =
        '\uFEFF${encodeEntries([entryFields(meaning: '含义,一\n含义"二"')])}';
    expect(VocabularyCsv.parse(input).single.meaning, '含义,一\n含义"二"');
  });
  for (final column in ['entry_id', 'word', 'meaning_zh']) {
    test('rejects empty $column without manufacturing content', () {
      final row = entryFields()..[column] = '';
      expect(
        () => VocabularyCsv.parse(encodeEntries([row])),
        throwsFormatException,
      );
    });
  }
  test('rejects duplicate IDs and exact word duplicates', () {
    expect(
      () => VocabularyCsv.parse(
        encodeEntries([entryFields(), entryFields(word: 'beta')]),
      ),
      throwsFormatException,
    );
    expect(
      () => VocabularyCsv.parse(
        encodeEntries([
          entryFields(),
          entryFields(id: 'another', word: 'alpha'),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('rejects malformed quotes, missing columns and duplicate headers', () {
    final valid = encodeEntries([entryFields()]);
    for (final damaged in [
      '$valid\n"not closed',
      valid.replaceFirst('entry_id,word', 'entry_id,entry_id'),
      '$valid,extra',
    ]) {
      expect(() => VocabularyCsv.parse(damaged), throwsFormatException);
    }
  });
  test(
    'unverified heads, bad categories and full-library imports are rejected',
    () {
      expect(
        () => VocabularyCsv.parse(
          encodeEntries([entryFields()..['book_verification'] = '待核实']),
        ),
        throwsFormatException,
      );
      expect(
        () => VocabularyCsv.parse(
          encodeEntries([entryFields(library: 'unknown')]),
        ),
        throwsFormatException,
      );
      expect(
        () => VocabularyCsv.parse(
          encodeEntries(
            List.generate(501, (i) => entryFields(id: 'id-$i', word: 'word$i')),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('2025 official claims are refused in this unverified phase', () {
    final row = entryFields()..['pets2025_status'] = '已收录';
    expect(
      () => VocabularyCsv.parse(encodeEntries([row])),
      throwsFormatException,
    );
  });
}
