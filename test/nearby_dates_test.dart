import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atlanta_events/event.dart';
import 'package:atlanta_events/event_service.dart';
import 'package:atlanta_events/main.dart';

class LocalEvents extends EventService {
  @override
  Future<List<Hap>> live() async => parseDirtySouth('''
    <div data-testid="richTextElement"><h2>Tuesdays<br>
    Parkgrounds, Reynoldstown - 7:00❔</h2></div>
    <div data-testid="richTextElement"><h2>Wednesdays<br>
    Industry Tavern, Buckhead - 8:00❔</h2></div>''');
}

class LocalLocation extends GeolocatorPlatform {
  Completer<Position>? pending;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => pending == null ? position : pending!.future;
  Position get position => Position(
    longitude: -84.354791,
    latitude: 33.750114,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

Future<void> chooseDay(WidgetTester tester, DateTime target) async {
  final dropdown = find.byType(DropdownButton<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose date').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    DateFormat.yMd().format(target),
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  late LocalLocation location;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    location = LocalLocation();
    GeolocatorPlatform.instance = location;
  });
  testWidgets('Dirty South remains visible for its chosen day in Near me', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: Explore(eventService: LocalEvents())),
    );
    await tester.pumpAndSettle();
    final today = DateUtils.dateOnly(DateTime.now());
    final tuesday = today.add(
      Duration(days: (DateTime.tuesday - today.weekday + 7) % 7),
    );
    await chooseDay(tester, tuesday);
    expect(find.text(DateFormat('EEE, MMM d').format(tuesday)), findsOneWidget);
    expect(find.textContaining('Parkgrounds'), findsOneWidget);
    await tester.ensureVisible(find.text('Near me'));
    await tester.tap(find.text('Near me'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Parkgrounds'), findsOneWidget);
    expect(find.textContaining('Industry Tavern'), findsNothing);
    expect(find.text('Every Tuesday · 7:00 PM'), findsOneWidget);
    // Changing date while the distance filter is active changes the weekday.
    await chooseDay(tester, tuesday.add(const Duration(days: 1)));
    expect(find.textContaining('Industry Tavern'), findsOneWidget);
    expect(find.textContaining('Parkgrounds'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A delayed GPS result cannot undo switching back to Atlanta', (
    tester,
  ) async {
    location.pending = Completer<Position>();
    await tester.pumpWidget(
      MaterialApp(home: Explore(eventService: LocalEvents())),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Near me'));
    await tester.tap(find.text('Near me'));
    await tester.pump();
    await tester.tap(find.text('Atlanta'));
    await tester.pump();
    location.pending!.complete(location.position);
    await tester.pumpAndSettle();
    expect(find.text('Within 25 mi'), findsNothing);
    expect(find.text('Near me'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
