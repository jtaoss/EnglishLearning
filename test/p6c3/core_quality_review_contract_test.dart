import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final review = readJson('docs/p6/p6c3/independent_quality_review.json');
  final revised = readJson('docs/p6/p6c3/REVISED_CANDIDATES.json');
  final base = readJson('docs/p6/p6c2/core_meanings_500.json');
  final original = {
    for (final row in base['records'] as List)
      row['stable_id'] as String: row as Map<String, dynamic>,
  };

  test('90 unique reviewed IDs are drawn only from the existing 500', () {
    final rows = (review['records'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(90));
    expect(rows.map((r) => r['stable_id']).toSet(), hasLength(90));
    expect(rows.every((r) => original.containsKey(r['stable_id'])), isTrue);
    expect(
      rows.where((r) => r['selection']['role'] == 'target_major'),
      hasLength(42),
    );
    expect(
      rows.where((r) => r['selection']['role'] == 'stratified_audit'),
      hasLength(48),
    );
  });

  test('revisions preserve source identity and Unicode spans', () {
    expect(revised['records'], hasLength(3));
    for (final entry in revised['records'] as List) {
      final c = entry['candidate'] as Map<String, dynamic>;
      final a = original[c['stable_id']]!;
      for (final key in [
        'headword',
        'part_of_speech',
        'original_meaning_zh',
        'original_meanings',
        'source_fields',
        'source_hash',
      ]) {
        expect(c[key], a[key], reason: key);
      }
      final runes = (c['original_meaning_zh'] as String).runes.toList();
      for (final atom in c['original_meanings'] as List) {
        expect(
          String.fromCharCodes(
            runes.sublist(atom['start'] as int, atom['end'] as int),
          ),
          atom['text'],
        );
      }
      expect(c['model_version'], isA<String>());
      expect(c['prompt_version'], 'P6C3/RULES_V4');
    }
  });

  test(
    'one-to-many use mapping keeps every original and explicit annotation',
    () {
      for (final entry in revised['records'] as List) {
        final c = entry['candidate'] as Map<String, dynamic>;
        final source = {
          for (final atom in c['original_meanings'] as List)
            atom['source_sense_id'] as String,
        };
        final mapped = <String>[];
        for (final layer in [
          'core_meanings',
          'extended_meanings',
          'other_meanings',
        ]) {
          for (final group in c[layer] as List) {
            expect(group['display_zh'], isA<String>());
            expect(group['part_of_speech'], isA<String>());
            expect(group['source_subsenses'], isNotEmpty);
            expect(group['evidence_ids'], isNotEmpty);
            mapped.addAll((group['source_sense_ids'] as List).cast<String>());
          }
        }
        for (final atom in c['reserved_original_items'] as List) {
          mapped.add(atom['source_sense_id'] as String);
        }
        expect(mapped.toSet(), source);
        final repeated = mapped
            .where((s) => mapped.where((v) => v == s).length > 1)
            .toSet();
        final annotated = {
          for (final split in c['semantic_splits'] as List? ?? [])
            split['source_sense_id'] as String,
        };
        expect(annotated.containsAll(repeated), isTrue);
      }
    },
  );

  test('external additions and AI status are never silently adopted', () {
    for (final entry in revised['records'] as List) {
      final c = entry['candidate'];
      expect(entry['adopted'], isFalse);
      expect(entry['human_approved'], isFalse);
      expect(c['needs_human_review'], isTrue);
      expect(c['human_approved'], isFalse);
      for (final addition in c['dictionary_additions'] as List) {
        expect(addition['source_sense_ids'], isEmpty);
        expect(addition['human_approved'] ?? false, isFalse);
        expect(addition['auto_promoted_to_core'] ?? false, isFalse);
      }
    }
    final m = (revised['records'] as List).firstWhere(
      (r) => r['headword'] == 'management',
    )['candidate'];
    expect(m['core_meanings'], original[m['stable_id']]!['core_meanings']);
  });

  test(
    'unresolved legacy queue and model identity limits block false clearance',
    () {
      expect(review['inherited100_pending_queue'], hasLength(48));
      expect(review['not_rechecked_ids'], hasLength(410));
      expect(review['quality_gate']['decision'], 'B');
      expect(review['quality_gate']['expand_remaining_4832_now'], isFalse);
      expect(
        review['independence']['proven_different_model_identity'],
        isFalse,
      );
      expect(
        review['summary']['proven_different_backend_model_disagreement_words'],
        isNull,
      );
    },
  );
}
