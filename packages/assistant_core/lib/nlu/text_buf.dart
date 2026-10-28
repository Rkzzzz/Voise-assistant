/// Текст в двух видах одинаковой длины: нормализованный [low] (для регулярок)
/// и исходный [orig] (для названия записи с сохранением регистра).
/// Все вырезания применяются к обоим синхронно.
class TextBuf {
  TextBuf(String s)
      : orig = s,
        low = s.toLowerCase().replaceAll('ё', 'е');

  TextBuf.pair(this.low, this.orig);

  String low;
  String orig;

  void cut(Match m) => _replace(m.start, m.end, ' ');
  void replace(Match m, String s) => _replace(m.start, m.end, s);

  void cutAll(RegExp r) {
    for (final m in r.allMatches(low).toList().reversed) {
      _replace(m.start, m.end, ' ');
    }
  }

  void _replace(int a, int b, String s) {
    low = low.replaceRange(a, b, s);
    orig = orig.replaceRange(a, b, s);
  }

  String get clean => orig.replaceAll(RegExp(r'\s+'), ' ').trim();
}
