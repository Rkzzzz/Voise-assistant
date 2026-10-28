import 'dart:convert';
import 'dart:typed_data';

import 'package:assistant_core/yandex/gpt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voice_assistant/data/entry_repository.dart';
import 'package:voice_assistant/data/settings.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/services/yandex/caldav.dart';
import 'package:voice_assistant/services/yandex/cloud_sync.dart';
import 'package:voice_assistant/services/yandex/speechkit.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12);

  group('CalDAV / iCalendar', () {
    test('разбирает событие с UTC и UID', () {
      const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:abc-123
SUMMARY:Встреча с командой
DTSTART:20261029T070000Z
DTEND:20261029T080000Z
LOCATION:Офис
DESCRIPTION:Планерка
LAST-MODIFIED:20261028T100000Z
END:VEVENT
END:VCALENDAR''';
      final events = parseIcsEvents(ics);
      expect(events, hasLength(1));
      final e = events.first;
      expect(e.uid, 'abc-123');
      expect(e.summary, 'Встреча с командой');
      expect(e.location, 'Офис');
      expect(e.start.toUtc(), DateTime.utc(2026, 10, 29, 7));
      expect(e.lastModified?.toUtc(), DateTime.utc(2026, 10, 28, 10));
    });

    test('событие на весь день', () {
      const ics = '''
BEGIN:VEVENT
UID:day-1
SUMMARY:День рождения
DTSTART;VALUE=DATE:20261115
DTEND;VALUE=DATE:20261116
END:VEVENT''';
      final e = parseIcsEvents(ics).single;
      expect(e.allDay, isTrue);
      expect(e.start, DateTime(2026, 11, 15));
    });

    test('запись приложения переживает запись и чтение', () {
      final entry = Entry(
        type: EntryType.meeting,
        title: 'Созвон',
        dueAt: DateTime(2026, 10, 29, 15),
        hasTime: true,
        createdAt: now,
        durationMin: 90,
        place: 'Онлайн',
        externalId: 'entry-1@voice-assistant',
      );
      final ics = buildEntryIcs(entry, uid: entry.externalId, stamp: now);
      final parsed = parseIcsEvents(ics).single;
      expect(parsed.uid, entry.externalId);
      expect(parsed.summary, 'Созвон');
      expect(parsed.start.toUtc(), entry.dueAt!.toUtc());
      expect(parsed.location, 'Онлайн');
    });
  });

  group('YandexGPT', () {
    test('разбирает JSON модели в команду', () {
      final cmd = commandFromJson({
        'intent': 'create',
        'type': 'reminder',
        'title': 'Позвонить Ивану',
        'date': '2026-10-29',
        'time': '10:00',
        'untimed': false,
        'durationMin': null,
      }, 'Напомни завтра в 10 позвонить Ивану', now);
      expect(cmd, isNotNull);
      expect(cmd!.title, 'Позвонить Ивану');
      expect(cmd.type, EntryType.reminder);
      expect(cmd.date.day, DateTime(2026, 10, 29));
      expect(cmd.date.hour, 10);
    });

    test('игнорирует неизвестное намерение', () {
      final cmd =
          commandFromJson({'intent': 'unknown', 'title': ''}, 'привет', now);
      expect(cmd, isNull);
    });

    test('без ключа модель не вызывается', () async {
      const config = YandexGptConfig();
      expect(config.isConfigured, isFalse);
      expect(await YandexGpt(config).parseCommand('что у меня завтра', now),
          isNull);
    });
  });

  group('SpeechKit', () {
    test('без ключа распознавание и синтез отключены', () async {
      const config = SpeechKitConfig();
      final kit = SpeechKit(config);
      expect(await kit.recognize(Uint8List(10)), isNull);
      expect(await kit.synthesize('привет', male: false), isNull);
    });

    test('формирует адрес модели', () {
      const config = YandexGptConfig(apiKey: 'k', folderId: 'f');
      expect(config.modelUri, 'gpt://f/yandexgpt-lite/latest');
    });
  });

  group('Синхронизация с Алисой', () {
    test('забирает новые записи сервера', () async {
      final repo = InMemoryEntryRepository();
      final settings = AppSettings.memory()
        ..change(
          cloudSyncEnabled: true,
          cloudSyncUrl: 'https://alice.example',
          cloudSyncToken: 'token',
        );
      await repo.add(Entry(
        type: EntryType.task,
        title: 'Локальная',
        dueAt: DateTime(2026, 10, 29, 9),
        hasTime: true,
        createdAt: now,
        externalId: 'cloud:1',
        updatedAt: now,
      ));

      final serverEntry = Entry(
        type: EntryType.task,
        title: 'Из Алисы',
        dueAt: DateTime(2026, 10, 30, 11),
        hasTime: true,
        createdAt: now,
        externalId: 'cloud:2',
        updatedAt: now.add(const Duration(minutes: 5)),
      );

      final client = MockClient((req) async {
        expect(req.url.path, '/api/sync');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'added': 0,
            'updated': 0,
            'entries': [serverEntry.toMap()],
            'marks': [],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await CloudSync(
        repo: repo,
        settings: settings,
        client: client,
      ).sync();

      expect(result.error, isFalse);
      final all = await repo.all();
      expect(all.map((e) => e.title), contains('Из Алисы'));
    });

    test('без настроек синхронизация не выполняется', () async {
      final repo = InMemoryEntryRepository();
      final settings = AppSettings.memory();
      final result = await CloudSync(repo: repo, settings: settings).sync();
      expect(result.error, isTrue);
    });
  });
}
