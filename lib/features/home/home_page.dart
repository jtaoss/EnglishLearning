import 'package:flutter/material.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/empty_state.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/study_queue.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';

final class HomePage extends StatelessWidget {
  const HomePage({
    this.environmentLabel,
    this.vocabulary,
    this.notion,
    this.hasPronunciation = false,
    this.hasEventSandbox = false,
    this.allowCsvImport = true,
    super.key,
  });
  final bool hasEventSandbox;
  final bool hasPronunciation;
  final bool allowCsvImport;
  final String? environmentLabel;
  final VocabularyController? vocabulary;
  final NotionSyncController? notion;
  static const Key openSettingsKey = Key('open-settings');
  static const Key environmentKey = Key('app-environment');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppMetadata.title),
        actions: [
          if (MediaQuery.sizeOf(context).width > 360)
            IconButton(
              key: const Key('switch-to-japanese'),
              tooltip: '日本語 / 日语',
              onPressed: () => context.push(AppRouter.japaneseHome),
              icon: const Icon(Icons.translate_rounded),
            ),
          IconButton(
            key: openSettingsKey,
            tooltip: '设置',
            onPressed: () => context.push(AppRouter.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                if (environmentLabel != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(
                        label: environmentLabel!,
                        status: 'neutral',
                        textKey: environmentKey,
                      ),
                    ),
                  ),
                if (vocabulary == null)
                  const Expanded(
                    child: EmptyState(
                      title: '还没有学习词库',
                      message: '词库准备好后，可以从这里开始学习。',
                    ),
                  ),
                if (vocabulary != null)
                  Expanded(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([vocabulary!, ?notion]),
                      builder: (context, _) {
                        final v = vocabulary!;
                        final now = v.nowUtc;
                        final words = v.words;
                        final stats = v.dashboardStats(now);
                        final allDue = v.dueWords(now, libraryClass: null);
                        final dueReviewCount = stats.dueReviewCount;
                        final newLearnableCount = stats.newLearnableCount;
                        final studiedCount = stats.studiedCount;
                        final untestedCount = stats.untestedCount;
                        final weakWordsCount = stats.weakWordsCount;
                        final completedTodayCount = stats.completedTodayCount;
                        final remainingReviewCount = stats.remainingReviewCount;
                        final notYetDueCount = stats.notYetDueCount;

                        StudyWord? nextNew;
                        for (final word in allDue) {
                          if (!isScheduledReview(word, now)) {
                            nextNew = word;
                            break;
                          }
                        }
                        final mainCount = stats.coreCount;
                        final extensionCount = stats.extensionCount;
                        final pausedCount =
                            words.length - mainCount - extensionCount;
                        // Scope size comes from the bundled, accepted sync
                        // scope; local size comes from SQLite. Never invented.
                        final scopeKnown = notion?.scopeLoaded ?? false;
                        final scopeLength = notion?.scopeLength ?? 0;
                        final libraryIncomplete =
                            scopeKnown &&
                            words.isNotEmpty &&
                            words.length < scopeLength;
                        final libraryComplete =
                            scopeKnown &&
                            words.isNotEmpty &&
                            words.length >= scopeLength;

                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (v.busy)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: LinearProgressIndicator(),
                                ),
                              if (v.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: StatusBanner(
                                    message: v.error!,
                                    tone: BannerTone.danger,
                                    trailing: TextButton(
                                      onPressed: v.busy ? null : v.refresh,
                                      child: const Text('重试读取'),
                                    ),
                                  ),
                                ),

                              // 1. Primary Hero Card: Start Today's Study
                              SectionCard(
                                padding: const EdgeInsets.all(24),
                                borderColor: scheme.primary.withValues(
                                  alpha: 0.35,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '每天一点，离线也能继续',
                                              style:
                                                  theme.textTheme.headlineSmall,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '本地词库：${formatCount(words.length)} 词',
                                              key: const Key('local-total'),
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '主学习 ${formatCount(mainCount)} · 扩展 ${formatCount(extensionCount)}'
                                              '${pausedCount > 0 ? ' · 暂缓 ${formatCount(pausedCount)}' : ''}'
                                              ' · 可学习未测试 / 到期 ${formatCount(allDue.length)} 词',
                                              key: const Key(
                                                'library-class-counts',
                                              ),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                            if (nextNew != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                '当前新词阶段：${BookStudyOrder.stageLabel(nextNew.entry.fields['book_category'])}',
                                                key: const Key(
                                                  'new-word-stage',
                                                ),
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        StatusBadge(
                                          label: allDue.isNotEmpty
                                              ? '待处理 ${formatCount(allDue.length)} 词'
                                              : words.isEmpty
                                              ? '词库待导入'
                                              : '今日已完成',
                                          colors: allDue.isNotEmpty
                                              ? AppTheme.infoColors(brightness)
                                              : AppTheme.masteredColors(
                                                  brightness,
                                                ),
                                          icon: allDue.isNotEmpty
                                              ? Icons.schedule_outlined
                                              : Icons.check_circle_outline,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Focused Metrics Grid: Due Today vs Learnable New vs Studied Overview
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final isWide =
                                            constraints.maxWidth >= 640;
                                        final cards = <Widget>[
                                          _MetricTile(
                                            label: '今日待复习（到期）',
                                            value: formatCount(dueReviewCount),
                                            valueKey: const Key(
                                              'metric-due-review',
                                            ),
                                            unit: '词',
                                            caption: dueReviewCount > 0
                                                ? '优先复习已学到期与发音待练词'
                                                : '当前无已学到期词',
                                            accent: dueReviewCount > 0
                                                ? AppTheme.familiarColors(
                                                    brightness,
                                                  ).foreground
                                                : scheme.onSurface,
                                          ),
                                          _MetricTile(
                                            label: '未测试单词',
                                            value: formatCount(untestedCount),
                                            valueKey: const Key(
                                              'metric-untested',
                                            ),
                                            unit: '词',
                                            caption:
                                                '可学新词 ${formatCount(newLearnableCount)} 词 · 未到期 ${formatCount(notYetDueCount)} 词',
                                            accent: scheme.primary,
                                          ),
                                          _MetricTile(
                                            label: '已学单词',
                                            value: formatCount(studiedCount),
                                            valueKey: const Key(
                                              'metric-studied',
                                            ),
                                            unit: '词',
                                            caption:
                                                '掌握 ${formatCount(stats.masteredCount)} · 眼熟 ${formatCount(stats.familiarCount)} · 遗忘 ${formatCount(stats.forgottenCount)}',
                                            accent: AppTheme.masteredColors(
                                              brightness,
                                            ).foreground,
                                          ),
                                        ];
                                        if (isWide) {
                                          return Row(
                                            children: [
                                              Expanded(child: cards[0]),
                                              const SizedBox(width: 12),
                                              Expanded(child: cards[1]),
                                              const SizedBox(width: 12),
                                              Expanded(child: cards[2]),
                                            ],
                                          );
                                        }
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            cards[0],
                                            const SizedBox(height: 10),
                                            cards[1],
                                            const SizedBox(height: 10),
                                            cards[2],
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // Review Center Detail Badges
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        StatusBadge(
                                          label:
                                              '今日已完成：${formatCount(completedTodayCount)} 词',
                                          status: completedTodayCount > 0
                                              ? 'mastered'
                                              : 'neutral',
                                          textKey: const Key(
                                            'metric-completed-today',
                                          ),
                                        ),
                                        StatusBadge(
                                          label:
                                              '今日剩余：${formatCount(remainingReviewCount)} 词',
                                          status: remainingReviewCount > 0
                                              ? 'familiar'
                                              : 'neutral',
                                          textKey: const Key(
                                            'metric-remaining-review',
                                          ),
                                        ),
                                        StatusBadge(
                                          label:
                                              '未到期：${formatCount(notYetDueCount)} 词',
                                          status: 'neutral',
                                          textKey: const Key(
                                            'metric-not-yet-due',
                                          ),
                                        ),
                                        StatusBadge(
                                          label:
                                              '薄弱词：${formatCount(weakWordsCount)} 词',
                                          status: weakWordsCount > 0
                                              ? 'forgotten'
                                              : 'neutral',
                                          textKey: const Key(
                                            'metric-weak-words',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    if (dueReviewCount == 0 &&
                                        words.isNotEmpty) ...[
                                      Text(
                                        '今天暂无到期复习，先去学习一些新词吧。',
                                        key: const Key('no-due-review-hint'),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: scheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],

                                    // Primary & Secondary Action Bar
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (dueReviewCount > 0)
                                          FilledButton.icon(
                                            key: const Key('start-due-review'),
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 24,
                                                    vertical: 14,
                                                  ),
                                            ),
                                            onPressed: v.busy
                                                ? null
                                                : () => context.push(
                                                    AppRouter.reviewDue,
                                                  ),
                                            icon: const Icon(
                                              Icons
                                                  .replay_circle_filled_outlined,
                                            ),
                                            label: Text(
                                              '开始今日到期复习（$dueReviewCount 词）',
                                            ),
                                          )
                                        else
                                          OutlinedButton.icon(
                                            key: const Key('start-due-review'),
                                            onPressed: v.busy
                                                ? null
                                                : () => context.push(
                                                    AppRouter.reviewDue,
                                                  ),
                                            icon: const Icon(
                                              Icons.event_available_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('今日到期复习（0 词）'),
                                          ),
                                        if (newLearnableCount > 0)
                                          FilledButton.icon(
                                            key: const Key('start-new-words'),
                                            style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  dueReviewCount == 0
                                                  ? scheme.primary
                                                  : scheme.secondaryContainer,
                                              foregroundColor:
                                                  dueReviewCount == 0
                                                  ? scheme.onPrimary
                                                  : scheme.onSecondaryContainer,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 14,
                                                  ),
                                            ),
                                            onPressed: v.busy
                                                ? null
                                                : () {
                                                    if (nextNew != null) {
                                                      context.push(
                                                        AppRouter.wordPath(
                                                          nextNew.entry.id,
                                                        ),
                                                      );
                                                    } else {
                                                      context.push(
                                                        AppRouter.vocabulary,
                                                      );
                                                    }
                                                  },
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                            label: Text(
                                              '学习新词（$newLearnableCount 词）',
                                            ),
                                          ),
                                        if (weakWordsCount > 0)
                                          OutlinedButton.icon(
                                            key: const Key('start-weak-review'),
                                            onPressed: v.busy
                                                ? null
                                                : () => context.push(
                                                    AppRouter.reviewWeak,
                                                  ),
                                            icon: const Icon(
                                              Icons.fitness_center_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              '薄弱词巩固（$weakWordsCount 词）',
                                            ),
                                          ),
                                        FilledButton(
                                          key: const Key('open-vocabulary'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                scheme.secondaryContainer,
                                            foregroundColor:
                                                scheme.onSecondaryContainer,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 15,
                                            ),
                                          ),
                                          onPressed: () => context.push(
                                            AppRouter.vocabulary,
                                          ),
                                          child: const Text('打开本地词库'),
                                        ),
                                        if (hasPronunciation)
                                          OutlinedButton.icon(
                                            onPressed: () => context.push(
                                              AppRouter.pronunciation,
                                            ),
                                            icon: const Icon(
                                              Icons.hearing_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('发音与听音列表'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 2. Sync & Local Data Status Card
                              SectionCard(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.cloud_done_outlined,
                                              size: 18,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                '离线词库与云端同步状态',
                                                style:
                                                    theme.textTheme.titleMedium,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (notion != null)
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              StatusBadge(
                                                label: notion!.configured
                                                    ? 'Notion 已配置 · 缓存 ${formatCount(notion!.state.linkedWords)} 词'
                                                    : 'Notion 尚未配置',
                                                colors: notion!.configured
                                                    ? AppTheme.masteredColors(
                                                        brightness,
                                                      )
                                                    : AppTheme.neutralColors(
                                                        brightness,
                                                      ),
                                              ),
                                              if (libraryComplete)
                                                StatusBadge(
                                                  label: '完整词库已在本地',
                                                  colors: AppTheme.infoColors(
                                                    brightness,
                                                  ),
                                                  icon: Icons.verified_outlined,
                                                  textKey: const Key(
                                                    'library-complete',
                                                  ),
                                                ),
                                              TextButton.icon(
                                                onPressed: () => context.push(
                                                  AppRouter.notion,
                                                ),
                                                icon: const Icon(
                                                  Icons.sync,
                                                  size: 16,
                                                ),
                                                label: const Text('同步设置'),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (libraryIncomplete) ...[
                                      StatusBanner(
                                        message:
                                            '本地词库目前只有 ${formatCount(words.length)} 词，正式词库共 ${formatCount(scopeLength)} 词，尚未完整同步。'
                                            '全量同步只读取 Notion，已有评级和复习日期会保留。',
                                        tone: BannerTone.warning,
                                        textKey: const Key('full-sync-needed'),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: FilledButton.tonalIcon(
                                          key: const Key('open-full-sync'),
                                          onPressed: () =>
                                              context.push(AppRouter.notion),
                                          icon: const Icon(
                                            Icons.cloud_download_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            '前往全量同步（${formatCount(scopeLength)} 词）',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Text(
                                      allowCsvImport
                                          ? '首次使用可导入 100 词 CSV 样本。词义与词性复核状态见词卡；新词学习与发音状态从未测试开始。'
                                          : '首次使用请在词库中连接 Notion，同步后可离线学习。词义学习与发音自评独立保存在手机。',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    if (notion?.state.syncedAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '上次成功同步：${formatLocalDateTime(notion!.state.syncedAt!)} · 本地 SQLite 离线可用',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                    if (hasEventSandbox) ...[
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          key: const Key('open-event-sandbox'),
                                          onPressed: () => context.push(
                                            AppRouter.eventSandbox,
                                          ),
                                          icon: const Icon(
                                            Icons.science_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('同步实验（仅模拟事件）'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // 4. Japanese Module Entry Card
                              const SizedBox(height: 16),
                              SectionCard(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: scheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.translate_rounded,
                                            color: scheme.onPrimaryContainer,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                '日本語学習 · 日语学习模块 (J1)',
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const StatusBadge(
                                                label: '五十音 + Pilot100',
                                                status: 'neutral',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '零基础五十音图、假名练习与 100 词试点卡片学习。与英语数据完全物理隔离。',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        key: const Key(
                                          'open-japanese-module-btn',
                                        ),
                                        onPressed: () => context.push(
                                          AppRouter.japaneseHome,
                                        ),
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('进入日语'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.caption,
    required this.accent,
    this.valueKey,
  });

  final String label;
  final String value;
  final String unit;
  final String caption;
  final Color accent;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  key: valueKey,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(caption, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
