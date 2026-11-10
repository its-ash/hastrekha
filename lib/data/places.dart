import 'dart:convert';

import 'package:flutter/services.dart';

/// A birth place with the coordinates the chart needs.
class Place {
  const Place({required this.name, required this.region, required this.latitude, required this.longitude, this.utcOffsetMinutes});

  final String name;

  /// State and/or country, shown under the name.
  final String region;
  final double latitude;
  final double longitude;

  /// Standard time zone of the place (no summer time), when known.
  final int? utcOffsetMinutes;

  String get label => region.isEmpty ? name : '$name, $region';

  String get coordinates {
    String f(double v, String pos, String neg) => '${v.abs().toStringAsFixed(2)}° ${v >= 0 ? pos : neg}';
    return '${f(latitude, 'N', 'S')}, ${f(longitude, 'E', 'W')}';
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'region': region,
        'lat': latitude,
        'lon': longitude,
        'tz': utcOffsetMinutes,
      };

  static Place? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = (j['lat'] as num?)?.toDouble(), lon = (j['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return Place(
      name: j['name'] as String? ?? '',
      region: j['region'] as String? ?? '',
      latitude: lat,
      longitude: lon,
      utcOffsetMinutes: (j['tz'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => label;
}

/// The offline list of cities in `assets/geo/cities.json`.
class Places {
  Places._(this.all);
  final List<Place> all;

  static Places? _cache;

  static Future<Places> load([AssetBundle? bundle]) async {
    final cached = _cache;
    if (cached != null && bundle == null) return cached;
    final raw = jsonDecode(await (bundle ?? rootBundle).loadString('assets/geo/cities.json')) as Map;
    final list = <Place>[
      for (final c in raw['cities'] as List)
        Place(
          name: c[0] as String,
          region: c[1] as String,
          latitude: (c[2] as num).toDouble(),
          longitude: (c[3] as num).toDouble(),
          utcOffsetMinutes: (c[4] as num).toInt(),
        ),
    ];
    return _cache = Places._(list);
  }

  /// Cities whose name starts with [query] first, then those that
  /// contain it in the name or region.
  List<Place> search(String query, {int limit = 8}) {
    final q = _fold(query.trim());
    if (q.isEmpty) return const [];
    final starts = <Place>[], contains = <Place>[];
    for (final p in all) {
      final n = _fold(p.name);
      if (n.startsWith(q) || n.split(RegExp(r'[\s(\-]+')).any((w) => w.startsWith(q))) {
        starts.add(p);
      } else if (n.contains(q) || _fold(p.region).contains(q)) {
        contains.add(p);
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll('ā', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ã', 'a')
      .replaceAll('ü', 'u');
}
