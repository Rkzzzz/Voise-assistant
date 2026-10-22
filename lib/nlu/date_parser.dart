import 'text_buf.dart';

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Результат разбора дат/времени из фразы.
class ParsedDate {
  ParsedDate({
    this.day,
    this.hour,
    this.minute,
    this.exact,
    this.rangeStart,
    this.rangeEnd,
    required this.rest,
  });

  /// Дата без времени.
  final DateTime? day;
  final int? hour;
  final int? minute;

  /// Точный момент («через два часа»).
  final DateTime? exact;

  /// Диапазон [rangeStart, rangeEnd) — «на этой неделе».
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  /// Фраза с вырезанными датами.
  final TextBuf rest;

  bool get hasTime => hour != null || exact != null;
  bool get hasAny => day != null || hasTime || rangeStart != null;

  /// Собирает итоговый момент. Если задано только время — ближайшее будущее.
  DateTime? resolve(DateTime now, {DateTime? day}) {
    if (exact != null) return exact;
    final base = day ?? this.day;
    if (base == null && hour == null) return null;
    if (base == null) {
      var c = DateTime(now.year, now.month, now.day, hour!, minute ?? 0);
      if (!c.isAfter(now)) c = addDays(c, 1).add(Duration(hours: hour!, minutes: minute ?? 0));
      return c;
    }
    return DateTime(base.year, base.month, base.day, hour ?? 0, minute ?? 0);
  }
}

class DateParser {
  static const _b = '(?<![а-я0-9])';
  static const _e = '(?![а-я0-9])';

  static const _months = {
    'января': 1, 'февраля': 2, 'марта': 3, 'апреля': 4, 'мая': 5, 'июня': 6,
    'июля': 7, 'августа': 8, 'сентября': 9, 'октября': 10, 'ноября': 11,
    'декабря': 12,
  };

  static const _numWords = {
    'один': 1, 'одну': 1, 'два': 2, 'две': 2, 'три': 3, 'четыре': 4,
    'пять': 5, 'шесть': 6, 'семь': 7, 'восемь': 8, 'девять': 9, 'десять': 10,
    'пятнадцать': 15, 'двадцать': 20, 'тридцать': 30,
  };

  static const _weekdays = {
    'пон': 1, 'вто': 2, 'сре': 3, 'чет': 4, 'пят': 5, 'суб': 6, 'вос': 7,
  };

  static final _relHalf = RegExp('$_b' r'через\s+полчаса' '$_e');
  static final _rel = RegExp('$_b'
      r'через\s+(?:(\d+|[а-я]+)\s+)?'
      r'(минуту|минуты|минут|час|часа|часов|день|дня|дней|неделю|недели|недель)'
      '$_e');
  static final _dateText = RegExp('$_b'
      r'(?:(?:на|к|до)\s+)?(\d{1,2})\s+('
      '${_months.keys.join('|')}'
      ')$_e');
  static final _dateFull =
      RegExp(r'(?<![0-9:.])(\d{1,2})\.(\d{1,2})\.(\d{4})(?![0-9])');
  static final _after = RegExp('$_b' r'послезавтра' '$_e');
  static final _tomorrow = RegExp('$_b' r'(?:на\s+)?завтра' '$_e');
  static final _today = RegExp('$_b' r'(?:на\s+)?сегодня' '$_e');
  static final _endOfWeek = RegExp('$_b' r'до\s+конца\s+недели' '$_e');
  static final _nextWeek =
      RegExp('$_b' r'(?:на\s+)?след[а-я]*\s+недел[еюи]' '$_e');
  static final _thisWeek = RegExp('$_b'
      r'(?:на\s+)?(?:(?:этой|эту|текущей)\s+недел[еюи]|неделю|неделе)'
      '$_e');
  static final _weekday = RegExp('$_b'
      r'(?:(?:в|во|на|к|до)\s+)?(?:след[а-я]*\s+)?'
      r'(понедельник|вторник|среду|среда|среды|четверг|пятницу|пятница|'
      r'пятницы|субботу|суббота|субботы|воскресенье)'
      '$_e');

  static const _marks = r'(утра|утром|дня|днем|вечера|вечером|ночи|ночью)';
  static final _noon = RegExp('$_b' r'(?:в\s+)?полдень' '$_e');
  // Во всех трёх шаблонах: 1 — часы, 2 — минуты, 3 — «утра/вечера…».
  static final _timeV = RegExp('$_b'
      r'(?:в|к)\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*час[а-я]*)?'
      '(?:\\s*$_marks)?'
      r'(?![0-9:а-я])');
  static final _timeMk = RegExp(
      r'(?<![0-9:.])(\d{1,2})(?:[:.](\d{2}))?\s*(утра|дня|вечера|ночи)(?![а-я])');
  static final _timeColon =
      RegExp(r'(?<![0-9:.])(\d{1,2}):(\d{2})(?![0-9])()');
  static final _pod = RegExp('$_b(утром|днем|вечером)$_e');

  static int _hour(int h, String? mk) {
    if (mk == null || mk.isEmpty) return (h >= 1 && h <= 6) ? h + 12 : h;
    if (mk.startsWith('ут')) return h == 12 ? 0 : h;
    if (mk.startsWith('дн') || mk.startsWith('веч')) return h < 12 ? h + 12 : h;
    if (h == 12) return 0; // ночи
    return (h >= 6 && h < 12) ? h + 12 : h;
  }

  static ParsedDate parse(String text, DateTime now) {
    final b = TextBuf(text);
    final today = DateTime(now.year, now.month, now.day);
    DateTime? day, exact, rs, re;
    int? h, mi;

    // 1. «через полчаса / два часа / 3 дня»
    final half = _relHalf.firstMatch(b.low);
    if (half != null) {
      exact = now.add(const Duration(minutes: 30));
      b.cut(half);
    }
    final rel = _rel.firstMatch(b.low);
    if (rel != null && exact == null) {
      final g = rel.group(1);
      final n = g == null ? 1 : (int.tryParse(g) ?? _numWords[g] ?? 1);
      final u = rel.group(2)!;
      if (u.startsWith('мин')) {
        exact = now.add(Duration(minutes: n));
      } else if (u.startsWith('час')) {
        exact = now.add(Duration(hours: n));
      } else if (u.startsWith('д')) {
        day = addDays(today, n);
      } else {
        day = addDays(today, 7 * n);
      }
      b.cut(rel);
    }

    // 2. Явная дата: «15 марта», «15.03.2026»
    if (day == null && exact == null) {
      final dt = _dateText.firstMatch(b.low);
      final full = _dateFull.firstMatch(b.low);
      if (dt != null) {
        final dd = int.parse(dt.group(1)!);
        final mm = _months[dt.group(2)!]!;
        var c = DateTime(now.year, mm, dd);
        if (c.isBefore(today)) c = DateTime(now.year + 1, mm, dd);
        day = c;
        b.cut(dt);
      } else if (full != null) {
        day = DateTime(int.parse(full.group(3)!), int.parse(full.group(2)!),
            int.parse(full.group(1)!));
        b.cut(full);
      }
    }

    // 3. «сегодня / завтра / послезавтра»
    if (day == null && exact == null) {
      Match? m;
      if ((m = _after.firstMatch(b.low)) != null) {
        day = addDays(today, 2);
        b.cut(m!);
      } else if ((m = _tomorrow.firstMatch(b.low)) != null) {
        day = addDays(today, 1);
        b.cut(m!);
      } else if ((m = _today.firstMatch(b.low)) != null) {
        day = today;
        b.cut(m!);
      }
    }

    // 4. Недели
    if (day == null && exact == null) {
      Match? m;
      if ((m = _endOfWeek.firstMatch(b.low)) != null) {
        day = addDays(today, 7 - now.weekday);
        b.cut(m!);
      } else if ((m = _nextWeek.firstMatch(b.low)) != null) {
        rs = addDays(today, 8 - now.weekday);
        re = addDays(rs, 7);
        b.cut(m!);
      } else if ((m = _thisWeek.firstMatch(b.low)) != null) {
        rs = today;
        re = addDays(today, 8 - now.weekday);
        b.cut(m!);
      }
    }

    // 5. День недели
    if (day == null && exact == null && rs == null) {
      final m = _weekday.firstMatch(b.low);
      if (m != null) {
        final wd = _weekdays[m.group(1)!.substring(0, 3)]!;
        var ahead = (wd - now.weekday + 7) % 7;
        if (ahead == 0) ahead = 7;
        day = addDays(today, ahead);
        b.cut(m);
      }
    }

    // 6. Время
    if (exact == null) {
      final noon = _noon.firstMatch(b.low);
      if (noon != null) {
        h = 12;
        mi = 0;
        b.cut(noon);
      } else {
        final t = _timeV.firstMatch(b.low) ??
            _timeMk.firstMatch(b.low) ??
            _timeColon.firstMatch(b.low);
        if (t != null) {
          final hh = int.parse(t.group(1)!);
          final mm = int.tryParse(t.group(2) ?? '') ?? 0;
          final hr = _hour(hh, t.group(3));
          if (hh <= 23 && hr <= 23 && mm <= 59) {
            h = hr;
            mi = mm;
            b.cut(t);
          }
        }
      }
      final pod = _pod.firstMatch(b.low);
      if (pod != null) {
        h ??= switch (pod.group(1)) { 'утром' => 9, 'днем' => 13, _ => 19 };
        mi ??= 0;
        b.cut(pod);
      }
    }

    return ParsedDate(
      day: day,
      hour: h,
      minute: mi,
      exact: exact,
      rangeStart: rs,
      rangeEnd: re,
      rest: b,
    );
  }
}
