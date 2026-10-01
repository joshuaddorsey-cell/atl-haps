# ATL Haps

An Atlanta event finder for Android, built with Flutter. Includes music, festivals, arts, sports, community events, and neighborhood bar happenings such as trivia, karaoke, and music bingo.

## Use

- Explore Atlanta or tap Near me to request the phone's location.
- Search, filter by category/date, and choose a nearby radius.
- Open an event for dates, start/end hours when published, venue, address, details, and the source listing.
- Tap Google Maps directions to navigate. Save events for later.

## Event coverage

Virginia Highland District is imported from its published public Google Calendar subscription. Dated entries and weekly/monthly recurrences are expanded for the coming year, with cancellation overrides, excluded dates and Eastern daylight saving time respected. All-day entries are labeled with a reminder to check opening hours. The source panel includes Dad’s official Instagram and directions to Dad’s and Atkins Park using the coordinates provided by the user.

Live imports include Team Trivia metro Atlanta schedules, Creative Loafing events and festivals (including venue addresses from its directory), Limerick Junction and Bona Fide Deluxe. Cancelled and postponed structured listings are excluded. The storefront button shows importer status and official links for Motorboat, Limerick Junction, Dad’s and Atkins Park. Motorboat’s official events page publishes Trivia Lab every Tuesday, 7:30–9:30 PM. Its schedule is read live, with a stable organizer event ID and venue coordinates from its own map. It appears on matching weekdays and links to the official events page. Limerick Wednesday trivia remains an unverified user report. Dad’s has no readable published schedule, and Atkins Park can reject automated requests. Discover Atlanta festivals are accessible through a live browser link rather than an aggregate feed. Cached events remain visible while sources refresh. Run `flutter test --dart-define=LIVE_SOURCES=true` for an optional live source audit.

This first version reads public Star Community Bar and The Atlanta Calendar listings and includes a verified Home Bar recurring schedule. Every listing links back to its source. Today is the default date. Listings are fetched from live calendars on startup and pull-to-refresh; recurring schedules are included only when the venue page still advertises the schedule. Previously fetched listings are cached for offline use and visibly labeled as cached when a source fails. No bundled event list is used by the app. Recurring schedules are explicitly labeled and end times are not invented. Source date quality varies; malformed historic listings are rejected. This is initial coverage, not a complete citywide database. Categories can have no available listings.

Near me currently filters known Atlanta venue coordinates. These coordinates are approximate; Google Maps directions use the venue's name and street address. Listings without coordinates remain visible in Atlanta mode and are excluded from nearby results. Outside the Atlanta area, nearby results may be empty. A future geographic event provider can add other cities. The browser preview requires an event proxy because third-party calendars do not allow cross-origin requests; Android reads them directly.

## Development

Dirty South Trivia's live weekday schedule adds pub quizzes, music trivia and music bingo. Bona Fide entries already covered by its direct venue feed are excluded from this import. The user confirmed its times are PM. All currently listed venue addresses were verified online and matched by venue and neighborhood; provenance is in `docs/dirty-south-venues.md`. New unrecognized venues show a street-address confirmation note. All 33 currently scheduled Dirty South venue addresses now have Census address-range coordinates, allowing their 35 shows to appear in Near me. Bona Fide and Limerick recurring events also have address-matched coordinates. Custom date selection displays the selected date and safely clamps old selections when reopening the picker. Switching to Atlanta cancels the effect of pending location requests. Access Atlanta imports up to 100 unique event pages linked from its live homepage, with structured dates, addresses and coordinates where published. Midnight placeholder listings show a check-hours label. Eventbrite and Discover Atlanta are available as live browser links because direct requests are currently rejected. Coverage remains partial; no calendar snapshot is bundled.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Optional source audit: Python with lxml, `python tools/refresh_catalog.py`. This writes a developer audit file and is not used as the runtime feed. Live parsing is in `lib/event_service.dart`; event fields and navigation in `lib/event.dart`; screens in `lib/main.dart`.

## Privacy

No account, advertising SDK, or background location tracking. Location is requested only by Near me and retained in memory for distance filtering. Calendar servers receive normal network requests; Google Maps receives the selected destination when directions are opened. Saved events and cached listings remain on the device. No private user information or account keys are committed.

## Branding

Original logo generated with the built-in image tool: bold interlocking ATL monogram, peach motif, warm orange/cream and midnight ink, transparent background, app-icon legibility. Asset: `assets/branding/atl-haps-logo.png`.

## Release

Version 1.1.3+5 is a device-test build signed with the development key. Google Play publication requires a separate release signing configuration, store materials, data safety review, and additional source coverage/permission review. No Google Play publication is performed in this task.

