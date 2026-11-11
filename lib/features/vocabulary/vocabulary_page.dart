import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_import_source.dart';
import 'package:english_learning/ui/status_badge.dart';

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
  String _search = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final brightness = theme.brightness;
      final c = widget.controller;
      final now = c.nowUtc;
      final words = c.words
          .where(
            (w) =>
                (_class == '全部' || w.entry.libraryClass == _class) &&
                (!_dueOnly || w.isDue(now) || w.isPronunciationDue(now)) &&
                w.entry.word.toLowerCase().contains(_search.toLowerCase()),
          )
          .toList();

      return Scaffold(
        appBar: AppBar(title: const Text('本地词库')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    // Scroll independently on small windows / large text settings.
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .52,
                        ),
                        child: SingleChildScrollView(
                          child: SectionCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '本地 ${c.words.length} 词 · 词义与发音状态分别保存。',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (widget.allowCsvImport)
                                          FilledButton.icon(
                                            key: VocabularyPage.sampleImportKey,
                                            onPressed: c.busy
                                                ? null
                                                : () => c.importCsv(
                                                    loadVerifiedSample,
                                                  ),
                                            icon: const Icon(
                                              Icons.download_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('导入 100 词样本'),
                                          ),
                                        if (widget.allowCsvImport)
                                          OutlinedButton.icon(
                                            key: VocabularyPage.fileImportKey,
                                            onPressed: c.busy
                                                ? null
                                                : () => c.importCsv(
                                                    pickVocabularyCsv,
                                                  ),
                                            icon: const Icon(
                                              Icons.folder_open,
                                              size: 18,
                                            ),
                                            label: const Text('选择 CSV 文件'),
                                          ),
                                        if (widget.hasPronunciation)
                                          OutlinedButton.icon(
                                            key: const Key(
                                              'open-pronunciation',
                                            ),
                                            onPressed: () => context.push(
                                              AppRouter.pronunciation,
                                            ),
                                            icon: const Icon(
                                              Icons.hearing_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('自主认读与听音'),
                                          ),
                                        if (widget.hasNotion)
                                          OutlinedButton.icon(
                                            key: const Key('open-notion-sync'),
                                            onPressed: () =>
                                                context.push(AppRouter.notion),
                                            icon: const Icon(
                                              Icons.cloud_download_outlined,
                                              size: 18,
                                            ),
                                            label: const Text('Notion 只读同步'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('vocabulary-search'),
                                  decoration: const InputDecoration(
                                    labelText: '查找英文单词',
                                    hintText: '输入词头字母快速筛选…',
                                    prefixIcon: Icon(Icons.search, size: 20),
                                  ),
                                  onChanged: (value) =>
                                      setState(() => _search = value),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          key: VocabularyPage.classFilterKey,
                                          isDense: true,
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
                                      ),
                                    ),
                                    FilterChip(
                                      label: const Text('仅看未测试 / 到期'),
                                      selected: _dueOnly,
                                      onSelected: (v) =>
                                          setState(() => _dueOnly = v),
                                    ),
                                    Text(
                                      '共 ${c.words.length} 词 · 当前 ${words.length} 词',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                if (c.importMessage != null) ...[
                                  const SizedBox(height: 10),
                                  StatusBanner(
                                    message: c.importMessage!,
                                    tone: BannerTone.success,
                                    textKey: const Key('import-result'),
                                  ),
                                ],
                                if (c.error != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    c.error!,
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (c.busy) const LinearProgressIndicator(),
                    Expanded(
                      child: Material(
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: words.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    c.busy
                                        ? '正在读取…'
                                        : !widget.allowCsvImport &&
                                              c.words.isEmpty
                                        ? '连接 Notion 同步词库后即可开始学习'
                                        : '当前筛选没有词条',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                key: const Key('word-list'),
                                itemCount: words.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final word = words[index];
                                  final isWordDue =
                                      word.isDue(now) ||
                                      word.isPronunciationDue(now);
                                  final pronLabel =
                                      word.pronunciationProgress?.label ??
                                      word.pronunciationStatus;
                                  return ListTile(
                                    key: ValueKey('word-${word.entry.id}'),
                                    title: Wrap(
                                      spacing: 10,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          word.entry.word,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        StatusBadge(
                                          label: word.statusLabel,
                                          status: word.status,
                                        ),
                                        if (pronLabel != '未测试')
                                          StatusBadge(
                                            label: '读音：$pronLabel',
                                            status: pronLabel,
                                          ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '${word.statusLabel} · ${word.entry.fields['book_category']} · ${word.entry.libraryClass}',
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isWordDue &&
                                            word.entry.libraryClass != '暂缓')
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: StatusBadge(
                                              label: word.status == 'untested'
                                                  ? '待学'
                                                  : '待复习',
                                              colors: word.status == 'untested'
                                                  ? AppTheme.infoColors(
                                                      brightness,
                                                    )
                                                  : AppTheme.familiarColors(
                                                      brightness,
                                                    ),
                                            ),
                                          ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                    onTap: () => context.push(
                                      AppRouter.wordPath(word.entry.id),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
