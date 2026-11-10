import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/kb/knowledge_base.dart';
import 'package:hastrekha/reading/astro.dart';
import 'package:hastrekha/reading/palm_features.dart';
import 'package:hastrekha/reading/rules_engine.dart';

KnowledgeBase loadKb() {
  final docs = <Map<String, Object?>>[];
  for (final f in Directory('assets/kb').listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    docs.add((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
  }
  return KnowledgeBase.fromDocuments(docs);
}

/// Allowed values for each `when` key pattern (see docs/KNOWLEDGE_SCHEMA.md).
Set<String>? allowedFor(String key, KnowledgeBase kb) {
  const bool = {'true', 'false'};
  final locations = {...Vocab.locations, 'any'};
  final lineKeys = {...Vocab.primaryLines, ...Vocab.secondaryLines};
  final p = key.split('.');
  if (p.first == 'hand') {
    return switch (p[1]) {
      'element' => {...Vocab.elements},
      'secondary' => {...Vocab.elements, 'none'},
      'palm' => {...Vocab.palmShapes},
      'fingers' => {...Vocab.fingerLengths},
      'line_density' => {...Vocab.densities},
      'side' => {'left', 'right'},
      _ => null,
    };
  }
  if (p.first == 'pattern') return {'simian', 'head_life_joined'}.contains(p[1]) ? bool : null;
  if (p.first == 'mound') {
    if (!Vocab.planets.contains(p[1])) return null;
    return p.length == 3 ? (p[2] == 'crossed' ? bool : null) : {...Vocab.moundLevels};
  }
  if (p.first == 'symbol') return kb.symbols.containsKey(p[1]) ? locations : null;
  if (lineKeys.contains(p.first) && p.length == 2) {
    return switch (p[1]) {
      'present' || 'chained' || 'fork' => bool,
      'length' => {...Vocab.lengths},
      'depth' => {...Vocab.depths},
      'breaks' => {...Vocab.breaks},
      'branches' => {...Vocab.branches},
      'curve' => {...Vocab.curves},
      'start' || 'end' => locations,
      _ => null,
    };
  }
  return null;
}

void main() {
  final kb = loadKb();

  test('knowledge base loads cleanly', () {
    expect(kb.warnings, isEmpty);
    expect(kb.rules.length, greaterThan(250));
    expect(kb.lines.keys, containsAll([...Vocab.primaryLines, ...Vocab.secondaryLines]));
    expect(kb.elements.keys, containsAll(Vocab.elements));
    expect(kb.planets.keys, containsAll(Vocab.planets));
    expect(kb.remedies.keys, containsAll(Vocab.planets));
    expect(kb.rashis, hasLength(12));
    expect(kb.nakshatras.map((e) => e.integer('index')), List.generate(27, (i) => i + 1));
    expect(kb.learn, isNotEmpty);
  });

  test('every rule uses the schema vocabulary', () {
    final problems = <String>[];
    for (final r in kb.rules) {
      if (!Vocab.areas.contains(r.area)) problems.add('${r.id}: area ${r.area}');
      if (!{'positive', 'neutral', 'caution'}.contains(r.tone)) problems.add('${r.id}: tone ${r.tone}');
      if (r.planet != null && !Vocab.planets.contains(r.planet)) problems.add('${r.id}: planet ${r.planet}');
      if (r.text.en.isEmpty || r.text.hi.isEmpty || r.text.hi == r.text.en) problems.add('${r.id}: text');
      for (final e in r.when.entries) {
        final allowed = allowedFor(e.key, kb);
        if (allowed == null) {
          problems.add('${r.id}: key ${e.key}');
          continue;
        }
        for (final v in e.value) {
          if (!allowed.contains(v)) problems.add('${r.id}: ${e.key}=$v');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('yantras are magic squares', () {
    for (final r in kb.remedies.values) {
      final grid = (r.child('yantra')!.raw['grid'] as List).map((row) => (row as List).cast<num>()).toList();
      final sums = <num>{
        for (final row in grid) row.reduce((a, b) => a + b),
        for (var c = 0; c < 3; c++) grid[0][c] + grid[1][c] + grid[2][c],
        grid[0][0] + grid[1][1] + grid[2][2],
        grid[0][2] + grid[1][1] + grid[2][0],
      };
      expect(sums, hasLength(1), reason: r.key);
    }
  });

  test('a typical palm gets insights in several life areas', () {
    final f = PalmFeatures(side: 'right', element: 'fire', secondary: 'air');
    for (final k in Vocab.primaryLines) {
      f.lines[k] = LineFeature(present: true, length: 'long', depth: 'deep');
    }
    f.lines['sun'] = LineFeature(present: true);
    f.mounds['jupiter'] = 'raised';
    f.symbols.add(const SymbolMark('star', 'sun'));
    final reading = RulesEngine(kb).evaluate(f);
    expect(reading.insights.length, greaterThan(15));
    expect(reading.byArea.length, greaterThan(4));
    expect(reading.forLine('life'), isNotEmpty);
    expect(reading.forLine('heart'), isNotEmpty);
    expect(reading.handInsights, isNotEmpty);
    expect(reading.symbolInsights, isNotEmpty);
  });

  test('absent lines only match present:false rules', () {
    final f = PalmFeatures();
    f.lines['fate'] = LineFeature(present: false, length: 'long');
    final r = RulesEngine(kb).evaluate(f);
    for (final rule in r.forLine('fate')) {
      expect(rule.when['fate.present'] ?? ['false'], contains('false'), reason: rule.id);
      expect(rule.when.keys.where((k) => k.startsWith('fate.') && k != 'fate.present'), isEmpty, reason: rule.id);
    }
  });

  test('moon position matches a known new moon', () {
    // New moon 2000-01-06 18:14 UTC: Moon ≈ Sun ≈ 285.8° tropical.
    final lon = Astro.moonTropicalLongitude(DateTime.utc(2000, 1, 6, 18, 14));
    expect(lon, closeTo(285.8, 0.6));
    // Full moon 2024-04-23 23:49 UTC: Moon ≈ 214.2° tropical (Sun + 180°).
    final full = Astro.moonTropicalLongitude(DateTime.utc(2024, 4, 23, 23, 49));
    expect(full, closeTo(214.2, 0.6));
    final p = Astro.moonPlacement(DateTime.utc(2024, 4, 23, 23, 49));
    // 214.2 - 24.19 ≈ 190° sidereal → Swati (15), Libra.
    expect(p.nakshatra, 15);
    expect(p.rashi, 'libra');
    expect(Astro.rulerOfNakshatra(15), 'rahu');
  });
}
