import 'package:flutter/material.dart';

import '../assistant/assistant.dart';
import '../nlu/schedule_parser.dart';
import 'theme.dart';

/// Расписание по фото: снимок → текст → проверка → записи в календарь.
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.assistant});

  final Assistant assistant;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _text = TextEditingController();
  List<ScheduleItem> _items = [];
  final Set<int> _off = {};
  int _weeks = 4;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    setState(() {
      _items = parseSchedule(_text.text);
      _off.clear();
      if (_items.isEmpty && _text.text.trim().isNotEmpty) {
        _error = 'Не нашёл занятий. Поправьте текст: день недели на '
            'отдельной строке, ниже «8:30-9:15 Математика».';
      } else {
        _error = null;
      }
    });
  }

  Future<void> _add() async {
    final chosen = [
      for (var i = 0; i < _items.length; i++)
        if (!_off.contains(i)) _items[i],
    ];
    if (chosen.isEmpty) return;
    setState(() => _busy = true);
    final n = await widget.assistant.addSchedule(chosen, weeks: _weeks);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Добавлено записей: $n')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Расписание')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Вставьте или введите текст расписания. Распознавание '
              'по фото появится позже.'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(color: Color(0xFFE53935))),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Текст расписания',
              helperText: 'День недели — отдельной строкой, ниже занятия: '
                  '«8:30-9:15 Математика». Кружок: «Шахматы вт 16:00-17:00».',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _parse,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Разобрать текст'),
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Найдено занятий: ${_items.length}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            for (var i = 0; i < _items.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: !_off.contains(i),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _off.remove(i);
                  } else {
                    _off.add(i);
                  }
                }),
                title: Text(_items[i].title),
                subtitle:
                    Text('${_items[i].dayShort}, ${_items[i].timeText}'),
              ),
            Row(children: [
              const Text('Повторять на недель:  '),
              DropdownButton<int>(
                value: _weeks,
                items: [
                  for (final w in const [1, 2, 4, 8, 12, 16])
                    DropdownMenuItem(value: w, child: Text('$w')),
                ],
                onChanged: (v) => setState(() => _weeks = v ?? 4),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: pal.circle, foregroundColor: pal.onCircle),
              onPressed: _busy ? null : _add,
              child: const Text('Добавить в календарь'),
            ),
          ],
        ],
      ),
    );
  }
}
