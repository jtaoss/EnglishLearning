import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_schedule.dart';

final class ImportResult {
  const ImportResult(this.inserted, this.updated, this.unchanged);
  final int inserted;
  final int updated;
  final int unchanged;
  String get message => '新增 $inserted，更新 $updated，未变 $unchanged';
}

abstract interface class LearningRepository {
  Future<ImportResult> importCsv(String csv);
  Future<List<StudyWord>> readWords();
  Future<void> recordReview(String entryId, ReviewGrade grade, DateTime at);
  Future<int> reviewEventCount();
  Future<void> close();
}
