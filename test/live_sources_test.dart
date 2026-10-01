import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:atlanta_events/event_service.dart';

void main() {
  test(
    'Live source audit',
    () async {
      final service = EventService();
      addTearDown(service.close);
      final events = await service.live();
      final counts = <String, int>{};
      for (final event in events) {
        counts.update(event.source, (n) => n + 1, ifAbsent: () => 1);
      }
      // Developer audit: opt in so regular tests stay deterministic and offline.
      debugPrint('$counts');
      debugPrint('${service.sourceStatus}');
      debugPrint(
        events
            .where((e) => e.category == 'Festivals')
            .map((e) => '${e.title}: ${e.start}')
            .take(10)
            .toList()
            .toString(),
      );
      expect(counts['Team Trivia'], greaterThan(0));
      expect(counts['Creative Loafing'], greaterThan(0));
      expect(counts['Virginia Highland District'], greaterThan(0));
    },
    skip: !const bool.fromEnvironment('LIVE_SOURCES'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
