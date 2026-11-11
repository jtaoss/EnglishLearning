import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/ui/status_badge.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.vocabulary,
    this.notion,
    this.hasPronunciation = false,
  });
  final AppSettings settings;
  final VocabularyController? vocabulary;
  final NotionSyncController? notion;
  final bool hasPronunciation;
  static const Key themeModeKey = Key('theme-mode');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([settings, ?vocabulary, ?notion]),
    builder: (context, child) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;

      return Scaffold(
        appBar: AppBar(title: const Text('设置与偏好')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 1. Theme & Appearance Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.palette_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            Text('Theme', style: theme.textTheme.titleMedium),
                            const StatusBadge(
                              label: '外观与显示',
                              status: 'neutral',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '切换浅色、深色或跟随 Windows 系统外观，减轻长时间背词的视觉疲劳。',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 480 ||
                                MediaQuery.textScalerOf(context).scale(1) >
                                    1.3) {
                              return DropdownButton<ThemeMode>(
                                key: themeModeKey,
                                isExpanded: true,
                                value: settings.themeMode,
                                items: const [
                                  DropdownMenuItem(
                                    value: ThemeMode.system,
                                    child: Text('System'),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeMode.light,
                                    child: Text('Light'),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeMode.dark,
                                    child: Text('Dark'),
                                  ),
                                ],
                                onChanged: (mode) {
                                  if (mode != null) {
                                    unawaited(settings.setThemeMode(mode));
                                  }
                                },
                              );
                            }
                            return SegmentedButton<ThemeMode>(
                              key: themeModeKey,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto_outlined),
                                  label: Text('System'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode_outlined),
                                  label: Text('Light'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_outlined),
                                  label: Text('Dark'),
                                ),
                              ],
                              selected: {settings.themeMode},
                              onSelectionChanged: (selection) => unawaited(
                                settings.setThemeMode(selection.first),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Learning Preferences & Review Rules Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.schedule_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            Text(
                              '学习与间隔复习偏好',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const _PreferenceRow(
                          label: '复习间隔规则',
                          value: '掌握 7 天 · 眼熟 1 天 · 遗忘 10 分钟',
                        ),
                        const SizedBox(height: 6),
                        const _PreferenceRow(
                          label: '回忆与自评顺序',
                          value: '先独立回忆词义与读音，查看答案后再分别评级',
                        ),
                        const SizedBox(height: 6),
                        _PreferenceRow(
                          label: '本地离线词库',
                          value: vocabulary == null
                              ? 'SQLite 本地独立保存，不覆盖个人学习记录'
                              : '已加载 ${vocabulary!.words.length} 词 · SQLite 本地离线保存',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Pronunciation & Audio Options Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.record_voice_over_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            Text('发音与音频选项', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const _PreferenceRow(
                          label: '辅助认读方式',
                          value: '自然拼读提示 + 音节/重音（不使用国际音标与中文谐音）',
                        ),
                        const SizedBox(height: 6),
                        const _PreferenceRow(
                          label: '音频来源优先级',
                          value: '优先使用合法授权真人录音，其余使用 Windows 本地英语 TTS',
                        ),
                        if (hasPronunciation) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.push(AppRouter.pronunciation),
                            icon: const Icon(Icons.hearing_outlined, size: 18),
                            label: const Text('打开自主认读与听音列表'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. Notion Sync & Security Configuration Card
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_sync_outlined,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Notion 词库同步与凭据安全',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            if (notion != null)
                              StatusBadge(
                                label: notion!.configured
                                    ? '凭据已安全保存'
                                    : '凭据尚未配置',
                                colors: notion!.configured
                                    ? AppTheme.masteredColors(brightness)
                                    : AppTheme.neutralColors(brightness),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _PreferenceRow(
                          label: '凭据加密存储',
                          value:
                              '${notion?.storageLabel ?? '系统安全凭据存储'}（不显示明文密钥）',
                        ),
                        const SizedBox(height: 6),
                        _PreferenceRow(
                          label: '云端同步状态',
                          value: notion == null
                              ? '只读增量同步，不上传真实个人学习事件'
                              : '已关联缓存 ${notion!.state.linkedWords} 词 · 只读同步不覆盖本地学习进度',
                        ),
                        if (notion != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => context.push(AppRouter.notion),
                            icon: const Icon(
                              Icons.cloud_download_outlined,
                              size: 18,
                            ),
                            label: const Text('管理 Notion 只读同步配置'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

final class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          '$label：',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
