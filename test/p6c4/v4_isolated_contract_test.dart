import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final reg = readJson('docs/p6/p6c4/regression_500.json');
  final blind = readJson('docs/p6/p6c4/blind_test_100.json');
  final old = readJson('docs/p6/p6c2/core_meanings_500.json');
  final originals = {for (final r in old['records'] as List) r['stable_id']: r};
  final regRows = (reg['records'] as List).cast<Map<String, dynamic>>();
  final newRows = (blind['records'] as List).cast<Map<String, dynamic>>();

  test('500 regression and fresh100 remain disjoint isolated datasets', () {
    expect(regRows, hasLength(500));
    expect(newRows, hasLength(100));
    final a = regRows.map((r) => r['stable_id']).toSet();
    final b = newRows.map((r) => r['stable_id']).toSet();
    expect(a, hasLength(500));
    expect(b, hasLength(100));
    expect(a.intersection(b), isEmpty);
    final strata = <String, int>{};
    for (final row in newRows) {
      final name = row['stratum'] as String;
      strata[name] = (strata[name] ?? 0) + 1;
    }
    expect(strata, hasLength(5));
    expect(strata.values.every((n) => n == 20), isTrue);
  });

  test('all original fields and Unicode spans remain parseable and intact', () {
    for (final row in [...regRows, ...newRows]) {
      final c = row['candidate'] as Map<String, dynamic>;
      final before = originals[c['stable_id']] ?? row['initial_generation'];
      for (final key in [
        'headword',
        'part_of_speech',
        'source_hash',
        'source_fields',
        'original_meaning_zh',
        'original_meanings',
      ]) {
        expect(c[key], before[key], reason: key);
      }
      final runes = (c['original_meaning_zh'] as String).runes.toList();
      for (final a in c['original_meanings'] as List) {
        expect(
          String.fromCharCodes(
            runes.sublist(a['start'] as int, a['end'] as int),
          ),
          a['text'],
        );
      }
    }
  });

  test('one-to-many annotation retains all original references', () {
    for (final row in [...regRows, ...newRows]) {
      final c = row['candidate'];
      final source = {
        for (final a in c['original_meanings'] as List) a['source_sense_id'],
      };
      final refs = <String>[];
      for (final layer in [
        'core_meanings',
        'extended_meanings',
        'other_meanings',
      ]) {
        for (final g in c[layer] as List) {
          refs.addAll((g['source_sense_ids'] as List).cast<String>());
          expect(g['display_zh'], isA<String>());
          expect(g['evidence_ids'], isNotEmpty);
        }
      }
      for (final a in c['reserved_original_items'] as List) {
        refs.add(a['source_sense_id'] as String);
      }
      expect(refs.toSet(), source);
      final repeated = refs
          .where((r) => refs.where((v) => v == r).length > 1)
          .toSet();
      final annotated = {
        for (final s in c['semantic_splits'] as List? ?? [])
          s['source_sense_id'],
      };
      expect(annotated.containsAll(repeated), isTrue);
    }
  });

  test('dictionary candidates and historical risks are not approvals', () {
    expect(reg['historical48_review'], hasLength(48));
    for (final r in reg['historical48_review'] as List) {
      expect(r['status'], 'pending_not_auto_passed');
      expect(r['historical_risk_retained'], isTrue);
    }
    for (final row in [...regRows, ...newRows]) {
      final c = row['candidate'];
      expect(c['human_approved'], isFalse);
      expect(c['needs_human_review'], isTrue);
      for (final a in c['dictionary_additions'] as List) {
        expect(a['source_sense_ids'], isEmpty);
        expect(a['human_approved'] ?? false, isFalse);
        expect(a['auto_promoted_to_core'] ?? false, isFalse);
      }
    }
  });

  test('clause correction keeps raw source and holds general replacement', () {
    final row = newRows.firstWhere((r) => r['headword'] == 'clause');
    final c = row['candidate'];
    expect(
      (row['initial_generation']['core_meanings'] as List).any(
        (g) => (g['source_sense_ids'] as List).contains('s001'),
      ),
      isTrue,
    );
    expect(
      (c['core_meanings'] as List).any(
        (g) => (g['source_sense_ids'] as List).contains('s001'),
      ),
      isFalse,
    );
    expect(
      (c['reserved_original_items'] as List).any((a) => a['text'] == '从句'),
      isTrue,
    );
    expect(
      (c['dictionary_additions'] as List).any(
        (a) => (a['meaning_zh'] as String).contains('分句'),
      ),
      isTrue,
    );
  });

  test('gate allows only isolated scale and preserves backend uncertainty', () {
    final gate = readJson('docs/p6/p6c4/GATE_RESULT.json');
    expect(gate['decision'], 'A');
    expect((gate['checks'] as Map).values.every((v) => v == true), isTrue);
    expect(gate['source_gaps_still_pending'], hasLength(2));
    expect(gate['different_backend_model_proven'], isFalse);
    expect(gate['remaining_full_run_started'], isFalse);
    expect(gate['actually_unprocessed_after_this_task'], 4732);
  });
}
