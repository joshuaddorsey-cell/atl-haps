import 'package:html/parser.dart';
import 'event.dart';

const districtUrl = 'https://www.virginiahighlanddistrict.com/events';
const districtFeed =
    'https://calendar.google.com/calendar/ical/c_f362682ae90b43e2147711bca9e457207d12d6f999fcd9f4f6434f33ec26d2f8%40group.calendar.google.com/public/basic.ics';

// Public iCalendar dates use UTC or the publisher's America/New_York zone.
// Convert each local occurrence separately so weekly times survive DST changes.
DateTime easternUtc(DateTime wall) {
  DateTime sunday(int month, int number) {
    final first = DateTime.utc(wall.year, month);
    return DateTime.utc(
      wall.year,
      month,
      1 + (7 - first.weekday) % 7 + (number - 1) * 7,
      2,
    );
  }

  final summer = !wall.isBefore(sunday(3, 2)) && wall.isBefore(sunday(11, 1));
  return wall.add(Duration(hours: summer ? 4 : 5));
}

List<Hap> parseDistrict(String input, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final earliest = today.subtract(const Duration(days: 2));
  final horizon = today.add(const Duration(days: 365));
  final text = input.replaceAll('\r', '').replaceAll(RegExp(r'\n[ \t]'), '');
  final records = <Map<String, List<(String, String)>>>[];
  for (final block in text.split('BEGIN:VEVENT').skip(1)) {
    final fields = <String, List<(String, String)>>{};
    for (final line in block.split('END:VEVENT').first.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final key = line.substring(0, colon);
      fields.putIfAbsent(key.split(';').first, () => []).add((
        key,
        line.substring(colon + 1),
      ));
    }
    records.add(fields);
  }
  String unescape(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');
  DateTime wall(String s) => DateTime.utc(
    int.parse(s.substring(0, 4)),
    int.parse(s.substring(4, 6)),
    int.parse(s.substring(6, 8)),
    s.length >= 13 ? int.parse(s.substring(9, 11)) : 0,
    s.length >= 13 ? int.parse(s.substring(11, 13)) : 0,
    s.length >= 15 ? int.parse(s.substring(13, 15)) : 0,
  );
  DateTime instant((String, String) field, [DateTime? occurrence]) {
    final v = occurrence ?? wall(field.$2);
    if (field.$2.endsWith('Z')) return v;
    if (field.$1.contains('TZID=') && !field.$1.contains('America/New_York')) {
      throw FormatException('Unsupported calendar timezone');
    }
    return easternUtc(v);
  }

  final overrides = <String>{};
  for (final record in records) {
    try {
      if (record.containsKey('RECURRENCE-ID')) {
        overrides.add(
          '${record['UID']!.first.$2}|${instant(record['RECURRENCE-ID']!.first).toIso8601String()}',
        );
      }
    } catch (_) {}
  }
  final events = <Hap>[];
  for (final record in records) {
    try {
      if (record['STATUS']?.first.$2 == 'CANCELLED') continue;
      final begin = record['DTSTART']!.first;
      final finish = record['DTEND']?.first;
      final anchor = wall(begin.$2);
      final duration = finish == null
          ? const Duration(hours: 3)
          : wall(finish.$2).difference(anchor);
      final allDay = begin.$1.contains('VALUE=DATE');
      final uid = record['UID']!.first.$2;
      final exclusions = <DateTime>{};
      for (final field in record['EXDATE'] ?? <(String, String)>[]) {
        for (final date in field.$2.split(',')) {
          exclusions.add(instant((field.$1, date)));
        }
      }
      final rule = <String, String>{};
      for (final part in (record['RRULE']?.first.$2 ?? '').split(';')) {
        final pair = part.split('=');
        if (pair.length == 2) rule[pair[0]] = pair[1];
      }
      if (rule.isNotEmpty &&
          !['WEEKLY', 'MONTHLY', 'DAILY'].contains(rule['FREQ'])) {
        continue;
      }
      final until = rule['UNTIL'] == null
          ? horizon
          : instant((begin.$1, rule['UNTIL']!));
      final interval = int.tryParse(rule['INTERVAL'] ?? '') ?? 1;
      final count = int.tryParse(rule['COUNT'] ?? '');
      final byday = (rule['BYDAY'] ?? '').split(',');
      const weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      var matched = 0;
      for (var day = anchor; ; day = day.add(const Duration(days: 1))) {
        final start = instant(begin, day);
        if (start.isAfter(horizon) || start.isAfter(until)) break;
        var applies = rule.isEmpty ? day == anchor : true;
        if (rule['FREQ'] == 'WEEKLY') {
          applies =
              day.difference(anchor).inDays ~/ 7 % interval == 0 &&
              (byday.first.isEmpty
                  ? day.weekday == anchor.weekday
                  : byday.contains(weekdays[day.weekday - 1]));
        }
        if (rule['FREQ'] == 'DAILY') {
          applies = day.difference(anchor).inDays % interval == 0;
        }
        if (rule['FREQ'] == 'MONTHLY') {
          applies =
              ((day.year - anchor.year) * 12 + day.month - anchor.month) %
                  interval ==
              0;
          applies =
              applies &&
              (byday.first.isEmpty
                  ? day.day == anchor.day
                  : byday.any((v) {
                      final m = RegExp(
                        r'^([1-5])?(MO|TU|WE|TH|FR|SA|SU)$',
                      ).firstMatch(v);
                      return m != null &&
                          weekdays[day.weekday - 1] == m[2] &&
                          (m[1] == null ||
                              (day.day - 1) ~/ 7 + 1 == int.parse(m[1]!));
                    }));
        }
        if (!applies) {
          if (rule.isEmpty) break;
          continue;
        }
        matched++;
        if (count != null && matched > count) break;
        final end = instant(
          begin,
          day.add(
            allDay && finish == null ? const Duration(days: 1) : duration,
          ),
        );
        if (end.isBefore(earliest) ||
            exclusions.contains(start) ||
            (!record.containsKey('RECURRENCE-ID') &&
                overrides.contains('$uid|${start.toIso8601String()}'))) {
          if (rule.isEmpty) break;
          continue;
        }
        final title = unescape(record['SUMMARY']?.first.$2 ?? 'District event');
        final address = unescape(record['LOCATION']?.first.$2 ?? '');
        if (address.isEmpty) {
          if (rule.isEmpty) break;
          continue;
        }
        final atkins = address.toLowerCase().contains('atkins park restaurant');
        final dads = address.toLowerCase().contains("dad's");
        events.add(
          Hap(
            id: 'district-$uid|${start.toIso8601String()}',
            title: title,
            venue: atkins
                ? 'Atkins Park Tavern'
                : dads
                ? 'Dad’s'
                : address.split(',').first,
            address: address,
            category: categorize(title),
            description:
                parse(
                  unescape(record['DESCRIPTION']?.first.$2 ?? ''),
                ).body?.text ??
                '',
            url: districtUrl,
            source: 'Virginia Highland District',
            start: start,
            end: finish == null && !allDay ? null : end,
            allDay: allDay,
            latitude: atkins
                ? 33.7766
                : dads
                ? 33.7783
                : null,
            longitude: atkins
                ? -84.3526
                : dads
                ? -84.3531
                : null,
          ),
        );
        if (rule.isEmpty) break;
      }
    } catch (_) {
      /* Skip incomplete or unsupported entries. */
    }
  }
  return events;
}
