import 'package:flutter_test/flutter_test.dart';
import 'package:atlanta_events/event.dart';
import 'package:atlanta_events/event_service.dart';
import 'package:atlanta_events/district_calendar.dart';

void main() {
  test(
    'Dirty South separates weekdays and uses confirmed PM hours and addresses',
    () {
      final service = EventService();
      addTearDown(service.close);
      const body =
          '''<div data-testid="richTextElement"><h2>Tuesdays<br><br>Parkgrounds, Reynoldstown - 7:00❔<br>Hotel Clermont, Poncey-Highland - 7:00 ♬<br>Wrong Venue, Nowhere - TBA❔</h2></div><div data-testid="richTextElement"><h5>Wednesdays<br>Bona Fide Deluxe, Edgewood - 7:00 ❔<br>Industry Tavern, Buckhead - 8:00❔</h5></div>''';
      final entries = service.parseDirtySouth(body);
      expect(entries, hasLength(3));
      expect(entries.first.start.weekday, DateTime.tuesday);
      expect(entries.last.start.weekday, DateTime.wednesday);
      expect(entries[1].category, 'Nightlife');
      expect(entries.first.start.hour, 19);
      expect(entries.first.address, contains('142 Flat Shoals'));
      expect(entries[1].address, contains('789 Ponce'));
      expect(entries.last.start.hour, 20);
      expect(entries.first.milesFrom(33.750114, -84.354791), closeTo(0, .001));
      expect(
        service.parseDirtySouth(
          body
              .replaceAll('Tuesdays', 'Cancelled')
              .replaceAll('Wednesdays', 'Removed'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'Access Atlanta date-only listings retain location and check-hours label',
    () {
      final service = EventService();
      addTearDown(service.close);
      final date = DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String()
          .substring(0, 10);
      final entries = service.parseCalendarDetail(
        '''<script type="application/ld+json">{"@type":"Event","name":"Atlanta Arab Festival","startDate":"${date}T00:00:00-04:00","location":{"name":"Alif Institute","address":{"streetAddress":"3288 Marjan Drive, Atlanta, GA"},"geo":{"latitude":"33.88477","longitude":"-84.26457"}}}</script>''',
        'https://events.accessatlanta.com/cal/4910499',
        source: 'Access Atlanta',
      );
      expect(entries.single.allDay, isTrue);
      expect(
        entries.single.end!.difference(entries.single.start),
        const Duration(days: 1),
      );
      expect(entries.single.category, 'Festivals');
      expect(entries.single.latitude, 33.88477);
      expect(entries.single.address, contains('3288 Marjan'));
    },
  );
  test('Motorboat reads published weekday, both hours and stable origin id', () {
    const card =
        '''<div class="event-text-holder"><h2>Trivia presented by Trivia Lab</h2><p class="event-day">Tuesday October 6th</p><div class="event-info-text"><div data-is-recurring="true" data-origin-event-id="2664707"></div><p>Every Tuesday</p><p>Gift cards for winners!</p></div><p class="event-time">07:30 PM - 09:30 PM</p></div>''';
    final service = EventService();
    final event = service.parseMotorboat(card).single;
    expect(event.start.weekday, DateTime.tuesday);
    expect(event.start.hour, 19);
    expect(event.start.minute, 30);
    expect(event.end!.difference(event.start), const Duration(hours: 2));
    expect(event.id, 'motorboat-2664707');
    expect(event.milesFrom(33.773703, -84.364107), closeTo(0, .001));
    expect(
      service.parseMotorboat(
        card.replaceAll('Every Tuesday', 'Event cancelled'),
      ),
      isEmpty,
    );
    expect(
      service.parseMotorboat(
        card.replaceAll('07:30 PM - 09:30 PM', 'Time TBA'),
      ),
      isEmpty,
    );
  });
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
