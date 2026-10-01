import 'package:flutter_test/flutter_test.dart';
import 'package:atlanta_events/event.dart';
import 'package:atlanta_events/event_service.dart';

void main() {
  test('Directions preserve venue and address as an encoded destination', () {
    final e = Hap(
      id: '1',
      title: 'Trivia',
      venue: 'Bob & Harriet',
      address: '1992 Hosea L Williams Dr NE, Atlanta, GA',
      category: 'Trivia',
      description: '',
      url: 'https://example.com',
      source: 'Venue',
      start: DateTime(2026, 10, 1, 20),
    );
    expect(
      e.directions.queryParameters['destination'],
      'Bob & Harriet, 1992 Hosea L Williams Dr NE, Atlanta, GA',
    );
    expect(e.directions.queryParameters['api'], '1');
    expect(e.milesFrom(33.7, -84.3), isNull);
  });
  test(
    'Calendar parser handles overnight UTC events and rejects incomplete cards',
    () {
      final parsed = EventService().parseStar(
        '''<article class="eventlist-event"><a class="eventlist-title-link" href="/shows/karaoke">Karaoke</a><a class="eventlist-meta-export-google" href="https://google.com/calendar?dates=20261003T010000Z/20261003T060000Z"></a><div class="eventlist-excerpt">Karaoke at the bar</div></article><article class="eventlist-event"></article>''',
      );
      expect(parsed.length, 1);
      expect(
        parsed.first.end!.difference(parsed.first.start),
        const Duration(hours: 5),
      );
      expect(parsed.first.category, 'Nightlife');
      expect(parsed.first.upcoming(DateTime.utc(2026, 10, 3, 4)), true);
      expect(parsed.first.upcoming(DateTime.utc(2026, 10, 3, 7)), false);
    },
  );
  test('Recurring trivia is parsed only while the venue advertises it', () {
    final service = EventService();
    expect(
      service
          .parseHomeBar('<p>TRIVIA THURSDAYS AT 8PM</p>')
          .single
          .start
          .weekday,
      DateTime.thursday,
    );
    expect(service.parseHomeBar('<p>No events this week</p>'), isEmpty);
  });
  test(
    'Date filter includes ongoing multi-day events and excludes other dates',
    () {
      final e = Hap(
        id: '1',
        title: 'Festival',
        venue: 'Venue',
        address: 'Atlanta',
        category: 'Festivals',
        description: '',
        url: 'https://example.com',
        source: 'Venue',
        start: DateTime(2026, 10, 1, 12),
        end: DateTime(2026, 10, 3, 18),
      );
      expect(e.occursOn(DateTime(2026, 10, 2)), true);
      expect(e.occursOn(DateTime(2026, 10, 4)), false);
    },
  );
}
