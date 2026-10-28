import 'package:assistant_core/assistant/assistant.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки пользователя (хранятся в SharedPreferences).
class AppSettings extends ChangeNotifier implements AssistantSettings {
  AppSettings._(this._prefs);

  /// Без хранения — для тестов.
  factory AppSettings.memory() => AppSettings._(null);

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  final SharedPreferences? _prefs;

  @override
  String userName = '';
  @override
  String assistantName = 'Ассистент';
  bool maleVoice = false;
  ThemeMode themeMode = ThemeMode.dark;
  bool notifyAtTime = true;
  bool notifyHourBefore = true;
  bool speak = true;

  /// Локальные профили: у каждого свои записи и своё обращение.
  List<String> profileNames = ['Основной'];
  int profileIndex = 0;

  // --- Яндекс.Календарь (CalDAV) ---
  bool yandexCalendarEnabled = false;
  String yandexCalendarLogin = '';
  String yandexCalendarPassword = '';

  /// Пусто — адрес календаря определяется автоматически.
  String yandexCalendarUrl = '';

  // --- Yandex SpeechKit ---
  bool yandexSpeechEnabled = false;
  String yandexApiKey = '';
  String yandexFolderId = '';

  /// Голос синтеза: alena, filipp, ermil, jane, omazh, zahar.
  /// Пусто — выбирается по настройке «мужской/женский голос».
  String yandexTtsVoice = '';

  // --- YandexGPT ---
  bool yandexGptEnabled = false;
  String yandexGptModel = 'yandexgpt-lite';

  // --- Синхронизация с сервером навыка Алисы ---
  bool cloudSyncEnabled = false;
  String cloudSyncUrl = '';
  String cloudSyncToken = '';
  String cloudSyncUser = '';

  String _userKey(int i) => i == 0 ? 'userName' : 'userName_$i';

  void _read() {
    final p = _prefs!;
    profileNames = p.getStringList('profileNames') ?? ['Основной'];
    profileIndex =
        (p.getInt('profileIndex') ?? 0).clamp(0, profileNames.length - 1);
    userName = p.getString(_userKey(profileIndex)) ?? '';
    assistantName = p.getString('assistantName') ?? 'Ассистент';
    maleVoice = p.getBool('maleVoice') ?? false;
    themeMode = ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.dark.index];
    notifyAtTime = p.getBool('notifyAtTime') ?? true;
    notifyHourBefore = p.getBool('notifyHourBefore') ?? true;
    speak = p.getBool('speak') ?? true;

    yandexCalendarEnabled = p.getBool('yandexCalendarEnabled') ?? false;
    yandexCalendarLogin = p.getString('yandexCalendarLogin') ?? '';
    yandexCalendarPassword = p.getString('yandexCalendarPassword') ?? '';
    yandexCalendarUrl = p.getString('yandexCalendarUrl') ?? '';
    yandexSpeechEnabled = p.getBool('yandexSpeechEnabled') ?? false;
    yandexApiKey = p.getString('yandexApiKey') ?? '';
    yandexFolderId = p.getString('yandexFolderId') ?? '';
    yandexTtsVoice = p.getString('yandexTtsVoice') ?? '';
    yandexGptEnabled = p.getBool('yandexGptEnabled') ?? false;
    yandexGptModel = p.getString('yandexGptModel') ?? 'yandexgpt-lite';
    cloudSyncEnabled = p.getBool('cloudSyncEnabled') ?? false;
    cloudSyncUrl = p.getString('cloudSyncUrl') ?? '';
    cloudSyncToken = p.getString('cloudSyncToken') ?? '';
    cloudSyncUser = p.getString('cloudSyncUser') ?? '';
  }

  @override
  void change({
    String? userName,
    String? assistantName,
    bool? maleVoice,
    ThemeMode? themeMode,
    bool? notifyAtTime,
    bool? notifyHourBefore,
    bool? speak,
    bool? yandexCalendarEnabled,
    String? yandexCalendarLogin,
    String? yandexCalendarPassword,
    String? yandexCalendarUrl,
    bool? yandexSpeechEnabled,
    String? yandexApiKey,
    String? yandexFolderId,
    String? yandexTtsVoice,
    bool? yandexGptEnabled,
    String? yandexGptModel,
    bool? cloudSyncEnabled,
    String? cloudSyncUrl,
    String? cloudSyncToken,
    String? cloudSyncUser,
  }) {
    this.userName = userName ?? this.userName;
    this.assistantName = assistantName ?? this.assistantName;
    this.maleVoice = maleVoice ?? this.maleVoice;
    this.themeMode = themeMode ?? this.themeMode;
    this.notifyAtTime = notifyAtTime ?? this.notifyAtTime;
    this.notifyHourBefore = notifyHourBefore ?? this.notifyHourBefore;
    this.speak = speak ?? this.speak;
    this.yandexCalendarEnabled =
        yandexCalendarEnabled ?? this.yandexCalendarEnabled;
    this.yandexCalendarLogin = yandexCalendarLogin ?? this.yandexCalendarLogin;
    this.yandexCalendarPassword =
        yandexCalendarPassword ?? this.yandexCalendarPassword;
    this.yandexCalendarUrl = yandexCalendarUrl ?? this.yandexCalendarUrl;
    this.yandexSpeechEnabled = yandexSpeechEnabled ?? this.yandexSpeechEnabled;
    this.yandexApiKey = yandexApiKey ?? this.yandexApiKey;
    this.yandexFolderId = yandexFolderId ?? this.yandexFolderId;
    this.yandexTtsVoice = yandexTtsVoice ?? this.yandexTtsVoice;
    this.yandexGptEnabled = yandexGptEnabled ?? this.yandexGptEnabled;
    this.yandexGptModel = yandexGptModel ?? this.yandexGptModel;
    this.cloudSyncEnabled = cloudSyncEnabled ?? this.cloudSyncEnabled;
    this.cloudSyncUrl = cloudSyncUrl ?? this.cloudSyncUrl;
    this.cloudSyncToken = cloudSyncToken ?? this.cloudSyncToken;
    this.cloudSyncUser = cloudSyncUser ?? this.cloudSyncUser;
    final p = _prefs;
    if (p != null) {
      p.setString(_userKey(profileIndex), this.userName);
      p.setString('assistantName', this.assistantName);
      p.setBool('maleVoice', this.maleVoice);
      p.setInt('themeMode', this.themeMode.index);
      p.setBool('notifyAtTime', this.notifyAtTime);
      p.setBool('notifyHourBefore', this.notifyHourBefore);
      p.setBool('speak', this.speak);
      p.setBool('yandexCalendarEnabled', this.yandexCalendarEnabled);
      p.setString('yandexCalendarLogin', this.yandexCalendarLogin);
      p.setString('yandexCalendarPassword', this.yandexCalendarPassword);
      p.setString('yandexCalendarUrl', this.yandexCalendarUrl);
      p.setBool('yandexSpeechEnabled', this.yandexSpeechEnabled);
      p.setString('yandexApiKey', this.yandexApiKey);
      p.setString('yandexFolderId', this.yandexFolderId);
      p.setString('yandexTtsVoice', this.yandexTtsVoice);
      p.setBool('yandexGptEnabled', this.yandexGptEnabled);
      p.setString('yandexGptModel', this.yandexGptModel);
      p.setBool('cloudSyncEnabled', this.cloudSyncEnabled);
      p.setString('cloudSyncUrl', this.cloudSyncUrl);
      p.setString('cloudSyncToken', this.cloudSyncToken);
      p.setString('cloudSyncUser', this.cloudSyncUser);
    }
    notifyListeners();
  }

  /// Добавляет профиль и возвращает его номер.
  int addProfile(String name) {
    profileNames = [...profileNames, name];
    final i = profileNames.length - 1;
    _prefs?.setStringList('profileNames', profileNames);
    _prefs?.setString(_userKey(i), name);
    return i;
  }

  void setProfile(int i) {
    profileIndex = i;
    userName =
        _prefs?.getString(_userKey(i)) ?? (i == 0 ? '' : profileNames[i]);
    _prefs?.setInt('profileIndex', i);
    notifyListeners();
  }
}
