import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Isolated review data only. No learning repository or synchronization API.
final class MeaningGroup {
  const MeaningGroup(this.partOfSpeech, this.glosses);
  final String partOfSpeech;
  final List<String> glosses;
}

final class CoreMeaningSample {
  CoreMeaningSample._(Map<String, dynamic> json)
    : id = json['stable_id'] as String,
      headword = json['headword'] as String,
      originalMeaning = json['original_meaning_zh'] as String,
      explanation = json['core_explanation'] as String,
      reason = json['selection_reason'] as String,
      sourceHash = json['source_hash'] as String,
      confidence = (json['confidence'] as num).toDouble(),
      core = _groups(json['core_meanings']),
      extended = _groups(json['extended_meanings']),
      other = _groups(json['other_meanings']);

  final String id, headword, originalMeaning, explanation, reason, sourceHash;
  final double confidence;
  final List<MeaningGroup> core, extended, other;

  static List<MeaningGroup> _groups(Object? value) => List.unmodifiable([
    for (final item in value as List<dynamic>)
      MeaningGroup(
        (item as Map<String, dynamic>)['part_of_speech'] as String,
        List<String>.unmodifiable(
          (item['glosses'] as List<dynamic>).cast<String>(),
        ),
      ),
  ]);
}

final class CoreMeaningPilotBundle {
  CoreMeaningPilotBundle._(this.samples);
  final List<CoreMeaningSample> samples;

  /// Reject incomplete, stale, mixed-source or accidentally approved payloads.
  /// Hashes detect drift; they do not establish semantic correctness.
  factory CoreMeaningPilotBundle.decode(String text) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['schema_version'] != 2 ||
          data['publication_status'] != 'isolated_draft_not_approved' ||
          data['record_count'] != 100) {
        throw const FormatException();
      }
      final records = (data['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final ids = <String>{};
      final cohorts = <String, int>{};
      for (final record in records) {
        final source = record['source_fields'] as Map<String, dynamic>;
        final decision = Map<String, dynamic>.of(record)
          ..remove('decision_hash');
        final confidence = record['confidence'] as num;
        if (!ids.add(record['stable_id'] as String) ||
            record['stable_id'] != source['entry_id'] ||
            record['headword'] != source['word'] ||
            record['part_of_speech'] != source['part_of_speech'] ||
            record['original_meaning_zh'] != source['meaning_zh'] ||
            record['source_hash'] != _hash(source) ||
            record['decision_hash'] != _hash(decision) ||
            record['review_required'] != true ||
            record['human_review_status'] != 'pending' ||
            record['official_exam_focus'] != false ||
            (record['model_added_senses'] as List<dynamic>).isNotEmpty ||
            !confidence.isFinite ||
            confidence < 0 ||
            confidence > 1) {
          throw const FormatException();
        }
        final cohort = record['cohort'] as String;
        cohorts[cohort] = (cohorts[cohort] ?? 0) + 1;
        for (final key in [
          'core_meanings',
          'extended_meanings',
          'other_meanings',
        ]) {
          for (final group in record[key] as List<dynamic>) {
            final g = group as Map<String, dynamic>;
            if (g['origin'] != 'formal_gloss' ||
                (g['glosses'] as List<dynamic>).isEmpty) {
              throw const FormatException();
            }
          }
        }
        if ((record['core_meanings'] as List<dynamic>).isEmpty) {
          throw const FormatException();
        }
      }
      const names = {
        'simple',
        'polyseme',
        'complex_pos',
        'high_frequency',
        'random',
      };
      if (records.length != 100 ||
          cohorts.length != names.length ||
          !names.every((name) => cohorts[name] == 20)) {
        throw const FormatException();
      }
      return CoreMeaningPilotBundle._(
        List.unmodifiable(records.map(CoreMeaningSample._)),
      );
    } catch (_) {
      throw const FormatException('试点文件不完整、已变更或超出隔离草稿范围。');
    }
  }

  static String _hash(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  static Object? _canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List<dynamic>) return value.map(_canonical).toList();
    return value;
  }
}
