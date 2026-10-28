import 'dart:convert';

import 'package:assistant_core/assistant_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'alice_webhook.dart';
import 'cloud_service.dart';
import 'cloud_store.dart';

/// REST API для приложения и вебхук Алисы.
///
///   POST /alice                    — вебхук Яндекс.Диалогов
///   POST /api/register             — новый аккаунт: {deviceId}
///   POST /api/pair                 — код для Алисы (Bearer)
///   POST /api/sync                 — обмен записями (Bearer)
///   GET  /api/entries              — записи (Bearer)
///   POST /api/unlink               — отвязать Алису (Bearer)
///   GET  /health                   — проверка сервера
class Api {
  Api(this.store, {String? publicUrl}) : service = CloudService(store) {
    alice = AliceWebhook(service);
    router = Router()
      ..get('/health', _health)
      ..post('/alice', _alice)
      ..post('/api/register', _register)
      ..post('/api/pair', _pair)
      ..post('/api/sync', _sync)
      ..get('/api/entries', _entries)
      ..post('/api/unlink', _unlink);
  }

  final CloudStore store;
  final CloudService service;
  late final AliceWebhook alice;
  late final Router router;

  Handler get handler => const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors)
      .addHandler(router.call);

  Response _health(Request req) => _json({'ok': true, 'service': 'alice'});

  Future<Response> _alice(Request req) async {
    final body = await _body(req);
    final answer = await alice.handle(body);
    return _json(answer);
  }

  Future<Response> _register(Request req) async {
    final body = await _body(req);
    final name = '${body['name'] ?? ''}'.trim();
    final user = await store.register(name: name);
    return _json({
      'userId': user.id,
      'token': user.token,
      'name': user.name,
    });
  }

  Future<Response> _pair(Request req) async {
    final user = _auth(req);
    if (user == null) return _error(401, 'Неверный токен');
    final code = await store.createPairCode(user);
    return _json({'code': code, 'expiresInMinutes': 15});
  }

  Future<Response> _sync(Request req) async {
    final user = _auth(req);
    if (user == null) return _error(401, 'Неверный токен');
    final body = await _body(req);
    final entries = ((body['entries'] as List?) ?? const [])
        .map((e) => Entry.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
    final marks = ((body['marks'] as List?) ?? const [])
        .map((m) => Mark.fromMap(Map<String, Object?>.from(m as Map)))
        .toList();
    final result = await service.merge(user, entries: entries, marks: marks);
    return _json({
      'added': result.added,
      'updated': result.updated,
      'entries': result.entries.map((e) => e.toMap()).toList(),
      'marks': result.marks.map((m) => m.toMap()).toList(),
    });
  }

  Future<Response> _entries(Request req) async {
    final user = _auth(req);
    if (user == null) return _error(401, 'Неверный токен');
    return _json({
      'entries': user.entries.map((e) => e.toMap()).toList(),
      'marks': user.marks.map((m) => m.toMap()).toList(),
    });
  }

  Future<Response> _unlink(Request req) async {
    final user = _auth(req);
    if (user == null) return _error(401, 'Неверный токен');
    await store.unlink(user);
    return _json({'ok': true});
  }

  CloudUser? _auth(Request req) {
    final h = req.headers['authorization'] ?? '';
    final token = h.toLowerCase().startsWith('bearer ')
        ? h.substring(7).trim()
        : h.trim();
    return store.byToken(token);
  }

  Future<Map<String, Object?>> _body(Request req) async {
    final raw = await req.readAsString();
    if (raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return {};
    }
  }

  static Response _json(Object? data) => Response.ok(
        jsonEncode(data),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static Response _error(int code, String message) => Response(
        code,
        body: jsonEncode({'error': message}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static Middleware get _cors => (inner) => (req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final res = await inner(req);
        return res.change(headers: _corsHeaders);
      };

  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
  };
}
