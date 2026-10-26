import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../models/entry.dart';
import '../models/mark.dart';
import '../services/day_load.dart';
import '../services/holidays.dart';
import 'entry_editor.dart';
import 'format.dart';
import 'theme.dart';

/// Панель выбранного дня: праздник, особые даты, записи, кнопки добавления.
Future<void> showDaySheet(
    BuildContext context, Assistant assistant, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: _DaySheet(assistant: assistant, day: day),
    ),
  );
}

class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.assistant, required this.day});

  final Assistant assistant;
  final DateTime day;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  List<Entry> _entries = [];
  List<Mark> _marks = [];

  Assistant get _a => widget.assistant;
  DateTime get _day => widget.day;

  @override
  void initState() {
    super.initState();
    _a.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _a.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final es = await _a.entriesBetween(
        _day, DateTime(_day.year, _day.month, _day.day + 1));
    final ms = (await _a.allMarks()).where((m) => m.fallsOn(_day)).toList();
    es.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    if (mounted) {
      setState(() {
        _entries = es;
        _marks = ms;
      });
    }
  }

  IconData _icon(EntryType t) => switch (t) {
        EntryType.task => Icons.check_circle_outline,
        EntryType.meeting => Icons.groups_outlined,
        EntryType.reminder => Icons.notifications_none,
      };

  Widget _entryCard(Pal p, Entry e) {
    final status = statusOf(e, _a.now);
    final time = e.dueAt == null
        ? 'без срока'
        : (e.hasTime
            ? (e.blocksTime
                ? '${hm(e.dueAt!)}–${hm(e.endAt!)}'
                : hm(e.dueAt!))
            : 'без времени');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: p.text.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ListTile(
        onTap: () => showEntryEditor(context, _a, entry: e),
        leading: Checkbox(
          value: e.done,
          activeColor: p.circle,
          checkColor: p.onCircle,
          onChanged: (_) => _a.toggleDone(e),
        ),
        title: Row(children: [
          Icon(_icon(e.type), size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(e.title,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: e.done ? TextDecoration.lineThrough : null)),
          ),
        ]),
        subtitle: Text([
          time,
          if (status.isNotEmpty) status,
          if (e.comment.isNotEmpty) '💬 ${e.comment}',
        ].join(' • ')),
        trailing: IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirmDialog(context, 'Удалить «${e.title}»?')) {
              await _a.deleteEntry(e);
            }
          },
        ),
      ),
    );
  }

  Future<void> _addMark() async {
    final ctrl = TextEditingController(text: 'День рождения ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Особая дата: ${_day.day} ${monthsGen[_day.month - 1]}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'День рождения Ивана',
              helperText: 'Повторяется каждый год'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && title.isNotEmpty) {
      await _a.addMark(Mark(
          title: title,
          month: _day.month,
          day: _day.day,
          kind: Mark.kindOf(title)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final h = holidayName(_day);
    final load = dayLoad(_entries);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${weekdayNames[_day.weekday - 1]}, ${_day.day} ${monthsGen[_day.month - 1]}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Занятость: ${load.label}',
              style: TextStyle(color: p.text.withValues(alpha: 0.7))),
          if (h != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Chip(label: Text('🎉 $h')),
            ),
          for (final m in _marks)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InputChip(
                label: Text('${m.emoji} ${m.title}'),
                onDeleted: () async {
                  if (await confirmDialog(context, 'Убрать «${m.title}»?',
                      ok: 'Убрать')) {
                    await _a.removeMark(m);
                  }
                },
              ),
            ),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('В этот день записей нет',
                  style: TextStyle(color: p.text.withValues(alpha: 0.6))),
            ),
          for (final e in _entries) _entryCard(p, e),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: p.circle, foregroundColor: p.onCircle),
                onPressed: () => showEntryEditor(context, _a, day: _day),
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addMark,
                icon: const Icon(Icons.cake_outlined),
                label: const Text('Особая дата'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
