import 'package:flutter_test/flutter_test.dart';
import 'package:voice_assistant/models/entry.dart';
import 'package:voice_assistant/services/ics.dart';

void main() {
  test('ics: встреча с местом и час длительности', () {
    final now = DateTime(2026, 10, 21, 10);
    final e = Entry(
      id: 1,
      type: EntryType.meeting,
      title: 'Встреча, с Иваном',
      dueAt: DateTime(2026, 10, 22, 15),
      hasTime: true,
      createdAt: now,
      place: 'Москва, Тверская 1',
    );
    final s = buildIcs([e], now: now);
    expect(s, contains('DTSTART:20261022T150000'));
    expect(s, contains('DTEND:20261022T160000'));
    expect(s, contains('SUMMARY:Встреча\\, с Иваном'));
    expect(s, contains('LOCATION:Москва\\, Тверская 1'));
    expect(s, contains('\r\n'));
  });
}
