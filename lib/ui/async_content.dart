import 'package:flutter/material.dart';

/// Which body [AsyncContent] should show.
enum AsyncView { loading, success, empty, error }

/// Switches a screen between loading, success, empty, and error content.
///
/// The widgets are supplied by the caller. This type has no knowledge of a
/// particular feature's data.
final class AsyncContent extends StatelessWidget {
  const AsyncContent({
    required this.view,
    required this.success,
    this.loading,
    this.empty,
    this.error,
    super.key,
  });

  final AsyncView view;
  final Widget success;
  final Widget? loading;
  final Widget? empty;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      AsyncView.loading =>
        loading ??
            const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Loading'),
            ),
      AsyncView.success => success,
      AsyncView.empty => empty ?? const SizedBox.shrink(),
      AsyncView.error => error ?? const SizedBox.shrink(),
    };
  }
}
