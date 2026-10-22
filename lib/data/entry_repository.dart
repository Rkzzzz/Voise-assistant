import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/entry.dart';

/// Хранилище записей. Бизнес-логика знает только этот интерфейс.
abstract class EntryRepository {
  Future<Entry> add(Entry e);
  Future<void> update(Entry e);
  Future<void> remove(int id);
  Future<List<Entry>> all();

  /// Записи с датой в промежутке [from, to).
  Future<List<Entry>> between(DateTime from, DateTime to);
}

class SqliteEntryRepository implements EntryRepository {
  Database? _db;

  Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'assistant.db'),
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            due_at INTEGER,
            has_time INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            done INTEGER NOT NULL DEFAULT 0
          )'''),
      );

  @override
  Future<Entry> add(Entry e) async {
    final db = await _open();
    final id = await db.insert('entries', e.toMap()..remove('id'));
    return e.copyWith(id: id);
  }

  @override
  Future<void> update(Entry e) async {
    final db = await _open();
    await db.update('entries', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  @override
  Future<void> remove(int id) async {
    final db = await _open();
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<Entry>> all() async {
    final db = await _open();
    final rows = await db.query('entries', orderBy: 'due_at IS NULL, due_at');
    return rows.map(Entry.fromMap).toList();
  }

  @override
  Future<List<Entry>> between(DateTime from, DateTime to) async {
    final db = await _open();
    final rows = await db.query(
      'entries',
      where: 'due_at >= ? AND due_at < ?',
      whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'due_at',
    );
    return rows.map(Entry.fromMap).toList();
  }
}

/// Для тестов.
class InMemoryEntryRepository implements EntryRepository {
  final _items = <Entry>[];
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
}
