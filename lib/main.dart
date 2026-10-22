import 'package:flutter/material.dart';

import 'assistant/assistant.dart';
import 'data/entry_repository.dart';
import 'ui/chat_page.dart';
import 'ui/theme.dart';
import 'voice/voice_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VoiceAssistantApp(
    assistant: Assistant(SqliteEntryRepository()),
    voice: VoiceService(),
  ));
}

class VoiceAssistantApp extends StatelessWidget {
  const VoiceAssistantApp(
      {super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Голосовой ассистент',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ChatPage(assistant: assistant, voice: voice),
      );
}
