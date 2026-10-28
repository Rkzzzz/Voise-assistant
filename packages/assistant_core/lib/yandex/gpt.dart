import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/entry.dart';
import '../nlu/date_parser.dart';
import '../nlu/intent_parser.dart';
import '../nlu/text_buf.dart';

/// Параметры доступа к YandexGPT (Yandex Cloud Foundation Models).
class YandexGptConfig {
  const YandexGptConfig({
    this.apiKey = '',
    this.folderId = '',
    this.model = 'yandexgpt-lite',
    this.baseUrl = 'https://llm.api.cloud.yandex.net/foundationModels/v1',
    this.timeout = const Duration(seconds: 20),
  });

  final String apiKey;
  final String folderId;

  /// `yandexgpt-lite`, `yandexgpt` или `yandexgpt-32k`.
  final String model;
  final String baseUrl;
  final Duration timeout;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty && folderId.trim().isNotEmpty;

  String get modelUri => 'gpt://${folderId.trim()}/${model.trim()}/latest';
}

/// Разбор свободных фраз через YandexGPT.
///
/// Правила остаются основным способом понимания речи: модель вызывается
/// только когда правила вернули [Intent.unknown], поэтому приложение
/// продолжает работать без интернета и без ключей.
class YandexGpt {
  YandexGpt(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final YandexGptConfig config;
  final http.Client _client;

  static const _system = '''
Ты — разборщик команд голосового ассистента на русском языке.
Верни ТОЛЬКО JSON без пояснений и без markdown.
Формат:
{"intent":"create|list|search|complete|delete|reschedule|unknown",
 "type":"task|meeting|reminder|null",
 "title":"название или поисковый запрос",
 "date":"YYYY-MM-DD или null",
 "time":"HH:MM или null",
 "untimed":false,
 "durationMin":null}

Правила:
- create — создать задачу, встречу или напоминание; title — суть без даты и слов «напомни/добавь».
- list — «что у меня сегодня/завтра/на неделе»; date — начало периода или null.
- search — найти запись; complete — отметить выполненной; delete — удалить;
  reschedule — перенести; title — по чему искать.
- type: task — задача, meeting — встреча/созвон, reminder — напоминание.
- Если время не названо, time = null; если сказано «без времени» — untimed = true.
- Даты вычисляй относительно сегодняшней даты, которая дана в запросе.
- Если фраза не про задачи и календарь — intent = "unknown".
''';

  /// Возвращает команду или null, если модель не смогла её разобрать.
  Future<Command?> parseCommand(String text, DateTime now) async {
    if (!config.isConfigured || text.trim().isEmpty) return null;
    final weekday = const [
      'понедельник',
      'вторник',
      'среда',
      'четверг',
      'пятница',
      'суббота',
      'воскресенье',
    ][now.weekday - 1];
    final raw = await complete(
      'Сегодня ${_isoDate(now)}, $weekday, текущее время '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}.\n'
      'Фраза пользователя: «${text.trim()}»',
    );
    if (raw == null) return null;
    return commandFromJson(_decodeJson(raw), text, now);
  }

  /// Свободный ответ модели (используется сервером Алисы как запасной путь).
  Future<String?> complete(String userText) async {
    if (!config.isConfigured) return null;
    final uri = Uri.parse('${config.baseUrl}/completion');
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Api-Key ${config.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'modelUri': config.modelUri,
              'completionOptions': {
                'stream': false,
                'temperature': 0,
                'maxTokens': 400,
              },
              'messages': [
                {'role': 'system', 'text': _system},
                {'role': 'user', 'text': userText},
              ],
            }),
          )
          .timeout(config.timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final alternatives =
          (body['result'] as Map?)?['alternatives'] as List? ?? const [];
      if (alternatives.isEmpty) return null;
      final message = (alternatives.first as Map)['message'] as Map?;
      return message?['text'] as String?;
    } catch (_) {
      return null; // сеть/ключ/лимиты — тихо откатываемся к правилам
    }
  }

  static Map<String, Object?>? _decodeJson(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*```$'), '');
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(s.substring(start, end + 1));
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Преобразует JSON модели в [Command]. Вынесено отдельно, чтобы покрыть тестами.
Command? commandFromJson(
  Map<String, Object?>? json,
  String original,
  DateTime now,
) {
  if (json == null) return null;
  final intentName = (json['intent'] as String?)?.trim().toLowerCase();
  final intent = Intent.values
      .where((i) => i.name.toLowerCase() == intentName)
      .firstOrNull;
  if (intent == null || intent == Intent.unknown) return null;

  final typeName = (json['type'] as String?)?.trim().toLowerCase();
  final type = EntryType.values.where((t) => t.name == typeName).firstOrNull;

  final title = (json['title'] as String?)?.trim() ?? '';
  final day = _parseDay(json['date'], now);
  final time = _parseTime(json['time']);
  final untimed = json['untimed'] == true;
  final duration = (json['durationMin'] as num?)?.toInt();

  final date = ParsedDate(
    day: day,
    hour: time?.$1,
    minute: time?.$2,
    rest: TextBuf(title.isEmpty ? original : title),
  );

  if (intent == Intent.create && title.isEmpty) return null;
  if (intent != Intent.create && intent != Intent.list && title.isEmpty) {
    return null;
  }

  return Command(
    intent,
    type: type,
    text: title,
    date: date,
    untimed: untimed,
    durationMin: duration,
  );
}

DateTime? _parseDay(Object? value, DateTime now) {
  if (value is! String || value.trim().isEmpty || value == 'null') return null;
  final s = value.trim();
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  final ru = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(s);
  if (ru != null) {
    return DateTime(
      int.parse(ru.group(3)!),
      int.parse(ru.group(2)!),
      int.parse(ru.group(1)!),
    );
  }
  return null;
}

(int, int)? _parseTime(Object? value) {
  if (value is! String || value.trim().isEmpty || value == 'null') return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return (h, min);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
