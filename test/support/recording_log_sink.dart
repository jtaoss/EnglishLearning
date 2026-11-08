import 'package:english_learning/core/logging/app_logger.dart';

final class RecordingLogSink implements LogSink {
  final List<LogRecord> records = <LogRecord>[];

  @override
  void write(LogRecord record) {
    records.add(record);
  }
}
