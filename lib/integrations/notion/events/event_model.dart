import 'dart:convert';

import 'package:crypto/crypto.dart';

const eventSandboxSource = '3bf5dab6-53fc-4ba8-bcf4-cec0be0addd8';
const eventTestBatch = 'P2A-20261108-v1';
const eventDevice = 'windows-p2a-simulator';

/// Synthetic-only immutable payload. No personal history is accepted in P2-A.
final class LearningEvent {
  LearningEvent({
    required this.id,
    required this.wordId,
    required this.type,
    required this.grade,
    required this.occurredAt,
    required this.sequence,
  }) {
    if (!RegExp(r'^sim-[a-f0-9]{32}$').hasMatch(id) ||
        wordId.isEmpty ||
        sequence < 1 ||
        sequence > 24 ||
        !(type == 'meaning'
                ? ['mastered', 'familiar', 'forgotten']
                : type == 'pronunciation'
                ? ['needsPractice', 'familiar', 'confident']
                : <String>[])
            .contains(grade)) {
      throw const FormatException('Invalid simulation event');
    }
  }
  final String id, wordId, type, grade;
  final DateTime occurredAt;
  final int sequence;
  Map<String, Object> get payload => {
    'event_id': id,
    'word_id': wordId,
    'learning_type': type,
    'grade': grade,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'device_id': eventDevice,
    'device_sequence': sequence,
    'schema_version': 1,
    'algorithm_version': 'simulation-v1',
    'test_batch': eventTestBatch,
    'simulated': true,
  };
  String get hash =>
      sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  factory LearningEvent.decode(String value) {
    final p = jsonDecode(value) as Map<String, dynamic>;
    if (p['simulated'] != true ||
        p['test_batch'] != eventTestBatch ||
        p['device_id'] != eventDevice ||
        p['schema_version'] != 1 ||
        p['algorithm_version'] != 'simulation-v1') {
      throw const FormatException('Unsupported simulation payload');
    }
    return LearningEvent(
      id: p['event_id'] as String,
      wordId: p['word_id'] as String,
      type: p['learning_type'] as String,
      grade: p['grade'] as String,
      occurredAt: DateTime.parse(p['occurred_at'] as String),
      sequence: p['device_sequence'] as int,
    );
  }
  static List<LearningEvent> generate(List<String> wordIds) {
    if (wordIds.toSet().length < 12) {
      throw const FormatException('Need twelve verified IDs');
    }
    return [
      for (var n = 1; n <= 24; n++)
        LearningEvent(
          id: 'sim-${sha256.convert(utf8.encode('$eventTestBatch/$eventDevice/$n')).toString().substring(0, 32)}',
          wordId: wordIds[(n - 1) ~/ 2],
          type: n.isOdd ? 'meaning' : 'pronunciation',
          grade: (n.isOdd
              ? ['mastered', 'familiar', 'forgotten']
              : ['needsPractice', 'familiar', 'confident'])[((n - 1) ~/ 2) % 3],
          occurredAt: DateTime.utc(2026, 11, 8, 10).add(Duration(minutes: n)),
          sequence: n,
        ),
    ];
  }

  @override
  String toString() => 'LearningEvent($id, synthetic payload omitted)';
}

final class QueuedEvent {
  const QueuedEvent(
    this.event,
    this.state,
    this.nextAttempt,
    this.attempts,
    this.remoteId,
  );
  final LearningEvent event;
  final String state;
  final DateTime? nextAttempt;
  final int attempts;
  final String? remoteId;
}

/// Safe errors contain classifications only, never remote bodies/headers.
final class EventFailure implements Exception {
  const EventFailure(this.code, {this.retryAfter, this.ambiguous = false});
  final String code;
  final Duration? retryAfter;
  final bool ambiguous;
  @override
  String toString() => 'EventFailure($code)';
}
