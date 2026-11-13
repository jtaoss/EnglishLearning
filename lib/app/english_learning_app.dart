import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_controller.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';

final class EnglishLearningApp extends StatefulWidget {
  const EnglishLearningApp({
    super.key,
    required this.repository,
    required this.logger,
    required this.config,
    this.navigatorKey,
    this.learningRepository,
    this.clock,
    this.pronunciationServices,
    this.notionService,
    this.eventController,
    this.notionMobile = false,
  });
  final SettingsRepository repository;
  final AppLogger logger;
  final AppConfig config;
  final GlobalKey<NavigatorState>? navigatorKey;
  final LearningRepository? learningRepository;
  final DateTime Function()? clock;
  final PronunciationServices? pronunciationServices;
  final NotionSyncService? notionService;
  final EventSandboxController? eventController;
  final bool notionMobile;
  @override
  State<EnglishLearningApp> createState() => _EnglishLearningAppState();
}

class _EnglishLearningAppState extends State<EnglishLearningApp>
    with WidgetsBindingObserver {
  late final AppSettings _settings = AppSettings(repository: widget.repository);
  late final VocabularyController? _vocabulary =
      widget.learningRepository == null
      ? null
      : VocabularyController(
          widget.learningRepository!,
          widget.logger,
          clock: widget.clock,
        );
  late final NotionSyncController? _notion =
      widget.notionService == null || _vocabulary == null
      ? null
      : NotionSyncController(
          widget.notionService!,
          refreshVocabulary: _vocabulary.refresh,
          isMobile: widget.notionMobile,
          storageLabel: widget.notionMobile
              ? 'Android Keystore 加密存储'
              : 'Windows 凭据管理器',
        );
  late final JapaneseController _japaneseController = JapaneseController();
  late final GoRouter _router = AppRouter.create(
    appSettings: _settings,
    environmentLabel: AppConfig.debugLabel(
      widget.config.environment,
      debugMode: kDebugMode,
    ),
    navigatorKey: widget.navigatorKey,
    vocabularyController: _vocabulary,
    pronunciationServices: widget.pronunciationServices,
    notionController: _notion,
    eventController: widget.eventController,
    japaneseController: _japaneseController,
    allowCsvImport: !widget.notionMobile,
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.logger.info('English learning shell ready');
    unawaited(_settings.restore());
    unawaited(_japaneseController.initialize());
    if (_vocabulary != null) unawaited(_vocabulary.refresh());
    if (_notion != null) unawaited(_notion.restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _japaneseController.dispose();
    _vocabulary?.dispose();
    _notion?.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _vocabulary != null) {
      unawaited(_vocabulary.refresh());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, child) => MaterialApp.router(
      title: AppMetadata.title,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _settings.themeMode,
      routerConfig: _router,
    ),
  );
}
