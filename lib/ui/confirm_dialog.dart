import 'package:flutter/material.dart';

/// Asks the user to confirm or dismiss an action.
///
/// Returns `true` only when the confirm button is pressed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      );
    },
  ).then((bool? value) => value ?? false);
}

final class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  static const Key confirmKey = Key('confirm-dialog-accept');
  static const Key cancelKey = Key('confirm-dialog-cancel');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
