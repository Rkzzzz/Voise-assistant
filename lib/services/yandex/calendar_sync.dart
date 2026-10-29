import '../../data/entry_repository.dart';
import '../../data/settings.dart';
import '../../models/entry.dart';
import 'caldav.dart';

/// Итог синхронизации с Яндекс.Календарём.
class CalendarSyncResult {
  const CalendarSyncResult({
    this.pulled = 0,
    this.updated = 0,
    this.pushed = 0,
    this.error,
  });

  final int pulled;
  final int updated;
  final int pushed;
  final String? error;

  bool get ok => error == null;

  String get message {
    if (error != null) return error!;
    if (pulled == 0 && updated == 0 && pushed == 0) {
      return 'Всё уже синхронизировано.';
    }
    final parts = <String>[
      if (pulled > 0) 'получено $pulled',
      if (updated > 0) 'обновлено $updated',
      if (pushed > 0) 'отправлено $pushed',
    ];
    return 'Яндекс.Календарь: ${parts.join(', ')}.';
  }
}

/// Двусторонняя синхронизация записей с Яндекс.Календарём (CalDAV).
///
/// Правила конфликтов: сравниваем время последнего изменения. Более свежая
/// версия побеждает; при равенстве приоритет у записи на устройстве.
class YandexCalendarSync {
  YandexCalendarSync({
    required this.repo,
    required this.settings,
    DateTime Function()? clock,
    CalDavClient? client,
  })  : _clock = clock ?? DateTime.now,
        _client = client;

  final EntryRepository repo;
  final AppSettings settings;
  final DateTime Function() _clock;
  final CalDavClient? _client;

  static const _pastDays = 30;
  static const _futureDays = 365;

  Future<CalendarSyncResult> sync() async {
    if (!settings.yandexCalendarEnabled) {
      return const CalendarSyncResult(error: 'Синхронизация не включена.');
    }
    final config = CalDavConfig(
      login: settings.yandexCalendarLogin,
      password: settings.yandexCalendarPassword,
      calendarUrl: settings.yandexCalendarUrl,
    );
    if (!config.isConfigured) {
      return const CalendarSyncResult(
          error: 'Укажите логин и пароль приложения Яндекс.');
    }
    final client = _client ?? CalDavClient(config);
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: _pastDays));
    final to = today.add(const Duration(days: _futureDays));

    try {
      final events = await client.events(from: from, to: to);
      var pulled = 0;
      var updated = 0;

      final local = await repo.all();
      final byUid = <String, Entry>{
        for (final e in local)
          if (e.externalId.isNotEmpty) e.externalId: e,
      };
      // Индекс локальных записей без externalId: «название + минуту».
      // Позволяет за O(1) найти двойника события, а не перебором.
      final twins = <String, List<Entry>>{};
      for (final e in local) {
        if (e.externalId.isNotEmpty || e.dueAt == null) continue;
        twins.putIfAbsent(_twinKey(e.title, e.dueAt!), () => []).add(e);
      }
      // Что уже лежит в календаре и когда изменилось там — чтобы не
      // отправлять одно и то же на каждом проходе.
      final serverModified = <String, DateTime?>{
        for (final ev in events) ev.uid: ev.lastModified,
      };
      final syncedNow = <String>{};

      for (final event in events) {
        if (event.cancelled) continue;
        final existing = byUid[event.uid];
        if (existing == null) {
          // не дублируем запись, если такое же событие уже есть локально
          final twin = twins[_twinKey(event.summary, event.start)];
          if (twin != null && twin.isNotEmpty) {
            final e = twin.first;
            final adopted = e.copyWith(externalId: event.uid);
            await repo.update(adopted);
            byUid[event.uid] = adopted;
            syncedNow.add(event.uid);
            continue;
          }
          final created = event.toEntry(now: now);
          final saved = await repo.add(created);
          byUid[event.uid] = saved;
          syncedNow.add(event.uid);
          pulled++;
          continue;
        }
        if (_eventIsNewer(event, existing) && _differs(event, existing)) {
          await repo.update(existing.copyWith(
            title: event.summary.trim().isEmpty
                ? existing.title
                : event.summary.trim(),
            dueAt: event.allDay
                ? DateTime(event.start.year, event.start.month, event.start.day)
                : event.start,
            hasTime: !event.allDay,
            durationMin:
                event.allDay ? existing.durationMin : event.durationMinutes,
            place: event.location.trim(),
            comment: event.description.trim(),
            done: event.done,
            updatedAt: now,
          ));
          syncedNow.add(event.uid);
          updated++;
        }
      }

      // отправляем только то, что изменилось локально: новые записи и те,
      // что пользователь тронул после последней отправки
      final current = await repo.all();
      var pushed = 0;
      for (final e in current) {
        final due = e.dueAt;
        if (due == null) continue;
        if (due.isBefore(from) || !due.isBefore(to)) continue;
        final ext = e.externalId;
        if (ext.isNotEmpty) {
          if (syncedNow.contains(ext))
            continue; // только что пришли из календаря
          if (_alreadyOnServer(ext, serverModified, e)) continue;
        }
        final uid = ext.isNotEmpty ? ext : _uidFor(e);
        await client.putEvent(uid, buildEntryIcs(e, uid: uid, stamp: now));
        if (e.externalId != uid) {
          await repo.update(e.copyWith(externalId: uid));
        }
        pushed++;
      }

      return CalendarSyncResult(
          pulled: pulled, updated: updated, pushed: pushed);
    } on CalDavException catch (e) {
      return CalendarSyncResult(
          error: e.unauthorized
              ? 'Яндекс.Календарь: неверный логин или пароль приложения.'
              : 'Яндекс.Календарь: ${e.message}');
    } catch (e) {
      return CalendarSyncResult(
          error: 'Не удалось связаться с Яндекс.Календарём: $e');
    } finally {
      // фоновая синхронизация запускается каждые 15 минут — соединения
      // созданного здесь клиента надо закрывать
      if (_client == null) client.close();
    }
  }

  String _uidFor(Entry e) =>
      'entry-${settings.profileIndex}-${e.id ?? e.createdAt.millisecondsSinceEpoch}'
      '@voice-assistant';

  /// Ключ для быстрого поиска двойника: название + минута.
  static String _twinKey(String title, DateTime due) =>
      '${title.trim().toLowerCase()}|${due.millisecondsSinceEpoch ~/ 60000}';

  /// Уже есть на сервере и не изменилось с тех пор?
  static bool _alreadyOnServer(
      String ext, Map<String, DateTime?> serverModified, Entry e) {
    final m = serverModified[ext];
    if (m == null) return false; // сервер не сообщил — лучше отправить
    return !e.lastModified.isAfter(m);
  }

  static bool _sameMoment(DateTime a, DateTime b) =>
      a.difference(b).inMinutes.abs() < 1;

  static bool _eventIsNewer(CalDavEvent event, Entry entry) {
    final m = event.lastModified;
    if (m == null) return false;
    return m.isAfter(entry.lastModified);
  }

  static bool _differs(CalDavEvent event, Entry entry) {
    if (entry.title != event.summary.trim()) return true;
    if (entry.place != event.location.trim()) return true;
    if (entry.done != event.done) return true;
    final due = entry.dueAt;
    if (due == null) return true;
    if (!_sameMoment(due, event.start)) return true;
    if (entry.hasTime == event.allDay) return true;
    return false;
  }
}
