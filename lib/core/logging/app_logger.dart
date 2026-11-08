import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

final class LogRecord {
  const LogRecord({
    required this.level,
    required this.name,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;
  final String name;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

abstract interface class LogSink {
  void write(LogRecord record);
}

final class DeveloperLogSink implements LogSink {
  const DeveloperLogSink();

  @override
  void write(LogRecord record) {
    developer.log(
      record.message,
      name: record.name,
      level: switch (record.level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}

final class AppLogger {
  AppLogger({
    this.name = 'app',
    LogSink? sink,
    this.minimumLevel = LogLevel.debug,
  }) : _sink = sink ?? const DeveloperLogSink();

  final String name;
  final LogLevel minimumLevel;
  final LogSink _sink;

  void debug(String message) {
    _write(LogLevel.debug, message);
  }

  void info(String message) {
    _write(LogLevel.info, message);
  }

  void warning(String message) {
    _write(LogLevel.warning, message);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _write(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  void _write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) {
      return;
    }
    _sink.write(
      LogRecord(
        level: level,
        name: name,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
