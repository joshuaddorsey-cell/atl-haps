import 'package:geolocator/geolocator.dart';

class Hap {
  final String id, title, venue, address, category, description, url, source;
  final DateTime start;
  final DateTime? end;
  final double? latitude, longitude;
  final bool recurring;
  const Hap({
    required this.id,
    required this.title,
    required this.venue,
    required this.address,
    required this.category,
    required this.description,
    required this.url,
    required this.source,
    required this.start,
    this.end,
    this.latitude,
    this.longitude,
    this.recurring = false,
  });
  factory Hap.fromJson(Map<String, dynamic> j) => Hap(
    id: j['id'],
    title: j['title'],
    venue: j['venue'],
    address: j['address'],
    category: j['category'],
    description: j['description'],
    url: j['url'],
    source: j['source'],
    start: DateTime.parse(j['start']),
    end: j['end'] == null ? null : DateTime.parse(j['end']),
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    recurring: j['recurring'] ?? false,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'venue': venue,
    'address': address,
    'category': category,
    'description': description,
    'url': url,
    'source': source,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'recurring': recurring,
  };
  double? milesFrom(double lat, double lon) =>
      latitude == null || longitude == null
      ? null
      : Geolocator.distanceBetween(lat, lon, latitude!, longitude!) / 1609.344;
  Uri get directions => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$venue, $address',
    'travelmode': 'driving',
  });
  bool occursOn(DateTime day) {
    final begin = DateTime(day.year, day.month, day.day);
    final finish = begin.add(const Duration(days: 1));
    return start.isBefore(finish) &&
        (end ?? start.add(const Duration(hours: 3))).isAfter(begin);
  }

  bool upcoming(DateTime now) =>
      (end ?? start.add(const Duration(hours: 3))).isAfter(now);
}

String categorize(String text) {
  final s = text.toLowerCase();
  if (s.contains('trivia')) return 'Trivia';
  if (s.contains('karaoke') ||
      s.contains('bingo') ||
      s.contains('dj ') ||
      s.contains('nightlife')) {
    return 'Nightlife';
  }
  if (s.contains('festival') || s.contains('parade')) return 'Festivals';
  if (s.contains('sport') ||
      s.contains('braves') ||
      s.contains('hawks') ||
      s.contains('soccer') ||
      s.contains('football')) {
    return 'Sports';
  }
  if (s.contains('museum') ||
      s.contains('art ') ||
      s.contains('theatre') ||
      s.contains('film')) {
    return 'Arts';
  }
  if (s.contains('market') || s.contains('community') || s.contains('family')) {
    return 'Community';
  }
  return 'Music';
}
