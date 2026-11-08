import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';

final class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key, required this.path});

  final String path;

  static const Key homeKey = Key('not-found-home');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No page matches $path.'),
            const SizedBox(height: 16),
            FilledButton(
              key: homeKey,
              onPressed: () => context.go(AppRouter.home),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}
