import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки пользователя (хранятся в SharedPreferences).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  /// Без хранения — для тестов.
  factory AppSettings.memory() => AppSettings._(null);

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  final SharedPreferences? _prefs;

  String userName = '';
  String assistantName = 'Ассистент';
  bool maleVoice = false;
  ThemeMode themeMode = ThemeMode.dark;
  bool notifyAtTime = true;
  bool notifyHourBefore = true;
  bool speak = true;

  /// Локальные профили: у каждого свои записи и своё обращение.
  List<String> profileNames = ['Основной'];
  int profileIndex = 0;

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
  }

  void change({
    String? userName,
    String? assistantName,
    bool? maleVoice,
    ThemeMode? themeMode,
    bool? notifyAtTime,
    bool? notifyHourBefore,
    bool? speak,
  }) {
    this.userName = userName ?? this.userName;
    this.assistantName = assistantName ?? this.assistantName;
    this.maleVoice = maleVoice ?? this.maleVoice;
    this.themeMode = themeMode ?? this.themeMode;
    this.notifyAtTime = notifyAtTime ?? this.notifyAtTime;
    this.notifyHourBefore = notifyHourBefore ?? this.notifyHourBefore;
    this.speak = speak ?? this.speak;
    final p = _prefs;
    if (p != null) {
      p.setString(_userKey(profileIndex), this.userName);
      p.setString('assistantName', this.assistantName);
      p.setBool('maleVoice', this.maleVoice);
      p.setInt('themeMode', this.themeMode.index);
      p.setBool('notifyAtTime', this.notifyAtTime);
      p.setBool('notifyHourBefore', this.notifyHourBefore);
      p.setBool('speak', this.speak);
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
    userName = _prefs?.getString(_userKey(i)) ??
        (i == 0 ? '' : profileNames[i]);
    _prefs?.setInt('profileIndex', i);
    notifyListeners();
  }
}
