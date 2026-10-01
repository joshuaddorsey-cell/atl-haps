import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'event.dart';
import 'event_service.dart';

const ink = Color(0xff101d2f);
const peach = Color(0xffff985a);
const paper = Color(0xfffaf6ef);
void main() => runApp(const AtlHaps());

class AtlHaps extends StatelessWidget {
  const AtlHaps({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ATL Haps',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: peach,
        primary: ink,
        secondary: peach,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w900,
          color: ink,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const Explore(),
  );
}

class Explore extends StatefulWidget {
  const Explore({super.key});
  @override
  State<Explore> createState() => _ExploreState();
}

class _ExploreState extends State<Explore> with WidgetsBindingObserver {
  Timer? refreshTimer;
  DateTime? selectedDay;
  final service = EventService();
  List<Hap> events = [];
  Set<String> saved = {};
  String category = 'All',
      query = '',
      date = 'Today',
      status = 'Loading Atlanta happenings…';
  bool refreshing = false, locating = false, nearby = false;
  int tab = 0;
  double? lat, lon;
  double radius = 25;
  SharedPreferences? prefs;
  static const categories = [
    'All',
    'Trivia',
    'Nightlife',
    'Music',
    'Festivals',
    'Arts',
    'Sports',
    'Community',
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => refresh(),
    );
    load();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    service.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> changeDate(String value) async {
    if (value == 'Choose date') {
      final day = await showDatePicker(
        context: context,
        initialDate: selectedDay ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (day == null || !mounted) return;
      setState(() {
        selectedDay = day;
        date = value;
      });
    } else {
      setState(() {
        date = value;
        selectedDay = null;
      });
    }
  }

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    var initial = <Hap>[];
    final cache = prefs!.getString('events');
    if (cache != null) {
      try {
        initial = (jsonDecode(cache) as List)
            .map((e) => Hap.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      events = initial;
      saved = prefs!.getStringList('saved')?.toSet() ?? {};
      status = cache == null
          ? 'Venue listings • saved October 1, 2026'
          : 'Saved listings • ${prefs!.getString('updated') ?? 'last visit'}';
    });
    refresh();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final fresh = await service.live();
      final all = {
        for (final e in events.where(
          (e) => service.failedSources.contains(e.source),
        ))
          e.id: e,
        for (final e in fresh) e.id: e,
      }.values.toList();
      final updated = DateFormat('MMM d, h:mm a').format(DateTime.now());
      await prefs?.setString(
        'events',
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
      await prefs?.setString('updated', updated);
      if (mounted) {
        setState(() {
          events = all;
          status = service.failedSources.isEmpty
              ? 'Calendars refreshed • $updated'
              : 'Updated • $updated • Some sources unavailable; saved entries retained';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              status = 'Offline or source unavailable • showing saved listings',
        );
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> location() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on location services and try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Allow location for ATL Haps in your phone settings.');
      }
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission declined. You can still explore Atlanta.',
        );
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (mounted) {
        setState(() {
          lat = p.latitude;
          lon = p.longitude;
          nearby = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  DateTime occurrence(Hap e) {
    if (!e.recurring) return e.start;
    final now = selectedDay ?? DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      e.start.hour,
      e.start.minute,
    );
    next = next.add(Duration(days: (e.start.weekday - now.weekday + 7) % 7));
    return next;
  }

  List<Hap> get visible {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = events.where((e) {
      if (!e.recurring && date != 'Choose date' && !e.upcoming(now)) {
        return false;
      }
      if (tab == 1 && !saved.contains(e.id)) return false;
      if (category != 'All' && e.category != category) return false;
      if (!'${e.title} ${e.venue} ${e.address} ${e.description}'
          .toLowerCase()
          .contains(query.toLowerCase())) {
        return false;
      }
      final when = occurrence(e);
      final target = date == 'Today' ? today : selectedDay;
      if (target != null &&
          (e.recurring
              ? e.start.weekday != target.weekday
              : !e.occursOn(target))) {
        return false;
      }
      if (date == 'Next 7 days' &&
          !when.isBefore(today.add(const Duration(days: 7)))) {
        return false;
      }
      if (nearby && lat != null) {
        final d = e.milesFrom(lat!, lon!);
        if (d == null || d > radius) return false;
      }
      return true;
    }).toList();
    out.sort(
      (a, b) => nearby && lat != null
          ? (a.milesFrom(lat!, lon!) ?? 9999).compareTo(
              b.milesFrom(lat!, lon!) ?? 9999,
            )
          : occurrence(a).compareTo(occurrence(b)),
    );
    return out;
  }

  void toggle(Hap e) {
    setState(() => saved.contains(e.id) ? saved.remove(e.id) : saved.add(e.id));
    prefs?.setStringList('saved', saved.toList());
  }

  Future<void> open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open link. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = visible;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/branding/atl-haps-logo.png',
              width: 42,
              height: 42,
            ),
            const SizedBox(width: 9),
            const Text(
              'ATL Haps',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Event sources and neighborhood bars',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: FractionallySizedBox(
                  heightFactor: .8,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        'Neighborhood bars & sources',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Schedules are checked online when events refresh. Some bars post only on social media; a connected website does not guarantee a complete calendar.',
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        title: const Text('Team Trivia'),
                        subtitle: Text(
                          service.sourceStatus['Team Trivia'] ??
                              'Checking live metro Atlanta schedules…',
                        ),
                        onTap: () => open(
                          Uri.parse(
                            'https://www.teamtrivia.com/trivia-in-atlanta/',
                          ),
                        ),
                      ),
                      ListTile(
                        title: const Text('Creative Loafing'),
                        subtitle: Text(
                          service.sourceStatus['Creative Loafing'] ??
                              'Checking music, arts and festivals…',
                        ),
                        onTap: () => open(
                          Uri.parse(
                            'https://creativeloafing.com/atlanta-events',
                          ),
                        ),
                      ),
                      ListTile(
                        title: const Text('Discover Atlanta'),
                        subtitle: const Text(
                          'Open the live festival calendar • direct feed unavailable',
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => open(
                          Uri.parse('https://discoveratlanta.com/events/main/'),
                        ),
                      ),
                      for (final source in {
                        'Dirty South Trivia':
                            'https://www.dirtysouthtrivia.com/',
                        'Access Atlanta': 'https://events.accessatlanta.com/',
                        'Eventbrite':
                            'https://www.eventbrite.com/d/ga--atlanta/events/',
                      }.entries)
                        ListTile(
                          title: Text(source.key),
                          subtitle: Text(
                            service.sourceStatus[source.key] ??
                                (source.key == 'Eventbrite'
                                    ? 'Open live calendar • direct import blocked'
                                    : 'Waiting for refresh'),
                          ),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => open(Uri.parse(source.value)),
                        ),
                      ...EventService.venues.entries.map(
                        (v) => ListTile(
                          title: Text(v.key),
                          isThreeLine: true,
                          subtitle: Text(
                            '${service.sourceStatus[v.key] ?? 'Waiting for refresh'}${v.key == 'Limerick Junction' ? '\nWednesday trivia reported by you; website currently advertises poker.' : ''}',
                          ),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => open(Uri.parse(v.value)),
                        ),
                      ),
                      ListTile(
                        title: const Text('Dad’s on Instagram'),
                        subtitle: const Text('Official social updates'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => open(
                          Uri.parse('https://www.instagram.com/dadsatl/'),
                        ),
                      ),
                      ListTile(
                        title: const Text('Virginia Highland District'),
                        subtitle: Text(
                          service.sourceStatus['Virginia Highland District'] ??
                              'Checking public calendar feed…',
                        ),
                        onTap: () => open(
                          Uri.parse(
                            'https://www.virginiahighlanddistrict.com/events',
                          ),
                        ),
                      ),
                      ...[
                        ('Dad’s', 33.7783, -84.3531),
                        ('Atkins Park Tavern', 33.7766, -84.3526),
                      ].map(
                        (v) => ListTile(
                          title: Text('Directions to ${v.$1}'),
                          trailing: const Icon(Icons.directions),
                          onTap: () => open(
                            Uri.https('www.google.com', '/maps/dir/', {
                              'api': '1',
                              'destination': '${v.$2},${v.$3}',
                              'travelmode': 'driving',
                            }),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: refreshing ? null : refresh,
            tooltip: 'Refresh events',
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GO OUT. FIND YOUR PEOPLE.',
                        style: TextStyle(
                          color: peach,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tab == 1
                            ? 'Your next\ngood time.'
                            : 'What’s happening\nin the ATL?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Big nights. Neighborhood gems.\nEven trivia at your favorite bar.',
                        style: TextStyle(color: Color(0xffcbd1da), height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: nearby ? Colors.white : peach,
                              foregroundColor: ink,
                            ),
                            onPressed: () => setState(() => nearby = false),
                            icon: const Icon(Icons.location_city, size: 18),
                            label: const Text('Atlanta'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: nearby ? peach : Colors.white,
                              side: const BorderSide(color: Color(0xff637087)),
                            ),
                            onPressed: locating ? null : location,
                            icon: Icon(
                              locating
                                  ? Icons.hourglass_top
                                  : Icons.my_location,
                              size: 18,
                            ),
                            label: Text(locating ? 'Finding you…' : 'Near me'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  onChanged: (s) => setState(() => query = s),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find trivia, music, a venue…',
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s),
                              selected: category == s,
                              onSelected: (_) => setState(() => category = s),
                              selectedColor: peach,
                              showCheckmark: false,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: date,
                      underline: const SizedBox(),
                      items: ['Today', 'Next 7 days', 'Any day', 'Choose date']
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (s) => changeDate(s!),
                    ),
                    if (nearby)
                      DropdownButton<double>(
                        value: radius,
                        underline: const SizedBox(),
                        items: [5.0, 10.0, 25.0, 50.0]
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text('Within ${d.toInt()} mi'),
                              ),
                            )
                            .toList(),
                        onChanged: (d) => setState(() => radius = d!),
                      ),
                  ],
                ),
                if (nearby)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Atlanta coverage • showing venues with known map locations',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                Row(
                  children: [
                    Text(
                      '${list.length} happenings',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    const Spacer(),
                    if (nearby)
                      const Text(
                        'Nearest first',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.explore_outlined,
                          size: 42,
                          color: ink,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tab == 1
                              ? 'Save something worth going to.'
                              : 'No matching happenings yet.',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Try another category, date, or Atlanta mode.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ...list.map((e) => card(e)),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Schedules can change. Check the organizer before heading out. Event hours are separate from venue opening hours.',
                    style: TextStyle(color: Colors.black54, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String scheduleLabel(Hap e, DateTime when) {
    if (e.allDay) {
      return '${DateFormat('EEE, MMM d').format(when.toLocal())} • Check daily hours';
    }
    if (e.recurring) {
      return 'Every ${DateFormat('EEEE').format(e.start)} · ${DateFormat('h:mm a').format(e.start)}${e.end == null ? '' : ' – ${DateFormat('h:mm a').format(e.end!)}'}';
    }
    final start = e.start.toLocal();
    final end = e.end?.toLocal();
    if (end != null &&
        DateUtils.dateOnly(end).difference(DateUtils.dateOnly(start)).inDays >
            1) {
      return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(end)} • Check daily hours';
    }
    return '${DateFormat('EEE, MMM d').format(when.toLocal())} · ${DateFormat('h:mm a').format(when.toLocal())}';
  }

  Widget card(Hap e) {
    final when = occurrence(e);
    final distance = lat == null ? null : e.milesFrom(lat!, lon!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => details(e),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: peach.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.category.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: saved.contains(e.id)
                          ? 'Unsave event'
                          : 'Save event',
                      onPressed: () => toggle(e),
                      icon: Icon(
                        saved.contains(e.id)
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                Text(
                  e.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 10),
                line(Icons.schedule, scheduleLabel(e, when)),
                const SizedBox(height: 6),
                line(
                  Icons.place_outlined,
                  '${e.venue}${distance == null ? '' : ' • ${distance.toStringAsFixed(1)} mi'}',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'View details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => open(e.directions),
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Directions'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget line(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: Colors.black54),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, color: Color(0xff566171)),
        ),
      ),
    ],
  );
  void details(Hap e) {
    final when = occurrence(e);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: paper,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .78,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.category.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xffac4c14),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  line(
                    Icons.calendar_today,
                    e.recurring
                        ? 'Every ${DateFormat('EEEE').format(e.start)} • next ${DateFormat('MMM d').format(when)}'
                        : DateFormat(
                            'EEEE, MMM d, yyyy',
                          ).format(when.toLocal()),
                  ),
                  const SizedBox(height: 10),
                  line(
                    Icons.schedule,
                    (e.allDay
                        ? 'Check organizer for daily opening hours'
                        : '${DateFormat('h:mm a').format(when.toLocal())}${e.end == null ? ' • End time not published' : ' – ${DateFormat('h:mm a').format(e.end!.toLocal())}${e.end!.toLocal().day != e.start.toLocal().day ? ' (next day)' : ''}'}'),
                  ),
                  const SizedBox(height: 10),
                  line(Icons.place, '${e.venue}\n${e.address}'),
                  const SizedBox(height: 20),
                  Text(
                    e.description.isEmpty
                        ? 'Check the organizer listing for event details.'
                        : e.description,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                  ),
                  if (e.recurring)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Recurring schedule from the venue. Confirm this week with the venue.',
                      ),
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => open(e.directions),
                      icon: const Icon(Icons.directions),
                      label: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Google Maps directions'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => open(Uri.parse(e.url)),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text('Organizer • ${e.source}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
