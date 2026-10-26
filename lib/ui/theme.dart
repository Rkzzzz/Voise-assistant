import 'package:flutter/material.dart';

/// Рукописный шрифт для крупных заголовков из макета.
/// Чтобы включить: положите файл шрифта в assets/fonts/, объявите его в
/// pubspec.yaml (раздел fonts) и впишите имя семейства сюда.
const String? kDisplayFont = null;

/// Палитра из макета команды: тёмно-синий фон, светло-серые акценты.
class Pal {
  const Pal({
    required this.bgTop,
    required this.bgBottom,
    required this.circle,
    required this.onCircle,
    required this.button,
    required this.onButton,
    required this.pill,
    required this.text,
    required this.cardHead,
    required this.onCardHead,
    required this.cardBody,
    required this.line,
    required this.sheet,
    required this.glow,
  });

  final Color bgTop, bgBottom;
  final Color circle, onCircle; // большая кнопка микрофона
  final Color button, onButton; // круглые кнопки навигации
  final Color pill; // «таблетка» с текстом
  final Color text;
  final Color cardHead, onCardHead, cardBody, line; // карточка календаря
  final Color sheet; // нижние панели и диалоги
  final Color glow;

  static const dark = Pal(
    bgTop: Color(0xFF181937),
    bgBottom: Color(0xFF161421),
    circle: Color(0xFFDAD9D4),
    onCircle: Color(0xFF233D57),
    button: Color(0xFF233D57),
    onButton: Color(0xFFDCD9D2),
    pill: Color(0xCC2B374D),
    text: Color(0xFFDCD9D2),
    cardHead: Color(0xFFDCD9D2),
    onCardHead: Color(0xFF181937),
    cardBody: Color(0xFF19172F),
    line: Color(0xFFB4C0CF),
    sheet: Color(0xFF1F2340),
    glow: Color(0xFFFFFFFF),
  );

  static const light = Pal(
    bgTop: Color(0xFFE4E8F3),
    bgBottom: Color(0xFFF5F3EE),
    circle: Color(0xFF233D57),
    onCircle: Color(0xFFDCD9D2),
    button: Color(0xFF233D57),
    onButton: Color(0xFFF5F3EE),
    pill: Color(0x26233D57),
    text: Color(0xFF181937),
    cardHead: Color(0xFF233D57),
    onCardHead: Color(0xFFF5F3EE),
    cardBody: Color(0xFFFFFFFF),
    line: Color(0xFF7D8DA3),
    sheet: Color(0xFFFFFFFF),
    glow: Color(0xFF233D57),
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: p.bgBottom,
    colorScheme: ColorScheme.fromSeed(seedColor: Pal.dark.button, brightness: b)
        .copyWith(
      primary: p.button,
      onPrimary: p.onButton,
      surface: p.sheet,
      onSurface: p.text,
      surfaceContainerHigh: p.sheet,
      surfaceContainerHighest: p.sheet,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.sheet,
      surfaceTintColor: Colors.transparent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.circle : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.onCircle : p.text),
      ),
    ),
  );
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Основной цвет текста.
Color fg(BuildContext c) => Pal.of(c).text;

/// Подложка карточек и «таблеток».
Color pill(BuildContext c) => Pal.of(c).pill;

/// Цвета занятости дня.
const kLoadFree = Color(0xFF9E9E9E);
const kLoadLight = Color(0xFF43A047);
const kLoadMedium = Color(0xFFFB8C00);
const kLoadBusy = Color(0xFFE53935);

/// Фоновый градиент экрана.
class NavyBackground extends StatelessWidget {
  const NavyBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.bgTop, p.bgBottom],
          stops: const [0, 0.55],
        ),
      ),
      child: child,
    );
  }
}
