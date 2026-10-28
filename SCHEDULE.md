# Расписание

## Как добавить расписание сейчас

Настройки → «Расписание» → вставьте текст (например, из письма школы или
распознанный со скриншота любым инструментом) → «Разобрать текст» → проверьте
список занятий → «Добавить в календарь».

Разбор текста работает офлайн, правила — в
`packages/assistant_core/lib/nlu/schedule_parser.dart`.

## Распознавание текста с фото — не реализовано

Плагин `flutter_tesseract_ocr` (Tesseract на устройстве) не собирается: его
`android/build.gradle` использует `jcenter()` и старую версию Android Gradle
Plugin, что несовместимо с Gradle 9 и AGP 9 в этом проекте. Зависимость удалена
из `pubspec.yaml`, а сервис `lib/services/schedule_ocr.dart` удалён, потому что
нигде не вызывался.

Если функцию нужно вернуть, варианты:

1. `google_ml_kit` (Text Recognition v2) — поддерживается Google, работает
   офлайн, русский язык доступен, совместим с новыми версиями Gradle.
2. Локальный форк `flutter_tesseract_ocr` с исправленным `android/build.gradle`:
   убрать блок `buildscript`, `compileSdkVersion` заменить на `compileSdk`,
   aar подключать из локального maven-репозитория, а не через `flatDir` +
   `name:` (в Gradle 8+ такая запись не поддерживается).

Файлы `assets/tessdata/` и `assets/tessdata_config.json` оставлены на случай
возврата Tesseract: им нужен `rus.traineddata` из репозитория
tesseract-ocr/tessdata_fast (~2 МБ).
