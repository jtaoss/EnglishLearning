import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/pronunciation/local_audio_cache.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/pronunciation/standard_audio_player.dart';

final class PronunciationServices {
  PronunciationServices({
    required this.store,
    required this.logger,
    Future<PronunciationCatalog> Function()? catalogLoader,
    PronunciationAudioCache? cache,
    StandardAudioPlayer Function()? playerFactory,
  }) : _load = catalogLoader ?? PronunciationCatalog.load,
       cache = cache ?? LocalAudioCache(),
       playerFactory = playerFactory ?? AudioplayersStandardAudioPlayer.new;
  final PronunciationStore store;
  final AppLogger logger;
  final Future<PronunciationCatalog> Function() _load;
  final PronunciationAudioCache cache;
  final StandardAudioPlayer Function() playerFactory;
  PronunciationCatalog? _catalog;
  Future<PronunciationCatalog> catalog() async => _catalog ??= await _load();
  Future<PronunciationSession?> open(String id, String word) async {
    final content = (await catalog()).entries[id];
    if (content == null) return null;
    if (content.word != word) throw const FormatException('词头与发音资源不一致，请先核对词条。');
    final session = PronunciationSession(
      content: content,
      store: store,
      cache: cache,
      player: playerFactory(),
      logger: logger,
    );
    try {
      await session.restore();
      return session;
    } catch (_) {
      session.dispose();
      rethrow;
    }
  }
}
