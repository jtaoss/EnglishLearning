import 'package:flutter/material.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/ui/empty_state.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';

final class HomePage extends StatelessWidget {
  const HomePage({
    this.environmentLabel,
    this.vocabulary,
    this.hasEventSandbox = false,
    this.allowCsvImport = true,
    super.key,
  });
  final bool hasEventSandbox;
  final bool allowCsvImport;
  final String? environmentLabel;
  final VocabularyController? vocabulary;
  static const Key openSettingsKey = Key('open-settings');
  static const Key environmentKey = Key('app-environment');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppMetadata.title),
      actions: [
        IconButton(
          key: openSettingsKey,
          tooltip: '设置',
          onPressed: () => context.push(AppRouter.settings),
          icon: const Icon(Icons.settings),
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
                  padding: const EdgeInsets.all(12),
                  child: Text(environmentLabel!, key: environmentKey),
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
                    listenable: vocabulary!,
                    builder: (context, _) => SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '每天一点，离线也能继续',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '本地 ${vocabulary!.words.length} 词 · 可学习未测试 / 到期 ${vocabulary!.dueWords(vocabulary!.nowUtc, libraryClass: null).length} 词',
                          ),
                          const SizedBox(height: 24),
                          if (vocabulary!
                              .dueWords(vocabulary!.nowUtc, libraryClass: null)
                              .isNotEmpty) ...[
                            FilledButton.icon(
                              key: const Key('start-due-review'),
                              onPressed: vocabulary!.busy
                                  ? null
                                  : () => context.push(
                                      AppRouter.wordPath(
                                        vocabulary!
                                            .dueWords(
                                              vocabulary!.nowUtc,
                                              libraryClass: null,
                                            )
                                            .first
                                            .entry
                                            .id,
                                      ),
                                    ),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('开始今日学习 / 到期复习'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton(
                            key: const Key('open-vocabulary'),
                            onPressed: () => context.push(AppRouter.vocabulary),
                            child: const Text('打开本地词库'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            allowCsvImport
                                ? '首次使用可导入 100 词 CSV 样本。词义与词性复核状态见词卡；新词学习与发音状态从未测试开始。'
                                : '首次使用请在词库中连接 Notion，同步后可离线学习。词义学习与发音自评独立保存在手机。',
                          ),
                          if (vocabulary!.busy) const LinearProgressIndicator(),
                          if (hasEventSandbox)
                            TextButton(
                              key: const Key('open-event-sandbox'),
                              onPressed: () =>
                                  context.push(AppRouter.eventSandbox),
                              child: const Text('同步实验（仅模拟事件）'),
                            ),
                          if (vocabulary!.error != null) ...[
                            Text(vocabulary!.error!),
                            TextButton(
                              onPressed: vocabulary!.busy
                                  ? null
                                  : vocabulary!.refresh,
                              child: const Text('重试读取'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
