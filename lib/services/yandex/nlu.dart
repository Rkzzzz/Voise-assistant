import 'package:assistant_core/yandex/gpt.dart';

import '../../data/settings.dart';
import '../../nlu/intent_parser.dart';

/// Запасной разбор фраз через YandexGPT. Настройки читаются при каждом
/// запросе, поэтому включение/выключение в интерфейсе действует сразу.
class YandexNlu {
  YandexNlu(this.settings);

  final AppSettings settings;

  Future<Command?> parse(String text, DateTime now) async {
    if (!settings.yandexGptEnabled) return null;
    final config = YandexGptConfig(
      apiKey: settings.yandexApiKey,
      folderId: settings.yandexFolderId,
      model: settings.yandexGptModel,
    );
    if (!config.isConfigured) return null;
    return YandexGpt(config).parseCommand(text, now);
  }
}
