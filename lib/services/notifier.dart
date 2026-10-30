import 'dart:io';

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

  /// true — разрешение на точные будильники выдано (Android 12+). Без него
  /// Android отдаёт время планирования на откуп Doze.
  @override
  bool get exactAlarmsAvailable => _exactAlarmsAvailable;

  bool _exactAlarmsAvailable = true;
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

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      await _android?.requestNotificationsPermission();
      await refreshExactAlarms();
      _ready = true;
    } catch (e) {
      debugPrint('Уведомления недоступны: $e');
    }
  }

  /// Актуальное состояние разрешения на точные будильники.
  @override
  Future<void> refreshExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _exactAlarmsAvailable =
        await _android?.canScheduleExactNotifications() ?? true;
  }

  /// Открывает системный экран с разрешением на точные будильники.
  @override
  Future<bool> requestExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final granted = await _android?.requestExactAlarmsPermission() ?? false;
    await refreshExactAlarms();
    return granted || _exactAlarmsAvailable;
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
    // inexactAllowWhileIdle отдает время на откуп Doze — уведомление может
    // прийти на часы позже. Точный будильник срабатывает вовремя.
    final mode = _exactAlarmsAvailable
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      await _schedule(id, when, title, body, mode);
    } catch (e) {
      // Разрешение могли отобрать уже после планирования — уходим в неточный
      // режим и пробуем ещё раз.
      if (mode == AndroidScheduleMode.inexactAllowWhileIdle) {
        debugPrint('Не удалось запланировать уведомление: $e');
        return;
      }
      _exactAlarmsAvailable = false;
      try {
        await _schedule(
            id, when, title, body, AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e) {
        debugPrint('Не удалось запланировать уведомление: $e');
      }
    }
  }

  Future<void> _schedule(
    int id,
    DateTime when,
    String title,
    String body,
    AndroidScheduleMode mode,
  ) =>
      _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.UTC), // абсолютный момент времени
        _details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
}
