import 'dart:convert';
import 'dart:io';

import 'package:alice_server/api.dart';
import 'package:alice_server/cloud_store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late Api api;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('alice_test');
    final store = CloudStore('${dir.path}/store.json');
    await store.load();
    api = Api(store);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<Response> post(String path, Map<String, Object?> body,
      {String? token}) async {
    final req = Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      headers: {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    );
    return api.handler(req);
  }

  Future<Map<String, Object?>> jsonOf(Response res) async =>
      Map<String, Object?>.from(
          jsonDecode(await res.readAsString()) as Map);

  Future<Map<String, Object?>> alice(
      String command, String userId, {bool isNew = false}) async {
    final res = await post('/alice', {
      'session': {
        'new': isNew,
        'user': {'user_id': userId},
      },
      'request': {'command': command},
    });
    final body = await jsonOf(res);
    return Map<String, Object?>.from(body['response'] as Map);
  }

  test('регистрация и код привязки', () async {
    final reg = await jsonOf(await post('/api/register', {'name': 'Иван'}));
    expect(reg['token'], isA<String>());
    final pair = await jsonOf(
        await post('/api/pair', {}, token: reg['token'] as String));
    expect(pair['code'], matches(RegExp(r'^\d{6}$')));
  });

  test('Алиса без привязки просит код', () async {
    final res = await alice('Что у меня сегодня?', 'y-1');
    expect('${res['text']}', contains('свяжите аккаунт'));
  });

  test('привязка и создание записи голосом', () async {
    final reg = await jsonOf(await post('/api/register', {'name': 'Иван'}));
    final pair = await jsonOf(
        await post('/api/pair', {}, token: reg['token'] as String));
    final link = await alice(
        'Свяжи аккаунт, код ${pair['code']}', 'y-1');
    expect('${link['text']}', contains('аккаунт связан'));

    final created =
        await alice('Напомни завтра в 10 утра позвонить Ивану', 'y-1');
    expect('${created['text']}', contains('напомню'));

    final list = await alice('Что у меня завтра?', 'y-1');
    expect('${list['text']}', contains('Позвонить Ивану'));
  });

  test('синхронизация: записи приложения видны Алисе', () async {
    final reg = await jsonOf(await post('/api/register', {'name': 'Иван'}));
    final token = reg['token'] as String;
    final pair = await jsonOf(await post('/api/pair', {}, token: token));
    await alice('Свяжи аккаунт, код ${pair['code']}', 'y-2');

    final sync = await jsonOf(await post('/api/sync', {
      'entries': [
        {
          'id': 1,
          'type': 'task',
          'title': 'Купить билеты',
          'due_at': DateTime(2026, 10, 29, 9).millisecondsSinceEpoch,
          'has_time': 1,
          'created_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
          'done': 0,
          'comment': '',
          'duration_min': 60,
          'place': '',
          'external_id': '',
          'updated_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
        }
      ],
      'marks': [],
    }, token: token));
    expect(sync['added'], 1);
    final entries = sync['entries'] as List;
    expect(entries, hasLength(1));
    expect((entries.first as Map)['external_id'], startsWith('cloud:'));

    final list = await alice('Что у меня завтра?', 'y-2');
    expect('${list['text']}', contains('Купить билеты'));
  });

  test('повторная синхронизация не создаёт дубликат', () async {
    final reg = await jsonOf(await post('/api/register', {}));
    final token = reg['token'] as String;
    final entry = {
      'id': 1,
      'type': 'task',
      'title': 'Отчёт',
      'due_at': DateTime(2026, 10, 29, 9).millisecondsSinceEpoch,
      'has_time': 1,
      'created_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
      'done': 0,
      'comment': '',
      'duration_min': 60,
      'place': '',
      'external_id': 'cloud:1',
      'updated_at': DateTime(2026, 10, 28).millisecondsSinceEpoch,
    };
    final first =
        await jsonOf(await post('/api/sync', {'entries': [entry]}, token: token));
    final second = await jsonOf(
        await post('/api/sync', {'entries': [entry]}, token: token));
    expect(first['added'], 1);
    expect(second['added'], 0);
    expect(second['entries'] as List, hasLength(1));
  });
}
