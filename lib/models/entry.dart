enum EntryType { task, meeting, reminder }

extension EntryTypeX on EntryType {
  String get label => switch (this) {
        EntryType.task => 'Задача',
        EntryType.meeting => 'Встреча',
        EntryType.reminder => 'Напоминание',
      };
}

/// Запись пользователя: задача, встреча или напоминание.
class Entry {
  const Entry({
    this.id,
    required this.type,
    required this.title,
    this.dueAt,
    this.hasTime = false,
    required this.createdAt,
    this.done = false,
    this.comment = '',
    this.durationMin = 60,
  });

  final int? id;
  final EntryType type;
  final String title;

  /// Срок / время события. Если [hasTime] == false, важна только дата.
  final DateTime? dueAt;
  final bool hasTime;
  final DateTime createdAt;
  final bool done;
  final String comment;
  final int durationMin;

  /// Длительность не меньше часа.
  int get duration => durationMin < 60 ? 60 : durationMin;

  DateTime? get endAt => (dueAt == null || !hasTime)
      ? null
      : dueAt!.add(Duration(minutes: duration));

  /// Встреча со временем занимает слот в расписании.
  bool get blocksTime => type == EntryType.meeting && hasTime && dueAt != null;

  bool overlaps(Entry o) =>
      blocksTime &&
      o.blocksTime &&
      dueAt!.isBefore(o.endAt!) &&
      o.dueAt!.isBefore(endAt!);

  Entry copyWith({
    int? id,
    EntryType? type,
    String? title,
    DateTime? dueAt,
    bool clearDue = false,
    bool? hasTime,
    bool? done,
    String? comment,
    int? durationMin,
  }) =>
      Entry(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        hasTime: hasTime ?? this.hasTime,
        createdAt: createdAt,
        done: done ?? this.done,
        comment: comment ?? this.comment,
        durationMin: durationMin ?? this.durationMin,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'has_time': hasTime ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'done': done ? 1 : 0,
        'comment': comment,
        'duration_min': durationMin,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        type: EntryType.values.byName(m['type'] as String),
        title: m['title'] as String,
        dueAt: m['due_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int),
        hasTime: (m['has_time'] as int) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        done: (m['done'] as int) == 1,
        comment: (m['comment'] as String?) ?? '',
        durationMin: (m['duration_min'] as int?) ?? 60,
      );
}
