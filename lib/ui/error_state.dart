import 'package:flutter/material.dart';

/// Centered error message with an optional retry action.
final class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.retryKey,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      semanticLabel: title,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    if (onRetry != null) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        key: retryKey,
                        onPressed: onRetry,
                        child: Text(retryLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
