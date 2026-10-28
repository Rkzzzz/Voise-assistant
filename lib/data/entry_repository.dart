import 'package:assistant_core/data/entry_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/entry.dart';
import '../models/mark.dart';

// Интерфейс и in-memory реализация живут в общем пакете: их использует
// и сервер навыка Алисы.
export 'package:assistant_core/data/entry_repository.dart';

const _marksSql = '''
  CREATE TABLE IF NOT EXISTS marks(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    month INTEGER NOT NULL,
    day INTEGER NOT NULL,
    kind TEXT NOT NULL DEFAULT 'other'
  )''';

class SqliteEntryRepository implements EntryRepository {
  SqliteEntryRepository({this.profile = 0});

  /// Номер профиля: у каждого пользователя своя база.
  final int profile;
  Database? _db;

  Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(),
            profile == 0 ? 'assistant.db' : 'assistant_$profile.db'),
        version: 4,
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
              duration_min INTEGER NOT NULL DEFAULT 60,
              place TEXT NOT NULL DEFAULT '',
              external_id TEXT NOT NULL DEFAULT '',
              updated_at INTEGER
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
          if (oldV < 3) {
            await db.execute(
                "ALTER TABLE entries ADD COLUMN place TEXT NOT NULL DEFAULT ''");
          }
          if (oldV < 4) {
            await db.execute(
                "ALTER TABLE entries ADD COLUMN external_id TEXT NOT NULL DEFAULT ''");
            await db.execute('ALTER TABLE entries ADD COLUMN updated_at INTEGER');
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
