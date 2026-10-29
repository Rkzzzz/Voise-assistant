import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'audio_store_io.dart' if (dart.library.html) 'audio_store_web.dart'
    as audio_store;

/// Доступ к Yandex SpeechKit (Yandex Cloud).
///
/// Один и тот же API-ключ и folderId используются для распознавания (STT)
/// и синтеза (TTS). Ключ создаётся в консоли Yandex Cloud у сервисного
/// аккаунта с ролью `ai.speechkit-stt.user` / `ai.speechkit-tts.user`.
class SpeechKitConfig {
  const SpeechKitConfig({
    this.apiKey = '',
    this.folderId = '',
    this.voice = '',
    this.lang = 'ru-RU',
    this.timeout = const Duration(seconds: 30),
  });

  final String apiKey;
  final String folderId;

  /// Голос синтеза. Пусто — `alena` или `filipp` по настройке пола голоса.
  final String voice;
  final String lang;
  final Duration timeout;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty && folderId.trim().isNotEmpty;
}

class SpeechKitException implements Exception {
  SpeechKitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SpeechKit {
  SpeechKit(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final SpeechKitConfig config;
  final http.Client _client;

  /// Освободить keep-alive соединения.
  void close() => _client.close();

  static const _sttUrl =
      'https://stt.api.cloud.yandex.net/speech/v1/stt:recognize';
  static const _ttsUrl =
      'https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize';

  /// Распознаёт сырой PCM16 mono.
  Future<String?> recognize(Uint8List pcm, {int sampleRate = 16000}) async {
    if (!config.isConfigured) return null;
    if (pcm.isEmpty) return null;
    final uri = Uri.parse('$_sttUrl?lang=${config.lang}&folderId='
        '${Uri.encodeQueryComponent(config.folderId.trim())}'
        '&format=lpcm&sampleRateHertz=$sampleRate');
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Api-Key ${config.apiKey.trim()}',
              'Content-Type': 'application/octet-stream',
            },
            body: pcm,
          )
          .timeout(config.timeout);
      if (res.statusCode != 200) {
        throw SpeechKitException(_error('распознавание', res));
      }
      final text = _jsonString(utf8.decode(res.bodyBytes), 'result');
      return text?.trim();
    } on SpeechKitException {
      rethrow;
    } catch (e) {
      throw SpeechKitException('SpeechKit STT: $e');
    }
  }

  /// Синтезирует речь в MP3.
  Future<Uint8List?> synthesize(String text, {required bool male}) async {
    if (!config.isConfigured || text.trim().isEmpty) return null;
    final voice = config.voice.trim().isNotEmpty
        ? config.voice.trim()
        : (male ? 'filipp' : 'alena');
    final body = {
      'text': text,
      'lang': config.lang,
      'voice': voice,
      'folderId': config.folderId.trim(),
      'format': 'mp3',
      'speed': '1.0',
    };
    try {
      final res = await _client
          .post(
            Uri.parse(_ttsUrl),
            headers: {
              'Authorization': 'Api-Key ${config.apiKey.trim()}',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(config.timeout);
      if (res.statusCode != 200) {
        throw SpeechKitException(_error('синтез', res));
      }
      return res.bodyBytes;
    } on SpeechKitException {
      rethrow;
    } catch (e) {
      throw SpeechKitException('SpeechKit TTS: $e');
    }
  }

  static String _error(String what, http.Response res) {
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    final msg = _jsonString(text, 'message') ?? _jsonString(text, 'error');
    return 'SpeechKit ($what): ${res.statusCode}'
        '${msg == null ? '' : ' — $msg'}';
  }
}

String? _jsonString(String source, String key) {
  final m = RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(source);
  if (m == null) return null;
  return m.group(1)!.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
}

/// Запись и воспроизведение через SpeechKit.
class YandexSpeech {
  YandexSpeech(SpeechKitConfig config)
      : config = config,
        _kit = SpeechKit(config);

  final SpeechKitConfig config;
  final SpeechKit _kit;

  final speaking = ValueNotifier<bool>(false);

  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  bool _recording = false;
  bool _male = false;

  void Function(String words, bool isFinal)? _onResult;
  void Function(bool listening)? onListening;

  set male(bool value) => _male = value;

  Future<bool> hasPermission() async {
    if (kIsWeb) return false; // в браузере облачный STT выключен
    final r = _recorder ??= AudioRecorder();
    try {
      return await r.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<bool> startListening(
      void Function(String words, bool isFinal) onResult) async {
    if (!config.isConfigured || kIsWeb) return false;
    final r = _recorder ??= AudioRecorder();
    if (!await r.hasPermission()) return false;
    try {
      final path = await audio_store.tempAudioPath('.pcm');
      await r.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _onResult = onResult;
      _recording = true;
      onListening?.call(true);
      return true;
    } catch (_) {
      onListening?.call(false);
      return false;
    }
  }

  /// Останавливает запись, отправляет её в SpeechKit и отдаёт текст.
  Future<void> stopListening() async {
    if (!_recording) return;
    _recording = false;
    onListening?.call(false);
    try {
      final saved = await _recorder?.stop();
      if (saved == null || saved.isEmpty) return;
      final bytes = await audio_store.readAndDelete(saved);
      if (bytes == null || bytes.length < 3200) return; // меньше 0,1 c
      final text = await _kit.recognize(Uint8List.fromList(bytes));
      if (text != null && text.isNotEmpty) _onResult?.call(text, true);
    } catch (_) {
      // ошибку покажет экран: текст просто не придёт
    } finally {
      _onResult = null;
    }
  }

  Future<void> speak(String text) async {
    if (!config.isConfigured) return;
    final bytes = await _kit.synthesize(text, male: _male);
    if (bytes == null || bytes.isEmpty) return;
    final player = _player ??= AudioPlayer();
    // Подписка одна на проигрыватель: слушать то же состояние несколько раз
    // бессмысленно, а старая подписка никогда не освобождается.
    _stateSub ??= player.onPlayerStateChanged.listen((s) {
      speaking.value = s == PlayerState.playing;
    });
    await player.stop();
    await player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
  }

  Future<void> stopSpeaking() async {
    await _player?.stop();
    speaking.value = false;
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    _stateSub = null;
    _kit.close();
    await _recorder?.dispose();
    await _player?.dispose();
  }
}
