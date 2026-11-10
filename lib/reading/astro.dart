import 'dart:math' as math;

/// Offline Moon position, enough to find the nakshatra and rashi.
///
/// Uses the main periodic terms of the lunar theory in Meeus,
/// *Astronomical Algorithms* ch. 47 (error well under 0.05°, much less
/// than the 13°20' width of a nakshatra), and the Lahiri ayanamsa for
/// the sidereal zodiac used in Jyotish.
abstract final class Astro {
  static const nakshatraSpan = 360 / 27;

  static double julianDay(DateTime utc) => 2440587.5 + utc.toUtc().millisecondsSinceEpoch / 86400000.0;

  /// Tropical (Western) ecliptic longitude of the Moon, degrees.
  static double moonTropicalLongitude(DateTime utc) {
    final t = (julianDay(utc) - 2451545.0) / 36525.0;
    double norm(double d) => (d % 360 + 360) % 360;
    final lp = norm(218.3164477 + 481267.88123421 * t);
    final d = norm(297.8501921 + 445267.1114034 * t);
    final m = norm(357.5291092 + 35999.0502909 * t);
    final mp = norm(134.9633964 + 477198.8675055 * t);
    final f = norm(93.2720950 + 483202.0175233 * t);
    final e = 1 - 0.002516 * t - 0.0000074 * t * t;
    final a1 = norm(119.75 + 131.849 * t);
    final a2 = norm(53.09 + 479264.290 * t);

    double s(double deg) => math.sin(deg * math.pi / 180);
    // (D, M, M', F, coefficient in 1e-6 degrees)
    const terms = <List<num>>[
      [0, 0, 1, 0, 6288774], [2, 0, -1, 0, 1274027], [2, 0, 0, 0, 658314],
      [0, 0, 2, 0, 213618], [0, 1, 0, 0, -185116], [0, 0, 0, 2, -114332],
      [2, 0, -2, 0, 58793], [2, -1, -1, 0, 57066], [2, 0, 1, 0, 53322],
      [2, -1, 0, 0, 45758], [0, 1, -1, 0, -40923], [1, 0, 0, 0, -34720],
      [0, 1, 1, 0, -30383], [2, 0, 0, -2, 15327], [0, 0, 1, 2, -12528],
      [0, 0, 1, -2, 10980], [4, 0, -1, 0, 10675], [0, 0, 3, 0, 10034],
      [4, 0, -2, 0, 8548], [2, 1, -1, 0, -7888], [2, 1, 0, 0, -6766],
      [1, 0, -1, 0, -5163], [1, 1, 0, 0, 4987], [2, -1, 1, 0, 4036],
      [2, 0, 2, 0, 3994], [4, 0, 0, 0, 3861], [2, 0, -3, 0, 3665],
      [0, 1, -2, 0, -2689], [2, 0, -1, 2, -2602], [2, -1, -2, 0, 2390],
      [1, 0, 1, 0, -2348], [2, -2, 0, 0, 2236], [0, 1, 2, 0, -2120],
      [0, 2, 0, 0, -2069], [2, -2, -1, 0, 2048], [2, 0, 1, -2, -1773],
      [2, 0, 0, 2, -1595], [4, -1, -1, 0, 1215], [0, 0, 2, 2, -1110],
    ];
    var sum = 0.0;
    for (final tm in terms) {
      final cm = tm[1].abs();
      final ecc = cm == 1 ? e : (cm == 2 ? e * e : 1.0);
      final arg = tm[0] * d + tm[1] * m + tm[2] * mp + tm[3] * f;
      sum += tm[4] * ecc * s(arg.toDouble());
    }
    sum += 3958 * s(a1) + 1962 * s(lp - f) + 318 * s(a2);
    return norm(lp + sum / 1e6);
  }

  /// Lahiri (Chitrapaksha) ayanamsa in degrees, linear approximation
  /// good to about 0.01° over 1900-2100.
  static double lahiriAyanamsa(DateTime utc) {
    final years = (julianDay(utc) - 2451545.0) / 365.25;
    return 23.853 + years * (50.2788 / 3600);
  }

  static double moonSiderealLongitude(DateTime utc) {
    final l = moonTropicalLongitude(utc) - lahiriAyanamsa(utc);
    return (l % 360 + 360) % 360;
  }

  /// Birth star from the sidereal Moon.
  static MoonPlacement moonPlacement(DateTime utc) {
    final lon = moonSiderealLongitude(utc);
    final idx = (lon / nakshatraSpan).floor() % 27;
    final within = lon - idx * nakshatraSpan;
    return MoonPlacement(
      longitude: lon,
      nakshatra: idx + 1,
      pada: (within / (nakshatraSpan / 4)).floor() + 1,
      rashiIndex: (lon / 30).floor() % 12,
      progress: within / nakshatraSpan,
    );
  }

  static const rashiKeys = [
    'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
    'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
  ];

  /// Planet ruling each weekday (Monday = 1 ... Sunday = 7), as in
  /// the Vedic week (vara).
  static const weekdayRuler = {
    DateTime.monday: 'moon',
    DateTime.tuesday: 'mars',
    DateTime.wednesday: 'mercury',
    DateTime.thursday: 'jupiter',
    DateTime.friday: 'venus',
    DateTime.saturday: 'saturn',
    DateTime.sunday: 'sun',
  };

  /// Nakshatra rulers in order (Vimshottari sequence from Ashwini).
  static const nakshatraRulers = [
    'ketu', 'venus', 'sun', 'moon', 'mars', 'rahu', 'jupiter', 'saturn', 'mercury',
  ];

  static String rulerOfNakshatra(int index) => nakshatraRulers[(index - 1) % 9];
}

class MoonPlacement {
  const MoonPlacement({
    required this.longitude,
    required this.nakshatra,
    required this.pada,
    required this.rashiIndex,
    required this.progress,
  });

  /// Sidereal longitude, degrees.
  final double longitude;

  /// 1..27, Ashwini = 1.
  final int nakshatra;

  /// Quarter of the nakshatra, 1..4.
  final int pada;

  /// 0 = Aries ... 11 = Pisces.
  final int rashiIndex;

  /// How far through the nakshatra (0..1). Near 0 or 1 the birth time
  /// matters: a small error can change the star.
  final double progress;

  String get rashi => Astro.rashiKeys[rashiIndex];
}
