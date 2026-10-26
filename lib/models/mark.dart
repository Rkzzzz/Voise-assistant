/// Особая дата, повторяющаяся каждый год (день рождения, годовщина…).
class Mark {
  const Mark({
    this.id,
    required this.title,
    required this.month,
    required this.day,
    this.kind = 'other',
  });

  final int? id;
  final String title;
  final int month;
  final int day;

  /// birthday | anniversary | other
  final String kind;

  String get emoji => switch (kind) {
        'birthday' => '🎂',
        'anniversary' => '💍',
        _ => '⭐',
      };

  bool fallsOn(DateTime d) => d.month == month && d.day == day;

  static String kindOf(String title) {
    final t = title.toLowerCase();
    if (t.contains('рожден')) return 'birthday';
    if (t.contains('годовщин') || t.contains('юбиле')) return 'anniversary';
    return 'other';
  }

  Map<String, Object?> toMap() =>
      {'id': id, 'title': title, 'month': month, 'day': day, 'kind': kind};

  factory Mark.fromMap(Map<String, Object?> m) => Mark(
        id: m['id'] as int?,
        title: m['title'] as String,
        month: m['month'] as int,
        day: m['day'] as int,
        kind: (m['kind'] as String?) ?? 'other',
      );
}
