import 'dart:math' as math;

import 'astro.dart';

/// Offline Vedic birth chart (kundali): sidereal positions of the nine
/// grahas, the ascendant (lagna), whole-sign houses, dignities and the
/// Vimshottari dasha periods.
///
/// Planets use the JPL Keplerian elements for 1800–2050 (Standish,
/// "Approximate Positions of the Planets"), good to well under a degree:
/// far finer than a sign (30°) or a nakshatra (13°20'). The Moon comes
/// from [Astro.moonTropicalLongitude]. Longitudes are converted to the
/// sidereal zodiac with the Lahiri ayanamsa, as in Jyotish.
abstract final class Ephemeris {
  static const planets = ['sun', 'moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'rahu', 'ketu'];

  // a (AU), e, I, L, long. perihelion, long. node (deg), then rates per
  // Julian century, J2000 ecliptic and equinox.
  static const _elements = <String, List<double>>{
    'mercury': [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593, //
        0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081],
    'venus': [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255, //
        0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418],
    'earth': [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0, //
        0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0],
    'mars': [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891, //
        0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343],
    'jupiter': [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909, //
        -0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106],
    'saturn': [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448, //
        -0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794],
  };

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;
  static double norm(double d) => (d % 360 + 360) % 360;

  /// Heliocentric ecliptic position (J2000), AU.
  static (double, double, double) _helio(String body, double t) {
    final el = _elements[body]!;
    final a = el[0] + el[6] * t;
    final e = el[1] + el[7] * t;
    final i = _rad(el[2] + el[8] * t);
    final l = el[3] + el[9] * t;
    final varpi = el[4] + el[10] * t;
    final node = el[5] + el[11] * t;
    final w = _rad(varpi - node);
    final o = _rad(node);
    final m = _rad(norm(l - varpi + 180) - 180);
    // Kepler's equation.
    var ecc = m + e * math.sin(m);
    for (var k = 0; k < 8; k++) {
      ecc -= (ecc - e * math.sin(ecc) - m) / (1 - e * math.cos(ecc));
    }
    final xp = a * (math.cos(ecc) - e);
    final yp = a * math.sqrt(1 - e * e) * math.sin(ecc);
    final cw = math.cos(w), sw = math.sin(w), co = math.cos(o), so = math.sin(o), ci = math.cos(i), si = math.sin(i);
    final x = (cw * co - sw * so * ci) * xp + (-sw * co - cw * so * ci) * yp;
    final y = (cw * so + sw * co * ci) * xp + (-sw * so + cw * co * ci) * yp;
    final z = (sw * si) * xp + (cw * si) * yp;
    return (x, y, z);
  }

  static double _centuries(double jd) => (jd - 2451545.0) / 36525.0;

  /// Tropical geocentric longitude (equinox of date), degrees.
  static double tropicalLongitude(String planet, double jd) {
    final t = _centuries(jd);
    switch (planet) {
      case 'moon':
        return Astro.moonTropicalLongitude(_dateOf(jd));
      case 'rahu':
        // Mean lunar node (Meeus 47.7), equinox of date.
        return norm(125.0445479 - 1934.1362891 * t + 0.0020754 * t * t);
      case 'ketu':
        return norm(tropicalLongitude('rahu', jd) + 180);
    }
    final (ex, ey, _) = _helio('earth', t);
    double gx, gy;
    if (planet == 'sun') {
      gx = -ex;
      gy = -ey;
    } else {
      final (px, py, _) = _helio(planet, t);
      gx = px - ex;
      gy = py - ey;
    }
    // J2000 → equinox of date: general precession in longitude.
    return norm(_deg(math.atan2(gy, gx)) + 1.396971 * t);
  }

  static DateTime _dateOf(double jd) =>
      DateTime.fromMillisecondsSinceEpoch(((jd - 2440587.5) * 86400000).round(), isUtc: true);

  static double siderealLongitude(String planet, DateTime utc) {
    final jd = Astro.julianDay(utc);
    return norm(tropicalLongitude(planet, jd) - Astro.lahiriAyanamsa(utc));
  }

  /// Daily motion in degrees (negative = retrograde).
  static double speed(String planet, DateTime utc) {
    final jd = Astro.julianDay(utc);
    final a = tropicalLongitude(planet, jd - 0.5), b = tropicalLongitude(planet, jd + 0.5);
    return norm(b - a + 180) - 180;
  }

  /// Sidereal ascendant (lagna) for a place, degrees.
  static double ascendant(DateTime utc, {required double latitude, required double longitude}) {
    final jd = Astro.julianDay(utc);
    final t = _centuries(jd);
    final gmst = norm(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * t * t - t * t * t / 38710000);
    final ramc = _rad(norm(gmst + longitude));
    final eps = _rad(23.439291 - 0.0130042 * t);
    final phi = _rad(latitude.clamp(-66.0, 66.0));
    final asc = _deg(math.atan2(math.cos(ramc), -(math.sin(ramc) * math.cos(eps) + math.tan(phi) * math.sin(eps))));
    return norm(asc - Astro.lahiriAyanamsa(utc));
  }
}

/// A planet's standing by sign.
enum Dignity { exalted, own, friendly, neutral, enemy, debilitated }

/// One graha in the birth chart.
class PlanetPlacement {
  const PlanetPlacement({
    required this.key,
    required this.longitude,
    required this.retrograde,
    required this.house,
    required this.dignity,
    required this.combust,
  });

  final String key;

  /// Sidereal longitude, degrees.
  final double longitude;
  final bool retrograde;

  /// Whole-sign house from the lagna (1..12), or null when the birth time
  /// or place is unknown.
  final int? house;
  final Dignity dignity;

  /// Too close to the Sun, which weakens it.
  final bool combust;

  int get signIndex => (longitude / 30).floor() % 12;
  String get sign => Astro.rashiKeys[signIndex];
  double get degreeInSign => longitude - signIndex * 30;
  int get nakshatra => (longitude / Astro.nakshatraSpan).floor() % 27 + 1;
  int get pada => ((longitude % Astro.nakshatraSpan) / (Astro.nakshatraSpan / 4)).floor() + 1;
}

/// How strong a planet is, read from the chart or from the palm.
enum Strength { weak, moderate, strong }

/// A Vimshottari period.
class DashaPeriod {
  const DashaPeriod(this.lord, this.start, this.end);
  final String lord;
  final DateTime start;
  final DateTime end;
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

class BirthChart {
  BirthChart._({
    required this.utc,
    required this.timeKnown,
    required this.ascendant,
    required this.planets,
    required this.moon,
  });

  final DateTime utc;
  final bool timeKnown;

  /// Sidereal lagna in degrees; null without birth time and place.
  final double? ascendant;
  final Map<String, PlanetPlacement> planets;
  final MoonPlacement moon;

  int? get lagnaIndex => ascendant == null ? null : (ascendant! / 30).floor() % 12;
  String? get lagna => lagnaIndex == null ? null : Astro.rashiKeys[lagnaIndex!];

  static const signRulers = [
    'mars', 'venus', 'mercury', 'moon', 'sun', 'mercury',
    'venus', 'mars', 'jupiter', 'saturn', 'saturn', 'jupiter',
  ];

  static const _exaltation = {
    'sun': 0, 'moon': 1, 'mars': 9, 'mercury': 5, 'jupiter': 3, 'venus': 11, 'saturn': 6,
  };

  // Natural friendships (naisargika maitri), Parashari.
  static const _friends = {
    'sun': ['moon', 'mars', 'jupiter'],
    'moon': ['sun', 'mercury'],
    'mars': ['sun', 'moon', 'jupiter'],
    'mercury': ['sun', 'venus'],
    'jupiter': ['sun', 'moon', 'mars'],
    'venus': ['mercury', 'saturn'],
    'saturn': ['mercury', 'venus'],
  };
  static const _enemies = {
    'sun': ['venus', 'saturn'],
    'moon': <String>[],
    'mars': ['mercury'],
    'mercury': ['moon'],
    'jupiter': ['mercury', 'venus'],
    'venus': ['sun', 'moon'],
    'saturn': ['sun', 'moon', 'mars'],
  };

  /// Degrees from the Sun within which a planet is combust.
  static const _combustOrb = {'moon': 12.0, 'mars': 17.0, 'mercury': 14.0, 'jupiter': 11.0, 'venus': 10.0, 'saturn': 15.0};

  static Dignity dignityOf(String planet, int sign) {
    final ex = _exaltation[planet];
    if (ex == null) return Dignity.neutral; // Rahu, Ketu
    if (sign == ex) return Dignity.exalted;
    if (sign == (ex + 6) % 12) return Dignity.debilitated;
    final ruler = signRulers[sign];
    if (ruler == planet) return Dignity.own;
    if (_friends[planet]!.contains(ruler)) return Dignity.friendly;
    if (_enemies[planet]!.contains(ruler)) return Dignity.enemy;
    return Dignity.neutral;
  }

  /// Builds the chart. Without [latitude]/[longitude] (or with
  /// [timeKnown] false) there is no lagna and no houses.
  factory BirthChart.compute(DateTime utc, {bool timeKnown = true, double? latitude, double? longitude}) {
    final asc = timeKnown && latitude != null && longitude != null
        ? Ephemeris.ascendant(utc, latitude: latitude, longitude: longitude)
        : null;
    final lagnaIdx = asc == null ? null : (asc / 30).floor() % 12;
    final sun = Ephemeris.siderealLongitude('sun', utc);
    final placements = <String, PlanetPlacement>{};
    for (final p in Ephemeris.planets) {
      final lon = p == 'sun' ? sun : Ephemeris.siderealLongitude(p, utc);
      final sign = (lon / 30).floor() % 12;
      final retro = p == 'rahu' || p == 'ketu' ? true : (p == 'sun' || p == 'moon' ? false : Ephemeris.speed(p, utc) < 0);
      var orb = _combustOrb[p];
      if (orb != null && retro && (p == 'mercury' || p == 'venus')) orb -= 2;
      final gap = (Ephemeris.norm(lon - sun + 180) - 180).abs();
      placements[p] = PlanetPlacement(
        key: p,
        longitude: lon,
        retrograde: retro,
        house: lagnaIdx == null ? null : (sign - lagnaIdx + 12) % 12 + 1,
        dignity: dignityOf(p, sign),
        combust: orb != null && gap < orb,
      );
    }
    return BirthChart._(
      utc: utc,
      timeKnown: timeKnown,
      ascendant: asc,
      planets: placements,
      moon: Astro.moonPlacement(utc),
    );
  }

  static const _malefics = {'sun', 'mars', 'saturn', 'rahu', 'ketu'};

  /// Score behind [strength]: dignity, combustion, house and (for the
  /// Moon) how full it is. Positive is stronger.
  double strengthScore(String planet) {
    final p = planets[planet]!;
    var s = switch (p.dignity) {
      Dignity.exalted => 2.0,
      Dignity.own => 1.5,
      Dignity.friendly => 0.5,
      Dignity.neutral => 0.0,
      Dignity.enemy => -0.5,
      Dignity.debilitated => -2.0,
    };
    if (p.combust) s -= 1;
    final h = p.house;
    if (h != null) {
      if (_malefics.contains(planet) && (h == 3 || h == 6 || h == 11)) {
        s += 0.5;
      } else if ({1, 4, 5, 7, 9, 10}.contains(h)) {
        s += 0.5;
      } else if ({6, 8, 12}.contains(h)) {
        s -= 0.5;
      }
    }
    if (planet == 'moon') {
      final phase = Ephemeris.norm(p.longitude - planets['sun']!.longitude);
      if (phase > 120 && phase < 240) s += 0.5;
      if (phase < 45 || phase > 315) s -= 0.5;
    }
    return s;
  }

  Strength strength(String planet) {
    final s = strengthScore(planet);
    return s >= 1 ? Strength.strong : (s <= -1 ? Strength.weak : Strength.moderate);
  }

  // ---- Vimshottari dasha ------------------------------------------------

  static const dashaYears = {
    'ketu': 7, 'venus': 20, 'sun': 6, 'moon': 10, 'mars': 7,
    'rahu': 18, 'jupiter': 16, 'saturn': 19, 'mercury': 17,
  };

  static DateTime _addYears(DateTime t, double years) =>
      t.add(Duration(milliseconds: (years * 365.25 * 86400000).round()));

  /// Main periods (mahadasha) from before birth to about 120 years later.
  List<DashaPeriod> mahadashas() {
    final order = Astro.nakshatraRulers;
    final first = (moon.nakshatra - 1) % 9;
    final lord = order[first];
    // The period running at birth started before it, in proportion to how
    // far the Moon had gone through its nakshatra.
    var start = _addYears(utc, -moon.progress * dashaYears[lord]!);
    final out = <DashaPeriod>[];
    for (var k = 0; k < 10; k++) {
      final l = order[(first + k) % 9];
      final end = _addYears(start, dashaYears[l]!.toDouble());
      out.add(DashaPeriod(l, start, end));
      start = end;
    }
    return out;
  }

  /// Sub-periods (antardasha) of a main period.
  static List<DashaPeriod> antardashas(DashaPeriod md) {
    final order = Astro.nakshatraRulers;
    final i0 = order.indexOf(md.lord);
    final total = dashaYears[md.lord]!;
    var start = md.start;
    final out = <DashaPeriod>[];
    for (var k = 0; k < 9; k++) {
      final l = order[(i0 + k) % 9];
      final end = _addYears(start, total * dashaYears[l]! / 120);
      out.add(DashaPeriod(l, start, end));
      start = end;
    }
    return out;
  }

  /// The main and sub period running at [now].
  ({DashaPeriod main, DashaPeriod sub})? dashaAt(DateTime now) {
    for (final md in mahadashas()) {
      if (!md.contains(now)) continue;
      for (final ad in antardashas(md)) {
        if (ad.contains(now)) return (main: md, sub: ad);
      }
    }
    return null;
  }
}
