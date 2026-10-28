import 'package:assistant_core/services/notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/settings.dart';
import '../models/entry.dart';

export 'package:assistant_core/services/notifier.dart';

/// Локальные уведомления: в момент события и за час до него.
class LocalNotifier implements Notifier {
  LocalNotifier(this.settings);

  final AppSettings settings;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'entries',
      'События',
      channelDescription: 'Напоминания о задачах и встречах',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Уведомления недоступны: $e');
    }
  }

  @override
  Future<void> cancel(int entryId) async {
    if (!_ready) return;
    await _plugin.cancel(entryId * 10 + 1);
    await _plugin.cancel(entryId * 10 + 2);
  }

  @override
  Future<void> sync(Entry e) async {
    if (!_ready || e.id == null) return;
    await cancel(e.id!);
    if (e.done || !e.hasTime || e.dueAt == null) return;
    if (settings.notifyAtTime) {
      await _at(e.id! * 10 + 1, e.dueAt!, e.type.label, 'Сейчас: ${e.title}');
    }
    if (settings.notifyHourBefore) {
      await _at(e.id! * 10 + 2, e.dueAt!.subtract(const Duration(hours: 1)),
          'Через час', e.title);
    }
  }

  @override
  Future<void> syncAll(Iterable<Entry> entries) async {
    for (final e in entries) {
      await sync(e);
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  @override
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(0, 'Проверка', 'Уведомления работают', _details);
  }

  Future<void> _at(int id, DateTime when, String title, String body) async {
    if (!when.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.UTC), // абсолютный момент времени
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Не удалось запланировать уведомление: $e');
    }
  }
}
