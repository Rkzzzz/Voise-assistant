import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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

const _marksSql = '''
  CREATE TABLE IF NOT EXISTS marks(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    month INTEGER NOT NULL,
    day INTEGER NOT NULL,
    kind TEXT NOT NULL DEFAULT 'other'
  )''';

class SqliteEntryRepository implements EntryRepository {
  Database? _db;

  Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'assistant.db'),
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE entries(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              title TEXT NOT NULL,
              due_at INTEGER,
              has_time INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              done INTEGER NOT NULL DEFAULT 0,
              comment TEXT NOT NULL DEFAULT '',
              duration_min INTEGER NOT NULL DEFAULT 60
            )''');
          await db.execute(_marksSql);
        },
        onUpgrade: (db, oldV, _) async {
          if (oldV < 2) {
            await db.execute(
                "ALTER TABLE entries ADD COLUMN comment TEXT NOT NULL DEFAULT ''");
            await db.execute(
                'ALTER TABLE entries ADD COLUMN duration_min INTEGER NOT NULL DEFAULT 60');
            await db.execute(_marksSql);
          }
        },
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

  @override
  Future<List<Mark>> marks() async {
    final db = await _open();
    final rows = await db.query('marks', orderBy: 'month, day');
    return rows.map(Mark.fromMap).toList();
  }

  @override
  Future<Mark> addMark(Mark m) async {
    final db = await _open();
    final id = await db.insert('marks', m.toMap()..remove('id'));
    return Mark(
        id: id, title: m.title, month: m.month, day: m.day, kind: m.kind);
  }

  @override
  Future<void> removeMark(int id) async {
    final db = await _open();
    await db.delete('marks', where: 'id = ?', whereArgs: [id]);
  }
}

/// Для тестов.
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
