# ATL Haps

An Atlanta event finder for Android, built with Flutter. Includes music, festivals, arts, sports, community events, and neighborhood bar happenings such as trivia, karaoke, and music bingo.

## Use

- Explore Atlanta or tap Near me to request the phone's location.
- Search, filter by category/date, and choose a nearby radius.
- Open an event for dates, start/end hours when published, venue, address, details, and the source listing.
- Tap Google Maps directions to navigate. Save events for later.

## Event coverage

This first version reads public Star Community Bar and The Atlanta Calendar listings and includes a verified Home Bar recurring schedule. Every listing links back to its source. Today is the default date. Listings are fetched from live calendars on startup and pull-to-refresh; recurring schedules are included only when the venue page still advertises the schedule. Previously fetched listings are cached for offline use and visibly labeled as cached when a source fails. No bundled event list is used by the app. Recurring schedules are explicitly labeled and end times are not invented. Source date quality varies; malformed historic listings are rejected. This is initial coverage, not a complete citywide database. Categories can have no available listings.

Near me currently filters known Atlanta venue coordinates. These coordinates are approximate; Google Maps directions use the venue's name and street address. Listings without coordinates remain visible in Atlanta mode and are excluded from nearby results. Outside the Atlanta area, nearby results may be empty. A future geographic event provider can add other cities. The browser preview requires an event proxy because third-party calendars do not allow cross-origin requests; Android reads them directly.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

Optional bundled catalog refresh: Python with lxml, `python tools/refresh_catalog.py`. Live parsing is in `lib/event_service.dart`; event fields and navigation in `lib/event.dart`; screens in `lib/main.dart`.

## Privacy

No account, advertising SDK, or background location tracking. Location is requested only by Near me and retained in memory for distance filtering. Calendar servers receive normal network requests; Google Maps receives the selected destination when directions are opened. Saved events and cached listings remain on the device. No private user information or account keys are committed.

## Branding

Original logo generated with the built-in image tool: bold interlocking ATL monogram, peach motif, warm orange/cream and midnight ink, transparent background, app-icon legibility. Asset: `assets/branding/atl-haps-logo.png`.

## Release

Version 1.0.0+1 is a device-test build signed with the development key. Google Play publication requires a separate release signing configuration, store materials, data safety review, and additional source coverage/permission review. No Google Play publication is performed in this task.
