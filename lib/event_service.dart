import 'dart:convert';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'event.dart';
import 'district_calendar.dart';
import 'dirty_venues.dart';

class EventService {
  final http.Client _client = http.Client();
  void close() => _client.close();
  static const venues = <String, String>{
    'Motorboat':
        'https://motorboatsandwichbar.com/atlanta-poncey-highlands-motorboat-events',
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
  Future<String> get(
    String url, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await _client.get(Uri.parse(url)).timeout(timeout);
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
            end: rawEnd != null && rawEnd.isAfter(start)
                ? rawEnd
                : source == 'Access Atlanta' &&
                      RegExp(r'T00:00:00').hasMatch('${node['startDate']}')
                ? start.add(const Duration(days: 1))
                : null,
            allDay:
                source == 'Access Atlanta' &&
                RegExp(r'T00:00:00').hasMatch('${node['startDate']}'),
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

  List<Hap> parseMotorboat(String body) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final found = <Hap>[];
    for (final card in parse(body).querySelectorAll('.event-text-holder')) {
      final title = card.querySelector('h2')?.text.trim();
      final info = card.querySelector('.event-info-text');
      final infoText =
          info?.querySelectorAll('p').map((p) => p.text.trim()).join('\n') ??
          '';
      final weekly = RegExp(
        r'\bevery\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
      ).firstMatch(infoText.toLowerCase());
      final times = RegExp(
        r'^(\d{1,2}):(\d{2})\s*(AM|PM)\s*[-–]\s*(\d{1,2}):(\d{2})\s*(AM|PM)$',
        caseSensitive: false,
      ).firstMatch(card.querySelector('.event-time')?.text.trim() ?? '');
      if (title == null ||
          weekly == null ||
          times == null ||
          info?.querySelector('[data-is-recurring="true"]') == null) {
        continue;
      }
      int hour(int n) =>
          int.parse(times[n]!) % 12 +
          (times[n + 2]!.toUpperCase() == 'PM' ? 12 : 0);
      if ([
            1,
            4,
          ].any((n) => int.parse(times[n]!) < 1 || int.parse(times[n]!) > 12) ||
          [2, 5].any((n) => int.parse(times[n]!) > 59)) {
        continue;
      }
      final day = days.indexOf(weekly[1]!) + 1;
      final start = DateTime(2026, 1, 4 + day, hour(1), int.parse(times[2]!));
      var end = DateTime(2026, 1, 4 + day, hour(4), int.parse(times[5]!));
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      final origin =
          info!
              .querySelector('[data-origin-event-id]')
              ?.attributes['data-origin-event-id'] ??
          title;
      found.add(
        Hap(
          id: 'motorboat-$origin',
          title: title,
          venue: 'Motorboat',
          address: '710 Ponce De Leon Ave NE, Atlanta, GA 30306',
          category: categorize(title),
          description:
              '$infoText\nWeekly schedule published by Motorboat. Check the organizer for this week’s updates.',
          url: venues['Motorboat']!,
          source: 'Motorboat',
          start: start,
          end: end,
          recurring: true,
          // Coordinates from the venue's own public map marker.
          latitude: 33.773703,
          longitude: -84.364107,
        ),
      );
    }
    return found;
  }

  List<Hap> parseDirtySouth(String body) {
    // Venue identity checks avoid incorrect shared links on the organizer page.
    const detailPaths = {
      'Grindhouse Killer Burgers|Memorial Dr': 'grindhous-memorial',
      'Grindhouse Killer Burgers|Piedmont Rd': 'grindhouse',
      'Fado Buckhead|Buckhead': 'fado-buckhead',
      'Breaker Breaker|Reynoldstown': 'breakerbreaker',
      'Chicheria|The Works': 'chicheria',
      'Hotel Clermont|Poncey-Highland': 'hotelclermont',
      'Industry Tavern|Buckhead': 'industry-tavern',
      'Monday Night Garage|West End': 'mondaynight',
      'Round Trip Brewing|East Cobb': 'round-trip-brewing-ec',
      'Round Trip Brewing|Underwood Hills': 'round-trip-brewing',
      'Sceptre Brewing Arts|Decatur': 'sceptrebrewing',
      'The Family Dog|The Highlands': 'the-family-dog',
      'Wild Heaven|West End': 'wildheaven',
    };
    const days = [
      'Mondays',
      'Tuesdays',
      'Wednesdays',
      'Thursdays',
      'Fridays',
      'Saturdays',
      'Sundays',
    ];
    final found = <String, Hap>{};
    for (final block in parse(
      body,
    ).querySelectorAll('[data-testid="richTextElement"]')) {
      final lines =
          (parse(
                    block.innerHtml.replaceAll(
                      RegExp(r'<br\b[^>]*>', caseSensitive: false),
                      '\n',
                    ),
                  ).body?.text ??
                  '')
              .replaceAll('\u00a0', ' ')
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
      if (lines.isEmpty || !days.contains(lines.first)) continue;
      final day = days.indexOf(lines.first) + 1;
      for (final line in lines.skip(1)) {
        final m = RegExp(
          r'^(.+?),\s*(.+?)\s*-\s*(\d{1,2}:\d{2})\s*([❔♬🍆]+)$',
        ).firstMatch(line);
        if (m == null) continue;
        final venue = m[1]!, area = m[2]!, time = m[3]!;
        // Bona Fide's direct venue feed already supplies its verified 7 PM shows.
        if (venue == 'Bona Fide Deluxe') continue;
        final parts = time.split(':').map(int.parse).toList();
        if (parts[0] < 1 || parts[0] > 12 || parts[1] > 59) continue;
        final title = m[4]!.contains('♬')
            ? 'Music bingo'
            : m[4]!.contains('🍆')
            ? 'Sex, Drugs & Music trivia'
            : 'Pub quiz trivia';
        final id = 'dirtysouth|$venue|$area|$day|$title';
        found[id] = Hap(
          id: id,
          title: title,
          venue: venue,
          address: dirtyVenues['$venue|$area'] ?? '$area, Atlanta metro, GA',
          category: title == 'Music bingo' ? 'Nightlife' : 'Trivia',
          description:
              'Weekly evening show published by Dirty South Trivia. End time not published. Confirm this week’s schedule with the organizer.${dirtyVenues['$venue|$area'] == null ? ' Street address not verified; confirm before traveling.' : ''}',
          url:
              'https://www.dirtysouthtrivia.com/${detailPaths['$venue|$area'] ?? ''}',
          source: 'Dirty South Trivia',
          start: DateTime(2026, 1, 5 + day - 1, parts[0] % 12 + 12, parts[1]),
          recurring: true,
        );
      }
    }
    return found.values.toList();
  }

  Future<List<Hap>> live() async {
    failedSources.clear();
    final results = <Hap>[];
    // Sources fail independently; working sources still contribute events.
    await Future.wait([
      () async {
        try {
          final entries = parseDirtySouth(
            await get(
              'https://www.dirtysouthtrivia.com/',
              timeout: const Duration(seconds: 30),
            ),
          );
          if (entries.isEmpty) throw Exception('No readable schedule');
          results.addAll(entries);
          sourceStatus['Dirty South Trivia'] = '${entries.length} weekly shows';
        } catch (_) {
          sourceStatus['Dirty South Trivia'] = 'Schedule unavailable';
          failedSources.add('Dirty South Trivia');
        }
      }(),
      () async {
        try {
          final doc = parse(await get('https://events.accessatlanta.com/'));
          final links = doc
              .querySelectorAll('a[href]')
              .map(
                (a) => Uri.parse(
                  'https://events.accessatlanta.com/',
                ).resolve(a.attributes['href']!).toString(),
              )
              .where(
                (s) => RegExp(
                  r'^https://events\.accessatlanta\.com/cal/\d+$',
                ).hasMatch(s),
              )
              .toSet()
              .take(100)
              .toList();
          final entries = <Hap>[];
          for (var i = 0; i < links.length; i += 8) {
            await Future.wait(
              links.skip(i).take(8).map((url) async {
                try {
                  entries.addAll(
                    parseCalendarDetail(
                      await get(url),
                      url,
                      source: 'Access Atlanta',
                    ),
                  );
                } catch (_) {}
              }),
            );
          }
          if (entries.isEmpty) throw Exception('No readable events');
          results.addAll(entries);
          sourceStatus['Access Atlanta'] = '${entries.length} dated events';
        } catch (_) {
          sourceStatus['Access Atlanta'] = 'Calendar unavailable';
          failedSources.add('Access Atlanta');
        }
      }(),
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
          if (entry.key == 'Motorboat') entries.addAll(parseMotorboat(body));
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
