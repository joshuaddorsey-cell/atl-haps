import 'dart:convert';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'event.dart';
import 'district_calendar.dart';

class EventService {
  final http.Client _client = http.Client();
  void close() => _client.close();
  static const venues = <String, String>{
    'Motorboat': 'https://motorboatsandwichbar.com/',
    'Limerick Junction': 'https://www.limerickjunction.com/events',
    'Dad’s': 'https://www.dadsatl.com/',
    'Atkins Park': 'https://www.atkinspark.com/',
    'Bona Fide Deluxe': 'https://www.bonafide-atl.com/',
  };
  final Map<String, String> sourceStatus = {};
  final Set<String> failedSources = {};
  List<Map<String, dynamic>> structured(String body) {
    final nodes = <Map<String, dynamic>>[];
    void read(dynamic v) {
      if (v is List) {
        for (final item in v) {
          read(item);
        }
      }
      if (v is Map<String, dynamic>) {
        nodes.add(v);
        if (v['@graph'] != null) read(v['@graph']);
      }
    }

    for (final script in parse(
      body,
    ).querySelectorAll('script[type="application/ld+json"]')) {
      // Some publishers put literal newlines inside JSON strings.
      var quoted = false, escaped = false;
      final clean = StringBuffer();
      for (final rune in script.text.runes) {
        if (quoted && rune < 32) {
          clean.write(
            jsonEncode(
              String.fromCharCode(rune),
            ).substring(1, jsonEncode(String.fromCharCode(rune)).length - 1),
          );
          continue;
        }
        clean.writeCharCode(rune);
        if (escaped) {
          escaped = false;
          continue;
        }
        if (rune == 92 && quoted) {
          escaped = true;
          continue;
        }
        if (rune == 34) quoted = !quoted;
      }
      try {
        read(jsonDecode(clean.toString()));
      } catch (_) {}
    }
    return nodes;
  }

  static const calendar = 'https://www.theatlantacalendar.com';
  static const star = 'https://www.starbaratl.bar';
  Future<String> get(String url) async {
    final r = await _client
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

  List<Hap> parseCalendarDetail(
    String body,
    String url, {
    String source = 'The Atlanta Calendar',
  }) {
    final found = <Hap>[];
    void read(dynamic node) {
      if (node is List) {
        for (final n in node) {
          read(n);
        }
        return;
      }
      if (node is! Map) return;
      if (node['@type'] != 'Event') return;
      if ('${node['eventStatus']}'.contains('EventCancelled') ||
          '${node['eventStatus']}'.contains('EventPostponed')) {
        return;
      }
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
        final title =
            parse(node['name'] as String).body?.text ?? node['name'] as String;
        final rawEnd = DateTime.tryParse('${node['endDate']}');
        var category = categorize(title);
        if (category == 'Music') {
          final detailCategory = categorize('$title ${node['description']}');
          // A concert description mentioning another festival is not a festival listing.
          if (detailCategory != 'Festivals') category = detailCategory;
        }
        if (rawEnd != null &&
            rawEnd.difference(start).inDays > (category == 'Arts' ? 180 : 14)) {
          return;
        }
        found.add(
          Hap(
            id: source == 'The Atlanta Calendar'
                ? url
                : '$url|${start.toIso8601String()}|$title',
            title: title,
            venue: loc is Map
                ? '${loc['name'] ?? 'Event venue'}'
                : 'Event venue',
            address: addressText,
            category: category,
            description:
                parse('${node['description'] ?? ''}').documentElement?.text ??
                '',
            url: url,
            source: source,
            latitude: loc is Map && loc['geo'] is Map
                ? double.tryParse('${loc['geo']['latitude']}')
                : null,
            longitude: loc is Map && loc['geo'] is Map
                ? double.tryParse('${loc['geo']['longitude']}')
                : null,
            start: start,
            end: rawEnd != null && rawEnd.isAfter(start) ? rawEnd : null,
          ),
        );
      } catch (_) {
        /* Skip incomplete structured data. */
      }
    }

    for (final node in structured(body)) {
      read(node);
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
    failedSources.clear();
    final results = <Hap>[];
    // Sources fail independently; working sources still contribute events.
    await Future.wait([
      () async {
        try {
          final entries = parseDistrict(await get(districtFeed));
          results.addAll(entries);
          sourceStatus['Virginia Highland District'] =
              '${entries.length} published events';
        } catch (_) {
          sourceStatus['Virginia Highland District'] =
              'Calendar feed unavailable';
          failedSources.add('Virginia Highland District');
        }
      }(),
      () async {
        try {
          const base = 'https://creativeloafing.com/';
          // Dedicated date-filtered calendars avoid the site's stale legacy landing page.
          final pages = await Future.wait(
            [
              'atlanta-events/today',
              'atlanta-events/festivals/this-month',
              'atlanta-events/atlanta-arts/this-week',
            ].map((path) async {
              try {
                return await get('$base$path');
              } catch (_) {
                return '';
              }
            }),
          );
          final links = pages
              .expand((body) => parse(body).querySelectorAll('a[href]'))
              .map((a) => a.attributes['href']!)
              .where(
                (s) => RegExp(
                  r'^(https://creativeloafing.com/|/)?event-\d+',
                ).hasMatch(s),
              )
              .map((s) => Uri.parse(base).resolve(s).toString())
              .toSet()
              .take(60)
              .toList();
          final businesses = <String, Future<Map<String, dynamic>?>>{};
          var count = 0, failures = 0;
          for (var i = 0; i < links.length; i += 6) {
            await Future.wait(
              links.skip(i).take(6).map((url) async {
                try {
                  final nodes = structured(await get(url));
                  for (final node in nodes.where(
                    (v) => v['@type'] == 'Event',
                  )) {
                    final loc = node['location'];
                    if (loc is Map &&
                        loc['address'] == null &&
                        loc['url'] is String) {
                      final businessUrl = Uri.parse(
                        base,
                      ).resolve(loc['url']).toString();
                      if (Uri.parse(businessUrl).host ==
                          'creativeloafing.com') {
                        businesses.putIfAbsent(businessUrl, () async {
                          try {
                            return structured(await get(businessUrl))
                                .where((v) => v['@type'] == 'LocalBusiness')
                                .firstOrNull;
                          } catch (_) {
                            return null;
                          }
                        });
                        final business = await businesses[businessUrl];
                        if (business != null) {
                          loc['address'] = business['address'];
                          loc['geo'] = business['geo'];
                        }
                      }
                    }
                    final entries = parseCalendarDetail(
                      '<script type="application/ld+json">${jsonEncode(node)}</script>',
                      url,
                      source: 'Creative Loafing',
                    );
                    results.addAll(entries);
                    count += entries.length;
                  }
                } catch (_) {
                  failures++;
                }
              }),
            );
          }
          if (count == 0) throw Exception('No readable listings');
          sourceStatus['Creative Loafing'] =
              '$count published events${failures > 0 ? ' • $failures listings unavailable' : ''}';
        } catch (_) {
          sourceStatus['Creative Loafing'] = 'Source unavailable';
          failedSources.add('Creative Loafing');
        }
      }(),
      () async {
        try {
          final doc = parse(
            await get('https://www.teamtrivia.com/trivia-in-atlanta/'),
          );
          final links = doc
              .querySelectorAll('a.tt-area-venue-card')
              .map((a) => a.attributes['href']!)
              .where((s) => s.startsWith('https://www.teamtrivia.com/venue/'))
              .toSet()
              .toList();
          var failures = 0;
          var count = 0;
          for (var i = 0; i < links.length; i += 8) {
            await Future.wait(
              links.skip(i).take(8).map((url) async {
                try {
                  final entries = parseCalendarDetail(
                    await get(url),
                    url,
                    source: 'Team Trivia',
                  );
                  results.addAll(entries);
                  count += entries.length;
                } catch (_) {
                  failures++;
                }
              }),
            );
          }
          if (count == 0) throw Exception('No readable listings');
          sourceStatus['Team Trivia'] =
              '$count published events${failures > 0 ? ' • $failures venues unavailable' : ''}';
        } catch (_) {
          sourceStatus['Team Trivia'] = 'Source unavailable';
          failedSources.add('Team Trivia');
        }
      }(),
      ...venues.entries.map((entry) async {
        try {
          final body = await get(entry.value);
          final entries = parseCalendarDetail(
            body,
            entry.value,
            source: entry.key,
          );
          final text =
              parse(
                body,
              ).body?.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ??
              '';
          void weekly(
            String match,
            int day,
            int hour,
            String title,
            String address,
            String category,
          ) {
            if (!text.contains(match)) return;
            entries.add(
              Hap(
                id: '${entry.value}|$day|$title',
                title: title,
                venue: entry.key,
                address: address,
                category: category,
                description:
                    'Weekly schedule currently published by the venue. Check the organizer for cancellations and this week’s details. End time not published.',
                url: entry.value,
                source: entry.key,
                start: DateTime(2026, 1, 5 + day - 1, hour),
                recurring: true,
              ),
            );
          }

          if (entry.key == 'Limerick Junction' &&
              text.contains('free roll poker')) {
            weekly(
              'every wednesday at 8pm',
              3,
              20,
              'Free Roll Poker',
              '822 North Highland Ave NE, Atlanta, GA 30306',
              'Nightlife',
            );
          }
          if (entry.key == 'Bona Fide Deluxe') {
            // The exact schedule must still be present in the live venue page.
            if (RegExp(
              r'trivia.*?wednesday.*?sunday.*?7\s*pm',
            ).hasMatch(text)) {
              weekly(
                'trivia',
                3,
                19,
                'Wednesday trivia',
                '1454 La France St NE, Suite 110, Atlanta, GA 30307',
                'Trivia',
              );
              weekly(
                'trivia',
                7,
                19,
                'Sunday trivia',
                '1454 La France St NE, Suite 110, Atlanta, GA 30307',
                'Trivia',
              );
            }
            if (RegExp(r'music bingo.*?thursday.*?7\s*pm').hasMatch(text)) {
              weekly(
                'music bingo',
                4,
                19,
                'Music bingo',
                '1454 La France St NE, Suite 110, Atlanta, GA 30307',
                'Nightlife',
              );
            }
          }
          results.addAll(entries);
          sourceStatus[entry.key] = entries.isEmpty
              ? 'Website checked • no readable upcoming schedule'
              : '${entries.length} published events';
        } catch (_) {
          sourceStatus[entry.key] = 'Website unavailable • try organizer link';
          failedSources.add(entry.key);
        }
      }),
      () async {
        try {
          results.addAll(
            parseHomeBar(await get("https://www.homebaratl.com/")),
          );
        } catch (_) {
          failedSources.add('Home Bar');
        }
      }(),
      () async {
        try {
          results.addAll(parseStar(await get('$star/')));
        } catch (_) {
          failedSources.add('Star Community Bar');
        }
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
        } catch (_) {
          failedSources.add('The Atlanta Calendar');
        }
      }(),
    ]);
    if (results.isEmpty) throw Exception('Could not refresh event calendars');
    return results;
  }
}
