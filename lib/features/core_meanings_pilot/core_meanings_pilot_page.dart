import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/core_meanings_pilot/core_meaning_sample.dart';
import 'package:english_learning/ui/status_badge.dart';

final class CoreMeaningsPilotApp extends StatelessWidget {
  const CoreMeaningsPilotApp({required this.bundle, super.key});
  final CoreMeaningPilotBundle bundle;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '核心释义隔离试点',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: CoreMeaningsPilotPage(bundle: bundle),
  );
}

/// A standalone reviewer preview. It cannot read or write personal progress.
final class CoreMeaningsPilotPage extends StatefulWidget {
  const CoreMeaningsPilotPage({required this.bundle, super.key});
  final CoreMeaningPilotBundle bundle;

  @override
  State<CoreMeaningsPilotPage> createState() => _CoreMeaningsPilotPageState();
}

class _CoreMeaningsPilotPageState extends State<CoreMeaningsPilotPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final samples = widget.bundle.samples;
    final sample = samples[_index];
    return Scaffold(
      appBar: AppBar(title: const Text('核心释义试点')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: '100 词隔离草稿', status: 'neutral'),
                    Text('待人工审核 · 仅预览，不记录学习评级'),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      key: const Key('pilot-previous'),
                      tooltip: '上一词',
                      onPressed: _index == 0
                          ? null
                          : () => setState(() => _index--),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: DropdownButton<String>(
                        key: const Key('pilot-selector'),
                        value: sample.id,
                        isExpanded: true,
                        items: [
                          for (final entry in samples)
                            DropdownMenuItem(
                              value: entry.id,
                              child: Text(entry.headword),
                            ),
                        ],
                        onChanged: (id) {
                          if (id != null) {
                            setState(
                              () => _index = samples.indexWhere(
                                (s) => s.id == id,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${_index + 1} / ${samples.length}'),
                    IconButton(
                      key: const Key('pilot-next'),
                      tooltip: '下一词',
                      onPressed: _index == samples.length - 1
                          ? null
                          : () => setState(() => _index++),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CoreMeaningPilotCard(key: ValueKey(sample.id), sample: sample),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class CoreMeaningPilotCard extends StatefulWidget {
  const CoreMeaningPilotCard({required this.sample, super.key});
  final CoreMeaningSample sample;

  @override
  State<CoreMeaningPilotCard> createState() => _CoreMeaningPilotCardState();
}

class _CoreMeaningPilotCardState extends State<CoreMeaningPilotCard> {
  bool _revealed = false, _otherExpanded = false, _sourceExpanded = false;

  @override
  void didUpdateWidget(CoreMeaningPilotCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sample.id != widget.sample.id) {
      _revealed = _otherExpanded = _sourceExpanded = false;
    }
  }

  void _reveal() => setState(() => _revealed = true);

  @override
  Widget build(BuildContext context) {
    final sample = widget.sample;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        final editing =
            focusedContext?.widget is EditableText ||
            focusedContext?.findAncestorWidgetOfExactType<EditableText>() !=
                null;
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space &&
            !editing &&
            !_revealed) {
          _reveal();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sample.headword,
                key: const Key('pilot-headword'),
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 20),
              if (!_revealed) ...[
                const Text('先独立回忆词义，再查看记忆重点。'),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('pilot-reveal'),
                    onPressed: _reveal,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('查看重点释义 · 空格'),
                  ),
                ),
              ] else ...[
                Container(
                  key: const Key('pilot-answer'),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '优先记忆',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final group in sample.core)
                        _SenseRow(group: group, emphasis: true),
                      const SizedBox(height: 12),
                      Text(
                        sample.explanation,
                        key: const Key('pilot-explanation'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('常用扩展义', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                if (sample.extended.isEmpty)
                  const Text('本样本没有单列扩展义。')
                else
                  for (final group in sample.extended) _SenseRow(group: group),
                if (sample.other.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('pilot-expand-other'),
                      onPressed: () =>
                          setState(() => _otherExpanded = !_otherExpanded),
                      icon: Icon(
                        _otherExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        '${_otherExpanded ? '收起' : '展开'}其他义项（${sample.other.length} 组）',
                      ),
                    ),
                  ),
                  if (_otherExpanded)
                    for (final group in sample.other) _SenseRow(group: group),
                ],
                const SizedBox(height: 20),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('pilot-expand-source'),
                    onPressed: () =>
                        setState(() => _sourceExpanded = !_sourceExpanded),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('核对原始释义与选择理由'),
                  ),
                ),
                if (_sourceExpanded) ...[
                  SelectableText(
                    sample.originalMeaning,
                    key: const Key('pilot-original'),
                  ),
                  const SizedBox(height: 12),
                  Text(sample.reason, key: const Key('pilot-reason')),
                  const SizedBox(height: 8),
                  Text(
                    'AI 自评 ${sample.confidence.toStringAsFixed(2)}，不是准确率；待人工审核。',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    '来源 SHA-256：${sample.sourceHash}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SenseRow extends StatelessWidget {
  const _SenseRow({required this.group, this.emphasis = false});
  final MeaningGroup group;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${group.partOfSpeech}  ',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextSpan(text: group.glosses.join('、')),
        ],
      ),
      style: emphasis
          ? Theme.of(context).textTheme.titleLarge
          : Theme.of(context).textTheme.bodyLarge,
    ),
  );
}
