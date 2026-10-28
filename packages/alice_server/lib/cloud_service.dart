import 'package:assistant_core/assistant_core.dart';

import 'cloud_repository.dart';
import 'cloud_store.dart';

/// Логика сервера: ассистент для каждого пользователя и слияние записей
/// с мобильным приложением.
class CloudService {
  CloudService(this.store);

  final CloudStore store;
  final _assistants = <String, Assistant>{};

  /// Ассистент пользователя. Один экземпляр на пользователя — так работают
  /// уточняющие вопросы («На какое время поставить встречу?»).
  Assistant assistantFor(CloudUser user) => _assistants.putIfAbsent(
        user.id,
        () => Assistant(
          CloudRepository(user, () => store.persist(user)),
          settings: MemoryAssistantSettings(
            userName: user.name,
            assistantName: 'Ассистент',
          ),
        ),
      );

  Future<AssistantReply> handleText(CloudUser user, String text) =>
      assistantFor(user).handle(text);

  /// Сливает записи приложения с серверными. Более свежая версия побеждает
  /// (сравнение по `updatedAt`), новые записи получают `cloud:<id>`.
  Future<SyncResult> merge(
    CloudUser user, {
    required List<Entry> entries,
    required List<Mark> marks,
  }) async {
    var added = 0;
    var updated = 0;

    for (final incoming in entries) {
      final ext = incoming.externalId;
      final i = ext.isEmpty
          ? -1
          : user.entries.indexWhere((e) => e.externalId == ext);
      if (i < 0) {
        final id = user.nextId++;
        user.entries.add(incoming.copyWith(
          id: id,
          externalId: ext.isEmpty ? 'cloud:$id' : ext,
          updatedAt: incoming.updatedAt ?? incoming.createdAt,
        ));
        added++;
        continue;
      }
      final local = user.entries[i];
      if (incoming.lastModified.isAfter(local.lastModified)) {
        user.entries[i] = incoming.copyWith(
          id: local.id,
          externalId: local.externalId,
          updatedAt: incoming.updatedAt ?? incoming.createdAt,
        );
        updated++;
      }
    }

    for (final m in marks) {
      final exists = user.marks.any(
          (x) => x.month == m.month && x.day == m.day && x.title == m.title);
      if (!exists) {
        user.marks.add(Mark(
          id: user.nextId++,
          title: m.title,
          month: m.month,
          day: m.day,
          kind: m.kind,
        ));
      }
    }

    await store.persist(user);
    return SyncResult(
      added: added,
      updated: updated,
      entries: List.of(user.entries),
      marks: List.of(user.marks),
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.added,
    required this.updated,
    required this.entries,
    required this.marks,
  });

  final int added;
  final int updated;
  final List<Entry> entries;
  final List<Mark> marks;
}
