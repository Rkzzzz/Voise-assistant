import 'dart:io';

import 'package:alice_server/api.dart';
import 'package:alice_server/cloud_store.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Запуск сервера:
///   dart run bin/server.dart --port 8080 --data data/store.json
///
/// Порт можно задать переменной окружения PORT (так делают облачные
/// платформы), путь к данным — DATA_FILE.
Future<void> main(List<String> args) async {
  final port = _arg(args, '--port') ?? Platform.environment['PORT'] ?? '8080';
  final data = _arg(args, '--data') ??
      Platform.environment['DATA_FILE'] ??
      'data/store.json';

  final store = CloudStore(data);
  await store.load();

  final api = Api(store);
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, int.parse(port));
  stdout.writeln('Сервер Алисы: http://${server.address.host}:${server.port}');
  stdout.writeln('Вебхук для Яндекс.Диалогов: /alice');
  stdout.writeln('Данные: ${File(data).absolute.path}');
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
