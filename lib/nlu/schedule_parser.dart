/// Занятие из расписания: день недели, время, длительность, название.
class ScheduleItem {
  const ScheduleItem({
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.durationMin,
    required this.title,
  });

  final int weekday; // 1 = понедельник … 7 = воскресенье
  final int hour;
  final int minute;
  final int durationMin;
  final String title;

  static const _short = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  String get dayShort => _short[weekday - 1];

  String get timeText {
    String two(int n) => n.toString().padLeft(2, '0');
    final end = hour * 60 + minute + durationMin;
    return '${two(hour)}:${two(minute)}–${two((end ~/ 60) % 24)}:${two(end % 60)}';
  }
}

/// Разбор текста расписания (результат OCR или ручной ввод).
///
/// Понимает строки вида:
///   «Понедельник» — заголовок дня, ниже занятия;
///   «1. 8:30-9:15 Математика», «8.30 Русский язык»;
///   «Шахматы вт 16:00-17:00» — день прямо в строке.
List<ScheduleItem> parseSchedule(String text) {
  const nb = '(?<![а-яa-z])';
  const ne = '(?![а-яa-z])';
  final days = <RegExp, int>{
    RegExp('$nb(?:понедельник[а-я]*|пн)$ne'): 1,
    RegExp('$nb(?:вторник[а-я]*|вт)$ne'): 2,
    RegExp('$nb(?:сред[а-я]*|ср)$ne'): 3,
    RegExp('$nb(?:четверг[а-я]*|чт)$ne'): 4,
    RegExp('$nb(?:пятниц[а-я]*|пт)$ne'): 5,
    RegExp('$nb(?:суббот[а-я]*|сб)$ne'): 6,
    RegExp('$nb(?:воскресень[а-я]*|вс)$ne'): 7,
  };
  final timeRe = RegExp(
      r'(\d{1,2})\s*[:.]\s*(\d{2})(?:\s*[-–—]\s*(\d{1,2})\s*[:.]\s*(\d{2}))?');
  final numbering = RegExp(r'^\s*\d{1,2}\s*[.)]\s+');

  int? dayIn(String low, [RegExp? skip]) {
    for (final e in days.entries) {
      if (e.key.hasMatch(low)) return e.value;
    }
    return null;
  }

  final res = <ScheduleItem>[];
  int? current;
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    final low = line.toLowerCase().replaceAll('ё', 'е');
    final inlineDay = dayIn(low);
    final tm = timeRe.firstMatch(low.replaceFirst(numbering, ''));

    if (tm == null) {
      // строка без времени: заголовок дня
      if (inlineDay != null) current = inlineDay;
      continue;
    }

    final day = inlineDay ?? current;
    if (day == null) continue;

    final h = int.parse(tm.group(1)!), m = int.parse(tm.group(2)!);
    if (h > 23 || m > 59) continue;

    var dur = 60;
    if (tm.group(3) != null) {
      final h2 = int.parse(tm.group(3)!), m2 = int.parse(tm.group(4)!);
      if (h2 <= 23 && m2 <= 59) {
        final d = (h2 * 60 + m2) - (h * 60 + m);
        if (d >= 15 && d <= 12 * 60) dur = d;
      }
    }

    // название: строка без нумерации, времени и дней недели
    var title = line.replaceFirst(numbering, '');
    title = title.replaceFirst(timeRe, ' ');
    for (final r in days.keys) {
      title = title.replaceAll(RegExp(r.pattern, caseSensitive: false), ' ');
    }
    title = title
        .replaceAll(RegExp(r'[|_\[\]{}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s,.:;!?\-–—]+|[\s,.:;!?\-–—]+$'), '')
        .trim();
    if (title.isEmpty) continue;
    title = title[0].toUpperCase() + title.substring(1);

    res.add(ScheduleItem(
        weekday: day, hour: h, minute: m, durationMin: dur, title: title));
  }
  return res;
}
