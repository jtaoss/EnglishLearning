import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:english_learning/features/japanese/domain/gojuon_data.dart';

enum KanaPracticeMode {
  kanaToRomaji('看假名选读音', '根据显示的假名，选择正确的罗马字读音'),
  romajiToKana('看罗马字选假名', '根据显示的罗马字，选择对应的假名'),
  hiraganaKatakanaMatch('平假名·片假名对应', '在平假名与片假名之间进行对应识别');

  const KanaPracticeMode(this.label, this.description);
  final String label;
  final String description;
}

@immutable
final class KanaQuizQuestion {
  const KanaQuizQuestion({
    required this.prompt,
    required this.promptNote,
    required this.correctAnswer,
    required this.options,
    required this.targetKana,
    required this.mode,
  });

  final String prompt;
  final String promptNote;
  final String correctAnswer;
  final List<String> options;
  final KanaItem targetKana;
  final KanaPracticeMode mode;
}

final class KanaQuizSession {
  KanaQuizSession({required this.mode, required this.questions})
    : _answers = List<String?>.filled(questions.length, null);

  final KanaPracticeMode mode;
  final List<KanaQuizQuestion> questions;
  final List<String?> _answers;
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;
  int get totalQuestions => questions.length;
  KanaQuizQuestion get currentQuestion => questions[_currentIndex];
  String? get currentAnswer => _answers[_currentIndex];

  bool get isCurrentAnswered => _answers[_currentIndex] != null;
  bool get isCurrentCorrect =>
      isCurrentAnswered &&
      _answers[_currentIndex] == currentQuestion.correctAnswer;

  bool get isFinished =>
      _answers.every((a) => a != null) && _currentIndex == questions.length - 1;

  int get correctCount {
    var count = 0;
    for (var i = 0; i < questions.length; i++) {
      if (_answers[i] == questions[i].correctAnswer) {
        count++;
      }
    }
    return count;
  }

  void answerCurrent(String answer) {
    if (_answers[_currentIndex] == null) {
      _answers[_currentIndex] = answer;
    }
  }

  bool next() {
    if (_currentIndex < questions.length - 1) {
      _currentIndex++;
      return true;
    }
    return false;
  }

  void reset() {
    _currentIndex = 0;
    for (var i = 0; i < _answers.length; i++) {
      _answers[i] = null;
    }
  }

  /// Factory to generate a randomized set of questions for a chosen mode.
  static KanaQuizSession create({
    required KanaPracticeMode mode,
    int count = 10,
    Random? random,
  }) {
    final rng = random ?? Random();
    final allKana = List<KanaItem>.from(GojuonData.basicKanaList)..shuffle(rng);
    final selectedKana = allKana.take(min(count, allKana.length)).toList();

    final questions = <KanaQuizQuestion>[];

    for (final kana in selectedKana) {
      late final String prompt;
      late final String promptNote;
      late final String correctAnswer;
      late final List<String> pool;

      switch (mode) {
        case KanaPracticeMode.kanaToRomaji:
          // Randomly choose Hiragana or Katakana as prompt
          final useHiragana = rng.nextBool();
          prompt = useHiragana ? kana.hiragana : kana.katakana;
          promptNote = useHiragana ? '平假名' : '片假名';
          correctAnswer = kana.romaji;
          pool = GojuonData.basicKanaList.map((k) => k.romaji).toSet().toList();
        case KanaPracticeMode.romajiToKana:
          prompt = kana.romaji;
          promptNote = '罗马字';
          final toHiragana = rng.nextBool();
          correctAnswer = toHiragana ? kana.hiragana : kana.katakana;
          pool = GojuonData.basicKanaList
              .map((k) => toHiragana ? k.hiragana : k.katakana)
              .toList();
        case KanaPracticeMode.hiraganaKatakanaMatch:
          final hToK = rng.nextBool();
          prompt = hToK ? kana.hiragana : kana.katakana;
          promptNote = hToK ? '平假名 → 选片假名' : '片假名 → 选平假名';
          correctAnswer = hToK ? kana.katakana : kana.hiragana;
          pool = GojuonData.basicKanaList
              .map((k) => hToK ? k.katakana : k.hiragana)
              .toList();
      }

      // Generate 4 options: 1 correct, 3 distinct wrong options
      final distractors = pool.where((o) => o != correctAnswer).toList()
        ..shuffle(rng);
      final options = [correctAnswer, ...distractors.take(3)]..shuffle(rng);

      questions.add(
        KanaQuizQuestion(
          prompt: prompt,
          promptNote: promptNote,
          correctAnswer: correctAnswer,
          options: options,
          targetKana: kana,
          mode: mode,
        ),
      );
    }

    return KanaQuizSession(mode: mode, questions: questions);
  }
}
