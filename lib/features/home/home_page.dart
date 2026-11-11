import 'package:flutter/material.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/empty_state.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:go_router/go_router.dart';
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
                        final allDue = v.dueWords(now, libraryClass: null);
                        final dueReviewCount = allDue
                            .where(
                              (w) =>
                                  w.status != 'untested' ||
                                  w.reviewCount > 0 ||
                                  w.isPronunciationDue(now),
                            )
                            .length;
                        final newLearnableCount =
                            allDue.length - dueReviewCount;

                        final masteredCount = words
                            .where((w) => w.status == 'mastered')
                            .length;
                        final familiarCount = words
                            .where((w) => w.status == 'familiar')
                            .length;
                        final forgottenCount = words
                            .where((w) => w.status == 'forgotten')
                            .length;
                        final studiedCount =
                            masteredCount + familiarCount + forgottenCount;
                        final untestedCount = words.length - studiedCount;

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
                                            const SizedBox(height: 6),
                                            Text(
                                              '本地 ${words.length} 词 · 可学习未测试 / 到期 ${allDue.length} 词',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        StatusBadge(
                                          label: allDue.isNotEmpty
                                              ? '待处理 ${allDue.length} 词'
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
                                            value: '$dueReviewCount',
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
                                            label: '可学新词（未测试）',
                                            value: '$newLearnableCount',
                                            unit: '词',
                                            caption: '先独立回忆词义与读音，再查看答案',
                                            accent: scheme.primary,
                                          ),
                                          _MetricTile(
                                            label: '已学 / 未学概况',
                                            value:
                                                '$studiedCount / $untestedCount',
                                            unit: '词',
                                            caption:
                                                '掌握 $masteredCount · 眼熟 $familiarCount · 遗忘 $forgottenCount',
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
                                    const SizedBox(height: 22),

                                    // Primary & Secondary Action Bar
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (allDue.isNotEmpty)
                                          FilledButton.icon(
                                            key: const Key('start-due-review'),
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 26,
                                                    vertical: 16,
                                                  ),
                                            ),
                                            onPressed: v.busy
                                                ? null
                                                : () => context.push(
                                                    AppRouter.wordPath(
                                                      allDue.first.entry.id,
                                                    ),
                                                  ),
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                            label: const Text('开始今日学习 / 到期复习'),
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
                                                    ? 'Notion 已配置 · 缓存 ${notion!.state.linkedWords} 词'
                                                    : 'Notion 尚未配置',
                                                colors: notion!.configured
                                                    ? AppTheme.masteredColors(
                                                        brightness,
                                                      )
                                                    : AppTheme.neutralColors(
                                                        brightness,
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
  });

  final String label;
  final String value;
  final String unit;
  final String caption;
  final Color accent;

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
