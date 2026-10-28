import '../models/entry.dart';

/// Занятость дня: серый — свободно, зелёный — чуть занят,
/// оранжевый — средняя занятость, красный — времени нет.
enum DayLoad { free, light, medium, busy }

/// Пороги в минутах. Меняются в одном месте.
const kLightUpToMin = 180; // до 3 ч — зелёный
const kMediumUpToMin = 480; // до 8 ч — оранжевый, дальше красный

extension DayLoadX on DayLoad {
  String get label => switch (this) {
        DayLoad.free => 'свободный день',
        DayLoad.light => 'чуть занят',
        DayLoad.medium => 'средняя занятость',
        DayLoad.busy => 'времени почти нет',
      };
}

/// Занятость по записям одного дня.
DayLoad dayLoad(Iterable<Entry> dayEntries) {
  var minutes = 0;
  var count = 0;
  for (final e in dayEntries) {
    count++;
    if (e.blocksTime) {
      minutes += e.duration;
    } else if (e.hasTime) {
      minutes += 15; // задача или напоминание на конкретное время
    } else {
      minutes += 30; // без времени
    }
  }
  if (count == 0) return DayLoad.free;
  if (minutes < kLightUpToMin) return DayLoad.light;
  if (minutes < kMediumUpToMin) return DayLoad.medium;
  return DayLoad.busy;
}
