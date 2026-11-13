import 'package:flutter/material.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/ui/status_badge.dart';
import 'package:english_learning/features/japanese/domain/gojuon_data.dart';
import 'package:english_learning/features/japanese/domain/japanese_controller.dart';
import 'package:go_router/go_router.dart';

enum KanaDisplayMode {
  hiragana('平假名'),
  katakana('片假名'),
  both('平片对照');

  const KanaDisplayMode(this.label);
  final String label;
}

final class GojuonPage extends StatefulWidget {
  const GojuonPage({required this.controller, super.key});

  final JapaneseController controller;

  @override
  State<GojuonPage> createState() => _GojuonPageState();
}

class _GojuonPageState extends State<GojuonPage> {
  KanaDisplayMode _displayMode = KanaDisplayMode.hiragana;
  bool _showRomaji = true;

  void _showKanaDetail(KanaItem kana) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _KanaDetailDialog(
        kana: kana,
        controller: widget.controller,
        showRomaji: _showRomaji,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grid = GojuonData.grid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('五十音图 · 46 基础清音'),
        actions: [
          FilledButton.icon(
            key: const Key('go-kana-practice-action'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => context.push(AppRouter.japaneseGojuonPractice),
            icon: const Icon(Icons.quiz_outlined, size: 18),
            label: const Text('假名练习'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Control bar
                  SectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Segmented display toggle
                        SegmentedButton<KanaDisplayMode>(
                          key: const Key('kana-display-toggle'),
                          segments: const [
                            ButtonSegment(
                              value: KanaDisplayMode.hiragana,
                              label: Text('平假名'),
                            ),
                            ButtonSegment(
                              value: KanaDisplayMode.katakana,
                              label: Text('片假名'),
                            ),
                            ButtonSegment(
                              value: KanaDisplayMode.both,
                              label: Text('平片对照'),
                            ),
                          ],
                          selected: {_displayMode},
                          onSelectionChanged: (set) {
                            setState(() => _displayMode = set.first);
                          },
                        ),

                        // Romaji visibility toggle
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              key: const Key('toggle-romaji-switch'),
                              value: _showRomaji,
                              onChanged: (val) {
                                setState(() => _showRomaji = val);
                              },
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showRomaji ? '显示罗马字' : '隐藏罗马字',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Table / Grid
                  SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Header row (Vowels: a, i, u, e, o)
                        Row(
                          children: [
                            const SizedBox(
                              width: 80,
                              child: Center(
                                child: Text(
                                  '行',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                            for (final vowel in GojuonData.colVowels)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    vowel.toUpperCase(),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Divider(height: 20),

                        // 11 Rows of Kana
                        for (var r = 0; r < 11; r++) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                // Row name label
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    GojuonData.rowNames[r],
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),

                                // 5 Column slots
                                for (var c = 0; c < 5; c++)
                                  Expanded(
                                    child: _buildKanaSlot(
                                      grid[r][c],
                                      theme,
                                      scheme,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (r < 10) const Divider(height: 8, thickness: 0.5),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Mnemonic note
                  Text(
                    '提示：点击任意假名卡片可查看字源记忆提示、读音及对照假名。基础清音共 46 个，已排除古代废弃假名与空白格。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKanaSlot(KanaItem? item, ThemeData theme, ColorScheme scheme) {
    if (item == null) {
      return Container(
        height: 64,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('—', style: TextStyle(color: Colors.black26)),
        ),
      );
    }

    late final String charDisplay;
    switch (_displayMode) {
      case KanaDisplayMode.hiragana:
        charDisplay = item.hiragana;
      case KanaDisplayMode.katakana:
        charDisplay = item.katakana;
      case KanaDisplayMode.both:
        charDisplay = '${item.hiragana} ${item.katakana}';
    }

    return InkWell(
      key: Key('kana-card-${item.id}'),
      onTap: () => _showKanaDetail(item),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 64,
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              charDisplay,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: _displayMode == KanaDisplayMode.both ? 13 : 18,
              ),
            ),
            if (_showRomaji) ...[
              const SizedBox(height: 2),
              Text(
                item.romaji,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _KanaDetailDialog extends StatelessWidget {
  const _KanaDetailDialog({
    required this.kana,
    required this.controller,
    required this.showRomaji,
  });

  final KanaItem kana;
  final JapaneseController controller;
  final bool showRomaji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${kana.rowName} · 假名详情'),
          StatusBadge(
            label: '清音 46 基础',
            colors: AppTheme.infoColors(brightness),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Side by side Hiragana and Katakana
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _KanaBox(
                  label: '平假名',
                  char: kana.hiragana,
                  accentColor: scheme.primary,
                ),
                _KanaBox(
                  label: '片假名',
                  char: kana.katakana,
                  accentColor: scheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Romaji display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('标准罗马字：', style: theme.textTheme.bodyMedium),
                  Text(
                    kana.romaji,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Etymology / Mnemonic
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '字源与记忆提示',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    kana.mnemonicHint,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Pronunciation playback button
            OutlinedButton.icon(
              key: const Key('play-kana-audio'),
              onPressed: () async {
                final result = await controller.audio.playKana(kana);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.volume_up_outlined, size: 18),
              label: const Text('播放发音（日语 TTS 校验）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

final class _KanaBox extends StatelessWidget {
  const _KanaBox({
    required this.label,
    required this.char,
    required this.accentColor,
  });

  final String label;
  final String char;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            char,
            style: theme.textTheme.displaySmall?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
