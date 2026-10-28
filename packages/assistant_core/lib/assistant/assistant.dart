import '../data/entry_repository.dart';
import '../models/entry.dart';
import '../models/mark.dart';
import '../nlu/date_parser.dart';
import '../nlu/intent_parser.dart';
import '../nlu/schedule_parser.dart';
import '../nlu/search.dart';
import '../nlu/text_buf.dart';
import '../services/day_load.dart';
import '../services/holidays.dart';
import '../services/notifier.dart';

class AssistantReply {
  const AssistantReply(this.text);
  final String text;
}

/// Что ассистенту нужно знать о настройках. Реализуется настройками
/// приложения (SharedPreferences) и настройками пользователя на сервере.
abstract class AssistantSettings {
  String get userName;
  String get assistantName;
  void change({String? userName, String? assistantName});
}

/// Настройки по умолчанию — для тестов и сервера.
class MemoryAssistantSettings implements AssistantSettings {
  MemoryAssistantSettings(
      {this.userName = '', this.assistantName = 'Ассистент'});

  @override
  String userName;
  @override
  String assistantName;

  @override
  void change({String? userName, String? assistantName}) {
    this.userName = userName ?? this.userName;
    this.assistantName = assistantName ?? this.assistantName;
  }
}

enum _PK { time, when, choose, confirm }

/// Незавершённый диалог: ассистент задал уточняющий вопрос.
class _Pending {
  _Pending(this.kind);
  final _PK kind;
  EntryType? type;
  String? title;
  DateTime? day;
  int? duration;
  Entry? entry;
  Intent? action;
  ParsedDate? date;
  List<Entry> candidates = const [];
  Entry? draft; // запись, ожидающая подтверждения при накладке
  DateTime? alt; // ближайшее свободное время
}

const _wdIn = [
  'в понедельник',
  'во вторник',
  'в среду',
  'в четверг',
  'в пятницу',
  'в субботу',
  'в воскресенье',
];
const _monthsGen = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _plural(int n, String one, String few, String many) {
  final a = n % 100, b = n % 10;
  if (a >= 11 && a <= 14) return many;
  if (b == 1) return one;
  if (b >= 2 && b <= 4) return few;
  return many;
}

/// Бизнес-логика: принимает текст, меняет данные, формирует ответ.
/// Не знает ни о микрофоне, ни о виджетах, ни о SQL — поэтому одинаково
/// работает в приложении и на сервере навыка Алисы.
class Assistant {
  Assistant(
    this.repo, {
    DateTime Function()? clock,
    AssistantSettings? settings,
    Notifier? notifier,
    this.repoFor,
    this.aiParser,
  })  : _clock = clock ?? DateTime.now,
        settings = settings ?? MemoryAssistantSettings(),
        notifier = notifier ?? NoopNotifier();

  EntryRepository repo;

  /// Создаёт хранилище для профиля по его номеру (null — профили выключены).
  final EntryRepository Function(int profile)? repoFor;
  final AssistantSettings settings;
  final Notifier notifier;

  /// Запасной разбор фразы (YandexGPT), когда правила не поняли запрос.
  /// Возвращает null, если модель недоступна или не уверена.
  final Future<Command?> Function(String text, DateTime now)? aiParser;

  /// Уведомление об изменении данных (в приложении — перерисовка экранов).
  void Function()? onChanged;

  final DateTime Function() _clock;

  Entry? _last; // контекст диалога: «перенеси её на завтра»
  _Pending? _pending;

  static const help =
      'Я помогу с задачами, напоминаниями и встречами. Например: '
      '«Напомни завтра в 10 утра позвонить Ивану», '
      '«Что у меня сегодня?», «Найди задачу про презентацию».';

  static final _cancelRe =
      RegExp(r'^\s*(?:отмена|забудь|не надо|не нужно|стоп|отбой)');
  static final _noTimeRe = RegExp(
      r'без\s+времени|неважно|не\s+важно|в\s+течение\s+дня|на\s+весь\s+день|любое');
  static final _keepRe = RegExp(r'все\s+равно|оставь|как\s+есть');
  static final _yesRe = RegExp(r'^\s*(?:да|давай|ок|окей|хорошо|поставь|ага)');
  static final _noRe = RegExp(r'^\s*(?:нет|отмена|не\s+надо|отбой|стоп)');
  static const _ords = ['перв', 'втор', 'трет', 'четверт', 'пят'];

  static final _splitRe = RegExp(
      r'(?:,\s*)?(?:(?<![а-я])(?:а\s+также|и\s+еще|а\s+еще|затем|потом|после\s+этого)(?![а-я])|'
      r'\sи\s+(?=(?:добавь|поставь|напомни|запиши|удали|покажи|найди|перенеси|отметь|запомни)(?![а-я])))\s*');

  void _changed() => onChanged?.call();

  // ---------- Публичный API для интерфейса ----------

  DateTime get now => _clock();

  Future<List<Entry>> entriesBetween(DateTime from, DateTime to) =>
      repo.between(from, to);

  Future<List<Mark>> allMarks() => repo.marks();

  Future<Entry> save(Entry e) => _commit(e);

  Future<void> deleteEntry(Entry e) async {
    if (e.id == null) return;
    await repo.remove(e.id!);
    await notifier.cancel(e.id!);
    if (_last?.id == e.id) _last = null;
    _changed();
  }

  Future<void> toggleDone(Entry e) => _commit(e.copyWith(done: !e.done));

  Future<void> addMark(Mark m) async {
    await repo.addMark(m);
    _changed();
  }

  Future<void> removeMark(Mark m) async {
    if (m.id == null) return;
    await repo.removeMark(m.id!);
    _changed();
  }

  /// Переключение на другой профиль пользователя.
  Future<void> switchProfile(int i) async {
    final make = repoFor;
    if (make == null) return;
    repo = make(i);
    _last = null;
    _pending = null;
    await notifier.cancelAll();
    await resyncNotifications();
    _changed();
  }

  Future<void> resyncNotifications() async =>
      notifier.syncAll(await repo.all());

  /// Добавляет занятия из расписания на [weeks] недель вперёд.
  Future<int> addSchedule(List<ScheduleItem> items,
      {int weeks = 4, EntryType type = EntryType.meeting}) async {
    final n = _clock();
    final today = DateTime(n.year, n.month, n.day);
    var count = 0;
    for (final it in items) {
      final first = addDays(today, (it.weekday - today.weekday) % 7);
      for (var w = 0; w < weeks; w++) {
        final day = addDays(first, 7 * w);
        final due = DateTime(day.year, day.month, day.day, it.hour, it.minute);
        if (due.isBefore(n)) continue;
        final saved = await repo.add(Entry(
          type: type,
          title: it.title,
          dueAt: due,
          hasTime: true,
          createdAt: n,
          durationMin: it.durationMin,
        ));
        await notifier.sync(saved);
        count++;
      }
    }
    _changed();
    return count;
  }

  /// Ближайшее предстоящее событие со временем.
  Future<Entry?> nextUpcoming() async {
    final n = _clock();
    Entry? best;
    for (final e in await repo.all()) {
      if (e.done || !e.hasTime || e.dueAt == null) continue;
      if (e.endAt!.isBefore(n)) continue;
      if (best == null || e.dueAt!.isBefore(best.dueAt!)) best = e;
    }
    return best;
  }

  /// Встреча, с которой пересекается [e] (если есть).
  Future<Entry?> conflictFor(Entry e) async {
    if (!e.blocksTime) return null;
    for (final o in await repo.all()) {
      if (o.id == e.id || o.done) continue;
      if (e.overlaps(o)) return o;
    }
    return null;
  }

  /// Ближайшее свободное время для встречи [e].
  Future<DateTime> nextFree(Entry e) async {
    final others = (await repo.all())
        .where((o) => o.id != e.id && !o.done && o.blocksTime)
        .toList();
    var start = e.dueAt!;
    for (var i = 0; i < 48; i++) {
      final cand = e.copyWith(dueAt: start);
      Entry? hit;
      for (final o in others) {
        if (cand.overlaps(o)) {
          hit = o;
          break;
        }
      }
      if (hit == null) return start;
      start = hit.endAt!;
    }
    return start;
  }

  /// Занятость дня.
  DayLoad loadOf(Iterable<Entry> dayEntries) => dayLoad(dayEntries);

  // ---------- Разбор фразы ----------

  String _addr(String s) {
    final n = settings.userName.trim();
    if (n.isEmpty || s.isEmpty) return s;
    return '$n, ${s[0].toLowerCase()}${s.substring(1)}';
  }

  String _stripName(String t) {
    final n = settings.assistantName.trim().toLowerCase();
    if (n.isEmpty) return t;
    if (!t.toLowerCase().startsWith(n)) return t;
    final rest = t.substring(n.length);
    if (rest.isNotEmpty && !RegExp(r'^[\s,.:!\-]').hasMatch(rest)) return t;
    return rest.replaceFirst(RegExp(r'^[\s,.:!\-]+'), '');
  }

  List<String> _split(String t) {
    final low = TextBuf(t).low;
    final parts = <String>[];
    var from = 0;
    for (final m in _splitRe.allMatches(low)) {
      if (m.start > from) parts.add(t.substring(from, m.start));
      from = m.end;
    }
    parts.add(t.substring(from));
    final res = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    return res.isEmpty ? [t] : res;
  }

  Future<AssistantReply> handle(String input) async {
    final raw = input.trim();
    final text = _stripName(raw);
    if (text.isEmpty) {
      return AssistantReply(raw.isEmpty
          ? 'Я ничего не услышал. Повторите, пожалуйста.'
          : _addr('слушаю вас.'));
    }
    final n = _clock();
    if (_pending != null) {
      final r = await _continuePending(text, n);
      if (r != null) return r;
    }
    final parts = _split(text);
    if (parts.length == 1) return _handleOne(parts.first, n);

    // составной запрос: несколько действий в одной фразе
    final replies = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final r = await _handleOne(parts[i], n);
      replies.add(r.text);
      if (_pending != null && i < parts.length - 1) {
        replies.add('Остальную часть запроса повторите после ответа.');
        break;
      }
    }
    return AssistantReply(replies.join('\n\n'));
  }

  Future<AssistantReply> _handleOne(String text, DateTime n) async {
    var cmd = IntentParser.parse(text, n);
    if (cmd.intent == Intent.unknown && aiParser != null) {
      // правила не поняли фразу — пробуем YandexGPT
      final ai = await aiParser!(text, n);
      if (ai != null) cmd = ai;
    }
    return _dispatch(cmd, n);
  }

  Future<AssistantReply> _dispatch(Command cmd, DateTime n) async {
    switch (cmd.intent) {
      case Intent.create:
        return _create(cmd.title, cmd.type!, cmd.date, n,
            untimed: cmd.untimed, duration: cmd.durationMin);
      case Intent.list:
        return _list(cmd, n);
      case Intent.search:
        return _search(cmd, n);
      case Intent.complete:
      case Intent.delete:
      case Intent.reschedule:
        return _modify(cmd, n);
      case Intent.mark:
        return _mark(cmd);
      case Intent.setUserName:
        settings.change(userName: cmd.text);
        _changed();
        return AssistantReply('Хорошо, буду обращаться к вам: ${cmd.text}.');
      case Intent.setAssistantName:
        settings.change(assistantName: cmd.text);
        _changed();
        return AssistantReply('Теперь меня зовут ${cmd.text}.');
      case Intent.askAssistantName:
        return AssistantReply('Меня зовут ${settings.assistantName}.');
      case Intent.askUserName:
        final u = settings.userName;
        return AssistantReply(u.isEmpty
            ? 'Пока не знаю. Скажите: «Называй меня …».'
            : 'Вас зовут $u.');
      case Intent.unknown:
        return const AssistantReply(help);
    }
  }

  // ---------- Уточняющие вопросы ----------

  Future<AssistantReply?> _continuePending(String text, DateTime n) async {
    final p = _pending!;
    final low = TextBuf(text).low;
    if (p.kind != _PK.confirm && _cancelRe.hasMatch(low)) {
      _pending = null;
      return const AssistantReply('Хорошо, отменено.');
    }
    switch (p.kind) {
      case _PK.confirm:
        _pending = null;
        final d = p.draft!;
        if (_keepRe.hasMatch(low)) {
          return _finishSave(d, n);
        }
        if (_yesRe.hasMatch(low) && p.alt != null) {
          return _finishSave(d.copyWith(dueAt: p.alt), n);
        }
        if (_noRe.hasMatch(low)) {
          return const AssistantReply('Хорошо, не добавляю.');
        }
        return null; // это новая команда
      case _PK.time:
        final d = DateParser.parse(text, n);
        if (_noTimeRe.hasMatch(low)) {
          _pending = null;
          return _create(p.title!, p.type!, d, n,
              day: p.day, untimed: true, duration: p.duration);
        }
        if (d.hasTime) {
          _pending = null;
          return _create(p.title!, p.type!, d, n,
              day: d.day ?? p.day, duration: p.duration);
        }
        if (d.day != null) {
          p.day = d.day;
          return const AssistantReply(
              'А на какое время? Можно сказать «без времени».');
        }
        _pending = null;
        return null; // это новая команда
      case _PK.when:
        final d = DateParser.parse(text, n);
        if (!d.hasAny) {
          _pending = null;
          return null;
        }
        _pending = null;
        return _reschedule(p.entry!, d, n);
      case _PK.choose:
        Entry? pick;
        final digits = RegExp(r'\d+').firstMatch(low);
        if (digits != null) {
          final i = int.parse(digits.group(0)!) - 1;
          if (i >= 0 && i < p.candidates.length) pick = p.candidates[i];
        }
        if (pick == null) {
          for (var i = 0; i < _ords.length && i < p.candidates.length; i++) {
            if (RegExp('(?<![а-я])${_ords[i]}').hasMatch(low)) {
              pick = p.candidates[i];
              break;
            }
          }
        }
        if (pick == null) {
          final r = Search.rank(text, p.candidates);
          if (r.isNotEmpty && (r.length == 1 || r[0].score > r[1].score)) {
            pick = r.first.entry;
          }
        }
        _pending = null;
        if (pick == null) return null;
        return _apply(p.action!, pick, p.date!, n);
    }
  }

  // ---------- Сохранение с проверкой накладок ----------

  Future<Entry> _commit(Entry e) async {
    // Отметка времени нужна синхронизации: по ней выбирается более свежая
    // версия записи на устройстве и в облаке.
    final stamped = e.copyWith(updatedAt: _clock());
    Entry saved;
    if (stamped.id == null) {
      saved = await repo.add(stamped);
    } else {
      await repo.update(stamped);
      saved = stamped;
    }
    await notifier.sync(saved);
    _last = saved;
    _changed();
    return saved;
  }

  /// Сохраняет запись; при накладке встреч задаёт вопрос.
  Future<AssistantReply> _saveChecked(Entry e, DateTime n,
      {required String Function(Entry saved) okText}) async {
    final c = await conflictFor(e);
    if (c == null) return AssistantReply(okText(await _commit(e)));
    final alt = await nextFree(e);
    _pending = _Pending(_PK.confirm)
      ..draft = e
      ..alt = alt;
    final altEntry = e.copyWith(dueAt: alt);
    return AssistantReply('В это время уже есть «${c.title}» '
        '(${_hm(c.dueAt!)}–${_hm(c.endAt!)}). '
        'Ближайшее свободное время — ${_when(altEntry, n)}. '
        'Поставить на него? Скажите «да», «всё равно» (оставить как есть) или «нет».');
  }

  Future<AssistantReply> _finishSave(Entry e, DateTime n) async {
    final saved = await _commit(e);
    return AssistantReply(
        _addr('готово: «${saved.title}», ${_when(saved, n)}.'));
  }

  // ---------- Создание ----------

  Future<AssistantReply> _create(
    String title,
    EntryType type,
    ParsedDate d,
    DateTime n, {
    DateTime? day,
    bool untimed = false,
    int? duration,
  }) async {
    if (title.isEmpty) {
      return const AssistantReply('Что именно нужно записать?');
    }
    final today = DateTime(n.year, n.month, n.day);
    // «на этой неделе» → срок в конце недели
    day ??= d.day ?? (d.rangeEnd == null ? null : addDays(d.rangeEnd!, -1));

    if (type != EntryType.task && !d.hasTime && !untimed) {
      _pending = _Pending(_PK.time)
        ..type = type
        ..title = title
        ..day = day
        ..duration = duration;
      final meeting = type == EntryType.meeting;
      const tail = ' Можно сказать «без времени».';
      return AssistantReply(day == null
          ? (meeting
              ? 'На какой день и время поставить встречу?$tail'
              : 'Когда напомнить?$tail')
          : (meeting
              ? 'На какое время поставить встречу?$tail'
              : 'На какое время поставить напоминание?$tail'));
    }

    final hasTime = d.hasTime && !untimed;
    DateTime? due;
    if (hasTime) {
      due = d.resolve(n, day: day);
    } else {
      final base = day ?? (type == EntryType.task ? null : today);
      due = base == null ? null : DateTime(base.year, base.month, base.day);
    }

    // нельзя ставить событие на время, которое уже прошло
    if (hasTime && due != null && due.isBefore(n)) {
      _pending = _Pending(_PK.time)
        ..type = type
        ..title = title
        ..day = day;
      return AssistantReply(
          'Это время уже прошло (${_when(Entry(type: type, title: title, dueAt: due, hasTime: true, createdAt: n), n)}). '
          'Назовите другое время или скажите «отмена».');
    }

    final entry = Entry(
      type: type,
      title: title,
      dueAt: due,
      hasTime: hasTime,
      createdAt: n,
      durationMin: duration ?? kMeetingMinutes,
    );
    _last = entry;

    return _saveChecked(entry, n, okText: (s) {
      final when = _when(s, n);
      return _addr(switch (type) {
        EntryType.reminder => 'напомню $when: «$title».',
        EntryType.meeting => 'встреча добавлена: «$title», $when.',
        EntryType.task => s.dueAt == null
            ? 'задача добавлена: «$title».'
            : 'задача добавлена: «$title», срок — $when.',
      });
    });
  }

  // ---------- Особые даты ----------

  Future<AssistantReply> _mark(Command c) async {
    final day = c.date.day;
    if (day == null) {
      return const AssistantReply(
          'Какого числа? Например: «Запомни день рождения Ивана 15 марта».');
    }
    final title = c.text.isEmpty ? 'Особая дата' : c.text;
    await repo.addMark(Mark(
        title: title,
        month: day.month,
        day: day.day,
        kind: Mark.kindOf(title)));
    _changed();
    return AssistantReply(_addr(
        'отметил: «$title» — ${day.day} ${_monthsGen[day.month - 1]}, каждый год.'));
  }

  // ---------- Список за период ----------

  Future<AssistantReply> _list(Command c, DateTime n) async {
    final today = DateTime(n.year, n.month, n.day);
    final d = c.date;
    late DateTime from, to;
    late String label;
    var range = false;
    var byDefault = false;
    if (d.rangeStart != null) {
      from = d.rangeStart!;
      to = d.rangeEnd!;
      label = from.isAfter(today) ? 'на следующей неделе' : 'на этой неделе';
      range = true;
    } else if (d.day != null) {
      from = d.day!;
      to = addDays(from, 1);
      label = _dayLabel(from, n);
    } else {
      from = today;
      to = addDays(today, 7);
      label = 'в ближайшие 7 дней';
      range = true;
      byDefault = true;
    }

    var items = await repo.between(from, to);
    if (c.type != null) items = items.where((e) => e.type == c.type).toList();
    final prefix = switch (c.type) {
      EntryType.task => 'Задачи',
      EntryType.meeting => 'Встречи',
      EntryType.reminder => 'Напоминания',
      null => 'Планы',
    };

    // праздники и особые даты
    final extras = <String>[];
    final marks = await repo.marks();
    for (var day = from; day.isBefore(to); day = addDays(day, 1)) {
      final when = range ? '${_dayLabel(day, n)}: ' : '';
      final h = holidayName(day);
      if (h != null) extras.add('🎉 $when$h');
      for (final m in marks.where((m) => m.fallsOn(day))) {
        extras.add('${m.emoji} $when${m.title}');
      }
    }

    final lines = items.map((e) => _line(e, n, withDay: range)).toList();
    if (byDefault) {
      final undated = (await repo.all()).where((e) =>
          e.dueAt == null && !e.done && (c.type == null || e.type == c.type));
      lines.addAll(undated.map((e) => '• без срока — ${e.title}'));
    }
    if (lines.isEmpty && extras.isEmpty) {
      return AssistantReply('$prefix $label: ничего нет.');
    }
    if (items.isNotEmpty) _last = items.first;
    final head =
        lines.isEmpty ? '$prefix $label: записей нет.' : '$prefix $label:';
    final load = (!range && items.isNotEmpty)
        ? '\nЗанятость дня: ${dayLoad(items).label}.'
        : '';
    return AssistantReply([head, ...extras, ...lines].join('\n') + load);
  }

  // ---------- Поиск ----------

  Future<AssistantReply> _search(Command c, DateTime n) async {
    final res = Search.rank(c.text, await repo.all(), type: c.type);
    if (res.isEmpty) {
      return const AssistantReply(
          'Ничего похожего не нашлось. Попробуйте переформулировать запрос.');
    }
    _last = res.first.entry;
    final top = res.take(5).map((s) => _line(s.entry, n, withDay: true));
    final cnt = res.length;
    return AssistantReply(cnt == 1
        ? 'Нашёл:\n${top.first}'
        : 'Нашёл $cnt ${_plural(cnt, 'запись', 'записи', 'записей')}'
            '${cnt > 5 ? ' (показываю 5)' : ''}:\n${top.join('\n')}');
  }

  // ---------- Изменение / удаление / выполнение ----------

  Future<AssistantReply> _modify(Command c, DateTime n) async {
    Entry? target;
    if (c.refersToLast &&
        _last != null &&
        (c.type == null || _last!.type == c.type)) {
      target = _last;
    } else {
      final res = Search.rank(c.text, await repo.all(), type: c.type);
      if (res.isEmpty) {
        return const AssistantReply('Не нашёл такую запись. О какой речь?');
      }
      final ambiguous = res.length > 1 && res[0].score == res[1].score;
      if (!ambiguous) {
        target = res.first.entry;
      } else {
        final tied = res.where((s) => s.score == res[0].score).take(5).toList();
        _pending = _Pending(_PK.choose)
          ..action = c.intent
          ..date = c.date
          ..candidates = tied.map((s) => s.entry).toList();
        final lines = [
          for (var i = 0; i < tied.length; i++)
            '${i + 1}) ${_line(tied[i].entry, n, withDay: true).substring(2)}',
        ];
        return AssistantReply(
            'Нашёл несколько записей. Какую выбрать?\n${lines.join('\n')}');
      }
    }
    return _apply(c.intent, target!, c.date, n);
  }

  Future<AssistantReply> _apply(
      Intent action, Entry e, ParsedDate d, DateTime n) async {
    switch (action) {
      case Intent.complete:
        await _commit(e.copyWith(done: true));
        return AssistantReply(_addr('отметил выполненным: «${e.title}».'));
      case Intent.delete:
        await deleteEntry(e);
        return AssistantReply(_addr('удалил: «${e.title}».'));
      case Intent.reschedule:
        return _reschedule(e, d, n);
      default:
        return const AssistantReply(Assistant.help);
    }
  }

  Future<AssistantReply> _reschedule(Entry e, ParsedDate nd, DateTime n) async {
    if (!nd.hasAny) {
      _pending = _Pending(_PK.when)..entry = e;
      return AssistantReply('На когда перенести «${e.title}»?');
    }
    final today = DateTime(n.year, n.month, n.day);
    final old = e.dueAt;
    DateTime due;
    bool hasTime;
    if (nd.exact != null) {
      due = nd.exact!;
      hasTime = true;
    } else {
      final base = nd.day ??
          nd.rangeStart ??
          (old == null ? null : DateTime(old.year, old.month, old.day));
      if (nd.hour != null) {
        hasTime = true;
        due = base == null
            ? nd.resolve(n)!
            : DateTime(
                base.year, base.month, base.day, nd.hour!, nd.minute ?? 0);
      } else {
        hasTime = e.hasTime && old != null;
        final b = base ?? today;
        due = DateTime(b.year, b.month, b.day, hasTime ? old.hour : 0,
            hasTime ? old.minute : 0);
      }
    }
    final upd = e.copyWith(dueAt: due, hasTime: hasTime);
    return _saveChecked(upd, n,
        okText: (s) => _addr('перенёс «${e.title}» — ${_when(s, n)}.'));
  }

  // ---------- Форматирование ----------

  String _dayLabel(DateTime d, DateTime n) {
    final diff = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(n.year, n.month, n.day))
        .inDays;
    switch (diff) {
      case -1:
        return 'вчера';
      case 0:
        return 'сегодня';
      case 1:
        return 'завтра';
      case 2:
        return 'послезавтра';
    }
    final year = d.year != n.year ? ' ${d.year}' : '';
    return '${_wdIn[d.weekday - 1]}, ${d.day} ${_monthsGen[d.month - 1]}$year';
  }

  String _when(Entry e, DateTime n) {
    final d = e.dueAt;
    if (d == null) return 'без срока';
    final day = _dayLabel(d, n);
    return e.hasTime ? '$day в ${_hm(d)}' : day;
  }

  String _line(Entry e, DateTime n, {required bool withDay}) {
    final d = e.dueAt;
    final mark = e.done ? '✓ ' : '';
    if (d == null) return '• $mark${e.title} — без срока';
    final time = e.hasTime ? _hm(d) : 'без времени';
    final when = withDay ? '${_dayLabel(d, n)}, $time' : time;
    return '• $mark$when — ${e.title}';
  }
}
