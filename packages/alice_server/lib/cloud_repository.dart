import 'package:assistant_core/assistant_core.dart';

import 'cloud_store.dart';

/// Хранилище записей одного пользователя поверх JSON-файла.
class CloudRepository implements EntryRepository {
  CloudRepository(this.user, this._onChange);

  final CloudUser user;
  final Future<void> Function() _onChange;

  int _nextId() => user.nextId++;

  @override
  Future<Entry> add(Entry e) async {
    final id = _nextId();
    final saved = e.copyWith(
      id: id,
      externalId: e.externalId.isEmpty ? 'cloud:$id' : e.externalId,
      updatedAt: e.updatedAt ?? DateTime.now(),
    );
    user.entries.add(saved);
    await _onChange();
    return saved;
  }

  @override
  Future<void> update(Entry e) async {
    final i = user.entries.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      user.entries[i] = e;
      await _onChange();
    }
  }

  @override
  Future<void> remove(int id) async {
    user.entries.removeWhere((x) => x.id == id);
    await _onChange();
  }

  @override
  Future<List<Entry>> all() async {
    final list = List.of(user.entries)
      ..sort((a, b) {
        if (a.dueAt == null && b.dueAt == null) return 0;
        if (a.dueAt == null) return 1;
        if (b.dueAt == null) return -1;
        return a.dueAt!.compareTo(b.dueAt!);
      });
    return list;
  }

  @override
  Future<List<Entry>> between(DateTime from, DateTime to) async => user.entries
      .where((e) =>
          e.dueAt != null && !e.dueAt!.isBefore(from) && e.dueAt!.isBefore(to))
      .toList()
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  @override
  Future<List<Mark>> marks() async => List.of(user.marks);

  @override
  Future<Mark> addMark(Mark m) async {
    final saved = Mark(
      id: _nextId(),
      title: m.title,
      month: m.month,
      day: m.day,
      kind: m.kind,
    );
    user.marks.add(saved);
    await _onChange();
    return saved;
  }

  @override
  Future<void> removeMark(int id) async {
    user.marks.removeWhere((m) => m.id == id);
    await _onChange();
  }
}
