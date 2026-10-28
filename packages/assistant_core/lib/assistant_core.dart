/// Общая логика ассистента: модели данных, разбор русского языка и клиент
/// YandexGPT. Используется мобильным приложением и сервером навыка Алисы.
library assistant_core;

export 'assistant/assistant.dart';
export 'data/entry_repository.dart';
export 'models/entry.dart';
export 'models/mark.dart';
export 'nlu/date_parser.dart';
export 'nlu/intent_parser.dart';
export 'nlu/schedule_parser.dart';
export 'nlu/search.dart';
export 'nlu/text_buf.dart';
export 'services/day_load.dart';
export 'services/holidays.dart';
export 'services/notifier.dart';
export 'yandex/gpt.dart';
