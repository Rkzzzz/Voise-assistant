import '../models/entry.dart';

/// Уведомления о записях. Ассистент знает только этот интерфейс.
abstract class Notifier {
  Future<void> sync(Entry e);
  Future<void> cancel(int entryId);
  Future<void> syncAll(Iterable<Entry> entries);
  Future<void> cancelAll();
  Future<void> showTest();

  /// Выдаёт ли система точные будильники. Если false, время уведомления
  /// может сильно сдвинуться — стоит предложить выдать разрешение.
  bool get exactAlarmsAvailable;

  /// Обновляет [exactAlarmsAvailable] после возвращения из настроек системы.
  Future<void> refreshExactAlarms();

  /// Запрашивает разрешение на точные будильники и возвращает его статус.
  Future<bool> requestExactAlarms();
}

class NoopNotifier implements Notifier {
  @override
  Future<void> sync(Entry e) async {}
  @override
  Future<void> cancel(int entryId) async {}
  @override
  Future<void> syncAll(Iterable<Entry> entries) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> showTest() async {}
  @override
  bool get exactAlarmsAvailable => true;
  @override
  Future<void> refreshExactAlarms() async {}
  @override
  Future<bool> requestExactAlarms() async => true;
}
