import 'package:flutter/material.dart';

/// Фирменный жёлтый акцент.
const kAccent = Color(0xFFFFF000);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: kAccent,
        onPrimary: Colors.black,
        surface: Colors.black,
      ),
    );
