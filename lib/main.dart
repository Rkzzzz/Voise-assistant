import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'assistant/assistant.dart';
import 'data/entry_repository.dart';
import 'data/settings.dart';
import 'data/web_entry_repository.dart';
import 'services/notifier.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';
import 'voice/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final notifier = LocalNotifier(settings);
  await notifier.init();
  final assistant = Assistant(
    // в браузере SQLite недоступен — используем localStorage
    kIsWeb ? PrefsEntryRepository() : SqliteEntryRepository(),
    settings: settings,
    notifier: notifier,
  );
  final voice = VoiceService();
  await voice.setGender(male: settings.maleVoice);
  runApp(VoiceAssistantApp(assistant: assistant, voice: voice));
  assistant.resyncNotifications();
}

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp(
      {super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: assistant.settings,
        builder: (_, __) => MaterialApp(
          title: 'Голосовой ассистент',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: assistant.settings.themeMode,
          home: AppShell(assistant: assistant, voice: voice),
        ),
      );
}
