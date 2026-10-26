import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/entry.dart';
import '../models/mark.dart';
import 'entry_repository.dart';

/// Хранилище для веб-версии: записи лежат в localStorage браузера
/// (SQLite в браузере не работает). На телефоне используется SQLite.
class PrefsEntryRepository implements EntryRepository {
  static const _kEntries = 'web_entries_v1';
  static const _kMarks = 'web_marks_v1';
  static const _kNextId = 'web_next_id_v1';

  SharedPreferences? _p;
  Future<SharedPreferences> get _prefs async =>
      _p ??= await SharedPreferences.getInstance();

  Future<int> _newId() async {
    final p = await _prefs;
    final n = (p.getInt(_kNextId) ?? 0) + 1;
    await p.setInt(_kNextId, n);
    return n;
  }

  Future<List<Map<String, Object?>>> _rows(String key) async {
    final raw = (await _prefs).getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
  }

  Future<void> _save(String key, List<Map<String, Object?>> rows) async =>
      (await _prefs).setString(key, jsonEncode(rows));

  Future<List<Entry>> _entries() async =>
      (await _rows(_kEntries)).map(Entry.fromMap).toList();

  Future<void> _saveEntries(List<Entry> es) =>
      _save(_kEntries, es.map((e) => e.toMap()).toList());

  @override
  Future<Entry> add(Entry e) async {
    final saved = e.copyWith(id: await _newId());
    final list = await _entries()..add(saved);
    await _saveEntries(list);
    return saved;
  }

  @override
  Future<void> update(Entry e) async {
    final list = await _entries();
    final i = list.indexWhere((x) => x.id == e.id);
    if (i >= 0) list[i] = e;
    await _saveEntries(list);
  }

  @override
  Future<void> remove(int id) async {
    final list = await _entries()..removeWhere((x) => x.id == id);
    await _saveEntries(list);
  }

  @override
  Future<List<Entry>> all() async {
    final list = await _entries();
    list.sort((a, b) {
      if (a.dueAt == null && b.dueAt == null) return 0;
      if (a.dueAt == null) return 1;
      if (b.dueAt == null) return -1;
      return a.dueAt!.compareTo(b.dueAt!);
    });
    return list;
  }

  @override
  Future<List<Entry>> between(DateTime from, DateTime to) async =>
      (await all())
          .where((e) =>
              e.dueAt != null &&
              !e.dueAt!.isBefore(from) &&
              e.dueAt!.isBefore(to))
          .toList();

  @override
  Future<List<Mark>> marks() async =>
      (await _rows(_kMarks)).map(Mark.fromMap).toList();

  @override
  Future<Mark> addMark(Mark m) async {
    final saved = Mark(
        id: await _newId(),
        title: m.title,
        month: m.month,
        day: m.day,
        kind: m.kind);
    final rows = await _rows(_kMarks)..add(saved.toMap());
    await _save(_kMarks, rows);
    return saved;
  }

  @override
  Future<void> removeMark(int id) async {
    final rows = await _rows(_kMarks)..removeWhere((r) => r['id'] == id);
    await _save(_kMarks, rows);
  }
}
