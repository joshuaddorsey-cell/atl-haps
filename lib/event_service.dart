import 'dart:convert';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'event.dart';

class EventService {
  static const calendar = 'https://www.theatlantacalendar.com';
  static const star = 'https://www.starbaratl.bar';
  Future<String> get(String url) async {
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Source unavailable');
    return r.body;
  }

  List<Hap> parseStar(String body) {
    final events = <Hap>[];
    for (final card in parse(
      body,
    ).querySelectorAll('article.eventlist-event')) {
      try {
        final a = card.querySelector('.eventlist-title-link')!;
        final export = card.querySelector('.eventlist-meta-export-google')!;
        final dates = Uri.parse(
          export.attributes['href']!,
        ).queryParameters['dates']!.split('/');
        DateTime date(String s) => DateTime.utc(
          int.parse(s.substring(0, 4)),
          int.parse(s.substring(4, 6)),
          int.parse(s.substring(6, 8)),
          int.parse(s.substring(9, 11)),
          int.parse(s.substring(11, 13)),
        );
        final title = a.text.trim();
        final description =
            card.querySelector('.eventlist-excerpt')?.text.trim() ?? '';
        events.add(
          Hap(
            id: '$star${a.attributes['href']}',
            title: title,
            venue: 'Star Community Bar',
            address: '437 Moreland Ave NE, Atlanta, GA 30307',
            category: categorize('$title $description'),
            description: description,
            url: '$star${a.attributes['href']}',
            source: 'Star Community Bar',
            start: date(dates[0]),
            end: date(dates[1]),
            latitude: 33.7661,
            longitude: -84.3491,
          ),
        );
      } catch (_) {
        /* Skip incomplete listings rather than invent dates. */
      }
    }
    return events;
  }

  List<Hap> parseCalendarDetail(String body, String url) {
    final found = <Hap>[];
    void read(dynamic node) {
      if (node is List) {
        for (final n in node) {
          read(n);
        }
        return;
      }
      if (node is! Map) return;
      if (node['@graph'] != null) read(node['@graph']);
      if (node['@type'] != 'Event') return;
      try {
        final start = DateTime.parse(node['startDate']);
        // Reject malformed multi-year events from upstream calendars.
        if (start.isBefore(
          DateTime.now().subtract(const Duration(days: 180)),
        )) {
          return;
        }
        final loc = node['location'];
        final address = loc is Map ? loc['address'] : null;
        String addressText = address is String
            ? address
            : address is Map
            ? [
                address['streetAddress'],
                address['addressLocality'],
                address['addressRegion'],
                address['postalCode'],
              ].where((v) => v != null).join(', ')
            : '';
        if (addressText.isEmpty) return;
        final title = node['name'] as String;
        final rawEnd = DateTime.tryParse('${node['endDate']}');
        found.add(
          Hap(
            id: url,
            title: title,
            venue: loc is Map
                ? '${loc['name'] ?? 'Event venue'}'
                : 'Event venue',
            address: addressText,
            category: categorize('$title ${node['description']}'),
            description:
                parse('${node['description'] ?? ''}').documentElement?.text ??
                '',
            url: url,
            source: 'The Atlanta Calendar',
            start: start,
            end: rawEnd != null && rawEnd.isAfter(start) ? rawEnd : null,
          ),
        );
      } catch (_) {
        /* Skip incomplete structured data. */
      }
    }

    for (final script in parse(
      body,
    ).querySelectorAll('script[type="application/ld+json"]')) {
      try {
        read(jsonDecode(script.text));
      } catch (_) {}
    }
    return found;
  }

  List<Hap> parseHomeBar(String body) {
    final text = parse(body).documentElement?.text.toLowerCase() ?? '';
    final schedule = <(String, int, int, int, String, String)>[
      (
        'trivia thursdays at 8pm',
        4,
        20,
        0,
        'Thursday trivia at Home Bar',
        'Trivia',
      ),
      (
        'karaoke saturdays at 9pm',
        6,
        21,
        0,
        'Saturday karaoke at Home Bar',
        'Nightlife',
      ),
      (
        'music bingo wendsdays 7;30pm',
        3,
        19,
        30,
        'Music bingo at Home Bar',
        'Nightlife',
      ),
      (
        'old time jams tuesdays 7pm',
        2,
        19,
        0,
        'Old-time jam at Home Bar',
        'Music',
      ),
    ];
    return schedule
        .where((s) => text.contains(s.$1))
        .map(
          (s) => Hap(
            id: 'homebar-${s.$2}',
            title: s.$5,
            venue: 'Bob & Harriet’s Home Bar',
            address: '1992 Hosea L Williams Dr NE, Atlanta, GA 30317',
            category: s.$6,
            description:
                'A recurring neighborhood bar event. The venue publishes a start time but no end time. Check the organizer for this week’s updates and admission.',
            url: 'https://www.homebaratl.com/',
            source: 'Home Bar',
            start: DateTime(2026, 1, 5 + s.$2 - 1, s.$3, s.$4),
            latitude: 33.7524,
            longitude: -84.3227,
            recurring: true,
          ),
        )
        .toList();
  }

  Future<List<Hap>> live() async {
    final results = <Hap>[];
    // Sources fail independently; working sources still contribute events.
    await Future.wait([
      () async {
        try {
          results.addAll(
            parseHomeBar(await get("https://www.homebaratl.com/")),
          );
        } catch (_) {}
      }(),
      () async {
        try {
          results.addAll(parseStar(await get('$star/')));
        } catch (_) {}
      }(),
      () async {
        try {
          final doc = parse(await get('$calendar/'));
          final links = doc
              .querySelectorAll('a[href^="/events/"]')
              .map((a) => a.attributes['href']!)
              .where((s) => s != '/events/new')
              .toSet()
              .take(45)
              .toList();
          for (var i = 0; i < links.length; i += 6) {
            await Future.wait(
              links.skip(i).take(6).map((path) async {
                try {
                  results.addAll(
                    parseCalendarDetail(
                      await get('$calendar$path'),
                      '$calendar$path',
                    ),
                  );
                } catch (_) {}
              }),
            );
          }
        } catch (_) {}
      }(),
    ]);
    if (results.isEmpty) throw Exception('Could not refresh event calendars');
    return results;
  }
}
