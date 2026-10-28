import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'assistant/assistant.dart';
import 'data/entry_repository.dart';
import 'data/settings.dart';
import 'data/web_entry_repository.dart';
import 'services/notifier.dart';
import 'services/yandex/calendar_sync.dart';
import 'services/yandex/cloud_sync.dart';
import 'services/yandex/nlu.dart';
import 'services/yandex/speechkit.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';
import 'voice/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final notifier = LocalNotifier(settings);
  await notifier.init();
  // в браузере SQLite недоступен — используем localStorage
  EntryRepository repoFor(int profile) => kIsWeb
      ? PrefsEntryRepository(profile: profile)
      : SqliteEntryRepository(profile: profile);
  final nlu = YandexNlu(settings);
  final assistant = Assistant(
    repoFor(settings.profileIndex),
    settings: settings,
    notifier: notifier,
    repoFor: repoFor,
    aiParser: nlu.parse,
  );
  final voice = VoiceService();
  voice.configureYandex(settings.yandexSpeechEnabled
      ? SpeechKitConfig(
          apiKey: settings.yandexApiKey,
          folderId: settings.yandexFolderId,
          voice: settings.yandexTtsVoice,
        )
      : null);
  await voice.setGender(male: settings.maleVoice);
  runApp(VoiceAssistantApp(assistant: assistant, voice: voice));
  assistant.resyncNotifications();
  _startBackgroundSync(assistant);
}

bool _syncing = false;

/// Синхронизация при запуске и каждые 15 минут: не задерживает старт,
/// не накладывается сама на себя и не мешает работе, если интернета нет.
void _startBackgroundSync(Assistant assistant) {
  Timer.periodic(
      const Duration(minutes: 15), (_) => _backgroundSync(assistant));
  _backgroundSync(assistant);
}

Future<void> _backgroundSync(Assistant assistant) async {
  if (_syncing) return;
  _syncing = true;
  try {
    final s = assistant.appSettings;
    if (s.yandexCalendarEnabled) {
      await YandexCalendarSync(repo: assistant.repo, settings: s).sync();
    }
    if (s.cloudSyncEnabled && s.cloudSyncToken.isNotEmpty) {
      await CloudSync(
        repo: assistant.repo,
        settings: s,
        profile: s.profileIndex,
      ).sync();
    }
  } catch (e, s) {
    debugPrint('sync error: $e\n$s');
  } finally {
    _syncing = false;
  }
}

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp(
      {super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: assistant.appSettings,
        builder: (_, __) => MaterialApp(
          title: 'Голосовой ассистент',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: assistant.appSettings.themeMode,
          home: AppShell(assistant: assistant, voice: voice),
        ),
      );
}
