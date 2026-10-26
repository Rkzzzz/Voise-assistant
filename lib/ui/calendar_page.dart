import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../models/entry.dart';
import '../models/mark.dart';
import '../services/day_load.dart';
import '../services/holidays.dart';
import 'day_sheet.dart';
import 'format.dart';
import 'theme.dart';

const _monthAbbr = [
  'ЯНВ', 'ФЕВ', 'МАР', 'АПР', 'МАЙ', 'ИЮН', 'ИЮЛ', 'АВГ', 'СЕН', 'ОКТ',
  'НОЯ', 'ДЕК',
];

/// Календарь в стиле макета: год и месяц сверху, сетка на светлой карточке.
/// Цвет клетки показывает занятость дня; нажатие открывает день.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.assistant});

  final Assistant assistant;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  List<Entry> _entries = [];
  List<Mark> _marks = [];

  Assistant get _a => widget.assistant;

  @override
  void initState() {
    super.initState();
    final n = _a.now;
    _month = DateTime(n.year, n.month);
    _a.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _a.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final from = DateTime(_month.year, _month.month, 1);
    final to = DateTime(_month.year, _month.month + 1, 1);
    final es = await _a.entriesBetween(from, to);
    final ms = await _a.allMarks();
    if (mounted) {
      setState(() {
        _entries = es;
        _marks = ms;
      });
    }
  }

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Entry> _on(DateTime d) =>
      _entries.where((e) => e.dueAt != null && _same(e.dueAt!, d)).toList();

  Color? _tint(DayLoad l) => switch (l) {
        DayLoad.free => kLoadFree.withValues(alpha: 0.28),
        DayLoad.light => kLoadLight.withValues(alpha: 0.75),
        DayLoad.medium => kLoadMedium.withValues(alpha: 0.8),
        DayLoad.busy => kLoadBusy.withValues(alpha: 0.85),
      };

  Widget _cell(Pal p, int dayNum, int days, bool lastCol, bool lastRow) {
    final border = Border(
      right: lastCol ? BorderSide.none : BorderSide(color: p.line.withValues(alpha: 0.7), width: 1.5),
      bottom: lastRow ? BorderSide.none : BorderSide(color: p.line.withValues(alpha: 0.7), width: 1.5),
    );
    if (dayNum < 1 || dayNum > days) {
      return DecoratedBox(decoration: BoxDecoration(border: border));
    }
    final d = DateTime(_month.year, _month.month, dayNum);
    final load = dayLoad(_on(d));
    final holiday = holidayName(d) != null;
    final marks = _marks.where((m) => m.fallsOn(d)).toList();
    final today = _same(d, _a.now);
    final onTint = load == DayLoad.free ? p.text : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDaySheet(context, _a, d),
      child: DecoratedBox(
        decoration: BoxDecoration(border: border),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _tint(load),
            borderRadius: BorderRadius.circular(8),
            border: today ? Border.all(color: p.text, width: 2) : null,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 3,
                left: 5,
                child: Text('$dayNum',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: (holiday && load == DayLoad.free)
                            ? const Color(0xFFFF6B66)
                            : onTint)),
              ),
              if (holiday || marks.isNotEmpty)
                Positioned(
                  bottom: 1,
                  right: 3,
                  child: Text(
                      '${holiday ? '🎉' : ''}${marks.isNotEmpty ? marks.first.emoji : ''}',
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Pal p) {
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final weeks = (offset + days + 6) ~/ 7;
    return Container(
      decoration: BoxDecoration(
        color: p.cardBody,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: p.line, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Column(
          children: [
            Container(
              height: 52,
              color: p.cardHead,
              child: Row(
                children: [
                  for (final w in weekdayShort)
                    Expanded(
                      child: Center(
                        child: Text(w.toUpperCase(),
                            style: TextStyle(
                                fontFamily: kDisplayFont,
                                color: p.onCardHead,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  for (var w = 0; w < weeks; w++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 7; c++)
                            Expanded(
                              child: _cell(p, w * 7 + c - offset + 1, days,
                                  c == 6, w == weeks - 1),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Pal p) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 4),
          Text(t, style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: 0.8))),
        ]);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        item(kLoadFree.withValues(alpha: 0.5), 'свободно'),
        item(kLoadLight, 'чуть занят'),
        item(kLoadMedium, 'средне'),
        item(kLoadBusy, 'времени нет'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final big = TextStyle(
        fontFamily: kDisplayFont,
        color: p.text,
        fontSize: 46,
        fontWeight: FontWeight.w300,
        height: 1.1);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -250) _shift(1);
            if (v > 250) _shift(-1);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_month.year}', style: big),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _shift(-1),
                          icon: Icon(Icons.chevron_left, color: p.text),
                        ),
                        Text(_monthAbbr[_month.month - 1], style: big),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _shift(1),
                          icon: Icon(Icons.chevron_right, color: p.text),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(child: _card(p)),
                const SizedBox(height: 10),
                _legend(p),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
