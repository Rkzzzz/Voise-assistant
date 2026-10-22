import '../models/entry.dart';
import 'date_parser.dart';
import 'search.dart';
import 'text_buf.dart';

enum Intent { create, list, search, complete, delete, reschedule, unknown }

/// Распознанная команда: что делать, с какой записью и когда.
class Command {
  const Command(
    this.intent, {
    this.type,
    this.text = '',
    required this.date,
    this.refersToLast = false,
  });

  final Intent intent;

  /// create — тип новой записи; list/search/… — фильтр по типу (может быть null).
  final EntryType? type;

  /// create — название; search/complete/… — поисковый запрос.
  final String text;
  final ParsedDate date;

  /// «её», «это» — речь о последней записи из диалога.
  final bool refersToLast;

  String get title => text;
}

/// Правила для русского языка. Реализация намеренно изолирована за
/// [IntentParser.parse]: её можно заменить на LLM с тем же результатом.
class IntentParser {
  static const _nb = '(?<![а-я])';
  static const _ne = '(?![а-я])';

  static final _createVerbs = RegExp('$_nb'
      r'(?:пожалуйста|напомни(?:\s+мне)?|добавь|добавить|поставь|создай|запиши|'
      r'запланируй|запланировать|назначь|заведи)'
      '$_ne');
  static final _remind = RegExp('$_nb' r'напомни' '$_ne');
  static final _meeting = RegExp('$_nb'
      r'(?:встреч[а-я]*|созвон[а-я]*|митинг[а-я]*|совещани[а-я]*|'
      r'планерк[а-я]*|собеседовани[а-я]*)');
  static final _wTask = RegExp('$_nb' r'задач[а-я]*');
  static final _wRem = RegExp('$_nb' r'напоминани[а-я]*');

  static final _delete = RegExp(
      r'^\s*(?:а\s+)?(?:пожалуйста\s+)?(?:удали|удалить|убери|сотри|отмени|отменить)(?![а-я])');
  static final _resched = RegExp('$_nb' r'(?:перенес|перенест|сдвин|передвин)[а-я]*');
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
  static final _need = RegExp('$_nb' r'(?:нужно|надо|необходимо|не\s+забыть|не\s+забудь)' '$_ne');
  static final _modVerbs = RegExp('$_nb'
      r'(?:а|отметь|пометь|как|выполненн[а-я]*|сделанн[а-я]*|готов[а-я]*|'
      r'выполнил[а-я]*|сделал[а-я]*|завершил[а-я]*|закрой|готово|я|'
      r'перенес[а-я]*|перенест[а-я]*|сдвин[а-я]*|передвин[а-я]*|'
      r'удали[а-я]*|убери|сотри|отмени[а-я]*|пожалуйста)'
      '$_ne');
  static final _pronoun = RegExp('$_nb' r'(?:ее|его|это|эту|этот|нее)' '$_ne');

  static EntryType? _filter(String low) {
    if (_meeting.hasMatch(low)) return EntryType.meeting;
    if (_wRem.hasMatch(low)) return EntryType.reminder;
    if (_wTask.hasMatch(low)) return EntryType.task;
    return null;
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

    if (_delete.hasMatch(low)) return target(Intent.delete);
    if (_resched.hasMatch(low)) return target(Intent.reschedule);
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

  static Command _create(ParsedDate d) {
    final low = d.rest.low;
    final type = _remind.hasMatch(low)
        ? EntryType.reminder
        : (_meeting.hasMatch(low) ? EntryType.meeting : EntryType.task);

    final b = TextBuf.pair(d.rest.low, d.rest.orig)
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

    var t = b.clean
        .replaceAll(RegExp(r'^[\s,.:;!?\-–—]+|[\s,.:;!?\-–—]+$'), '')
        .replaceAll(RegExp(r'^(?:[вВ]|[нН]а|[дД]о|[кК]|[иИ])\s+'), '')
        .replaceAll(RegExp(r'\s+(?:[вВ]|[нН]а|[дД]о|[кК])$'), '')
        .trim();
    if (t.isNotEmpty) t = t[0].toUpperCase() + t.substring(1);
    return Command(Intent.create, type: type, text: t, date: d);
  }
}
