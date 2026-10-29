import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:xml/xml.dart';

import '../../models/entry.dart';

/// Подключение к Яндекс.Календарю по CalDAV.
///
/// Нужен логин Яндекс 360 и **пароль приложения** (не основной пароль):
/// id.yandex.ru → Безопасность → Пароли приложений → «Календарь».
class CalDavConfig {
  const CalDavConfig({
    this.login = '',
    this.password = '',
    this.baseUrl = 'https://caldav.yandex.ru',
    this.calendarUrl = '',
    this.timeout = const Duration(seconds: 30),
  });

  final String login;
  final String password;
  final String baseUrl;

  /// Пусто — адрес календаря определяется автоматически.
  final String calendarUrl;
  final Duration timeout;

  bool get isConfigured =>
      login.trim().isNotEmpty && password.trim().isNotEmpty;
}

class CalDavException implements Exception {
  CalDavException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get unauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'CalDAV $statusCode: $message';
}

/// Событие из календаря.
class CalDavEvent {
  const CalDavEvent({
    required this.uid,
    required this.summary,
    this.description = '',
    this.location = '',
    required this.start,
    this.end,
    this.allDay = false,
    this.done = false,
    this.cancelled = false,
    this.etag = '',
    this.lastModified,
  });

  final String uid;
  final String summary;
  final String description;
  final String location;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final bool done;
  final bool cancelled;
  final String etag;
  final DateTime? lastModified;

  int get durationMinutes {
    final e = end;
    if (e == null) return kMeetingMinutes;
    final m = e.difference(start).inMinutes;
    return m.clamp(kMinMinutes, kMaxMinutes);
  }

  Entry toEntry({required DateTime now}) => Entry(
        type: EntryType.meeting,
        title: summary.trim().isEmpty ? 'Событие из календаря' : summary.trim(),
        dueAt: allDay ? DateTime(start.year, start.month, start.day) : start,
        hasTime: !allDay,
        createdAt: now,
        done: done,
        comment: description.trim(),
        durationMin: allDay ? kMeetingMinutes : durationMinutes,
        place: location.trim(),
        externalId: uid,
        updatedAt: now,
      );
}

class CalDavClient {
  CalDavClient(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final CalDavConfig config;
  final http.Client _client;

  String? _calendarHref;

  String get _root {
    final b = config.baseUrl.trim();
    return b.endsWith('/') ? b : '$b/';
  }

  Map<String, String> get _auth => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${config.login.trim()}:${config.password}'))}',
        'User-Agent': 'voice-assistant/1.0',
      };

  /// Адрес календаря: заданный вручную или найденный через PROPFIND.
  Future<String> calendarUrl() async {
    if (_calendarHref != null) return _calendarHref!;
    final manual = config.calendarUrl.trim();
    if (manual.isNotEmpty) {
      _calendarHref = _absolute(manual);
      return _calendarHref!;
    }

    var xml = await _propfind(
      _root,
      0,
      '<d:prop><d:current-user-principal/></d:prop>',
    );
    final principal = _firstHref(xml, 'current-user-principal') ?? _root;

    xml = await _propfind(
      principal,
      0,
      '<d:prop><c:calendar-home-set/></d:prop>',
    );
    final home = _firstHref(xml, 'calendar-home-set') ?? principal;

    xml = await _propfind(
      home,
      1,
      '<d:prop><d:resourcetype/><d:displayname/>'
      '<c:supported-calendar-component-set/></d:prop>',
    );

    final doc = XmlDocument.parse(xml);
    String? firstCalendar;
    for (final response in _elements(doc.rootElement, 'response')) {
      final href = _elements(response, 'href').firstOrNull?.innerText.trim();
      if (href == null || href.isEmpty) continue;
      final isCalendar = _elements(response, 'calendar').isNotEmpty;
      if (!isCalendar) continue;
      firstCalendar ??= href;
      // у Яндекс.Календаря основной календарь обычно называется «events»
      if (href.contains('events') || href.toLowerCase().contains('calendar')) {
        _calendarHref = _absolute(href);
        return _calendarHref!;
      }
    }
    if (firstCalendar != null) {
      _calendarHref = _absolute(firstCalendar);
      return _calendarHref!;
    }
    throw CalDavException(404, 'В аккаунте не найден календарь');
  }

  /// События за промежуток [from, to).
  Future<List<CalDavEvent>> events({
    required DateTime from,
    required DateTime to,
  }) async {
    final url = await calendarUrl();
    final body = '''
<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="${_utcStamp(from)}" end="${_utcStamp(to)}"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>''';
    final xml = await _request('REPORT', url, body: body, depth: '1');
    final doc = XmlDocument.parse(xml);
    final result = <CalDavEvent>[];
    for (final response in _elements(doc.rootElement, 'response')) {
      final etag =
          _elements(response, 'getetag').firstOrNull?.innerText.trim() ?? '';
      final data =
          _elements(response, 'calendar-data').firstOrNull?.innerText ?? '';
      for (final e in parseIcsEvents(data)) {
        result.add(CalDavEvent(
          uid: e.uid,
          summary: e.summary,
          description: e.description,
          location: e.location,
          start: e.start,
          end: e.end,
          allDay: e.allDay,
          done: e.done,
          cancelled: e.cancelled,
          etag: etag,
          lastModified: e.lastModified,
        ));
      }
    }
    return result;
  }

  /// Создаёт или перезаписывает событие с указанным UID.
  Future<void> putEvent(String uid, String ics) async {
    final url = await eventUrl(uid);
    await _request(
      'PUT',
      url,
      body: ics,
      headers: {'Content-Type': 'text/calendar; charset=utf-8'},
      okStatuses: const {200, 201, 204},
    );
  }

  Future<void> deleteEvent(String uid) async {
    final url = await eventUrl(uid);
    await _request(
      'DELETE',
      url,
      okStatuses: const {200, 204, 404},
    );
  }

  Future<String> eventUrl(String uid) async {
    final cal = await calendarUrl();
    final base = cal.endsWith('/') ? cal : '$cal/';
    return '$base${Uri.encodeComponent(uid)}.ics';
  }

  Future<String> _propfind(String url, int depth, String props) => _request(
        'PROPFIND',
        url,
        depth: '$depth',
        body: '<?xml version="1.0" encoding="utf-8"?>'
            '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '$props</d:propfind>',
      );

  /// Освободить соединения. Клиент создаётся на одну синхронизацию.
  void close() => _client.close();

  Future<String> _request(
    String method,
    String url, {
    String? body,
    String? depth,
    Map<String, String> headers = const {},
    Set<int> okStatuses = const {200, 201, 204, 207},
  }) async {
    final req = http.Request(method, Uri.parse(url))
      ..headers.addAll(_auth)
      ..headers.addAll(headers);
    if (depth != null) req.headers['Depth'] = depth;
    if (body != null) {
      req.headers
          .putIfAbsent('Content-Type', () => 'application/xml; charset=utf-8');
      req.body = body;
    }
    final res = await _client.send(req).timeout(config.timeout);
    // Чтение тела тоже должно быть ограничено: иначе зависший сервер
    // держит запрос открытым бесконечно.
    final text = await utf8.decodeStream(res.stream).timeout(config.timeout);
    if (!okStatuses.contains(res.statusCode)) {
      throw CalDavException(res.statusCode, _short(text));
    }
    return text;
  }

  String _absolute(String href) {
    final h = href.trim();
    if (h.startsWith('http://') || h.startsWith('https://')) return h;
    return Uri.parse(_root).resolve(h).toString();
  }

  static String _short(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 200 ? '${one.substring(0, 200)}…' : one;
  }

  static Iterable<XmlElement> _elements(XmlElement root, String local) =>
      root.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == local);

  static String? _firstHref(String xml, String parentLocal) {
    final doc = XmlDocument.parse(xml);
    for (final parent in _elements(doc.rootElement, parentLocal)) {
      final href = _elements(parent, 'href').firstOrNull?.innerText.trim();
      if (href != null && href.isNotEmpty) return href;
    }
    return null;
  }
}

/// Разобранное VEVENT-событие из iCalendar.
class IcsEvent {
  const IcsEvent({
    required this.uid,
    required this.summary,
    required this.start,
    this.end,
    this.description = '',
    this.location = '',
    this.allDay = false,
    this.done = false,
    this.cancelled = false,
    this.lastModified,
  });

  final String uid;
  final String summary;
  final DateTime start;
  final DateTime? end;
  final String description;
  final String location;
  final bool allDay;
  final bool done;
  final bool cancelled;
  final DateTime? lastModified;
}

/// Разбирает все VEVENT из ICS-текста. Понимает переносы строк, UTC,
/// смещение от UTC, явную таймзону (TZID) и события на весь день.
List<IcsEvent> parseIcsEvents(String ics) {
  final unfolded = ics.replaceAll(_reFold, '');
  final lines = unfolded.split(_reNewline);
  final result = <IcsEvent>[];

  Map<String, String>? props;
  Map<String, Map<String, String>> params = {};
  var inEvent = false;

  void flush() {
    final current = props;
    if (current == null) return;
    final dtStart = current['DTSTART'];
    final start = dtStart == null
        ? null
        : _parseIcsDate(dtStart, params['DTSTART'] ?? const {});
    if (start != null) {
      final uid = current['UID']?.trim();
      final dtEnd = current['DTEND'];
      result.add(IcsEvent(
        uid: (uid == null || uid.isEmpty)
            ? 'ics-${start.millisecondsSinceEpoch}'
            : uid,
        summary: _unescape(current['SUMMARY'] ?? ''),
        start: start,
        end: dtEnd == null
            ? null
            : _parseIcsDate(dtEnd, params['DTEND'] ?? const {}),
        description: _unescape(current['DESCRIPTION'] ?? ''),
        location: _unescape(current['LOCATION'] ?? ''),
        allDay: (params['DTSTART'] ?? const {})['VALUE'] == 'DATE' ||
            dtStart!.length == 8,
        done: current['X-VOICE-ASSISTANT-DONE'] == '1',
        cancelled: current['STATUS']?.toUpperCase() == 'CANCELLED',
        lastModified: current['LAST-MODIFIED'] == null
            ? null
            : _parseIcsDate(current['LAST-MODIFIED']!, const {}),
      ));
    }
    props = null;
    params = {};
  }

  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.toUpperCase() == 'BEGIN:VEVENT') {
      inEvent = true;
      props = {};
      params = {};
      continue;
    }
    if (line.toUpperCase() == 'END:VEVENT') {
      if (inEvent) flush();
      inEvent = false;
      continue;
    }
    if (!inEvent) continue;
    final colon = _colonIndex(line);
    if (colon <= 0) continue;
    final left = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = left.split(';');
    final name = parts.first.toUpperCase();
    props![name] = value;
    if (parts.length > 1) {
      final p = <String, String>{};
      for (final raw in parts.skip(1)) {
        final eq = raw.indexOf('=');
        if (eq > 0) {
          p[raw.substring(0, eq).toUpperCase()] = raw.substring(eq + 1);
        }
      }
      params[name] = p;
    }
  }
  return result;
}

int _colonIndex(String line) {
  // двоеточие внутри параметра в кавычках не считается разделителем
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') quoted = !quoted;
    if (c == ':' && !quoted) return i;
  }
  return -1;
}

// Регулярные выражения собираются один раз: разбор ICS идёт на каждое
// событие при каждой синхронизации.
final _reFold = RegExp(r'\r?\n[ 	]');
final _reNewline = RegExp(r'\r?\n');
final _reDateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final _reUtc = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$');
final _reLocal = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$');
final _reOffset = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})([+-])(\d{2})(\d{2})$');

List<int> _ymdhms(RegExpMatch m) => [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    ];

/// Время из строки ICS. [params] — параметры строки DTSTART/DTEND:
/// без них `TZID=Europe/Moscow` читался бы как время телефона.
DateTime? _parseIcsDate(String value, Map<String, String> params) {
  final v = value.trim();

  final dateOnly = _reDateOnly.firstMatch(v);
  if (dateOnly != null) {
    return DateTime(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
    );
  }

  final utc = _reUtc.firstMatch(v);
  if (utc != null) {
    final p = _ymdhms(utc);
    return DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]).toLocal();
  }

  // Явное смещение: «20261030T100000+0300». Раньше такая строка не
  // разбирались и событие молча пропадало.
  final off = _reOffset.firstMatch(v);
  if (off != null) {
    final p = _ymdhms(off);
    final sign = off.group(7) == '-' ? -1 : 1;
    final shift = Duration(
        hours: int.parse(off.group(8)!), minutes: int.parse(off.group(9)!));
    return DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5])
        .subtract(Duration(seconds: sign * shift.inSeconds))
        .toLocal();
  }

  final local = _reLocal.firstMatch(v);
  if (local != null) {
    final p = _ymdhms(local);
    final tzid = params['TZID'];
    if (tzid != null && tzid.isNotEmpty) {
      final zoned = _fromTzid(tzid, p);
      if (zoned != null) return zoned;
    }
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }
  return null;
}

/// Момент «wall clock в зоне [tzid]», приведённый к часовой зоне устройства.
DateTime? _fromTzid(String tzid, List<int> p) {
  try {
    return tz.TZDateTime(
            tz.getLocation(tzid), p[0], p[1], p[2], p[3], p[4], p[5])
        .toLocal();
  } catch (_) {
    // База часовых зон не инициализирована или зона неизвестна —
    // разберём как локальное время, как раньше.
    return null;
  }
}

String _unescape(String s) => s
    .replaceAll('\\n', '\n')
    .replaceAll('\\N', '\n')
    .replaceAll('\\,', ',')
    .replaceAll('\\;', ';')
    .replaceAll('\\\\', '\\');

/// Собирает VEVENT для записи приложения. Время передаётся в UTC.
String buildEntryIcs(
  Entry e, {
  required String uid,
  required DateTime stamp,
}) {
  String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  String two(int n) => n.toString().padLeft(2, '0');
  String dt(DateTime d) {
    final u = d.toUtc();
    return '${u.year}${two(u.month)}${two(u.day)}T'
        '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  String date(DateTime d) => '${d.year}${two(d.month)}${two(d.day)}';

  final due = e.dueAt!;
  final b = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:-//Voice Assistant//RU')
    ..writeln('BEGIN:VEVENT')
    ..writeln('UID:$uid')
    ..writeln('DTSTAMP:${dt(stamp)}')
    ..writeln('LAST-MODIFIED:${dt(e.lastModified)}')
    ..writeln('SUMMARY:${esc(e.title)}')
    ..writeln('X-VOICE-ASSISTANT:1');
  if (e.hasTime) {
    b
      ..writeln('DTSTART:${dt(due)}')
      ..writeln('DTEND:${dt(due.add(Duration(minutes: e.duration)))}');
  } else {
    final next = DateTime(due.year, due.month, due.day + 1);
    b
      ..writeln('DTSTART;VALUE=DATE:${date(due)}')
      ..writeln('DTEND;VALUE=DATE:${date(next)}');
  }
  if (e.place.isNotEmpty) b.writeln('LOCATION:${esc(e.place)}');
  final desc = [
    e.type.label,
    if (e.comment.isNotEmpty) e.comment,
  ].join('. ');
  b.writeln('DESCRIPTION:${esc(desc)}');
  if (e.done) b.writeln('X-VOICE-ASSISTANT-DONE:1');
  b
    ..writeln('END:VEVENT')
    ..writeln('END:VCALENDAR');
  return b.toString().replaceAll('\n', '\r\n');
}

String _utcStamp(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
