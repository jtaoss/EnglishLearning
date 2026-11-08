import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Delivers the same `popRoute` message Android sends for the system back key.
Future<void> simulateSystemBack(WidgetTester tester) {
  final message = const JSONMethodCodec().encodeMethodCall(
    const MethodCall('popRoute'),
  );
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    message,
    (ByteData? reply) {},
  );
}
