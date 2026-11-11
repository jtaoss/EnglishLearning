import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:english_learning/integrations/notion/events/event_api.dart';
import 'package:english_learning/integrations/notion/events/event_store.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/android_notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';
import 'package:english_learning/app/open_learning_repository.dart';
import 'package:english_learning/ui/error_state.dart';
import 'package:english_learning/app/config_error_app.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/error/app_error_handler.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment();
  } on ConfigException catch (error) {
    runApp(ConfigErrorApp(message: error.message));
    return;
  }
  final logger = AppLogger(
    name: 'english_learning',
    minimumLevel: config.logLevel,
  );
  AppErrorHandler(logger).install();
  await _start(config, logger);
}

Future<void> _start(AppConfig config, AppLogger logger) async {
  try {
    final learningRepository = await openLearningRepository();
    runApp(
      EnglishLearningApp(
        repository: SharedPreferencesSettingsRepository(),
        logger: logger,
        config: config,
        learningRepository: learningRepository,
        notionMobile: Platform.isAndroid,
        eventController: Platform.isWindows
            ? EventSandboxController(
                openStore: () => EventStore.open(
                  p.join(
                    p.dirname(learningRepository.path),
                    'english_learning_p2a_simulation.sqlite3',
                  ),
                ),
                credentials: WindowsNotionCredentials(eventSandbox: true),
                api: EventApi(http.Client()),
                loadIds: () async => NotionScope(
                  await rootBundle.loadString(
                    'assets/vocabulary/verified100.csv',
                  ),
                ).entries.map((e) => e.id).toList(),
              )
            : null,
        pronunciationServices: PronunciationServices(
          store: learningRepository,
          logger: logger,
          speechFactory: defaultLocalSpeech,
        ),
        notionService: Platform.isWindows || Platform.isAndroid
            ? NotionSyncService(
                store: learningRepository,
                credentials: Platform.isAndroid
                    ? AndroidNotionCredentials()
                    : WindowsNotionCredentials(),
                api: NotionReadApi(http.Client()),
                loadScope: () async {
                  if (!Platform.isWindows) {
                    return NotionScope(
                      await rootBundle.loadString(
                        'assets/vocabulary/verified100.csv',
                      ),
                    );
                  }
                  return NotionScope.withHistoricalPrefix(
                    await rootBundle.loadString(
                      'docs/p5a/public/formal_learning_vocabulary.csv',
                    ),
                    await rootBundle.loadString(
                      'assets/vocabulary/reviewed500.csv',
                    ),
                  );
                },
              )
            : null,
      ),
    );
  } catch (error, stack) {
    logger.error(
      'Local database initialization failed',
      error: error,
      stackTrace: stack,
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(
            title: '本地词库暂时无法打开',
            message: '原有数据未删除。请检查磁盘空间后重试。',
            onRetry: () => _start(config, logger),
          ),
        ),
      ),
    );
  }
}
