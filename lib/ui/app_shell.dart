import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../voice/voice_service.dart';
import 'calendar_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'theme.dart';

/// Три экрана: календарь (слева), ассистент (центр), настройки (справа).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.assistant, required this.voice});

  final Assistant assistant;
  final VoiceService voice;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _i = 0; // 0 — ассистент, 1 — календарь, 2 — настройки

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      body: NavyBackground(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _i,
                children: [
                  ChatPage(assistant: widget.assistant, voice: widget.voice),
                  CalendarPage(assistant: widget.assistant),
                  SettingsPage(
                      assistant: widget.assistant, voice: widget.voice),
                ],
              ),
            ),
            if (!keyboard)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavCircle(
                        size: 62,
                        selected: _i == 1,
                        tooltip: 'Календарь',
                        onTap: () => setState(() => _i = 1),
                        child: Icon(Icons.calendar_month,
                            size: 32, color: Pal.of(context).onButton),
                      ),
                      _NavCircle(
                        size: 68,
                        ring: true,
                        selected: _i == 0,
                        tooltip: 'Ассистент',
                        onTap: () => setState(() => _i = 0),
                      ),
                      _NavCircle(
                        size: 62,
                        selected: _i == 2,
                        tooltip: 'Настройки',
                        onTap: () => setState(() => _i = 2),
                        child: Icon(Icons.settings,
                            size: 32, color: Pal.of(context).onButton),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Круглая кнопка навигации со свечением (у выбранной свечение сильнее).
class _NavCircle extends StatelessWidget {
  const _NavCircle({
    required this.size,
    required this.selected,
    required this.onTap,
    required this.tooltip,
    this.child,
    this.ring = false,
  });

  final double size;
  final bool selected;
  final bool ring;
  final VoidCallback onTap;
  final String tooltip;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: p.button,
            shape: BoxShape.circle,
            border: ring ? Border.all(color: p.text, width: 3.5) : null,
            boxShadow: [
              BoxShadow(
                color: p.glow.withValues(alpha: selected ? 0.55 : 0.22),
                blurRadius: selected ? 26 : 14,
                spreadRadius: selected ? 3 : 1,
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
