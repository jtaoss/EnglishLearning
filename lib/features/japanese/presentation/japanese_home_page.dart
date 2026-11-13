import 'package:flutter/material.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:english_learning/features/japanese/domain/gojuon_data.dart';
import 'package:go_router/go_router.dart';

final class JapaneseHomePage extends StatelessWidget {
  const JapaneseHomePage({required this.controller, super.key});

  final JapaneseController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日本語学習 · 日语学习'),
        actions: [
          TextButton.icon(
            key: const Key('switch-to-english'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: () => context.go(AppRouter.home),
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            label: const Text('返回 English / 英语'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Safety & Status Header Banner
                  StatusBanner(
                    message: '日语学习模块（J1 基础版）：五十音图、发音校验及 Pilot100 试点词汇已就绪。所有候选释义均处于待校对状态，已与英语正式词库完全物理隔离。',
                    tone: BannerTone.info,
                    icon: Icons.shield_outlined,
                  ),
                  const SizedBox(height: 20),

                  // 1. 五十音学习 (Gojuon Hero Card)
                  SectionCard(
                    padding: const EdgeInsets.all(24),
                    borderColor: scheme.primary.withValues(alpha: 0.35),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(
                              label: '零基础入门 · 五十音图',
                              colors: AppTheme.infoColors(brightness),
                              icon: Icons.grid_view_rounded,
                            ),
                            StatusBadge(
                              label: '现代常用 46 基础清音',
                              status: 'neutral',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '假名认知与基础练习',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '平假名、片假名标准五十音图对应。支持罗马字独立显示隐藏、正统字源记忆提示、清音读音与多种练习模式。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Mini preview row of vowels
                        Wrap(
                          spacing: 10,
                          children: GojuonData.basicKanaList.take(5).map((k) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                '${k.hiragana} ${k.katakana} (${k.romaji})',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              key: const Key('open-gojuon'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () =>
                                  context.push(AppRouter.japaneseGojuon),
                              icon: const Icon(Icons.apps_rounded),
                              label: const Text('进入五十音图'),
                            ),
                            OutlinedButton.icon(
                              key: const Key('open-kana-practice'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                              ),
                              onPressed: () => context.push(
                                AppRouter.japaneseGojuonPractice,
                              ),
                              icon: const Icon(Icons.quiz_outlined),
                              label: const Text('假名测验与练习'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Pilot 100 词汇卡片 (Pilot Vocabulary Hero Card)
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final entries = controller.entries;
                      final practiced = controller.reviewState.totalPracticed;

                      return SectionCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusBadge(
                                  label: 'Irodori 入门词汇 · 100 词试点',
                                  colors: AppTheme.infoColors(brightness),
                                  icon: Icons.translate_rounded,
                                ),
                                StatusBadge(
                                  label: '中文释义待校对',
                                  colors: AppTheme.familiarColors(brightness),
                                  icon: Icons.warning_amber_rounded,
                                ),
                                StatusBadge(
                                  label: '隔离演示数据源',
                                  status: 'neutral',
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '日语词卡与双维度自评',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '采用与英语统一的 Antigravity 蓝白卡片设计。默认隐藏中文释义，支持独立隐藏假名训练看汉字认读能力。预留词义与发音双维度独立评级。',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Metric indicators
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '试点词库规模',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${entries.length} 词',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '来源: Pilot100',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '本轮体验练习',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$practiced 词',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: scheme.secondary,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '仅内存演示，不入库',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  key: const Key('open-japanese-vocab'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: scheme.secondaryContainer,
                                    foregroundColor:
                                        scheme.onSecondaryContainer,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () => context.push(
                                    AppRouter.japaneseVocabulary,
                                  ),
                                  icon: const Icon(Icons.list_alt_rounded),
                                  label: const Text('浏览试点词表'),
                                ),
                                if (entries.isNotEmpty)
                                  OutlinedButton.icon(
                                    key: const Key('start-pilot-cards'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                    ),
                                    onPressed: () => context.push(
                                      AppRouter.japaneseWordPath(
                                        entries.first.sampleId,
                                      ),
                                    ),
                                    icon: const Icon(Icons.style_outlined),
                                    label: const Text('开始试点词卡学习'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // 3. Data Safety & Architecture Boundary Notice
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: scheme.surfaceContainerLowest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '严格数据隔离与安全边界保证',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '• 英语 5,332 个正式词条、学习记录、间隔复习与 SQLite 数据库完全受保护，未发生任何修改。\n'
                          '• 日语 Pilot100 中 100 条中文释义均为模型拟定候选（0 个人工确认），明确标注待校对。\n'
                          '• 日语学习与复习评分仅在 J1 演示模式下运行，未创建生产日语数据库，不向云端或正式数据库写入。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
