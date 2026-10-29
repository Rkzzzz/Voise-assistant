import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voice_assistant/data/entry_repository.dart';
import 'package:voice_assistant/data/settings.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/services/yandex/cloud_sync.dart';

/// Проверка реального сценария: приложение отправляет локальную запись
/// без externalId, сервер назначает ей cloud:<id> и возвращает обратно.
void main() {
  final now = DateTime(2026, 10, 28, 12);

  test('синхронизация не плодит дубликаты локальных записей', () async {
    final repo = InMemoryEntryRepository();
    final settings = AppSettings.memory()
      ..change(
        cloudSyncEnabled: true,
        cloudSyncUrl: 'https://alice.example',
        cloudSyncToken: 'token',
      );
    await repo.add(Entry(
      type: EntryType.task,
      title: 'Купить хлеб',
      dueAt: DateTime(2026, 10, 29, 9),
      hasTime: true,
      createdAt: now,
      updatedAt: now,
      // externalId пуст — запись создана в приложении
    ));

    // Сервер ведёт себя как CloudService.merge: выдаёт cloud:<id> новым
    // записям и возвращает полный список.
    var serverId = 0;
    final client = MockClient((req) async {
      final body =
          jsonDecode(req.body) as Map<String, Object?>;
      final incoming = ((body['entries'] as List?) ?? const [])
          .map((e) => Entry.fromMap(Map<String, Object?>.from(e as Map)))
          .toList();
      final out = <Entry>[];
      for (final e in incoming) {
        if (e.externalId.isEmpty) {
          out.add(e.copyWith(externalId: 'cloud:${++serverId}'));
        } else {
          out.add(e);
        }
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'added': 0,
          'updated': 0,
          'entries': out.map((e) => e.toMap()).toList(),
          'marks': [],
        })),
        200,
      );
    });

    final sync = CloudSync(repo: repo, settings: settings, client: client);
    await sync.sync();
    await sync.sync();
    await sync.sync();

    final all = await repo.all();
    // ignore: avoid_print
    print('Записей после трёх синхронизаций: ${all.length}');
    for (final e in all) {
      // ignore: avoid_print
      print('  ${e.title} ext=${e.externalId}');
    }
    expect(all.length, 1, reason: 'локальная запись не должна размножаться');
  });
}
