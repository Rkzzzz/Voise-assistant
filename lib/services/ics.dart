import '../models/entry.dart';
import '../models/mark.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _dt(DateTime d) =>
    '${d.year}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}00';

String _date(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}';

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n');

/// Календарь в формате iCalendar (.ics). Его понимают Яндекс Календарь,
/// Google Календарь, Outlook и системные календари. Работает без интернета.
String buildIcs(
  Iterable<Entry> entries, {
  Iterable<Mark> marks = const [],
  required DateTime now,
  String prodId = '-//Voice Assistant//RU',
}) {
  final b = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:$prodId')
    ..writeln('CALSCALE:GREGORIAN');
  final stamp = '${_dt(now.toUtc())}Z';

  for (final e in entries) {
    final d = e.dueAt;
    if (d == null) continue;
    b
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:entry-${e.id ?? e.createdAt.millisecondsSinceEpoch}@voice-assistant')
      ..writeln('DTSTAMP:$stamp')
      ..writeln('SUMMARY:${_esc(e.title)}');
    if (e.hasTime) {
      b
        ..writeln('DTSTART:${_dt(d)}')
        ..writeln('DTEND:${_dt(d.add(Duration(minutes: e.duration)))}');
    } else {
      final next = DateTime(d.year, d.month, d.day + 1);
      b
        ..writeln('DTSTART;VALUE=DATE:${_date(d)}')
        ..writeln('DTEND;VALUE=DATE:${_date(next)}');
    }
    if (e.place.isNotEmpty) b.writeln('LOCATION:${_esc(e.place)}');
    final desc = [
      e.type.label,
      if (e.comment.isNotEmpty) e.comment,
    ].join('. ');
    b.writeln('DESCRIPTION:${_esc(desc)}');
    if (e.done) b.writeln('STATUS:CONFIRMED');
    b.writeln('END:VEVENT');
  }

  for (final m in marks) {
    final d = DateTime(now.year, m.month, m.day);
    final next = DateTime(d.year, d.month, d.day + 1);
    b
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:mark-${m.id ?? '${m.month}-${m.day}'}@voice-assistant')
      ..writeln('DTSTAMP:$stamp')
      ..writeln('SUMMARY:${_esc('${m.emoji} ${m.title}')}')
      ..writeln('DTSTART;VALUE=DATE:${_date(d)}')
      ..writeln('DTEND;VALUE=DATE:${_date(next)}')
      ..writeln('RRULE:FREQ=YEARLY')
      ..writeln('END:VEVENT');
  }

  b.writeln('END:VCALENDAR');
  // по стандарту строки заканчиваются CRLF
  return b.toString().replaceAll('\n', '\r\n');
}
