import 'dart:convert';

import 'package:flutter/services.dart';

final class PronunciationContent {
  PronunciationContent(Map<String, dynamic> json)
    : id = json['entry_id'] as String,
      word = json['word'] as String,
      assetId = json['audio_asset_id'] as String,
      assetPath = json['asset_path'] as String,
      sha256 = json['sha256'] as String,
      accent = json['accent'] as String,
      author = json['author'] as String,
      sourceUrl = json['source_url'] as String,
      license = json['license'] as String,
      licenseUrl = json['license_url'] as String,
      changes = json['changes'] as String,
      cacheAllowed = json['cache_allowed'] as bool,
      segments = (json['phonics_segments'] as List).cast<String>(),
      syllables = (json['syllables'] as List).cast<String>(),
      stressedSyllable = json['stressed_syllable'] as int,
      note = json['phonics_note'] as String,
      listenToRemember = json['listen_to_remember'] as bool,
      reviewStatus = json['review_status'] as String,
      evidenceUrls = (json['evidence_urls'] as List).cast<String>() {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(assetId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        !RegExp(r'^assets/pronunciation/audio/[a-z]+\.wav$')
            .hasMatch(assetPath) ||
        syllables.isEmpty ||
        stressedSyllable < 0 ||
        stressedSyllable >= syllables.length ||
        !sourceUrl.startsWith('https://') ||
        !licenseUrl.startsWith('https://')) {
      throw const FormatException('发音资源清单不完整，未加载音频。');
    }
  }
  final String id, word, assetId, assetPath, sha256, accent;
  final String author, sourceUrl, license, licenseUrl, changes;
  final bool cacheAllowed, listenToRemember;
  final List<String> segments, syllables, evidenceUrls;
  final int stressedSyllable;
  final String note, reviewStatus;
  String get stressDisplay => [
    for (var i = 0; i < syllables.length; i++)
      i == stressedSyllable ? syllables[i].toUpperCase() : syllables[i],
  ].join(' · ');
}

final class PronunciationCatalog {
  PronunciationCatalog(Iterable<PronunciationContent> items)
    : entries = Map.unmodifiable({for (final item in items) item.id: item});
  final Map<String, PronunciationContent> entries;

  static Future<PronunciationCatalog> load([AssetBundle? bundle]) async {
    final json = jsonDecode(
      await (bundle ?? rootBundle).loadString(
        'assets/pronunciation/manifest.json',
      ),
    ) as Map<String, dynamic>;
    if (json['version'] != 1) throw const FormatException('不支持的发音清单版本。');
    final items = (json['items'] as List)
        .map((v) => PronunciationContent((v as Map).cast<String, dynamic>()))
        .toList();
    if (items.map((v) => v.id).toSet().length != items.length ||
        items.map((v) => v.assetId).toSet().length != items.length) {
      throw const FormatException('发音清单存在重复 ID。');
    }
    return PronunciationCatalog(items);
  }
}
