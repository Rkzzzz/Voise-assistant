import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/assistant/assistant.dart';
import 'package:voice_assistant/data/entry_repository.dart';
import 'package:voice_assistant/data/settings.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/nlu/intent_parser.dart';
import 'package:voice_assistant/nlu/schedule_parser.dart';
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
      expect(c.durationMin, 120); // парсер слышит, но запись всё равно на час
    });
  });

  group('Расписание', () {
    test('день заголовком, нумерация и диапазон времени', () {
      final r = parseSchedule('''
Понедельник
1. 8:30-9:15 Математика
2) 9.25 – 10.10 Русский язык
Вторник
8:30 Литература
''');
      expect(r.length, 3);
      expect(r[0].weekday, 1);
      expect(r[0].title, 'Математика');
      expect(r[0].durationMin, 45);
      expect(r[1].hour, 9);
      expect(r[1].minute, 25);
      expect(r[2].weekday, 2);
      expect(r[2].durationMin, 60);
    });

    test('кружок с днём в строке', () {
      final r = parseSchedule('Шахматы вт 16:00-17:30\nПлавание, пт 18:00');
      expect(r[0].weekday, 2);
      expect(r[0].title, 'Шахматы');
      expect(r[0].durationMin, 90);
      expect(r[1].weekday, 5);
      expect(r[1].title, 'Плавание');
    });

    test('строки без дня и с неверным временем пропускаются', () {
      expect(parseSchedule('8:30 Математика'), isEmpty);
      expect(parseSchedule('Среда\n25:00 Ошибка'), isEmpty);
    });
  });

  group('Модель и занятость', () {
    test('длительность задаёт человек, по умолчанию час', () {
      Entry e(int? m) => Entry(
          type: EntryType.meeting,
          title: 'x',
          dueAt: now,
          hasTime: true,
          createdAt: now,
          durationMin: m ?? 60);
      expect(e(null).duration, 60);
      expect(e(30).duration, 30);
      expect(e(180).duration, 180);
      expect(e(5).duration, 15); // минимум 15 минут
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

    test('прошедшее время не принимается', () async {
      final r = await a.handle('Напомни сегодня в 8 утра позвонить маме');
      expect(r.text, contains('уже прошло'));
      final ok = await a.handle('в 18:00');
      expect(ok.text, contains('18:00'));
    });

    test('встреча на 2 часа занимает 2 часа', () async {
      await a.handle('Добавь встречу с командой завтра в 15:00 на 2 часа');
      final r = await a.handle('Добавь встречу с дизайнером завтра в 16:00');
      expect(r.text, contains('уже есть'));
      expect(r.text, contains('17:00')); // ближайшее свободное время
    });

    test('встреча на 30 минут и по умолчанию час', () async {
      await a.handle('Добавь встречу с Аней завтра в 15:00 на 30 минут');
      final es = await a.entriesBetween(
          DateTime(2026, 10, 22), DateTime(2026, 10, 23));
      expect(es.single.duration, 30);
    });

    test('расписание: недели и занятия добавляются', () async {
      final items = parseSchedule('Понедельник\n1. 8:30-9:15 Математика');
      final n = await a.addSchedule(items, weeks: 2);
      expect(n, 2);
    });

    test('профили: записи не смешиваются', () async {
      final s = AppSettings.memory();
      final repos = <int, EntryRepository>{};
      EntryRepository make(int i) =>
          repos.putIfAbsent(i, () => InMemoryEntryRepository());
      final b = Assistant(make(0),
          clock: () => now, settings: s, repoFor: make);
      await b.handle('Добавь задачу купить хлеб');
      await b.addProfile('Аня');
      final l = await b.handle('Какие задачи у меня?');
      expect(l.text, isNot(contains('Купить хлеб')));
      await b.switchProfile(0);
      final l0 = await b.handle('Какие задачи у меня?');
      expect(l0.text, contains('Купить хлеб'));
    });

    test('двойной запрос в одной фразе', () async {
      final r = await a
          .handle('Добавь задачу купить хлеб и добавь задачу позвонить маме');
      expect(r.text, contains('Купить хлеб'));
      expect(r.text, contains('Позвонить маме'));
    });
  });
}
