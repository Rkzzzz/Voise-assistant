import 'dart:convert';

import 'cloud_service.dart';

/// Обработчик вебхука Яндекс.Диалогов (навык Алисы).
///
/// Протокол: POST с JSON, в ответ — JSON с полями version/session/response.
class AliceWebhook {
  AliceWebhook(this.service);

  final CloudService service;

  static const _linkHint =
      'Чтобы я видел ваши записи, свяжите аккаунт. Откройте приложение, '
      'нажмите «Получить код для Алисы» и скажите: «Свяжи аккаунт, код 123456».';

  Future<Map<String, Object?>> handle(Map<String, Object?> body) async {
    final session = Map<String, Object?>.from(
        (body['session'] as Map?) ?? const <String, Object?>{});
    final request = Map<String, Object?>.from(
        (body['request'] as Map?) ?? const <String, Object?>{});
    final user = Map<String, Object?>.from(
        (session['user'] as Map?) ?? const <String, Object?>{});
    final yandexId = '${user['user_id'] ?? ''}';
    final command =
        '${request['command'] ?? request['original_utterance'] ?? ''}'.trim();

    final text = await _answer(yandexId, command, session['new'] == true);
    return {
      'version': '1.0',
      'session': session,
      'response': {
        'text': text,
        'tts': text,
        'end_session': false,
      },
    };
  }

  Future<String> _answer(String yandexId, String command, bool isNew) async {
    final low = command.toLowerCase().replaceAll('ё', 'е');

    // привязка аккаунта: «свяжи аккаунт, код 123456»
    final codeMatch = RegExp(r'(?:код|code)\s*(\d{6})').firstMatch(low);
    if (codeMatch != null) {
      if (yandexId.isEmpty) {
        return 'Не получилось определить ваш аккаунт Яндекса.';
      }
      final user = await service.store.link(codeMatch.group(1)!, yandexId);
      if (user == null) {
        return 'Код не подошёл или уже истёк. Получите новый код в приложении.';
      }
      return 'Готово, аккаунт связан. Теперь я вижу ваши задачи и встречи.';
    }

    if (low.contains('отвяжи') || low.contains('отвязать')) {
      final user = service.store.byYandex(yandexId);
      if (user == null) return 'Аккаунт и так не связан.';
      await service.store.unlink(user);
      return 'Аккаунт отвязан. Записи остались в приложении.';
    }

    final user = service.store.byYandex(yandexId);
    if (user == null) return _linkHint;

    if (isNew) {
      final reply = await service.handleText(user, 'Что у меня сегодня?');
      final hello = user.name.isEmpty ? 'Привет! ' : '${user.name}, привет! ';
      return '$hello${reply.text}'.replaceAll('\n', ' ');
    }

    if (command.isEmpty) return 'Я слушаю.';

    final reply = await service.handleText(user, command);
    return reply.text;
  }

  /// Проверка подписи/секрета не требуется протоколом, но можно ограничить
  /// доступ по пути вебхука. Метод оставлен для будущего OAuth.
  static String encode(Map<String, Object?> body) => jsonEncode(body);
}

/// Склонение для коротких ответов Алисы.
String plural(int n, String one, String few, String many) {
  final a = n % 100, b = n % 10;
  if (a >= 11 && a <= 14) return many;
  if (b == 1) return one;
  if (b >= 2 && b <= 4) return few;
  return many;
}
