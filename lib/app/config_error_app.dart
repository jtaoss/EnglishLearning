import 'package:flutter/material.dart';

/// Shown when startup configuration is missing or invalid.
final class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({required this.message, super.key});

  final String message;

  static const Key messageKey = Key('config-error');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, key: messageKey),
          ),
        ),
      ),
    );
  }
}
