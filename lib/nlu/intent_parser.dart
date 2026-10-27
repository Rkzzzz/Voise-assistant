import '../models/entry.dart';
import 'date_parser.dart';
import 'search.dart';
import 'text_buf.dart';

enum Intent {
  create,
  list,
  search,
  complete,
  delete,
  reschedule,
  mark,
  setUserName,
  setAssistantName,
  askAssistantName,
  askUserName,
  unknown,
}

/// Распознанная команда: что делать, с какой записью и когда.
class Command {
  const Command(
    this.intent, {
    this.type,
    this.text = '',
    required this.date,
    this.refersToLast = false,
    this.untimed = false,
    this.durationMin,
  });

  final Intent intent;

  /// create — тип новой записи; list/search/… — фильтр по типу (может быть null).
  final EntryType? type;

  /// create — название; search/complete/… — поисковый запрос; set*Name — имя.
  final String text;
  final ParsedDate date;

  /// «её», «это» — речь о последней записи из диалога.
  final bool refersToLast;

  /// Явно сказано «без времени».
  final bool untimed;
  final int? durationMin;

  String get title => text;
}

/// Правила для русского языка. Реализация изолирована за [IntentParser.parse]:
/// её можно заменить на LLM с тем же результатом.
class IntentParser {
  static const _nb = '(?<![а-я])';
  static const _ne = '(?![а-я])';

  static final _createVerbs = RegExp('$_nb'
      r'(?:пожалуйста|напомни(?:\s+мне)?|добавь|добавить|поставь|создай|запиши|'
      r'запланируй|запланировать|назначь|заведи)'
      '$_ne');
  static final _markVerbs = RegExp('$_nb'
      r'(?:запомни|отметь|запиши|добавь|поставь|создай|сохрани|пометь)'
      '$_ne');
  static final _birthday = RegExp('$_nb'
      r'(?:день\s+рожден[а-я]*|годовщин[а-я]*|юбиле[а-я]*|именин[а-я]*)');
  static final _remind = RegExp('$_nb' r'напомни' '$_ne');
  static final _meeting = RegExp('$_nb'
      r'(?:встреч[а-я]*|созвон[а-я]*|митинг[а-я]*|совещани[а-я]*|'
      r'планерк[а-я]*|собеседовани[а-я]*)');
  static final _wTask = RegExp('$_nb' r'задач[а-я]*');
  static final _wRem = RegExp('$_nb' r'напоминани[а-я]*');

  static final _delete = RegExp(
      r'^\s*(?:а\s+)?(?:пожалуйста\s+)?(?:удали|удалить|убери|сотри|отмени|отменить)(?![а-я])');
  static final _resched =
      RegExp('$_nb' r'(?:перенес|перенест|сдвин|передвин)[а-я]*');
  static final _complete = RegExp('$_nb'
      r'(?:отметь|пометь|выполнил[а-я]*|сделал[а-я]*|завершил[а-я]*|закрой|готово)'
      '$_ne');
  static final _search = RegExp('$_nb'
      r'(?:найд[а-я]*|поищи|ищи|когда|помнишь)'
      '$_ne');
  static final _list = RegExp('$_nb'
      r'(?:что\s+у\s+меня|что\s+на|что\s+запланирован[а-я]*|что\s+по\s+плану|'
      r'какие|какой|покажи|есть\s+ли|план[а-я]*|распис[а-я]+|'
      r'чем\s+занят[а-я]*|что\s+мне|ближайш[а-я]+)');
  static final _need =
      RegExp('$_nb' r'(?:нужно|надо|необходимо|не\s+забыть|не\s+забудь)' '$_ne');
  static final _modVerbs = RegExp('$_nb'
      r'(?:а|отметь|пометь|как|выполненн[а-я]*|сделанн[а-я]*|готов[а-я]*|'
      r'выполнил[а-я]*|сделал[а-я]*|завершил[а-я]*|закрой|готово|я|'
      r'перенес[а-я]*|перенест[а-я]*|сдвин[а-я]*|передвин[а-я]*|'
      r'удали[а-я]*|убери|сотри|отмени[а-я]*|пожалуйста)'
      '$_ne');
  static final _pronoun = RegExp('$_nb' r'(?:ее|его|это|эту|этот|нее)' '$_ne');

  // имена
  static final _askAsst = RegExp(r'как\s+тебя\s+(?:зовут|звать)');
  static final _askUser = RegExp(r'как\s+меня\s+(?:зовут|звать)');
  static const _nameWord = r'\s+([а-яa-z][а-яa-z\-]*)';
  static final _setUser = RegExp('$_nb'
      r'(?:меня\s+зовут|называй\s+меня|зови\s+меня|обращайся\s+ко\s+мне(?:\s+как)?)'
      '$_nameWord');
  static final _setAsst = RegExp('$_nb'
      r'(?:тебя\s+(?:теперь\s+|будут\s+)?(?:зовут|звать)|буду\s+звать\s+тебя|'
      r'называйся|твое\s+имя(?:\s+будет)?)'
      '$_nameWord');

  // без времени / длительность
  static final _untimed = RegExp('$_nb'
      r'(?:без\s+времени|на\s+весь\s+день|в\s+течение\s+дня|весь\s+день)'
      '$_ne');
  static final _dur = RegExp('$_nb'
      r'на\s+(?:(\d+|один|два|три|четыре|пять|шесть)\s+час(?:а|ов)?|час|'
      r'полтора\s+часа|полчаса)'
      '$_ne');
  static final _durMin =
      RegExp('$_nb' r'на\s+(\d+)\s+мин(?:ут[а-я]*)?' '$_ne');
  static const _words = {
    'один': 1, 'два': 2, 'три': 3, 'четыре': 4, 'пять': 5, 'шесть': 6,
  };

  static EntryType? _filter(String low) {
    if (_meeting.hasMatch(low)) return EntryType.meeting;
    if (_wRem.hasMatch(low)) return EntryType.reminder;
    if (_wTask.hasMatch(low)) return EntryType.task;
    return null;
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Имя стоит в конце совпадения, поэтому берём его по длине группы.
  static String _nameFrom(RegExpMatch m, TextBuf b) {
    final g = m.group(1)!;
    return _cap(b.orig.substring(m.end - g.length, m.end));
  }

  static Command parse(String input, DateTime now) {
    final d = DateParser.parse(input, now);
    final low = d.rest.low;

    Command target(Intent i) {
      final b = TextBuf.pair(d.rest.low, d.rest.orig)..cutAll(_modVerbs);
      final q = b.clean;
      return Command(
        i,
        type: _filter(low),
        text: q,
        date: d,
        refersToLast: _pronoun.hasMatch(b.low) || Search.tokens(q).isEmpty,
      );
    }

    // Имена
    if (_askAsst.hasMatch(low)) return Command(Intent.askAssistantName, date: d);
    if (_askUser.hasMatch(low)) return Command(Intent.askUserName, date: d);
    final su = _setUser.firstMatch(low);
    if (su != null) {
      return Command(Intent.setUserName,
          text: _nameFrom(su, d.rest), date: d);
    }
    final sa = _setAsst.firstMatch(low);
    if (sa != null) {
      return Command(Intent.setAssistantName,
          text: _nameFrom(sa, d.rest), date: d);
    }

    if (_delete.hasMatch(low)) return target(Intent.delete);
    if (_resched.hasMatch(low)) return target(Intent.reschedule);

    // Особая дата: «запомни день рождения Ивана 15 марта»
    if (_birthday.hasMatch(low) &&
        _markVerbs.hasMatch(low) &&
        !_remind.hasMatch(low)) {
      final b = TextBuf.pair(d.rest.low, d.rest.orig)
        ..cutAll(_markVerbs)
        ..cutAll(_createVerbs);
      return Command(Intent.mark, text: _finish(b), date: d);
    }

    if (_createVerbs.hasMatch(low)) return _create(d);
    if (_complete.hasMatch(low)) return target(Intent.complete);
    if (_search.hasMatch(low)) {
      return Command(Intent.search,
          type: _filter(low), text: d.rest.clean, date: d);
    }
    if (_list.hasMatch(low)) {
      return Command(Intent.list, type: _filter(low), date: d);
    }
    if (d.hasAny || _meeting.hasMatch(low) || _need.hasMatch(low)) {
      return _create(d);
    }
    return Command(Intent.unknown, date: d);
  }

  static int? _duration(RegExpMatch m) {
    final g = m.group(1);
    if (g != null) return (int.tryParse(g) ?? _words[g] ?? 1) * 60;
    final s = m.group(0)!;
    if (s.contains('полтора')) return 90;
    if (s.contains('полчаса')) return 30;
    return 60;
  }

  static Command _create(ParsedDate d) {
    final low = d.rest.low;
    final type = _remind.hasMatch(low)
        ? EntryType.reminder
        : (_meeting.hasMatch(low) ? EntryType.meeting : EntryType.task);

    final b = TextBuf.pair(d.rest.low, d.rest.orig);
    final untimed = _untimed.hasMatch(b.low);
    b.cutAll(_untimed);
    int? dur;
    final mm = _durMin.firstMatch(b.low);
    if (mm != null) {
      dur = int.parse(mm.group(1)!);
      b.cut(mm);
    }
    final dm = _dur.firstMatch(b.low);
    if (dm != null) {
      dur = _duration(dm);
      b.cut(dm);
    }
    b
      ..cutAll(_createVerbs)
      ..cutAll(RegExp('$_nb' r'(?:задачу|задача|напоминание)' '$_ne'))
      ..cutAll(RegExp('$_nb' r'у\s+меня' '$_ne'))
      ..cutAll(RegExp('$_nb' r'(?:мне\s+)?(?:нужно|надо|необходимо)' '$_ne'));
    for (final m in RegExp('$_nb' r'встречу' '$_ne')
        .allMatches(b.low)
        .toList()
        .reversed) {
      b.replace(m, 'встреча');
    }
    return Command(Intent.create,
        type: type,
        text: _finish(b),
        date: d,
        untimed: untimed,
        durationMin: dur);
  }

  /// Чистка и оформление названия.
  static String _finish(TextBuf b) {
    var t = b.clean
        .replaceAll(RegExp(r'^[\s,.:;!?\-–—]+|[\s,.:;!?\-–—]+$'), '')
        .replaceAll(RegExp(r'^(?:[вВ]|[нН]а|[дД]о|[кК]|[иИ])\s+'), '')
        .replaceAll(RegExp(r'\s+(?:[вВ]|[нН]а|[дД]о|[кК])$'), '')
        .trim();
    return _cap(t);
  }
}
