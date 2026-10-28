import '../models/entry.dart';

/// Уведомления о записях. Ассистент знает только этот интерфейс.
abstract class Notifier {
  Future<void> sync(Entry e);
  Future<void> cancel(int entryId);
  Future<void> syncAll(Iterable<Entry> entries);
  Future<void> cancelAll();
  Future<void> showTest();
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
}
