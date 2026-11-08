enum ReviewGrade {
  mastered('掌握'),
  familiar('眼熟'),
  forgotten('遗忘');

  const ReviewGrade(this.label);
  final String label;
}

abstract final class ReviewSchedule {
  static DateTime nextDue(ReviewGrade grade, DateTime reviewedAt) =>
      reviewedAt.toUtc().add(switch (grade) {
        ReviewGrade.mastered => const Duration(days: 7),
        ReviewGrade.familiar => const Duration(days: 1),
        ReviewGrade.forgotten => const Duration(minutes: 10),
      });
}
