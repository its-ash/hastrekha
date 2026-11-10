import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/reading/astro.dart';
import 'package:hastrekha/reading/chart.dart';
import 'package:hastrekha/reading/name_sign.dart';
import 'package:hastrekha/reading/palm_features.dart';
import 'package:hastrekha/reading/unified.dart';

import 'kb_test.dart' show loadKb;

double _gap(double a, double b) => ((a - b + 540) % 360 - 180).abs();

double _trop(String p, DateTime utc) => Ephemeris.tropicalLongitude(p, Astro.julianDay(utc));

void main() {
  test('Sun at J2000', () {
    expect(_gap(_trop('sun', DateTime.utc(2000, 1, 1, 12)), 280.4), lessThan(0.3));
  });

  test('great conjunction of Jupiter and Saturn, 21 Dec 2020', () {
    final t = DateTime.utc(2020, 12, 21, 18);
    final j = _trop('jupiter', t), s = _trop('saturn', t);
    expect(_gap(j, s), lessThan(0.4));
    expect(_gap(j, 300.3), lessThan(0.8));
  });

  test('transit of Venus, 6 Jun 2012: Venus on the Sun and retrograde', () {
    final t = DateTime.utc(2012, 6, 6, 1, 30);
    expect(_gap(_trop('venus', t), _trop('sun', t)), lessThan(0.3));
    expect(_gap(_trop('sun', t), 75.8), lessThan(0.3));
    expect(Ephemeris.speed('venus', t), lessThan(0));
  });

  test('transit of Mercury, 11 Nov 2019', () {
    final t = DateTime.utc(2019, 11, 11, 15, 20);
    expect(_gap(_trop('mercury', t), _trop('sun', t)), lessThan(0.3));
    expect(Ephemeris.speed('mercury', t), lessThan(0));
  });

  test('Mars opposition, 13 Oct 2020', () {
    final t = DateTime.utc(2020, 10, 13, 23, 20);
    expect(_gap(_trop('mars', t), _trop('sun', t) + 180), lessThan(1.0));
    expect(Ephemeris.speed('mars', t), lessThan(0));
  });

  test('lagna equals the Sun at sunrise (Delhi, March equinox 2024)', () {
    // Sunrise in New Delhi on 20 Mar 2024 is about 06:24 IST.
    final t = DateTime.utc(2024, 3, 20, 0, 54);
    final asc = Ephemeris.ascendant(t, latitude: 28.61, longitude: 77.21);
    final sun = Ephemeris.siderealLongitude('sun', t);
    expect(_gap(asc, sun), lessThan(2.5));
  });

  test('the lagna passes through all twelve signs in a day', () {
    final signs = <int>{};
    for (var m = 0; m < 24 * 60; m += 20) {
      final t = DateTime.utc(2024, 1, 1).add(Duration(minutes: m));
      signs.add((Ephemeris.ascendant(t, latitude: 19.08, longitude: 72.88) / 30).floor());
    }
    expect(signs, hasLength(12));
  });

  test('chart: houses, dignity and dasha', () {
    // 15 Aug 1990, 10:30 IST, Mumbai.
    final utc = DateTime.utc(1990, 8, 15, 5, 0);
    final c = BirthChart.compute(utc, latitude: 19.08, longitude: 72.88);
    expect(c.lagna, isNotNull);
    for (final p in c.planets.values) {
      expect(p.house, inInclusiveRange(1, 12));
      expect(p.nakshatra, inInclusiveRange(1, 27));
    }
    // Rahu and Ketu are always opposite.
    expect(_gap(c.planets['rahu']!.longitude, c.planets['ketu']!.longitude + 180), lessThan(0.001));
    // The Sun is in sidereal Cancer in mid-August.
    expect(c.planets['sun']!.sign, 'cancer');

    final md = c.mahadashas();
    expect(md.first.contains(utc), isTrue);
    expect(md.first.lord, Astro.rulerOfNakshatra(c.moon.nakshatra));
    for (var i = 1; i < md.length; i++) {
      expect(md[i].start, md[i - 1].end);
    }
    final now = c.dashaAt(DateTime.utc(2026, 1, 1));
    expect(now, isNotNull);
    expect(now!.main.contains(DateTime.utc(2026, 1, 1)), isTrue);
    final subs = BirthChart.antardashas(now.main);
    expect(subs.first.lord, now.main.lord);
    expect(subs.last.end.difference(now.main.end).inHours.abs(), lessThan(2));
  });

  test('without time or place there is no lagna', () {
    final c = BirthChart.compute(DateTime.utc(1990, 8, 15, 6, 30), timeKnown: false, latitude: 19.08, longitude: 72.88);
    expect(c.lagna, isNull);
    expect(c.planets['moon']!.house, isNull);
  });

  test('dignities', () {
    expect(BirthChart.dignityOf('sun', 0), Dignity.exalted);
    expect(BirthChart.dignityOf('sun', 6), Dignity.debilitated);
    expect(BirthChart.dignityOf('jupiter', 8), Dignity.own);
    expect(BirthChart.dignityOf('saturn', 6), Dignity.exalted);
    expect(BirthChart.dignityOf('rahu', 3), Dignity.neutral);
  });

  test('unified reading combines palm and chart', () {
    final kb = loadKb();
    final chart = BirthChart.compute(DateTime.utc(1990, 8, 15, 5, 0), latitude: 19.08, longitude: 72.88);
    // A palm with a raised Jupiter mound and a clear Sun line.
    final palm = PalmFeatures(element: 'fire')
      ..mounds['jupiter'] = 'raised'
      ..mounds['saturn'] = 'flat'
      ..lines['sun'] = LineFeature(present: true, depth: 'deep');
    final u = UnifiedReading.build(palm: palm, chart: chart, kb: kb, nameSign: NameSign.of('Asha'), now: DateTime.utc(2026, 1, 1));
    expect(u.verdicts, hasLength(9));
    expect(u.verdicts.firstWhere((v) => v.planet == 'jupiter').palm, Strength.strong);
    expect(u.verdicts.firstWhere((v) => v.planet == 'saturn').palm, Strength.weak);
    final ids = u.summary.map((r) => r.id).toSet();
    expect(ids, containsAll(['unified.lagna', 'unified.dasha', 'unified.name']));
    for (final r in [...u.summary, ...u.planetInsights]) {
      expect(r.text.en, isNotEmpty);
      expect(r.text.hi, isNot(r.text.en), reason: '${r.id} has Hindi');
      expect(r.text.en.toLowerCase(), isNot(contains('death')));
    }
  });

  test('name sign from the first syllable', () {
    String? sign(String n) => NameSign.of(n)?.rashi;
    expect(sign('Rahul'), 'libra');
    expect(sign('Amit'), 'aries');
    expect(sign('Mohan'), 'leo');
    expect(sign('Priya'), 'virgo');
    expect(sign('Deepak'), 'pisces');
    expect(sign('Chandra'), 'pisces');
    expect(sign('Vikram'), 'taurus');
    expect(sign('Ganesh'), 'capricorn');
    expect(sign('Kavya'), 'gemini');
    expect(sign('Yash'), 'scorpio');
    expect(sign('राहुल'), 'libra');
    expect(sign('दीपक'), 'pisces');
    expect(sign('टीना'), 'leo');
    expect(sign('श्याम'), 'aquarius');
    expect(NameSign.of('Rahul')!.ruler, 'venus');
    expect(sign(''), isNull);
  });
}
