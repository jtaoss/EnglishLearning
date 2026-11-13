import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(
    File('docs/p6/p6c5a/regression_700.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final rows = (data['records'] as List).cast<Map<String, dynamic>>();
  final oldData = jsonDecode(
    File('docs/p6/p6c5/core_meanings_5332_candidates.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final old = {for (final r in oldData['records'] as List) r['stable_id']: r};

  test('scope export contains exactly the existing 700 IDs', () {
    expect(rows, hasLength(700));
    expect(rows.map((r) => r['stable_id']).toSet(), old.keys.toSet());
    expect(data['new_formal_IDs'], 0);
  });

  test('1702 source mappings retain Unicode, POS and traceable targets', () {
    var count = 0;
    const relations = {'语义等价', '合理概括', '范围收窄', '范围扩大', '语义不匹配', '无法确定'};
    for (final r in rows) {
      final c = r['candidate'];
      final runes = (c['original_meaning_zh'] as String).runes.toList();
      final originals = {
        for (final s in c['original_meanings'] as List) s['source_sense_id']: s,
      };
      final mappings = r['source_scope_mappings'] as List;
      expect(mappings.length, originals.length);
      for (final m in mappings) {
        count++;
        final source = originals[m['source_sense_id']];
        expect(m['original_text'], source['text']);
        expect(m['source_pos'], source['part_of_speech']);
        expect(
          String.fromCharCodes(
            runes.sublist(source['start'] as int, source['end'] as int),
          ),
          m['original_text'],
        );
        expect(relations, contains(m['mapping_relation']));
        expect(
          (m['target_links'] as List).isNotEmpty ||
              (m['held_original'] as List).isNotEmpty,
          isTrue,
        );
        expect(m['human_approved'], isFalse);
      }
    }
    expect(count, 1702);
  });

  test('600 reused semantics and all 700 original snapshots remain intact', () {
    for (final r in rows) {
      final c = r['candidate'];
      final b = old[r['stable_id']];
      for (final key in ['source_fields', 'original_meanings', 'source_hash']) {
        expect(c[key], b[key]);
      }
      if (r['cohort'] == 'reused600') {
        for (final key in [
          'core_meanings',
          'extended_meanings',
          'other_meanings',
          'dictionary_additions',
          'reserved_original_items',
        ]) {
          expect(c[key], b[key]);
        }
      }
    }
  });

  test('historical risks and failed review remain isolated', () {
    expect(
      rows.where((r) => r['historical_risk_retained'] == true),
      hasLength(48),
    );
    final pursue = rows.singleWhere((r) => r['headword'] == 'pursue');
    expect(
      pursue['prior_review_status'],
      'review_incomplete_after_bounded_attempts',
    );
    expect(pursue['prior_failure_reconciliation_pending'], isTrue);
    for (final r in rows) {
      expect(r['human_approved'], isFalse);
      expect(r['publication_status'], 'isolated_not_published');
    }
  });
}
