import 'package:english_learning/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_log_sink.dart';

void main() {
  test('writes level, name, message, and error to the sink', () {
    final sink = RecordingLogSink();
    final logger = AppLogger(name: 'starter', sink: sink);
    final stack = StackTrace.current;

    logger.info('ready');
    logger.warning('slow');
    logger.error('failed', error: StateError('boom'), stackTrace: stack);

    expect(sink.records, hasLength(3));
    expect(sink.records[0].level, LogLevel.info);
    expect(sink.records[0].name, 'starter');
    expect(sink.records[0].message, 'ready');
    expect(sink.records[1].level, LogLevel.warning);
    expect(sink.records[2].level, LogLevel.error);
    expect(sink.records[2].error, isA<StateError>());
    expect(sink.records[2].stackTrace, same(stack));
  });

  test('drops messages below the configured level', () {
    final sink = RecordingLogSink();
    final logger = AppLogger(sink: sink, minimumLevel: LogLevel.warning);

    logger.debug('trace');
    logger.info('ready');
    logger.warning('slow');

    expect(sink.records.map((record) => record.message), ['slow']);
  });
}
