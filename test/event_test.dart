import 'package:flutter_test/flutter_test.dart';
import 'package:atlanta_events/event.dart';
import 'package:atlanta_events/event_service.dart';
import 'package:atlanta_events/district_calendar.dart';

void main() {
  test(
    'District recurrence respects exclusions, end date and daylight saving',
    () {
      final events = parseDistrict('''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:market
DTSTART;TZID=America/New_York:20260927T083000
DTEND;TZID=America/New_York:20260927T113000
RRULE:FREQ=WEEKLY;UNTIL=20261123T045959Z;BYDAY=SU
EXDATE;TZID=America/New_York:20261011T083000
SUMMARY:Farmers Market
LOCATION:Virginia Highland\\, Atlanta
END:VEVENT
END:VCALENDAR''', now: DateTime.utc(2026, 10, 1));
      expect(events.first.start, DateTime.utc(2026, 10, 4, 12, 30));
      expect(
        events.any((e) => e.start.day == 11 && e.start.month == 10),
        false,
      );
      expect(events.last.start, DateTime.utc(2026, 11, 22, 13, 30));
      expect(
        events.last.end!.difference(events.last.start),
        const Duration(hours: 3),
      );
    },
  );
  test(
    'All-day district listings preserve exclusive end and ignore cancelled events',
    () {
      final events = parseDistrict('''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:fest
DTSTART;VALUE=DATE:20261212
DTEND;VALUE=DATE:20261214
SUMMARY:Winterfest
LOCATION:Atkins Park Restaurant & Bar\\, 794 N Highland Ave
END:VEVENT
BEGIN:VEVENT
UID:cancelled
DTSTART:20261028T200000Z
SUMMARY:Cancelled
LOCATION:Atlanta
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR''', now: DateTime.utc(2026, 10, 1));
      expect(events.length, 1);
      expect(events.single.allDay, true);
      expect(events.single.latitude, 33.7766);
      expect(
        events.single.end!.difference(events.single.start),
        const Duration(days: 2),
      );
    },
  );
  test('Structured schedules keep dates, coordinates and cancellations', () {
    final events = EventService().parseCalendarDetail(
      '''<script type="application/ld+json">{"@graph":[{"@type":"Event","name":"Trivia","startDate":"2026-12-01T20:00:00-05:00","location":{"name":"Bar","address":"1 Main St, Atlanta","geo":{"latitude":33.7,"longitude":-84.3}}},{"@type":"Event","name":"Trivia","startDate":"2026-12-08T20:00:00-05:00","location":{"name":"Bar","address":"1 Main St, Atlanta"}},{"@type":"Event","name":"Cancelled","eventStatus":"https://schema.org/EventCancelled","startDate":"2026-12-02T20:00:00-05:00","location":{"address":"Atlanta"}}]}</script>''',
      'https://example.com/bar',
      source: 'Team Trivia',
    );
    expect(events.length, 2);
    expect(events.map((e) => e.id).toSet().length, 2);
    expect(events.first.source, 'Team Trivia');
    expect(events.first.latitude, 33.7);
    expect(events.first.milesFrom(33.7, -84.3), closeTo(0, .001));
  });
  test('Publisher JSON accepts literal newlines inside descriptions', () {
    final nodes = EventService().structured(
      '<script type="application/ld+json">{"@type":"Event","description":"Line one\nLine two"}</script>',
    );
    expect(nodes.single['description'], 'Line one\nLine two');
  });
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
