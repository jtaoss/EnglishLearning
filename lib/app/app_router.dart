import 'package:flutter/widgets.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:english_learning/app/not_found_page.dart';
import 'package:english_learning/features/home/home_page.dart';
import 'package:english_learning/features/settings/settings_page.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_list_page.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/integrations/notion/notion_sync_page.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_controller.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_page.dart';

abstract final class AppRouter {
  static const String home = '/';
  static const String settings = '/settings';
  static const String vocabulary = '/vocabulary';
  static const String pronunciation = '/pronunciation';
  static const String notion = '/notion-sync';
  static const String eventSandbox = '/event-sandbox';
  static String pronunciationWordPath(String id) =>
      '$pronunciation/${Uri.encodeComponent(id)}';
  static String wordPath(String id) => '$vocabulary/${Uri.encodeComponent(id)}';
  static GoRouter create({
    required AppSettings appSettings,
    String? environmentLabel,
    GlobalKey<NavigatorState>? navigatorKey,
    VocabularyController? vocabularyController,
    PronunciationServices? pronunciationServices,
    NotionSyncController? notionController,
    EventSandboxController? eventController,
    bool allowCsvImport = true,
  }) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: home,
    debugLogDiagnostics: false,
    errorBuilder: (context, state) => NotFoundPage(path: state.uri.path),
    routes: <RouteBase>[
      GoRoute(
        path: home,
        builder: (context, state) => HomePage(
          environmentLabel: environmentLabel,
          vocabulary: vocabularyController,
          hasEventSandbox: eventController != null,
          allowCsvImport: allowCsvImport,
        ),
      ),
      GoRoute(
        path: settings,
        builder: (context, state) => SettingsPage(settings: appSettings),
      ),
      if (vocabularyController != null) ...[
        GoRoute(
          path: vocabulary,
          builder: (context, state) => VocabularyPage(
            controller: vocabularyController,
            hasPronunciation: pronunciationServices != null,
            hasNotion: notionController != null,
            allowCsvImport: allowCsvImport,
          ),
        ),
        GoRoute(
          path: '$vocabulary/:entryId',
          builder: (context, state) => ReviewPage(
            key: ValueKey(state.pathParameters['entryId']),
            controller: vocabularyController,
            entryId: state.pathParameters['entryId']!,
            hasPronunciation: pronunciationServices != null,
          ),
        ),
        if (pronunciationServices != null) ...[
          GoRoute(
            path: pronunciation,
            builder: (context, state) => PronunciationListPage(
              services: pronunciationServices,
              vocabulary: vocabularyController,
            ),
          ),
          GoRoute(
            path: '$pronunciation/:entryId',
            builder: (context, state) {
              final id = state.pathParameters['entryId']!;
              final word = vocabularyController.find(id);
              return word == null
                  ? NotFoundPage(path: state.uri.path)
                  : PronunciationPage(
                      key: ValueKey(id),
                      entryId: id,
                      word: word.entry.word,
                      services: pronunciationServices,
                    );
            },
          ),
        ],
      ],
      if (eventController != null)
        GoRoute(
          path: eventSandbox,
          builder: (context, state) =>
              EventSandboxPage(controller: eventController),
        ),
      if (notionController != null)
        GoRoute(
          path: notion,
          builder: (context, state) =>
              NotionSyncPage(controller: notionController),
        ),
    ],
  );
}
