import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/entry_repository.dart';
import '../../data/settings.dart';
import '../../models/entry.dart';
import '../../models/mark.dart';

class CloudSyncResult {
  const CloudSyncResult({this.message = '', this.error = false});

  final String message;
  final bool error;
}

/// Синхронизация с сервером навыка Алисы (`packages/alice_server`).
///
/// Один аккаунт на профиль: записи, созданные голосом через Алису,
/// появляются в приложении, а записи приложения — в ответах Алисы.
class CloudSync {
  CloudSync({
    required this.repo,
    required this.settings,
    http.Client? client,
    this.profile = 0,
  }) : _client = client ?? http.Client();

  final EntryRepository repo;
  final AppSettings settings;
  final http.Client _client;
  final int profile;

  String get _base {
    var url = settings.cloudSyncUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  bool get _configured =>
      settings.cloudSyncEnabled &&
      _base.isNotEmpty &&
      settings.cloudSyncToken.trim().isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer ${settings.cloudSyncToken.trim()}',
      };

  /// Регистрирует аккаунт на сервере и сохраняет токен.
  Future<CloudSyncResult> register({String name = ''}) async {
    if (!settings.cloudSyncEnabled || _base.isEmpty) {
      return const CloudSyncResult(
          message: 'Укажите адрес сервера и включите синхронизацию.',
          error: true);
    }
    try {
      final res = await _client.post(
        Uri.parse('$_base/api/register'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'name': name, 'profile': profile}),
      );
      if (res.statusCode != 200) {
        return CloudSyncResult(
            message: 'Сервер ответил ${res.statusCode}.', error: true);
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      settings.change(
        cloudSyncToken: '${body['token']}',
        cloudSyncUser: '${body['userId']}',
      );
      return const CloudSyncResult(message: 'Аккаунт создан на сервере.');
    } catch (e) {
      return CloudSyncResult(message: 'Нет связи с сервером: $e', error: true);
    }
  }

  /// Код привязки: его нужно назвать Алисе.
  Future<CloudSyncResult> pairCode() async {
    if (!_configured) {
      return const CloudSyncResult(
          message: 'Сначала создайте аккаунт на сервере.', error: true);
    }
    try {
      final res = await _client.post(
        Uri.parse('$_base/api/pair'),
        headers: _headers,
        body: '{}',
      );
      if (res.statusCode != 200) {
        return CloudSyncResult(
            message: 'Сервер ответил ${res.statusCode}.', error: true);
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      return CloudSyncResult(
          message: 'Скажите Алисе: «Свяжи аккаунт, код ${body['code']}».');
    } catch (e) {
      return CloudSyncResult(message: 'Нет связи с сервером: $e', error: true);
    }
  }

  /// Двусторонний обмен: отправляет локальные записи, забирает серверные.
  Future<CloudSyncResult> sync() async {
    if (!_configured) {
      return const CloudSyncResult(
          message: 'Синхронизация с Алисой не настроена.', error: true);
    }
    try {
      final local = await repo.all();
      final marks = await repo.marks();
      final res = await _client
          .post(
            Uri.parse('$_base/api/sync'),
            headers: _headers,
            body: jsonEncode({
              'profile': profile,
              'entries': local.map((e) => e.toMap()).toList(),
              'marks': marks.map((m) => m.toMap()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        return CloudSyncResult(
            message: res.statusCode == 401
                ? 'Сервер не принял токен. Создайте аккаунт заново.'
                : 'Сервер ответил ${res.statusCode}.',
            error: true);
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final serverEntries = ((body['entries'] as List?) ?? const [])
          .map((e) => Entry.fromMap(Map<String, Object?>.from(e as Map)))
          .toList();
      final pulled = await _merge(serverEntries);
      return CloudSyncResult(
          message: pulled == 0
              ? 'Синхронизировано: новых записей нет.'
              : 'Синхронизировано, получено записей: $pulled.');
    } catch (e) {
      return CloudSyncResult(message: 'Нет связи с сервером: $e', error: true);
    }
  }

  Future<int> _merge(List<Entry> serverEntries) async {
    final local = await repo.all();
    final byExternal = <String, Entry>{
      for (final e in local)
        if (e.externalId.isNotEmpty) e.externalId: e,
    };
    var changed = 0;
    for (final s in serverEntries) {
      if (s.externalId.isEmpty) continue;
      final mine = byExternal[s.externalId];
      if (mine == null) {
        await repo.add(s.copyWith(id: null));
        changed++;
        continue;
      }
      if (s.lastModified.isAfter(mine.lastModified)) {
        await repo.update(mine.copyWith(
          title: s.title,
          type: s.type,
          dueAt: s.dueAt,
          clearDue: s.dueAt == null,
          hasTime: s.hasTime,
          done: s.done,
          comment: s.comment,
          durationMin: s.durationMin,
          place: s.place,
          externalId: s.externalId,
          updatedAt: s.updatedAt,
        ));
        changed++;
      }
    }
    return changed;
  }

  /// Отвязывает Алису от аккаунта.
  Future<CloudSyncResult> unlink() async {
    if (!_configured) {
      return const CloudSyncResult(
          message: 'Синхронизация не настроена.', error: true);
    }
    try {
      final res = await _client.post(
        Uri.parse('$_base/api/unlink'),
        headers: _headers,
        body: '{}',
      );
      if (res.statusCode != 200) {
        return CloudSyncResult(
            message: 'Сервер ответил ${res.statusCode}.', error: true);
      }
      return const CloudSyncResult(message: 'Алиса отвязана от аккаунта.');
    } catch (e) {
      return CloudSyncResult(message: 'Нет связи с сервером: $e', error: true);
    }
  }

  /// Отправляет одну запись сразу после изменения (если включена синхронизация).
  Future<void> push(Entry e) async {
    if (!_configured) return;
    try {
      await _client.post(
        Uri.parse('$_base/api/sync'),
        headers: _headers,
        body: jsonEncode({
          'profile': profile,
          'entries': [e.toMap()],
          'marks': <Mark>[],
        }),
      );
    } catch (_) {
      // тихо: синхронизация повторится вручную
    }
  }
}
