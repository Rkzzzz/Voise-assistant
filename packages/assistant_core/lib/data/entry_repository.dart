import '../models/entry.dart';
import '../models/mark.dart';

/// Хранилище. Бизнес-логика знает только этот интерфейс.
abstract class EntryRepository {
  Future<Entry> add(Entry e);
  Future<void> update(Entry e);
  Future<void> remove(int id);
  Future<List<Entry>> all();

  /// Записи с датой в промежутке [from, to).
  Future<List<Entry>> between(DateTime from, DateTime to);

  Future<List<Mark>> marks();
  Future<Mark> addMark(Mark m);
  Future<void> removeMark(int id);
}

/// Для тестов и сервера без внешней базы.
class InMemoryEntryRepository implements EntryRepository {
  final _items = <Entry>[];
  final _marks = <Mark>[];
  var _nextId = 1;

  @override
  Future<Entry> add(Entry e) async {
    final saved = e.copyWith(id: _nextId++);
    _items.add(saved);
    return saved;
  }

  @override
  Future<void> update(Entry e) async {
    final i = _items.indexWhere((x) => x.id == e.id);
    if (i >= 0) _items[i] = e;
  }

  @override
  Future<void> remove(int id) async => _items.removeWhere((x) => x.id == id);

  @override
  Future<List<Entry>> all() async => List.of(_items);

  @override
  Future<List<Entry>> between(DateTime from, DateTime to) async => _items
      .where((e) =>
          e.dueAt != null && !e.dueAt!.isBefore(from) && e.dueAt!.isBefore(to))
      .toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  @override
  Future<List<Mark>> marks() async => List.of(_marks);

  @override
  Future<Mark> addMark(Mark m) async {
    final saved = Mark(
        id: _nextId++,
        title: m.title,
        month: m.month,
        day: m.day,
        kind: m.kind);
    _marks.add(saved);
    return saved;
  }

  @override
  Future<void> removeMark(int id) async =>
      _marks.removeWhere((m) => m.id == id);
}
