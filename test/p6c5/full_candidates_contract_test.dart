import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = jsonDecode(
    File('docs/p6/p6c5/core_meanings_5332_candidates.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final rows = (data['records'] as List).cast<Map<String, dynamic>>();

  test('candidate IDs are unique, complete or explicitly incomplete', () {
    final ids = rows.map((r) => r['stable_id']).toSet();
    expect(ids.length, rows.length);
    expect(data['record_count'], rows.length);
    expect(rows.length + (data['missing_ids'] as List).length, 5332);
    if (data['generation_complete'] == true) {
      expect(rows, hasLength(5332));
      expect(data['missing_ids'], isEmpty);
    }
  });

  test(
    'all layers are parseable isolated candidates without human signoff',
    () {
      for (final r in rows) {
        expect(r['human_approved'], isFalse);
        expect(r['publication_status'], 'isolated_not_published');
        expect(r['rules_hash'], data['rules_hash']);
        expect(r['stable_id'], r['source_fields']['entry_id']);
        expect(r['headword'], r['source_fields']['word']);
        expect(r['original_meaning_zh'], r['source_fields']['meaning_zh']);
        for (final layer in [
          'core_meanings',
          'extended_meanings',
          'other_meanings',
        ]) {
          expect(r[layer], isA<List<dynamic>>());
        }
      }
    },
  );

  test('all original Unicode spans and layer mappings survive', () {
    for (final r in rows) {
      final original = (r['original_meanings'] as List)
          .cast<Map<String, dynamic>>();
      final sids = original.map((s) => s['source_sense_id']).toSet();
      final runes = (r['original_meaning_zh'] as String).runes.toList();
      for (final a in original) {
        expect(
          String.fromCharCodes(
            runes.sublist(a['start'] as int, a['end'] as int),
          ),
          a['text'],
        );
      }
      final mapped = <dynamic>{};
      for (final layer in [
        'core_meanings',
        'extended_meanings',
        'other_meanings',
      ]) {
        for (final g in r[layer] as List) {
          mapped.addAll(g['source_sense_ids'] as List);
          expect(g['evidence_ids'], isNotEmpty);
          expect(g['display_zh'], isA<String>());
        }
      }
      for (final a in r['reserved_original_items'] as List) {
        mapped.add(a['source_sense_id']);
      }
      expect(mapped, sids);
    }
  });

  test('external senses are never source meanings or adopted approvals', () {
    for (final r in rows) {
      for (final a in r['dictionary_additions'] as List) {
        expect(a['source_sense_ids'], isEmpty);
        expect(a['human_approved'] ?? false, isFalse);
        expect(a['auto_promoted_to_core'] ?? false, isFalse);
      }
    }
  });

  test('historical48 and disputed source gaps are not silently released', () {
    final hist = rows
        .where((r) => r['historical_risk_retained'] == true)
        .toList();
    expect(hist, hasLength(48));
    expect(hist.every((r) => r['needs_human_review'] == true), isTrue);
    for (final w in ['management', 'clause']) {
      final r = rows.singleWhere((r) => r['headword'] == w);
      expect(r['review_status'], 'confirmed_problem_revision_pending');
      expect(r['quarantine'], isA<Map<String, dynamic>>());
    }
  });
}
