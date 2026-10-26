# Инструкция по установке и запуску (Windows)

Проект: голосовой ассистент на Flutter (Android). Ниже всё, что нужно поставить, чтобы приложение собиралось и запускалось так же, как у автора.

## 1. Что установить

| ПО | Зачем | Где взять |
|---|---|---|
| **Git** | скачать проект | git-scm.com |
| **Flutter SDK** (stable; у автора 3.47.7, Dart 3.13.5) | сборка приложения | docs.flutter.dev/get-started/install/windows |
| **Android Studio** | Android SDK, эмулятор, JDK | developer.android.com/studio |
| **VS Code** + расширения **Flutter** и **Dart** | редактор | code.visualstudio.com |
| **Android-телефон** (Android 7.0+) | запуск и проверка голоса | — |

Visual Studio, Chrome и Xcode **не нужны**: `flutter doctor` может ругаться на них, это нормально.

## 2. Установка Flutter

1. Скачайте Flutter SDK и распакуйте в папку **без пробелов и кириллицы**, например `C:\flutter` (не в `Program Files`).
2. Добавьте `C:\flutter\bin` в переменную среды **Path** (Win → «Изменение системных переменных среды» → Переменные среды → Path → Создать).
3. Перезапустите VS Code и проверьте в терминале: `flutter --version`.

## 3. Установка Android Studio и Android SDK

1. Установите Android Studio, при первом запуске выберите **Standard** — скачается Android SDK.
2. Откройте **More Actions → SDK Manager → вкладка SDK Tools** и отметьте:
   - Android SDK Command-line Tools (latest)
   - Android SDK Platform-Tools
   - Android SDK Build-Tools
   
   Нажмите Apply.
3. Если SDK стоит не в стандартной папке, укажите путь:
   ```
   flutter config --android-sdk D:\Android\Sdk
   ```
4. Примите лицензии (на каждый вопрос вводите `y`):
   ```
   flutter doctor --android-licenses
   ```
5. Проверьте: `flutter doctor -v`. Пункты **Flutter** и **Android toolchain** должны быть зелёными.

## 4. Подготовка телефона

1. Настройки → О телефоне → 7 раз нажмите «Номер сборки» (или «Версия MIUI/HyperOS»).
2. Настройки → Для разработчиков → включите **«Отладку по USB»**. На Xiaomi/Redmi/POCO включите ещё **«Установку через USB»**.
3. Подключите кабелем (короткий кабель для данных, порт прямо на компьютере). В шторке выберите режим USB **«Передача файлов»**, на телефоне нажмите «Разрешить отладку».
4. Если Windows не видит телефон, поставьте драйвер производителя (для Xiaomi — Mi USB Driver).
5. Проверьте: `flutter devices` — телефон должен быть в списке.

В настройках телефона для распознавания речи должен быть установлен **русский язык голосового ввода** (приложение Google).

## 5. Скачивание и настройка проекта

1. Клонируйте репозиторий в папку **без пробелов в пути** (например, `D:\repos\voice_assistant`):
   ```
   git clone <ссылка на репозиторий>
   cd voice_assistant
   ```
2. Если в проекте **нет папки `android`**, создайте её:
   ```
   flutter create . --platforms=android --project-name voice_assistant
   ```
   После этого удалите файл `test/widget_test.dart`.
3. В `android/app/src/main/AndroidManifest.xml` внутри `<manifest>` должны быть:
   ```xml
   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
   <uses-permission android:name="android.permission.VIBRATE"/>
   <queries>
     <intent><action android:name="android.speech.RecognitionService"/></intent>
     <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>
   </queries>
   ```
   и внутри `<application>`:
   ```xml
   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
     <intent-filter>
       <action android:name="android.intent.action.BOOT_COMPLETED"/>
       <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
     </intent-filter>
   </receiver>
   ```
4. В `android/app/build.gradle` (или `build.gradle.kts`):
   - `minSdk = 24`
   - включите desugaring (нужно для уведомлений):
   ```kotlin
   android {
       compileOptions { isCoreLibraryDesugaringEnabled = true }
   }
   dependencies {
       coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
   }
   ```
5. В `android/gradle.properties` добавьте строку:
   ```
   kotlin.incremental=false
   ```

## 6. Запуск

```
flutter pub get
flutter devices
flutter run -d <id телефона>
```

Первая сборка занимает 5–15 минут (скачивается Gradle и зависимости) — не прерывайте её. Красные предупреждения `WARNING: A restricted method in java.lang.System...` безвредны.

На телефоне разрешите микрофон и уведомления. Проверка: нажмите на жёлтый микрофон и скажите «Напомни завтра в 10 утра позвонить Ивану».

Сборка APK для передачи на другие телефоны:
```
flutter build apk
```
Файл: `build\app\outputs\flutter-apk\app-release.apk`.

## 7. Частые проблемы

| Симптом | Решение |
|---|---|
| `adb не распознано как имя командлета` | `adb` лежит в `<папка SDK>\platform-tools`; запускайте по полному пути или добавьте папку в Path. Для `flutter run` это не обязательно. |
| `Unable to locate Android SDK` | Установите Android Studio и SDK (п. 3), при необходимости `flutter config --android-sdk <путь>`. |
| `Could not close incremental caches` (Kotlin) | Проект и кэш пакетов на разных дисках или пробел в пути. Добавьте `kotlin.incremental=false`, храните проект без пробелов, а кэш пакетов — на том же диске: `setx PUB_CACHE "D:\pub_cache"` и перезапустите VS Code. |
| `INSTALL_PARSE_FAILED_NO_CERTIFICATES … SHA-256 digest did not verify` | APK повредился при передаче по USB: смените кабель и порт, выполните `adb kill-server`, `adb start-server`, либо скопируйте `app-debug.apk` на телефон и установите вручную. |
| `INSTALL_FAILED_USER_RESTRICTED` (Xiaomi) | Включите «Установку через USB» в «Для разработчиков». |
| Телефон не виден в `flutter devices` | Режим USB «Передача файлов», «Отладка по USB», подтвердите запрос на телефоне, драйвер, другой кабель. |
| Ошибка в `test/widget_test.dart` (`myApp isn't a class`) | Удалите этот файл — он создаётся автоматически и не относится к проекту. |
| Приложение открылось в браузере | Запускайте на телефоне: `flutter run -d <id телефона>`. Веб-версия не поддерживается. |
| Уведомления не приходят | Разрешите уведомления для приложения, отключите экономию батареи для него, проверьте кнопкой «Проверить уведомление» в настройках. |

## 8. Тесты

```
flutter analyze
flutter test
```
