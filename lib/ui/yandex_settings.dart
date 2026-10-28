import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../data/settings.dart';
import '../services/yandex/calendar_sync.dart';
import '../services/yandex/cloud_sync.dart';
import '../services/yandex/speechkit.dart';
import '../voice/voice_service.dart';
import 'theme.dart';

/// Настройки интеграций с Яндексом: Календарь, SpeechKit, YandexGPT,
/// навык Алисы.
class YandexSettingsSection extends StatefulWidget {
  const YandexSettingsSection(
      {super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  State<YandexSettingsSection> createState() => _YandexSettingsSectionState();
}

class _YandexSettingsSectionState extends State<YandexSettingsSection> {
  late final TextEditingController _calLogin;
  late final TextEditingController _calPassword;
  late final TextEditingController _calUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _folderId;
  late final TextEditingController _cloudUrl;
  bool _busy = false;

  AppSettings get _s => widget.assistant.appSettings;

  @override
  void initState() {
    super.initState();
    _calLogin = TextEditingController(text: _s.yandexCalendarLogin);
    _calPassword = TextEditingController(text: _s.yandexCalendarPassword);
    _calUrl = TextEditingController(text: _s.yandexCalendarUrl);
    _apiKey = TextEditingController(text: _s.yandexApiKey);
    _folderId = TextEditingController(text: _s.yandexFolderId);
    _cloudUrl = TextEditingController(text: _s.cloudSyncUrl);
  }

  @override
  void dispose() {
    _calLogin.dispose();
    _calPassword.dispose();
    _calUrl.dispose();
    _apiKey.dispose();
    _folderId.dispose();
    _cloudUrl.dispose();
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? const Color(0xFFB3261E) : null,
    ));
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    final msg = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(msg);
  }

  void _applySpeech() {
    widget.voice.configureYandex(_s.yandexSpeechEnabled
        ? SpeechKitConfig(
            apiKey: _s.yandexApiKey,
            folderId: _s.yandexFolderId,
            voice: _s.yandexTtsVoice,
          )
        : null);
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 12, color: fg(context).withValues(alpha: 0.6))),
      );

  Widget _field(TextEditingController c, String label,
          {bool secret = false,
          String? helper,
          ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: secret,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Яндекс.Календарь'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Синхронизировать с Яндекс.Календарём'),
          value: s.yandexCalendarEnabled,
          onChanged: (v) {
            setState(() => s.change(yandexCalendarEnabled: v));
            if (v) {
              _toast(
                  'Укажите логин и пароль приложения, затем нажмите «Синхронизировать».');
            }
          },
        ),
        if (s.yandexCalendarEnabled) ...[
          _field(_calLogin, 'Логин Яндекс (почта)',
              onChanged: (v) => s.change(yandexCalendarLogin: v.trim())),
          _field(_calPassword, 'Пароль приложения',
              secret: true,
              helper:
                  'id.yandex.ru → Безопасность → Пароли приложений → Календарь',
              onChanged: (v) => s.change(yandexCalendarPassword: v)),
          _field(_calUrl, 'Адрес календаря (необязательно)',
              onChanged: (v) => s.change(yandexCalendarUrl: v.trim())),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final r = await YandexCalendarSync(
                        repo: widget.assistant.repo,
                        settings: s,
                      ).sync();
                      await widget.assistant.resyncNotifications();
                      return r.message;
                    }),
            icon: const Icon(Icons.sync),
            label: const Text('Синхронизировать'),
          ),
          _hint('Встречи, задачи и напоминания с датой попадают в календарь '
              'и возвращаются из него. Побеждает более свежая версия.'),
        ],
        _title('Yandex SpeechKit и YandexGPT'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Распознавать и озвучивать через SpeechKit'),
          value: s.yandexSpeechEnabled,
          onChanged: (v) {
            setState(() => s.change(yandexSpeechEnabled: v));
            _applySpeech();
          },
        ),
        if (s.yandexSpeechEnabled || s.yandexGptEnabled) ...[
          _field(_apiKey, 'API-ключ Yandex Cloud', secret: true,
              onChanged: (v) {
            s.change(yandexApiKey: v.trim());
            _applySpeech();
          }),
          _field(_folderId, 'Folder ID', onChanged: (v) {
            s.change(yandexFolderId: v.trim());
            _applySpeech();
          }),
        ],
        if (s.yandexSpeechEnabled) ...[
          DropdownButtonFormField<String>(
            initialValue: s.yandexTtsVoice.isEmpty ? null : s.yandexTtsVoice,
            decoration: const InputDecoration(
              labelText: 'Голос синтеза',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'alena', child: Text('Алёна')),
              DropdownMenuItem(value: 'filipp', child: Text('Филипп')),
              DropdownMenuItem(value: 'jane', child: Text('Джейн')),
              DropdownMenuItem(value: 'omazh', child: Text('Омаж')),
              DropdownMenuItem(value: 'zahar', child: Text('Захар')),
              DropdownMenuItem(value: 'ermil', child: Text('Ермил')),
            ],
            onChanged: (v) {
              s.change(yandexTtsVoice: v ?? '');
              _applySpeech();
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () =>
                widget.voice.speak('Привет! Это Yandex SpeechKit.'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Проверить голос'),
          ),
        ],
        _hint('Тот же API-ключ и Folder ID используются для YandexGPT. '
            'Если облако недоступно, приложение вернётся к системному голосу '
            'и к правилам разбора фраз.'),
        _title('YandexGPT'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Понимать свободные фразы через YandexGPT'),
          value: s.yandexGptEnabled,
          onChanged: (v) {
            setState(() => s.change(yandexGptEnabled: v));
            if (v && !(s.yandexSpeechEnabled)) {
              _toast('Укажите API-ключ и Folder ID в разделе SpeechKit.');
            }
          },
        ),
        if (s.yandexGptEnabled)
          DropdownButtonFormField<String>(
            initialValue: s.yandexGptModel,
            decoration: const InputDecoration(
              labelText: 'Модель',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'yandexgpt-lite', child: Text('yandexgpt-lite')),
              DropdownMenuItem(value: 'yandexgpt', child: Text('yandexgpt')),
              DropdownMenuItem(
                  value: 'yandexgpt-32k', child: Text('yandexgpt-32k')),
            ],
            onChanged: (v) => s.change(yandexGptModel: v ?? 'yandexgpt-lite'),
          ),
        _hint('Правила остаются основным разбором: модель вызывается только '
            'если фраза не распознана. Нужны интернет и оплаченный API-ключ.'),
        _title('Алиса'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Синхронизировать с навыком Алисы'),
          value: s.cloudSyncEnabled,
          onChanged: (v) => setState(() => s.change(cloudSyncEnabled: v)),
        ),
        if (s.cloudSyncEnabled) ...[
          _field(_cloudUrl, 'Адрес сервера',
              helper: 'Например, https://alice.example.ru',
              onChanged: (v) => s.change(cloudSyncUrl: v.trim())),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final r = await CloudSync(
                              repo: widget.assistant.repo,
                              settings: s,
                              profile: s.profileIndex,
                            ).register(name: s.userName);
                            return r.message;
                          }),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Создать аккаунт'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final r = await CloudSync(
                              repo: widget.assistant.repo,
                              settings: s,
                              profile: s.profileIndex,
                            ).pairCode();
                            return r.message;
                          }),
                  icon: const Icon(Icons.link),
                  label: const Text('Код для Алисы'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final r = await CloudSync(
                              repo: widget.assistant.repo,
                              settings: s,
                              profile: s.profileIndex,
                            ).sync();
                            widget.assistant.onChanged?.call();
                            return r.message;
                          }),
                  icon: const Icon(Icons.cloud_sync),
                  label: const Text('Синхронизировать'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Отвязать Алису',
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final r = await CloudSync(
                            repo: widget.assistant.repo,
                            settings: s,
                            profile: s.profileIndex,
                          ).unlink();
                          return r.message;
                        }),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          _hint('1. Создайте аккаунт на сервере. 2. Получите код. '
              '3. Скажите Алисе: «Свяжи аккаунт, код 123456». '
              'После этого задачи и встречи общие для приложения и Алисы.'),
        ],
      ],
    );
  }
}
