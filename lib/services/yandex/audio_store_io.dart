import 'dart:io';

/// Временный файл для записи голоса (мобильные платформы).
Future<String> tempAudioPath(String suffix) async {
  final dir = Directory.systemTemp;
  return '${dir.path}${Platform.pathSeparator}va_speech_'
      '${DateTime.now().millisecondsSinceEpoch}$suffix';
}

/// Читает записанный файл и удаляет его.
Future<List<int>?> readAndDelete(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  try {
    await file.delete();
  } catch (_) {}
  return bytes;
}
