import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../data/settings.dart';
import '../voice/voice_service.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _user;
  late final TextEditingController _asst;

  Assistant get _a => widget.assistant;
  AppSettings get _s => _a.settings;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: _s.userName);
    _asst = TextEditingController(text: _s.assistantName);
  }

  @override
  void dispose() {
    _user.dispose();
    _asst.dispose();
    super.dispose();
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Настройки',
                style: TextStyle(
                    fontFamily: kDisplayFont,
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    color: fg(context))),
            _title('Имена'),
            TextField(
              controller: _user,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Как к вам обращаться',
                  border: OutlineInputBorder()),
              onChanged: (v) => s.change(userName: v.trim()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _asst,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Имя ассистента',
                  helperText:
                      'Можно начинать фразу с имени: «Джарвис, что у меня сегодня?»',
                  border: OutlineInputBorder()),
              onChanged: (v) => s.change(
                  assistantName: v.trim().isEmpty ? 'Ассистент' : v.trim()),
            ),
            _title('Голос'),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Женский')),
                ButtonSegment(value: true, label: Text('Мужской')),
              ],
              selected: {s.maleVoice},
              onSelectionChanged: (v) async {
                s.change(maleVoice: v.first);
                await widget.voice.setGender(male: v.first);
                widget.voice.speak('Привет! Так звучит мой голос.');
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.voice.speak('Привет! Так звучит мой голос.'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Проверить'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.voice.stopSpeaking,
                  icon: const Icon(Icons.stop),
                  label: const Text('Остановить'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Набор голосов зависит от телефона. Если подходящего голоса '
                  'нет, меняется высота тона. Другие голоса: Настройки Android → '
                  'Синтез речи.',
                  style: TextStyle(
                      fontSize: 12, color: fg(context).withValues(alpha: 0.6))),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Озвучивать ответы'),
              value: s.speak,
              onChanged: (v) => setState(() => s.change(speak: v)),
            ),
            _title('Тема'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Система')),
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => setState(() => s.change(themeMode: v.first)),
            ),
            _title('Уведомления'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('В момент события'),
              value: s.notifyAtTime,
              onChanged: (v) async {
                setState(() => s.change(notifyAtTime: v));
                await _a.resyncNotifications();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('За час до события'),
              value: s.notifyHourBefore,
              onChanged: (v) async {
                setState(() => s.change(notifyHourBefore: v));
                await _a.resyncNotifications();
              },
            ),
            OutlinedButton.icon(
              onPressed: _a.notifier.showTest,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Проверить уведомление'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Уведомления приходят со временем, указанным у события; '
                  'Android может сдвинуть их на несколько минут в режиме экономии.',
                  style: TextStyle(
                      fontSize: 12, color: fg(context).withValues(alpha: 0.6))),
            ),
            _title('О календаре'),
            Text(
                'Цвет дня: серый — свободно, зелёный — до 3 ч занято, '
                'оранжевый — до 8 ч, красный — времени почти нет. '
                'Встречи длятся не меньше часа и не должны пересекаться. '
                'Праздники — государственные РФ с фиксированными датами; '
                'переносы выходных не учитываются.',
                style: TextStyle(color: fg(context).withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }
}
