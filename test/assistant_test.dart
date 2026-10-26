import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/assistant/assistant.dart';
import 'package:voice_assistant/data/entry_repository.dart';
import 'package:voice_assistant/data/settings.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/nlu/intent_parser.dart';
import 'package:voice_assistant/services/day_load.dart';

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

    test('длительность встречи', () {
      final c = IntentParser.parse(
          'Добавь встречу с командой завтра в 15:00 на 2 часа', now);
      expect(c.type, EntryType.meeting);
      expect(c.durationMin, 120);
    });
  });

  group('Модель и занятость', () {
    test('минимум час', () {
      final e = Entry(
          type: EntryType.meeting,
          title: 'x',
          dueAt: now,
          hasTime: true,
          createdAt: now,
          durationMin: 30);
      expect(e.duration, 60);
    });

    test('цвета занятости', () {
      Entry m(int h) => Entry(
          type: EntryType.meeting,
          title: 'm',
          dueAt: now,
          hasTime: true,
          createdAt: now,
          durationMin: h * 60);
      expect(dayLoad([]), DayLoad.free);
      expect(dayLoad([m(1)]), DayLoad.light);
      expect(dayLoad([m(2), m(2), m(2)]), DayLoad.medium);
      expect(dayLoad([m(2), m(2), m(2), m(2), m(2)]), DayLoad.busy);
    });
  });

  group('Assistant', () {
    late AppSettings settings;
    late Assistant a;
    setUp(() {
      settings = AppSettings.memory();
      a = Assistant(InMemoryEntryRepository(),
          clock: () => now, settings: settings);
    });

    test('уточняет время встречи и сохраняет', () async {
      final q = await a.handle('Поставь встречу с Иваном завтра');
      expect(q.text, contains('какое время'));
      final r = await a.handle('в 14');
      expect(r.text, contains('14:00'));
      final list = await a.handle('Что у меня завтра?');
      expect(list.text, contains('Встреча с Иваном'));
    });

    test('мероприятие без времени', () async {
      await a.handle('Поставь встречу с Иваном завтра');
      final r = await a.handle('без времени');
      expect(r.text, contains('Встреча с Иваном'));
      final list = await a.handle('Что у меня завтра?');
      expect(list.text, contains('без времени'));
    });

    test('накладка: предлагает свободное время и ставит по «да»', () async {
      await a.handle('Добавь встречу с командой завтра в 15:00');
      final q = await a.handle('Добавь встречу с дизайнером завтра в 15:30');
      expect(q.text, contains('уже есть'));
      expect(q.text, contains('16:00'));
      final r = await a.handle('да');
      expect(r.text, contains('16:00'));
    });

    test('поиск по смыслу и перенос по контексту', () async {
      await a.handle('Поставь задачу подписать договор до конца недели');
      final found =
          await a.handle('Я когда-то ставил задачу по договору, найди её');
      expect(found.text, contains('Подписать договор'));
      final moved = await a.handle('А перенеси её на завтра');
      expect(moved.text, contains('завтра'));
    });

    test('особая дата и праздник в списке', () async {
      final r = await a.handle('Запомни день рождения Ивана 15 марта');
      expect(r.text, contains('15 марта'));
      final list = await a.handle('Что у меня 15 марта?');
      expect(list.text, contains('День рождения Ивана'));
      final h = await a.handle('Что у меня 8 марта?');
      expect(h.text, contains('Международный женский день'));
    });

    test('обращение по имени и имя ассистента', () async {
      await a.handle('Называй меня Иван');
      expect(settings.userName, 'Иван');
      final r = await a.handle('Добавь задачу купить хлеб');
      expect(r.text, startsWith('Иван,'));
      settings.change(assistantName: 'Джарвис');
      final l = await a.handle('Джарвис, что у меня сегодня?');
      expect(l.text, startsWith('Планы'));
    });

    test('двойной запрос в одной фразе', () async {
      final r = await a
          .handle('Добавь задачу купить хлеб и добавь задачу позвонить маме');
      expect(r.text, contains('Купить хлеб'));
      expect(r.text, contains('Позвонить маме'));
    });
  });
}
