import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_import_source.dart';

final class VocabularyPage extends StatefulWidget {
  const VocabularyPage({
    required this.controller,
    this.hasPronunciation = false,
    this.hasNotion = false,
    this.allowCsvImport = true,
    super.key,
  });
  final VocabularyController controller;
  final bool hasPronunciation;
  final bool hasNotion;
  final bool allowCsvImport;
  static const sampleImportKey = Key('import-verified100');
  static const fileImportKey = Key('import-csv-file');
  static const classFilterKey = Key('library-class-filter');
  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  String _class = '主学习';
  bool _dueOnly = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final now = c.nowUtc;
      final words = c.words
          .where(
            (w) =>
                (_class == '全部' || w.entry.libraryClass == _class) &&
                (!_dueOnly || w.isDue(now)),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('本地词库')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                children: [
                  // Scroll independently on small windows / large text settings.
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .55,
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('100 词试用 · 词义与词性的复核状态请查看词卡。'),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  if (widget.allowCsvImport)
                                    FilledButton.icon(
                                      key: VocabularyPage.sampleImportKey,
                                      onPressed: c.busy
                                          ? null
                                          : () =>
                                                c.importCsv(loadVerifiedSample),
                                      icon: const Icon(Icons.download_outlined),
                                      label: const Text('导入 100 词样本'),
                                    ),
                                  if (widget.allowCsvImport)
                                    OutlinedButton.icon(
                                      key: VocabularyPage.fileImportKey,
                                      onPressed: c.busy
                                          ? null
                                          : () =>
                                                c.importCsv(pickVocabularyCsv),
                                      icon: const Icon(Icons.folder_open),
                                      label: const Text('选择 CSV 文件'),
                                    ),
                                  if (widget.hasPronunciation)
                                    OutlinedButton.icon(
                                      key: const Key('open-pronunciation'),
                                      onPressed: () =>
                                          context.push(AppRouter.pronunciation),
                                      icon: const Icon(Icons.hearing_outlined),
                                      label: const Text('6 词发音练习'),
                                    ),
                                  if (widget.hasNotion)
                                    OutlinedButton.icon(
                                      key: const Key('open-notion-sync'),
                                      onPressed: () =>
                                          context.push(AppRouter.notion),
                                      icon: const Icon(
                                        Icons.cloud_download_outlined,
                                      ),
                                      label: const Text('Notion 只读同步'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  DropdownButton<String>(
                                    key: VocabularyPage.classFilterKey,
                                    value: _class,
                                    items: const ['主学习', '扩展', '暂缓', '全部']
                                        .map(
                                          (label) => DropdownMenuItem(
                                            value: label,
                                            child: Text(label),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) =>
                                        setState(() => _class = value!),
                                  ),
                                  FilterChip(
                                    label: const Text('仅看未测试 / 到期'),
                                    selected: _dueOnly,
                                    onSelected: (v) =>
                                        setState(() => _dueOnly = v),
                                  ),
                                  Text(
                                    '共 ${c.words.length} 词 · 当前 ${words.length} 词',
                                  ),
                                ],
                              ),
                              if (c.importMessage != null)
                                Text(
                                  c.importMessage!,
                                  key: const Key('import-result'),
                                ),
                              if (c.error != null)
                                Text(
                                  c.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (c.busy) const LinearProgressIndicator(),
                  Expanded(
                    child: words.isEmpty
                        ? Center(
                            child: Text(
                              c.busy
                                  ? '正在读取…'
                                  : !widget.allowCsvImport && c.words.isEmpty
                                  ? '连接 Notion 同步词库后即可开始学习'
                                  : '当前筛选没有词条',
                            ),
                          )
                        : ListView.separated(
                            key: const Key('word-list'),
                            itemCount: words.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final word = words[index];
                              return ListTile(
                                key: ValueKey('word-${word.entry.id}'),
                                title: Text(word.entry.word),
                                subtitle: Text(
                                  '${word.statusLabel} · ${word.entry.fields['book_category']} · ${word.entry.libraryClass}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                  AppRouter.wordPath(word.entry.id),
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
    },
  );
}
