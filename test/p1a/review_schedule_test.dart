import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/features/review/review_schedule.dart';

void main() {
  final at = DateTime.parse('2026-11-07T23:59:00+08:00');
  for (final item in <ReviewGrade, Duration>{
    ReviewGrade.forgotten: const Duration(minutes: 10),
    ReviewGrade.familiar: const Duration(days: 1),
    ReviewGrade.mastered: const Duration(days: 7),
  }.entries) {
    test(
      '${item.key.name} uses the defined interval and UTC across midnight',
      () {
        final result = ReviewSchedule.nextDue(item.key, at);
        expect(result.isUtc, isTrue);
        expect(result.difference(at), item.value);
        expect(result, at.toUtc().add(item.value));
      },
    );
  }
}
