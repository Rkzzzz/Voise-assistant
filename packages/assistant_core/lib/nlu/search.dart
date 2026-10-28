import '../models/entry.dart';

class Scored {
  const Scored(this.entry, this.score);
  final Entry entry;
  final double score;
}

/// Нечёткий поиск по записям: основы слов + синонимы + опечатки (расстояние 1).
/// Заменяем эмбеддингами, если подключать LLM/векторную БД.
class Search {
  static const _stop = <String>{
    'найди', 'найти', 'поищи', 'ищи', 'задачу', 'задача', 'задачи', 'встречу',
    'встреча', 'встречи', 'напоминание', 'про', 'об', 'по', 'насчет', 'мне',
    'меня', 'была', 'был', 'было', 'будет', 'когда', 'ставил', 'ставила',
    'поставил', 'поставила', 'ее', 'его', 'это', 'там', 'какую', 'какой',
    'какая', 'где', 'что', 'мой', 'моя', 'мою', 'мои', 'свою', 'старую',
    'давно', 'как', 'то', 'со', 'из', 'за', 'для', 'на', 'пожалуйста',
    'нибудь', 'либо', 'все',  'покажи',
  };

  static const _groups = <List<String>>[
    ['договор', 'контракт', 'соглашение'],
    ['презентация', 'слайды', 'доклад', 'питч'],
    ['встреча', 'митинг', 'совещание', 'планерка'],
    ['созвон', 'звонок', 'позвонить', 'звонить', 'набрать'],
    ['отчет', 'репорт', 'сводка'],
    ['билеты', 'билет', 'тикеты'],
    ['купить', 'приобрести', 'заказать'],
    ['врач', 'доктор', 'поликлиника', 'больница'],
    ['письмо', 'email', 'почта', 'имейл'],
  ];

  static final Map<String, Set<String>> _syn = () {
    final m = <String, Set<String>>{};
    for (final g in _groups) {
      final stems = g.map(stem).toSet();
      for (final s in stems) {
        (m[s] ??= {}).addAll(stems);
      }
    }
    return m;
  }();

  static List<String> tokens(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .split(RegExp(r'[^а-яa-z0-9]+'))
      .where((w) => w.length > 1 && !_stop.contains(w))
      .toList();

  static String stem(String w) =>
      w.length <= 4 ? w : (w.length <= 6 ? w.substring(0, 4) : w.substring(0, 5));

  static bool _related(String a, String b) {
    if (a == b) return true;
    if (a.length < 4 || b.length < 4) return false;
    return a.startsWith(b) || b.startsWith(a) || _lev(a, b) <= 1;
  }

  static int _lev(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// Записи, отсортированные по релевантности (потом — по свежести).
  /// Пустой запрос возвращает все записи нужного типа с одинаковой оценкой.
  static List<Scored> rank(String query, List<Entry> all, {EntryType? type}) {
    final q = tokens(query).map(stem).toList();
    final pool = type == null ? all : all.where((e) => e.type == type);
    final res = <Scored>[];
    for (final e in pool) {
      if (q.isEmpty) {
        res.add(Scored(e, 1));
        continue;
      }
      final es = tokens(e.title).map(stem).toList();
      var hits = 0;
      for (final qs in q) {
        final cands = {qs, ...?_syn[qs]};
        if (es.any((t) => cands.any((c) => _related(t, c)))) hits++;
      }
      if (hits > 0) res.add(Scored(e, hits / q.length));
    }
    res.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      final ad = a.entry.dueAt ?? a.entry.createdAt;
      final bd = b.entry.dueAt ?? b.entry.createdAt;
      return bd.compareTo(ad);
    });
    return res;
  }
}
