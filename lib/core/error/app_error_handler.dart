import 'package:flutter/foundation.dart';
import 'package:english_learning/core/logging/app_logger.dart';

/// Records framework and uncaught async errors through [AppLogger].
final class AppErrorHandler {
  AppErrorHandler(this.logger);

  final AppLogger logger;

  void install() {
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      handleFlutterError(details);
      previousFlutterOnError?.call(details);
    };
    PlatformDispatcher.instance.onError = handleAsyncError;
  }

  void handleFlutterError(FlutterErrorDetails details) {
    logger.error(
      details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
  }

  bool handleAsyncError(Object error, StackTrace stackTrace) {
    logger.error(
      'Uncaught asynchronous error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  }
}
