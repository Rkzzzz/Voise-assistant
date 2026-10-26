import '../models/entry.dart';

const weekdayNames = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота',
  'Воскресенье',
];
const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const monthNames = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август',
  'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];
const monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
  'сентября', 'октября', 'ноября', 'декабря',
];

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

/// «через 1 ч 20 мин» / «идёт сейчас».
String untilText(Entry e, DateTime now) {
  if (now.isAfter(e.dueAt!)) return 'идёт сейчас';
  final m = e.dueAt!.difference(now).inMinutes;
  if (m < 1) return 'меньше минуты';
  if (m < 60) return 'через $m мин';
  final h = m ~/ 60;
  if (h < 24) return m % 60 == 0 ? 'через $h ч' : 'через $h ч ${m % 60} мин';
  return 'через ${h ~/ 24} дн';
}

/// Статус записи для отслеживания.
String statusOf(Entry e, DateTime now) {
  if (e.done) return 'выполнено';
  final d = e.dueAt;
  if (d == null) return '';
  if (e.hasTime) {
    if (now.isBefore(d)) return untilText(e, now);
    if (now.isBefore(e.endAt!)) return 'идёт сейчас';
    return 'прошло';
  }
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'сегодня';
  return day.isBefore(today) ? 'просрочено' : '';
}
