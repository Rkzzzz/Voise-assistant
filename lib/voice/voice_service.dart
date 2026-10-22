import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Всё, что связано с голосом: распознавание (STT) и озвучка (TTS).
/// Использует системные движки устройства, ключи API не нужны.
class VoiceService {
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;

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

  Future<void> speak(String text) async {
    if (!_ttsReady) {
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.5);
      _ttsReady = true;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() => _tts.stop();
}
