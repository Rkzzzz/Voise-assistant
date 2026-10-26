import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Всё, что связано с голосом: распознавание (STT) и озвучка (TTS).
/// Использует системные движки устройства, ключи API не нужны.
class VoiceService {
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;
  bool _male = false;

  /// true, пока ассистент говорит.
  final speaking = ValueNotifier<bool>(false);

  /// Вызывается, когда микрофон включается / выключается.
  void Function(bool listening)? onListening;

  Future<bool> init() async {
    if (_sttReady) return true;
    _sttReady = await _stt.initialize(
      onStatus: (s) => onListening?.call(s == 'listening'),
      onError: (_) => onListening?.call(false),
    );
    return _sttReady;
  }

  Future<void> listen(void Function(String words, bool isFinal) onResult) =>
      _stt.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        localeId: 'ru_RU',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );

  Future<void> stopListening() => _stt.stop();

  Future<void> _initTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.5);
    _tts.setStartHandler(() => speaking.value = true);
    _tts.setCompletionHandler(() => speaking.value = false);
    _tts.setCancelHandler(() => speaking.value = false);
    _tts.setErrorHandler((_) => speaking.value = false);
    await _applyVoice();
  }

  /// Женский / мужской голос. Набор голосов зависит от телефона: если
  /// подходящего голоса нет, меняется только высота тона.
  Future<void> setGender({required bool male}) async {
    _male = male;
    if (_ttsReady) await _applyVoice();
  }

  Future<List<Map<String, String>>> russianVoices() async {
    try {
      final raw = await _tts.getVoices as List?;
      return (raw ?? [])
          .map((v) => {
                'name': '${(v as Map)['name']}',
                'locale': '${v['locale']}',
              })
          .where((v) => v['locale']!.toLowerCase().startsWith('ru'))
          .toList()
        ..sort((a, b) => a['name']!.compareTo(b['name']!));
    } catch (_) {
      return [];
    }
  }

  Future<void> _applyVoice() async {
    await _tts.setPitch(_male ? 0.7 : 1.1);
    try {
      final voices = await russianVoices();
      if (voices.isEmpty) return;
      final maleRe = RegExp(r'(?<![a-z])(male|man)(?![a-z])|[-_]m[-_]');
      final femaleRe = RegExp(r'female|woman|[-_]f[-_]');
      Map<String, String>? pick;
      for (final v in voices) {
        final n = v['name']!.toLowerCase();
        final isFemale = femaleRe.hasMatch(n);
        final isMale = !isFemale && maleRe.hasMatch(n);
        if (_male ? isMale : isFemale) {
          pick = v;
          break;
        }
      }
      // имена голосов не говорят о поле: берём разные голоса из списка
      pick ??= voices.length > 1 ? (_male ? voices.last : voices.first) : null;
      if (pick != null) await _tts.setVoice(pick);
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    await _initTts();
    await _tts.stop();
    await _tts.speak(text);
  }

  /// Остановить речь.
  Future<void> stopSpeaking() async {
    await _tts.stop();
    speaking.value = false;
  }
}
