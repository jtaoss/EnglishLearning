import 'package:flutter/foundation.dart';
import 'package:english_learning/features/japanese/data/pilot_vocab_loader.dart';
import 'package:english_learning/features/japanese/data/japanese_audio_service.dart';
import 'package:english_learning/features/japanese/domain/japanese_vocab_entry.dart';
import 'package:english_learning/features/japanese/domain/japanese_review_state.dart';

final class JapaneseController extends ChangeNotifier {
  JapaneseController({
    PilotVocabLoader? loader,
    JapaneseAudioService? audioService,
    JapaneseReviewSessionState? reviewState,
  }) : _loader = loader ?? const PilotVocabLoader(),
       _audio = audioService ?? JapaneseAudioService(),
       reviewState = reviewState ?? JapaneseReviewSessionState();

  final PilotVocabLoader _loader;
  final JapaneseAudioService _audio;
  final JapaneseReviewSessionState reviewState;

  List<JapaneseVocabEntry> _entries = [];
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  List<JapaneseVocabEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoaded => _initialized;
  JapaneseAudioService get audio => _audio;

  Future<void> initialize({String? csvContent}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _entries = await _loader.load(csvContent: csvContent);
      _initialized = true;
    } catch (e) {
      _error = '加载日语试点词库失败: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  JapaneseVocabEntry? find(String sampleId) {
    for (final entry in _entries) {
      if (entry.sampleId == sampleId) {
        return entry;
      }
    }
    return null;
  }

  JapaneseVocabEntry? nextEntry(String currentSampleId) {
    final idx = _entries.indexWhere((e) => e.sampleId == currentSampleId);
    if (idx >= 0 && idx < _entries.length - 1) {
      return _entries[idx + 1];
    }
    return null;
  }

  JapaneseVocabEntry? prevEntry(String currentSampleId) {
    final idx = _entries.indexWhere((e) => e.sampleId == currentSampleId);
    if (idx > 0) {
      return _entries[idx - 1];
    }
    return null;
  }

  @override
  void dispose() {
    _audio.dispose();
    reviewState.dispose();
    super.dispose();
  }
}
