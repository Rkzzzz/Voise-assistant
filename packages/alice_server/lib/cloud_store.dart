import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:assistant_core/assistant_core.dart';

/// Пользователь сервера: приложение и Алиса видят одни и те же записи.
class CloudUser {
  CloudUser({
    required this.id,
    required this.token,
    this.name = '',
    this.yandexUserId = '',
    List<Entry>? entries,
    List<Mark>? marks,
    this.nextId = 1,
  })  : entries = entries ?? [],
        marks = marks ?? [];

  final String id;
  final String token;
  String name;

  /// Идентификатор пользователя Яндекса, который привязал аккаунт в Алисе.
  String yandexUserId;
  final List<Entry> entries;
  final List<Mark> marks;
  int nextId;

  Map<String, Object?> toJson() => {
        'id': id,
        'token': token,
        'name': name,
        'yandexUserId': yandexUserId,
        'nextId': nextId,
        'entries': entries.map((e) => e.toMap()).toList(),
        'marks': marks.map((m) => m.toMap()).toList(),
      };

  factory CloudUser.fromJson(Map<String, Object?> j) => CloudUser(
        id: j['id'] as String,
        token: j['token'] as String,
        name: (j['name'] as String?) ?? '',
        yandexUserId: (j['yandexUserId'] as String?) ?? '',
        nextId: (j['nextId'] as int?) ?? 1,
        entries: ((j['entries'] as List?) ?? const [])
            .map((e) => Entry.fromMap(Map<String, Object?>.from(e as Map)))
            .toList(),
        marks: ((j['marks'] as List?) ?? const [])
            .map((m) => Mark.fromMap(Map<String, Object?>.from(m as Map)))
            .toList(),
      );
}

class PairCode {
  PairCode(this.userId, this.expiresAt);
  final String userId;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// Хранилище в JSON-файле. Простое и переносимое: подходит для VPS
/// с одним процессом сервера.
class CloudStore {
  CloudStore(this.path);

  final String path;
  final _users = <String, CloudUser>{};
  final _pairCodes = <String, PairCode>{};
  final _rnd = Random.secure();

  Future<void> load() async {
    final file = File(path);
    if (!await file.exists()) return;
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return;
    for (final u in (raw['users'] as List? ?? const [])) {
      final user = CloudUser.fromJson(Map<String, Object?>.from(u as Map));
      _users[user.id] = user;
    }
    for (final c in (raw['pairCodes'] as List? ?? const [])) {
      final m = Map<String, Object?>.from(c as Map);
      final code = m['code'] as String;
      _pairCodes[code] = PairCode(
        m['userId'] as String,
        DateTime.fromMillisecondsSinceEpoch(m['expiresAt'] as int),
      );
    }
  }

  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode({
      'users': _users.values.map((u) => u.toJson()).toList(),
      'pairCodes': [
        for (final e in _pairCodes.entries)
          {
            'code': e.key,
            'userId': e.value.userId,
            'expiresAt': e.value.expiresAt.millisecondsSinceEpoch,
          },
      ],
    }));
    await tmp.rename(path);
  }

  String _token() => List.generate(32, (_) => _rnd.nextInt(16).toRadixString(16))
      .join();

  Future<CloudUser> register({String? name}) async {
    final id = 'u_${_token().substring(0, 12)}';
    final user = CloudUser(id: id, token: _token(), name: name ?? '');
    _users[id] = user;
    await save();
    return user;
  }

  CloudUser? byToken(String token) {
    if (token.isEmpty) return null;
    for (final u in _users.values) {
      if (u.token == token) return u;
    }
    return null;
  }

  CloudUser? byYandex(String yandexUserId) {
    if (yandexUserId.isEmpty) return null;
    for (final u in _users.values) {
      if (u.yandexUserId == yandexUserId) return u;
    }
    return null;
  }

  CloudUser? byId(String id) => _users[id];

  /// Код привязки для Алисы. Живёт 15 минут.
  Future<String> createPairCode(CloudUser user) async {
    _pairCodes.removeWhere((_, c) => c.expired);
    final code = (100000 + _rnd.nextInt(900000)).toString();
    _pairCodes[code] = PairCode(
        user.id, DateTime.now().add(const Duration(minutes: 15)));
    await save();
    return code;
  }

  Future<CloudUser?> link(String code, String yandexUserId) async {
    final pair = _pairCodes[code];
    if (pair == null || pair.expired) return null;
    final user = _users[pair.userId];
    if (user == null) return null;
    // один аккаунт Яндекса — один пользователь приложения
    for (final u in _users.values) {
      if (u.yandexUserId == yandexUserId && u.id != user.id) {
        u.yandexUserId = '';
      }
    }
    user.yandexUserId = yandexUserId;
    _pairCodes.remove(code);
    await save();
    return user;
  }

  Future<void> unlink(CloudUser user) async {
    user.yandexUserId = '';
    await save();
  }

  Future<void> persist(CloudUser user) => save();
}
