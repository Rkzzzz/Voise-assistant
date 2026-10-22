import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/assistant/assistant.dart';
import 'package:voice_assistant/data/entry_repository.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/nlu/intent_parser.dart';

void main() {
  // Среда, 21 октября 2026, 10:00
  final now = DateTime(2026, 10, 21, 10);

  group('IntentParser', () {
    test('напоминание с датой и временем', () {
      final c = IntentParser.parse(
          'Напомни мне завтра в 10 утра позвонить Ивану', now);
      expect(c.intent, Intent.create);
      expect(c.type, EntryType.reminder);
      expect(c.title, 'Позвонить Ивану');
      expect(c.date.resolve(now), DateTime(2026, 10, 22, 10));
    });

    test('задача на пятницу без времени', () {
      final c = IntentParser.parse('В пятницу нужно отправить отчет', now);
      expect(c.intent, Intent.create);
      expect(c.type, EntryType.task);
      expect(c.title, 'Отправить отчет');
      expect(c.date.day, DateTime(2026, 10, 23));
      expect(c.date.hasTime, isFalse);
    });

    test('встреча: день недели и час', () {
      final c =
          IntentParser.parse('В четверг в 11 у меня встреча с дизайнером', now);
      expect(c.type, EntryType.meeting);
      expect(c.title, 'Встреча с дизайнером');
      expect(c.date.resolve(now), DateTime(2026, 10, 22, 11));
    });

    test('разные формулировки «что у меня сегодня»', () {
      for (final s in [
        'Что у меня сегодня?',
        'Какие планы на сегодня?',
        'Покажи мои встречи на сегодня',
      ]) {
        expect(IntentParser.parse(s, now).intent, Intent.list, reason: s);
      }
    });

    test('через два часа', () {
      final c = IntentParser.parse('Напомни через два часа выпить воды', now);
      expect(c.date.exact, DateTime(2026, 10, 21, 12));
    });
  });

  group('Assistant', () {
    late Assistant a;
    setUp(() => a = Assistant(InMemoryEntryRepository(), clock: () => now));

    test('уточняет время встречи и сохраняет', () async {
      final q = await a.handle('Поставь встречу с Иваном завтра');
      expect(q.text, contains('какое время'));
      final r = await a.handle('в 14');
      expect(r.text, contains('14:00'));
      final list = await a.handle('Что у меня завтра?');
      expect(list.text, contains('Встреча с Иваном'));
    });

    test('поиск по смыслу и перенос по контексту', () async {
      await a.handle('Поставь задачу подписать договор до конца недели');
      final found = await a.handle('Я когда-то ставил задачу по договору, найди её');
      expect(found.text, contains('Подписать договор'));
      final moved = await a.handle('А перенеси её на завтра');
      expect(moved.text, contains('завтра'));
    });
  });
}
