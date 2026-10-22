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
  });

  final int? id;
  final EntryType type;
  final String title;

  /// Срок / время события. Если [hasTime] == false, важна только дата.
  final DateTime? dueAt;
  final bool hasTime;
  final DateTime createdAt;
  final bool done;

  Entry copyWith({
    int? id,
    String? title,
    DateTime? dueAt,
    bool? hasTime,
    bool? done,
  }) =>
      Entry(
        id: id ?? this.id,
        type: type,
        title: title ?? this.title,
        dueAt: dueAt ?? this.dueAt,
        hasTime: hasTime ?? this.hasTime,
        createdAt: createdAt,
        done: done ?? this.done,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'title': title,
        'due_at': dueAt?.millisecondsSinceEpoch,
        'has_time': hasTime ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'done': done ? 1 : 0,
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
      );
}
