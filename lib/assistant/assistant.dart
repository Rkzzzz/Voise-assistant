import 'package:assistant_core/assistant/assistant.dart' as core;
import 'package:flutter/foundation.dart';

import '../data/settings.dart';
import '../models/entry.dart';

export 'package:assistant_core/assistant/assistant.dart' show AssistantReply;

/// Ассистент приложения: та же логика, что и на сервере Алисы
/// (`assistant_core`), плюс уведомление Flutter об изменениях.
class Assistant extends core.Assistant with ChangeNotifier {
  Assistant(
    super.repo, {
    super.clock,
    required AppSettings settings,
    super.notifier,
    super.repoFor,
    super.aiParser,
  })  : _appSettings = settings,
        super(settings: settings) {
    onChanged = notifyListeners;
  }

  final AppSettings _appSettings;

  /// Настройки приложения (тема, голос, ключи API).
  AppSettings get appSettings => _appSettings;

  @override
  Future<void> switchProfile(int i) async {
    if (i == _appSettings.profileIndex) return;
    _appSettings.setProfile(i);
    await super.switchProfile(i);
  }

  Future<void> addProfile(String name) async {
    final n = name.trim();
    if (n.isEmpty || repoFor == null) return;
    await switchProfile(_appSettings.addProfile(n));
  }

  /// Ручное сохранение записи из редактора.
  Future<Entry> saveEntry(Entry e) => save(e);
}
