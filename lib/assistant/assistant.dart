import '../data/entry_repository.dart';
import '../models/entry.dart';
import '../nlu/date_parser.dart';
import '../nlu/intent_parser.dart';
import '../nlu/search.dart';
import '../nlu/text_buf.dart';

class AssistantReply {
  const AssistantReply(this.text);
  final String text;
}

enum _PK { time, when, choose }

/// Незавершённый диалог: ассистент задал уточняющий вопрос.
class _Pending {
  _Pending(this.kind);
  final _PK kind;
  EntryType? type;
  String? title;
  DateTime? day;
  Entry? entry;
  Intent? action;
  ParsedDate? date;
  List<Entry> candidates = const [];
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

String _plural(int n, String one, String few, String many) {
  final a = n % 100, b = n % 10;
  if (a >= 11 && a <= 14) return many;
  if (b == 1) return one;
  if (b >= 2 && b <= 4) return few;
  return many;
}

/// Бизнес-логика: принимает текст, меняет данные, формирует ответ.
/// Ничего не знает ни о микрофоне, ни о UI, ни о SQL.
class Assistant {
  Assistant(this.repo, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final EntryRepository repo;
  final DateTime Function() _clock;

  Entry? _last; // контекст диалога: «перенеси её на завтра»
  _Pending? _pending;

  static const help =
      'Я помогу с задачами, напоминаниями и встречами. Например: '
      '«Напомни завтра в 10 утра позвонить Ивану», '
      '«Что у меня сегодня?», «Найди задачу про презентацию».';

  static final _cancelRe =
      RegExp(r'^\s*(?:отмена|забудь|не надо|не нужно|стоп|отбой)');
  static const _ords = ['перв', 'втор', 'трет', 'четверт', 'пят'];

  Future<AssistantReply> handle(String input) async {
    final text = input.trim();
    if (text.isEmpty) {
      return const AssistantReply(
          'Я ничего не услышал. Повторите, пожалуйста.');
    }
    final now = _clock();
    if (_pending != null) {
      final r = await _continuePending(text, now);
      if (r != null) return r;
    }
    final cmd = IntentParser.parse(text, now);
    switch (cmd.intent) {
      case Intent.create:
        return _create(cmd.title, cmd.type!, cmd.date, now);
      case Intent.list:
        return _list(cmd, now);
      case Intent.search:
        return _search(cmd, now);
      case Intent.complete:
      case Intent.delete:
      case Intent.reschedule:
        return _modify(cmd, now);
      case Intent.unknown:
        return const AssistantReply(help);
    }
  }

  // ---------- Уточняющие вопросы ----------

  Future<AssistantReply?> _continuePending(String text, DateTime now) async {
    final p = _pending!;
    final low = TextBuf(text).low;
    if (_cancelRe.hasMatch(low)) {
      _pending = null;
      return const AssistantReply('Хорошо, отменено.');
    }
    final d = DateParser.parse(text, now);
    switch (p.kind) {
      case _PK.time:
        if (d.hasTime) {
          _pending = null;
          return _create(p.title!, p.type!, d, now, day: d.day ?? p.day);
        }
        if (d.day != null) {
          p.day = d.day;
          return const AssistantReply('А на какое время?');
        }
        _pending = null;
        return null; // это новая команда
      case _PK.when:
        if (!d.hasAny) {
          _pending = null;
          return null;
        }
        _pending = null;
        return _reschedule(p.entry!, d, now);
      case _PK.choose:
        Entry? pick;
        final n = RegExp(r'\d+').firstMatch(low);
        if (n != null) {
          final i = int.parse(n.group(0)!) - 1;
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
        return _apply(p.action!, pick, p.date!, now);
    }
  }

  // ---------- Создание ----------

  Future<AssistantReply> _create(
    String title,
    EntryType type,
    ParsedDate d,
    DateTime now, {
    DateTime? day,
  }) async {
    if (title.isEmpty) {
      return const AssistantReply('Что именно нужно записать?');
    }
    // «на этой неделе» / «на следующей неделе» → срок в конце недели
    day ??= d.day ?? (d.rangeEnd == null ? null : addDays(d.rangeEnd!, -1));

    if (type != EntryType.task && !d.hasTime) {
      _pending = _Pending(_PK.time)
        ..type = type
        ..title = title
        ..day = day;
      final meeting = type == EntryType.meeting;
      return AssistantReply(day == null
          ? (meeting
              ? 'На какой день и время поставить встречу?'
              : 'Когда напомнить?')
          : (meeting
              ? 'На какое время поставить встречу?'
              : 'На какое время поставить напоминание?'));
    }

    final due = d.resolve(now, day: day);
    final entry = await repo.add(Entry(
      type: type,
      title: title,
      dueAt: due,
      hasTime: d.hasTime,
      createdAt: now,
    ));
    _last = entry;

    final when = _when(entry, now);
    var text = switch (type) {
      EntryType.reminder => 'Напомню $when: «$title».',
      EntryType.meeting => 'Встреча добавлена: «$title», $when.',
      EntryType.task => entry.dueAt == null
          ? 'Задача добавлена: «$title».'
          : 'Задача добавлена: «$title», срок — $when.',
    };
    if (type == EntryType.meeting && due != null) {
      final c = await _conflict(due, excludeId: entry.id);
      if (c != null) {
        text +=
            ' Внимание: в это время уже есть «${c.title}» (${_when(c, now)}).';
      }
    }
    return AssistantReply(text);
  }

  Future<Entry?> _conflict(DateTime due, {int? excludeId}) async {
    for (final e in await repo.all()) {
      if (e.type != EntryType.meeting || !e.hasTime || e.done) continue;
      if (e.id == excludeId || e.dueAt == null) continue;
      if (e.dueAt!.difference(due).abs() < const Duration(hours: 1)) return e;
    }
    return null;
  }

  // ---------- Список за период ----------

  Future<AssistantReply> _list(Command c, DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
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
      label = _dayLabel(from, now);
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

    final lines = items.map((e) => _line(e, now, withDay: range)).toList();
    if (byDefault) {
      final undated = (await repo.all()).where((e) =>
          e.dueAt == null && !e.done && (c.type == null || e.type == c.type));
      lines.addAll(undated.map((e) => '• без срока — ${e.title}'));
    }
    if (lines.isEmpty) {
      return AssistantReply('$prefix $label: ничего нет.');
    }
    if (items.isNotEmpty) _last = items.first;
    return AssistantReply('$prefix $label:\n${lines.join('\n')}');
  }

  // ---------- Поиск ----------

  Future<AssistantReply> _search(Command c, DateTime now) async {
    final res = Search.rank(c.text, await repo.all(), type: c.type);
    if (res.isEmpty) {
      return const AssistantReply(
          'Ничего похожего не нашлось. Попробуйте переформулировать запрос.');
    }
    _last = res.first.entry;
    final top = res.take(5).map((s) => _line(s.entry, now, withDay: true));
    final n = res.length;
    return AssistantReply(n == 1
        ? 'Нашёл:\n${top.first}'
        : 'Нашёл $n ${_plural(n, 'запись', 'записи', 'записей')}'
            '${n > 5 ? ' (показываю 5)' : ''}:\n${top.join('\n')}');
  }

  // ---------- Изменение / удаление / выполнение ----------

  Future<AssistantReply> _modify(Command c, DateTime now) async {
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
            '${i + 1}) ${_line(tied[i].entry, now, withDay: true).substring(2)}',
        ];
        return AssistantReply(
            'Нашёл несколько записей. Какую выбрать?\n${lines.join('\n')}');
      }
    }
    return _apply(c.intent, target!, c.date, now);
  }

  Future<AssistantReply> _apply(
      Intent action, Entry e, ParsedDate d, DateTime now) async {
    switch (action) {
      case Intent.complete:
        final upd = e.copyWith(done: true);
        await repo.update(upd);
        _last = upd;
        return AssistantReply('Отметил выполненным: «${e.title}».');
      case Intent.delete:
        await repo.remove(e.id!);
        if (_last?.id == e.id) _last = null;
        return AssistantReply('Удалил: «${e.title}».');
      case Intent.reschedule:
        return _reschedule(e, d, now);
      default:
        return const AssistantReply(Assistant.help);
    }
  }

  Future<AssistantReply> _reschedule(
      Entry e, ParsedDate nd, DateTime now) async {
    if (!nd.hasAny) {
      _pending = _Pending(_PK.when)..entry = e;
      return AssistantReply('На когда перенести «${e.title}»?');
    }
    final today = DateTime(now.year, now.month, now.day);
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
            ? nd.resolve(now)!
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
    await repo.update(upd);
    _last = upd;
    var text = 'Перенёс «${e.title}» — ${_when(upd, now)}.';
    if (e.type == EntryType.meeting && hasTime) {
      final c = await _conflict(due, excludeId: e.id);
      if (c != null) text += ' Внимание: в это время уже есть «${c.title}».';
    }
    return AssistantReply(text);
  }

  // ---------- Форматирование ----------

  String _dayLabel(DateTime d, DateTime now) {
    final diff = DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
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
    final year = d.year != now.year ? ' ${d.year}' : '';
    return '${_wdIn[d.weekday - 1]}, ${d.day} ${_monthsGen[d.month - 1]}$year';
  }

  String _when(Entry e, DateTime now) {
    final d = e.dueAt;
    if (d == null) return 'без срока';
    final day = _dayLabel(d, now);
    return e.hasTime ? '$day в ${_two(d.hour)}:${_two(d.minute)}' : day;
  }

  String _line(Entry e, DateTime now, {required bool withDay}) {
    final d = e.dueAt;
    final mark = e.done ? '✓ ' : '';
    if (d == null) return '• $mark${e.title} — без срока';
    final time =
        e.hasTime ? '${_two(d.hour)}:${_two(d.minute)}' : 'в течение дня';
    final when = withDay ? '${_dayLabel(d, now)}, $time' : time;
    return '• $mark$when — ${e.title}';
  }
}
