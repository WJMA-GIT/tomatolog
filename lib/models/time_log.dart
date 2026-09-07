enum LogStatus { completed, interrupted, manuallyAdded }

enum LogKind { focus, interval }

class TimeLog {
  const TimeLog({
    required this.id,
    required this.categoryId,
    required this.startedAt,
    required this.endedAt,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.status,
    this.kind = LogKind.focus,
    this.note,
  });

  final String id;
  final String categoryId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int plannedSeconds;
  final int actualSeconds;
  final LogStatus status;
  final LogKind kind;
  final String? note;

  Map<String, Object?> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'plannedSeconds': plannedSeconds,
    'actualSeconds': actualSeconds,
    'status': status.name,
    'kind': kind.name,
    'note': note,
  };

  factory TimeLog.fromJson(Map<String, Object?> json) {
    return TimeLog(
      id: json['id']! as String,
      categoryId: json['categoryId']! as String,
      startedAt: DateTime.parse(json['startedAt']! as String),
      endedAt: DateTime.parse(json['endedAt']! as String),
      plannedSeconds: json['plannedSeconds']! as int,
      actualSeconds: json['actualSeconds']! as int,
      status: LogStatus.values.byName(json['status']! as String),
      kind: LogKind.values.byName((json['kind'] as String?) ?? 'focus'),
      note: json['note'] as String?,
    );
  }
}
