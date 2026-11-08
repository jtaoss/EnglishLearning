import 'package:english_learning/ui/async_content.dart';
import 'package:english_learning/ui/confirm_dialog.dart';
import 'package:english_learning/ui/empty_state.dart';
import 'package:english_learning/ui/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('async content switches loading, empty, error and success', (
    tester,
  ) async {
    final view = ValueNotifier(AsyncView.loading);
    addTearDown(view.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<AsyncView>(
            valueListenable: view,
            builder: (context, value, child) => AsyncContent(
              view: value,
              success: const Text('Loaded record'),
              empty: const EmptyState(
                title: 'No records',
                message: 'Import a verified sample to continue.',
              ),
              error: ErrorState(
                title: 'Load failed',
                message: 'Try again.',
                onRetry: () => view.value = AsyncView.loading,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    view.value = AsyncView.empty;
    await tester.pump();
    expect(find.text('No records'), findsOneWidget);
    expect(find.text('Loaded record'), findsNothing);
    view.value = AsyncView.error;
    await tester.pump();
    expect(find.text('Load failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    view.value = AsyncView.success;
    await tester.pump();
    expect(find.text('Loaded record'), findsOneWidget);
    expect(find.text('Load failed'), findsNothing);
  });

  testWidgets('empty-state action remains reachable in a small window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            title: 'No vocabulary available yet',
            message:
                'Import verified records before starting a learning session.',
            actionLabel: 'Import sample',
            onAction: () => actions++,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Import sample'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import sample'));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error-state retry invokes the caller action once', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(
            title: 'Storage unavailable',
            message: 'Local records have not been changed.',
            retryLabel: 'Reload',
            retryKey: const Key('reload-storage'),
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reload-storage')));
    expect(retries, 1);
  });

  for (final action in ['confirm', 'cancel', 'dismiss']) {
    testWidgets('confirmation dialog returns the correct result for $action', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showConfirmDialog(
                    context,
                    title: 'Replace sample?',
                    message: 'Existing learning progress will be preserved.',
                  );
                },
                child: const Text('Open confirmation'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open confirmation'));
      await tester.pumpAndSettle();
      if (action == 'confirm') {
        await tester.tap(find.byKey(ConfirmDialog.confirmKey));
      } else if (action == 'cancel') {
        await tester.tap(find.byKey(ConfirmDialog.cancelKey));
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(result, action == 'confirm');
      expect(find.byType(ConfirmDialog), findsNothing);
    });
  }
}
