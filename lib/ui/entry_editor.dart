import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../models/entry.dart';
import 'format.dart';
import 'theme.dart';

/// Ручное создание / редактирование записи (с комментарием).
Future<void> showEntryEditor(BuildContext context, Assistant assistant,
    {Entry? entry, DateTime? day}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _EditorSheet(assistant: assistant, entry: entry, day: day),
  );
}

Future<bool> confirmDialog(BuildContext context, String text,
    {String ok = 'Удалить'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

class _EditorSheet extends StatefulWidget {
  const _EditorSheet({required this.assistant, this.entry, this.day});

  final Assistant assistant;
  final Entry? entry;
  final DateTime? day;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _comment;
  late EntryType _type;
  DateTime? _date;
  TimeOfDay? _time; // null — без времени
  late int _duration;

  Assistant get _a => widget.assistant;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?.title ?? '');
    _comment = TextEditingController(text: e?.comment ?? '');
    _type = e?.type ?? EntryType.task;
    _duration = e?.duration ?? 60;
    if (e != null) {
      final d = e.dueAt;
      _date = d == null ? null : DateTime(d.year, d.month, d.day);
      _time = (e.hasTime && d != null)
          ? TimeOfDay(hour: d.hour, minute: d.minute)
          : null;
    } else {
      final n = _a.now;
      _date = widget.day ?? DateTime(n.year, n.month, n.day);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final base = _date ?? _a.now;
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context,
        initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0));
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введите название')));
      return;
    }
    DateTime? due;
    if (_date != null) {
      due = DateTime(_date!.year, _date!.month, _date!.day, _time?.hour ?? 0,
          _time?.minute ?? 0);
    }
    var e = Entry(
      id: widget.entry?.id,
      type: _type,
      title: title,
      dueAt: due,
      hasTime: due != null && _time != null,
      createdAt: widget.entry?.createdAt ?? _a.now,
      done: widget.entry?.done ?? false,
      comment: _comment.text.trim(),
      durationMin: _duration < 60 ? 60 : _duration,
    );

    final c = await _a.conflictFor(e);
    if (c != null) {
      final alt = await _a.nextFree(e);
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Накладка по времени'),
          content: Text('В это время уже есть «${c.title}» '
              '(${hm(c.dueAt!)}–${hm(c.endAt!)}).\n'
              'Ближайшее свободное время — ${hm(alt)}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'alt'),
                child: Text('На ${hm(alt)}')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'keep'),
                child: const Text('Всё равно')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'alt') e = e.copyWith(dueAt: alt);
    }
    await _a.save(e);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final e = widget.entry!;
    if (!await confirmDialog(context, 'Удалить «${e.title}»?')) return;
    await _a.deleteEntry(e);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isMeeting = _type == EntryType.meeting;
    final durations = {60, 90, 120, 180, 240, _duration}.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.entry == null ? 'Новая запись' : 'Редактирование',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Название', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SegmentedButton<EntryType>(
              showSelectedIcon: false,
              segments: [
                for (final t in EntryType.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text(_date == null
                        ? 'Без даты'
                        : '${_date!.day} ${monthsGen[_date!.month - 1]} ${_date!.year}'),
                  ),
                ),
                if (_date != null && _type == EntryType.task)
                  IconButton(
                    tooltip: 'Убрать дату',
                    onPressed: () => setState(() {
                      _date = null;
                      _time = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (_date != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Без времени'),
                value: _time == null,
                onChanged: (v) => setState(() => _time =
                    v ? null : const TimeOfDay(hour: 10, minute: 0)),
              ),
              if (_time != null)
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(_time!.format(context)),
                ),
            ],
            if (isMeeting && _time != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Длительность:  '),
                  DropdownButton<int>(
                    value: _duration < 60 ? 60 : _duration,
                    items: [
                      for (final d in durations)
                        DropdownMenuItem(
                          value: d,
                          child: Text(d % 60 == 0
                              ? '${d ~/ 60} ч'
                              : '${d ~/ 60} ч ${d % 60} мин'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _duration = v ?? 60),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _comment,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Комментарий', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.entry != null)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFE53935)),
                    label: const Text('Удалить',
                        style: TextStyle(color: Color(0xFFE53935))),
                  ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Pal.of(context).circle,
                      foregroundColor: Pal.of(context).onCircle),
                  onPressed: _save,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
