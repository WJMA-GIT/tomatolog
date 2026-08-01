class DailyPlan {
  const DailyPlan({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.categoryId,
    required this.plannedMinutes,
    this.completedDates = const {},
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String categoryId;
  final int plannedMinutes;
  final Set<String> completedDates;

  bool occursOn(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  bool isCompletedOn(DateTime date) => completedDates.contains(dayKey(date));

  DailyPlan withCompletion(DateTime date, bool completed) {
    final dates = {...completedDates};
    if (completed) {
      dates.add(dayKey(date));
    } else {
      dates.remove(dayKey(date));
    }
    return DailyPlan(
      id: id,
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
      plannedMinutes: plannedMinutes,
      completedDates: dates,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'categoryId': categoryId,
    'plannedMinutes': plannedMinutes,
    'completedDates': completedDates.toList(),
  };

  factory DailyPlan.fromJson(Map<String, Object?> json) {
    final legacyDate = json['date'] as String?;
    final startSource = (json['startDate'] as String?) ?? legacyDate;
    if (startSource == null) throw const FormatException('Missing plan date');
    final parsedStart = DateTime.parse(startSource);
    final startDate = DateTime(
      parsedStart.year,
      parsedStart.month,
      parsedStart.day,
    );
    final parsedEnd = DateTime.parse(
      (json['endDate'] as String?) ?? startSource,
    );
    final plannedMinutes =
        (json['plannedMinutes'] as int?) ??
        ((json['endMinute'] as int? ?? 9 * 60 + 25) -
            (json['startMinute'] as int? ?? 9 * 60));
    if (plannedMinutes <= 0 || plannedMinutes > 24 * 60) {
      throw const FormatException('Invalid plan duration');
    }
    final legacyCompleted = (json['isCompleted'] as bool?) ?? false;
    return DailyPlan(
      id: json['id']! as String,
      startDate: startDate,
      endDate: DateTime(parsedEnd.year, parsedEnd.month, parsedEnd.day),
      categoryId: json['categoryId']! as String,
      plannedMinutes: plannedMinutes,
      completedDates: {
        ...((json['completedDates'] as List<Object?>?) ?? []).cast<String>(),
        if (legacyCompleted) dayKey(startDate),
      },
    );
  }

  static String dayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
