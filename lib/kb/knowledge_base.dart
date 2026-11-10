import 'dart:convert';

import 'package:flutter/services.dart';

/// Language of the reading text. The UI itself is English.
enum Lang {
  en('English'),
  hi('हिन्दी');

  const Lang(this.label);
  final String label;
}

/// A text in English and Hindi.
class LText {
  const LText(this.en, [String? hi]) : hi = hi ?? en;

  final String en;
  final String hi;

  String of(Lang lang) => lang == Lang.hi && hi.isNotEmpty ? hi : en;

  /// Accepts `{"en": ..., "hi": ...}` or a plain string.
  static LText? tryParse(Object? j) {
    if (j == null) return null;
    if (j is String) return LText(j);
    if (j is Map) {
      final en = j['en']?.toString() ?? '';
      final hi = j['hi']?.toString();
      if (en.isEmpty && (hi == null || hi.isEmpty)) return null;
      return LText(en.isEmpty ? hi! : en, hi);
    }
    return LText(j.toString());
  }

  static const empty = LText('');
}

/// One knowledge-base record (a line, planet, nakshatra, ...). Sections
/// differ in fields, so this wraps the raw JSON with typed getters.
class KbEntry {
  KbEntry(this.raw);
  final Map<String, Object?> raw;

  String get key => (raw['key'] ?? raw['planet'] ?? raw['id'] ?? raw['line'] ?? '').toString();

  String? str(String field) => raw[field]?.toString();

  int? integer(String field) => (raw[field] as num?)?.toInt();

  LText? text(String field) => LText.tryParse(raw[field]);

  LText get name =>
      text('name') ?? text('title') ?? LText(str('sanskrit') ?? _titleCase(key));

  List<LText> texts(String field) {
    final v = raw[field];
    if (v is! List) return const [];
    return [for (final e in v) ?LText.tryParse(e)];
  }

  List<String> strings(String field) {
    final v = raw[field];
    if (v is List) return [for (final e in v) e.toString()];
    if (v is String) return [v];
    return const [];
  }

  KbEntry? child(String field) {
    final v = raw[field];
    return v is Map ? KbEntry(v.cast<String, Object?>()) : null;
  }

  static String _titleCase(String k) => k
      .split('_')
      .where((e) => e.isNotEmpty)
      .map((e) => e[0].toUpperCase() + e.substring(1))
      .join(' ');
}

/// A reading rule: when all [when] conditions hold, [text] applies.
class KbRule {
  KbRule({
    required this.id,
    required this.when,
    required this.area,
    required this.tone,
    required this.weight,
    required this.title,
    required this.text,
    this.planet,
    this.source,
  });

  final String id;

  /// Feature key → accepted values (any one may match).
  final Map<String, List<String>> when;
  final String area;
  final String tone;
  final int weight;
  final String? planet;
  final LText title;
  final LText text;
  final String? source;

  static KbRule? tryParse(Map<String, Object?> j) {
    final id = j['id']?.toString();
    final w = j['when'];
    final text = LText.tryParse(j['text']);
    if (id == null || w is! Map || text == null) return null;
    return KbRule(
      id: id,
      when: {
        for (final e in w.entries)
          e.key.toString(): e.value is List
              ? [for (final v in e.value as List) v.toString()]
              : [e.value.toString()],
      },
      area: j['area']?.toString() ?? 'personality',
      tone: j['tone']?.toString() ?? 'neutral',
      weight: (j['weight'] as num?)?.toInt() ?? 1,
      planet: j['planet']?.toString(),
      title: LText.tryParse(j['title']) ?? const LText(''),
      text: text,
      source: j['source']?.toString(),
    );
  }

  /// Line keys this rule talks about (from `<line>.<attr>` conditions).
  Set<String> get lineKeys => {
        for (final k in when.keys)
          if (!k.startsWith('hand.') &&
              !k.startsWith('mound.') &&
              !k.startsWith('symbol.') &&
              !k.startsWith('pattern.'))
            k.split('.').first,
      };
}

/// All offline palmistry knowledge, merged from `assets/kb/*.json`.
class KnowledgeBase {
  KnowledgeBase._();

  final List<KbRule> rules = [];
  final Map<String, KbEntry> lines = {};
  final Map<String, KbEntry> symbols = {};
  final Map<String, KbEntry> elements = {};
  final List<KbEntry> mixed = [];
  final Map<String, KbEntry> gunas = {};
  final Map<String, KbEntry> fingers = {};
  final Map<String, KbEntry> planets = {};
  final Map<String, KbEntry> rashis = {};

  /// Birth-chart houses (`"1"`..`"12"`) and per-planet themes for the
  /// combined palm + chart reading.
  final Map<String, KbEntry> houses = {};
  final Map<String, KbEntry> planetThemes = {};
  final List<KbEntry> nakshatras = [];
  final Map<String, KbEntry> remedies = {};
  final List<KbEntry> timeline = [];
  final List<KbEntry> learn = [];

  /// Problems found while loading (bad rules, duplicate ids).
  final List<String> warnings = [];

  static Future<KnowledgeBase> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final files = manifest.listAssets().where((p) => p.startsWith('assets/kb/') && p.endsWith('.json')).toList()
      ..sort();
    final docs = <Map<String, Object?>>[];
    for (final f in files) {
      final decoded = jsonDecode(await b.loadString(f));
      if (decoded is Map) docs.add(decoded.cast<String, Object?>());
    }
    return KnowledgeBase.fromDocuments(docs);
  }

  factory KnowledgeBase.fromDocuments(List<Map<String, Object?>> docs) {
    final kb = KnowledgeBase._();
    final ids = <String>{};
    Iterable<Map<String, Object?>> items(Map<String, Object?> d, String k) sync* {
      final v = d[k];
      if (v is List) {
        for (final e in v) {
          if (e is Map) yield e.cast<String, Object?>();
        }
      }
    }

    void keyed(Map<String, KbEntry> into, Map<String, Object?> d, String section) {
      for (final m in items(d, section)) {
        final e = KbEntry(m);
        if (e.key.isNotEmpty) into[e.key] = e;
      }
    }

    for (final d in docs) {
      for (final m in items(d, 'rules')) {
        final r = KbRule.tryParse(m);
        if (r == null) {
          kb.warnings.add('Bad rule: ${m['id']}');
          continue;
        }
        if (!ids.add(r.id)) kb.warnings.add('Duplicate rule id: ${r.id}');
        kb.rules.add(r);
      }
      keyed(kb.lines, d, 'lines');
      keyed(kb.symbols, d, 'symbols');
      keyed(kb.elements, d, 'elements');
      keyed(kb.gunas, d, 'gunas');
      keyed(kb.fingers, d, 'fingers');
      keyed(kb.planets, d, 'planets');
      keyed(kb.rashis, d, 'rashis');
      keyed(kb.houses, d, 'houses');
      keyed(kb.planetThemes, d, 'planet_themes');
      keyed(kb.remedies, d, 'remedies');
      kb.mixed.addAll(items(d, 'mixed').map(KbEntry.new));
      kb.nakshatras.addAll(items(d, 'nakshatras').map(KbEntry.new));
      kb.timeline.addAll(items(d, 'timeline').map(KbEntry.new));
      kb.learn.addAll(items(d, 'learn').map(KbEntry.new));
    }
    kb.nakshatras.sort((a, b) => (a.integer('index') ?? 0).compareTo(b.integer('index') ?? 0));
    kb.learn.sort((a, b) => (a.integer('chapter') ?? 99).compareTo(b.integer('chapter') ?? 99));
    return kb;
  }

  KbEntry? mixedFor(String a, String b) {
    for (final m in mixed) {
      final keys = m.strings('keys');
      if (keys.contains(a) && keys.contains(b)) return m;
    }
    return null;
  }

  /// Display name of a line key (`sun` → "Sun Line").
  LText lineName(String key) => lines[key]?.name ?? LText(KbEntry._titleCase(key));

  /// Display name of a planet or palm location (`sun` → "Sun").
  LText placeName(String key) {
    final p = planets[key];
    if (p != null) return p.name;
    final l = _locationNames[key];
    return l == null ? LText(KbEntry._titleCase(key)) : LText(l.$1, l.$2);
  }

  /// Display name of any other key (symbol, rashi, element, finger).
  LText nameOf(String key) {
    for (final map in [symbols, rashis, elements, fingers, gunas, planets, lines]) {
      final e = map[key];
      if (e != null) return e.name;
    }
    return placeName(key);
  }

  static const _locationNames = <String, (String, String)>{
    'between_jupiter_saturn': ('Between Jupiter and Saturn', 'गुरु और शनि के बीच'),
    'palm_center': ('Centre of the palm', 'हथेली का केंद्र'),
    'wrist': ('Wrist', 'कलाई'),
    'thumb': ('Thumb', 'अंगूठा'),
    'any': ('Anywhere', 'कहीं भी'),
  };
}
