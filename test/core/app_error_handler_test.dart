import 'package:flutter/foundation.dart';
import 'package:english_learning/core/error/app_error_handler.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_log_sink.dart';

void main() {
  test('records framework and async errors', () {
    final sink = RecordingLogSink();
    final handler = AppErrorHandler(AppLogger(sink: sink));
    final stack = StackTrace.current;

    handler.handleFlutterError(
      FlutterErrorDetails(exception: StateError('framework'), stack: stack),
    );
    final handled = handler.handleAsyncError(StateError('async'), stack);

    expect(handled, isTrue);
    expect(sink.records, hasLength(2));
    expect(sink.records[0].message, contains('framework'));
    expect(sink.records[0].error, isA<StateError>());
    expect(sink.records[1].message, 'Uncaught asynchronous error');
    expect(sink.records[1].stackTrace, same(stack));
  });

  test('install forwards framework errors to the previous handler', () {
    final sink = RecordingLogSink();
    final handler = AppErrorHandler(AppLogger(sink: sink));
    final previousFlutterOnError = FlutterError.onError;
    final previousAsyncOnError = PlatformDispatcher.instance.onError;
    var forwarded = false;

    FlutterError.onError = (FlutterErrorDetails details) {
      forwarded = true;
    };
    addTearDown(() {
      FlutterError.onError = previousFlutterOnError;
      PlatformDispatcher.instance.onError = previousAsyncOnError;
    });

    handler.install();
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('installed')),
    );

    final asyncHandled = PlatformDispatcher.instance.onError?.call(
      StateError('async-installed'),
      StackTrace.current,
    );

    expect(forwarded, isTrue);
    expect(asyncHandled, isTrue);
    expect(sink.records, hasLength(2));
    expect(sink.records.first.error, isA<StateError>());
    expect(sink.records.last.message, 'Uncaught asynchronous error');
  });
}
