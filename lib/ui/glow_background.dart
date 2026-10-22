import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Чёрный фон с медленно плавающими цветными световыми пятнами.
/// Когда [active] (идёт запись), пятна становятся ярче.
class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key, required this.active});

  final bool active;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(Color color, double size, double dx, double dy, double k) =>
      Align(
        alignment: Alignment(dx, dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: 0.85 * k),
              color.withValues(alpha: 0),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: widget.active ? 1.0 : 0.6),
      duration: const Duration(milliseconds: 600),
      builder: (_, k, __) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value * 2 * math.pi;
          return Stack(
            children: [
              _blob(const Color(0xFFFFC400), 560, -0.6 + 0.3 * math.cos(t),
                  -0.55 + 0.2 * math.sin(t), k),
              _blob(const Color(0xFFFF1FD0), 480, 0.7 + 0.2 * math.sin(t),
                  -0.25 + 0.3 * math.cos(t), k),
              _blob(const Color(0xFF9AA800), 420, -0.1 + 0.4 * math.sin(t),
                  0.05 + 0.2 * math.cos(t), k),
              // затемнение к низу, чтобы текст и кнопки читались
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.transparent, Colors.black],
                      stops: [0.4, 0.8],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
