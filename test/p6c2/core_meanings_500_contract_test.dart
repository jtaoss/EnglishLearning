import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> payload;
  late List<Map<String, dynamic>> records;

  setUpAll(() {
    payload = jsonDecode(
      File('docs/p6/p6c2/core_meanings_500.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    records = (payload['records'] as List).cast<Map<String, dynamic>>();
  });

  test('500 unique formal IDs and original/new cohorts remain separate', () {
    expect(records, hasLength(500));
    expect(records.map((r) => r['stable_id']).toSet(), hasLength(500));
    expect(
      records.where((r) => r['cohort'] == 'inherited_100'),
      hasLength(100),
    );
    expect(records.where((r) => r['cohort'] == 'new_400'), hasLength(400));
  });

  test(
    'future UI can decode required fields without touching learning state',
    () {
      for (final record in records) {
        for (final key in [
          'stable_id',
          'headword',
          'part_of_speech',
          'original_meaning_zh',
          'core_explanation',
          'selection_reason',
          'risk_level',
          'review_status',
          'model_version',
          'prompt_version',
          'source_hash',
        ]) {
          expect(record[key], isA<String>(), reason: key);
          expect((record[key] as String).isNotEmpty, isTrue);
        }
        expect(record['original_meanings'], isA<List<dynamic>>());
        expect(record['supporting_sources'], isA<List<dynamic>>());
        expect(record['dictionary_additions'], isA<List<dynamic>>());
        expect(record['needs_human_review'], isTrue);
        expect(record['human_approved'], isFalse);
        for (final layer in [
          'core_meanings',
          'extended_meanings',
          'other_meanings',
        ]) {
          for (final group in record[layer] as List) {
            expect(group['display_zh'], isA<String>());
            expect(group['part_of_speech'], isA<String>());
            expect(group['source_sense_ids'], isNotEmpty);
            expect(group['source_subsenses'], isNotEmpty);
          }
        }
      }
    },
  );

  test('Unicode source spans and lossless mapping are portable to Dart', () {
    for (final record in records) {
      final text = (record['original_meaning_zh'] as String).runes.toList();
      final original = <String>{};
      for (final atom in record['original_meanings'] as List) {
        original.add(atom['source_sense_id'] as String);
        expect(
          String.fromCharCodes(
            text.sublist(atom['start'] as int, atom['end'] as int),
          ),
          atom['text'],
        );
      }
      final mapped = <String>[];
      for (final layer in [
        'core_meanings',
        'extended_meanings',
        'other_meanings',
      ]) {
        for (final group in record[layer] as List) {
          mapped.addAll((group['source_sense_ids'] as List).cast<String>());
        }
      }
      for (final item in record['reserved_original_items'] as List) {
        mapped.add(item['source_sense_id'] as String);
      }
      expect(mapped.toSet(), original);
      expect(mapped, hasLength(original.length));
    }
  });

  test('dictionary additions are never silently adopted as formal core', () {
    for (final record in records) {
      for (final addition in record['dictionary_additions'] as List) {
        expect(addition['source_sense_ids'], isEmpty);
        expect(addition['evidence_ids'], isNotEmpty);
        expect(addition['human_approved'] ?? false, isFalse);
        expect(addition['auto_promoted_to_core'] ?? false, isFalse);
      }
    }
  });
}
