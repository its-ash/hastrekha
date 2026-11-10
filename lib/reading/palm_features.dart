/// Everything the reading is built from: what the camera measured, plus
/// any corrections the user made on the review screen.
///
/// Values use the knowledge-base vocabulary directly (see
/// `docs/KNOWLEDGE_SCHEMA.md`), so [toFacts] can be matched against rules
/// without translation.
library;

/// Shared vocabulary.
abstract final class Vocab {
  static const primaryLines = ['life', 'head', 'heart', 'fate'];
  static const secondaryLines = [
    'sun', 'mercury', 'union', 'venus_belt', 'bracelets', 'mars_line',
    'jupiter_ring', 'saturn_ring', 'moon_line', 'jupiter_line', 'saturn_line',
    'contentment', 'progeny', 'siblings', 'kinship', 'fortune', 'thumb_barley',
  ];

  /// Secondary lines the camera tries to find. The others can only be
  /// added by hand on the review screen.
  static const detectableSecondary = [
    'sun', 'mercury', 'union', 'venus_belt', 'bracelets', 'mars_line',
    'jupiter_ring', 'saturn_ring', 'moon_line',
  ];

  static const planets = ['sun', 'moon', 'mars', 'mercury', 'jupiter', 'venus', 'saturn', 'rahu', 'ketu'];
  static const locations = [
    'jupiter', 'between_jupiter_saturn', 'saturn', 'sun', 'mercury', 'mars',
    'rahu', 'ketu', 'venus', 'moon', 'palm_center', 'wrist', 'thumb',
  ];
  static const lengths = ['short', 'medium', 'long'];
  static const depths = ['faint', 'medium', 'deep'];
  static const breaks = ['none', 'some', 'many'];
  static const branches = ['none', 'up', 'down', 'both'];
  static const curves = ['straight', 'gentle', 'steep'];
  static const elements = ['air', 'fire', 'water'];
  static const palmShapes = ['square', 'rectangular', 'rounded'];
  static const fingerLengths = ['short', 'medium', 'long'];
  static const densities = ['few', 'moderate', 'many'];
  static const moundLevels = ['flat', 'normal', 'raised'];
  static const areas = [
    'personality', 'mind', 'health', 'love', 'family', 'career', 'wealth',
    'spirituality', 'life_events',
  ];
}

/// Something seen at a point along a line: a break, a branch or a fork.
/// [t] runs from the line's start (0) to its end (1), as palmistry reads
/// it, so it maps onto the line's age span.
class LineEvent {
  const LineEvent(this.type, this.t);

  /// `break`, `branch_up`, `branch_down` or `fork`.
  final String type;
  final double t;

  Map<String, Object?> toJson() => {'type': type, 't': double.parse(t.toStringAsFixed(3))};
  factory LineEvent.fromJson(Map<String, Object?> j) =>
      LineEvent(j['type'] as String, (j['t'] as num).toDouble());
}

class LineFeature {
  LineFeature({
    this.present = false,
    this.length = 'medium',
    this.depth = 'medium',
    this.breaks = 'none',
    this.chained = false,
    this.fork = false,
    this.branches = 'none',
    this.curve = 'gentle',
    this.start,
    this.end,
    this.confidence = 0,
    this.edited = false,
    List<LineEvent>? events,
  }) : events = events ?? [];

  bool present;
  String length;
  String depth;
  String breaks;
  bool chained;
  bool fork;
  String branches;
  String curve;
  String? start;
  String? end;

  /// How sure the detector was (0..1). 1 for lines the user set by hand.
  double confidence;

  /// The user changed this line on the review screen.
  bool edited;

  /// Breaks, branches and forks along the line (from the camera).
  final List<LineEvent> events;

  LineFeature copy() => LineFeature.fromJson(toJson());

  Map<String, Object?> toJson() => {
        'present': present,
        'length': length,
        'depth': depth,
        'breaks': breaks,
        'chained': chained,
        'fork': fork,
        'branches': branches,
        'curve': curve,
        'start': start,
        'end': end,
        'confidence': confidence,
        'edited': edited,
        'events': [for (final e in events) e.toJson()],
      };

  factory LineFeature.fromJson(Map<String, Object?> j) => LineFeature(
        present: j['present'] as bool? ?? false,
        length: j['length'] as String? ?? 'medium',
        depth: j['depth'] as String? ?? 'medium',
        breaks: j['breaks'] as String? ?? 'none',
        chained: j['chained'] as bool? ?? false,
        fork: j['fork'] as bool? ?? false,
        branches: j['branches'] as String? ?? 'none',
        curve: j['curve'] as String? ?? 'gentle',
        start: j['start'] as String?,
        end: j['end'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        edited: j['edited'] as bool? ?? false,
        events: [
          for (final e in (j['events'] as List?) ?? const [])
            LineEvent.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
}

/// A symbol (star, cross, ...) the user marked at a location.
class SymbolMark {
  const SymbolMark(this.symbol, this.location);
  final String symbol;
  final String location;

  Map<String, Object?> toJson() => {'symbol': symbol, 'location': location};
  factory SymbolMark.fromJson(Map<String, Object?> j) =>
      SymbolMark(j['symbol'] as String, j['location'] as String? ?? 'any');

  @override
  bool operator ==(Object other) =>
      other is SymbolMark && other.symbol == symbol && other.location == location;

  @override
  int get hashCode => Object.hash(symbol, location);
}

class PalmFeatures {
  PalmFeatures({
    this.side = 'right',
    this.element = 'fire',
    this.secondary = 'none',
    this.palm = 'square',
    this.fingers = 'medium',
    this.lineDensity = 'moderate',
    Map<String, LineFeature>? lines,
    Map<String, String>? mounds,
    Set<String>? crossedMounds,
    List<SymbolMark>? symbols,
    this.simian = false,
    this.headLifeJoined = true,
  })  : lines = lines ?? {},
        mounds = mounds ?? {for (final p in Vocab.planets) p: 'normal'},
        crossedMounds = crossedMounds ?? {},
        symbols = symbols ?? [];

  String side;
  String element;
  String secondary;
  String palm;
  String fingers;
  String lineDensity;
  final Map<String, LineFeature> lines;
  final Map<String, String> mounds;
  final Set<String> crossedMounds;
  final List<SymbolMark> symbols;
  bool simian;
  bool headLifeJoined;

  LineFeature line(String key) => lines.putIfAbsent(key, LineFeature.new);

  /// Flat feature map for rule matching. Keys follow the knowledge-base
  /// schema (`life.length`, `mound.sun`, `hand.element`, ...).
  Map<String, String> toFacts() {
    final f = <String, String>{
      'hand.element': element,
      'hand.secondary': secondary,
      'hand.palm': palm,
      'hand.fingers': fingers,
      'hand.line_density': lineDensity,
      'hand.side': side,
      'pattern.simian': '$simian',
      'pattern.head_life_joined': '$headLifeJoined',
    };
    for (final key in [...Vocab.primaryLines, ...Vocab.secondaryLines]) {
      final l = lines[key];
      final present = l?.present ?? false;
      f['$key.present'] = '$present';
      if (!present) continue;
      f['$key.length'] = l!.length;
      f['$key.depth'] = l.depth;
      f['$key.breaks'] = l.breaks;
      f['$key.chained'] = '${l.chained}';
      f['$key.fork'] = '${l.fork}';
      f['$key.branches'] = l.branches;
      f['$key.curve'] = l.curve;
      if (l.start != null) f['$key.start'] = l.start!;
      if (l.end != null) f['$key.end'] = l.end!;
    }
    for (final p in Vocab.planets) {
      f['mound.$p'] = mounds[p] ?? 'normal';
      f['mound.$p.crossed'] = '${crossedMounds.contains(p)}';
    }
    return f;
  }

  PalmFeatures copy() => PalmFeatures.fromJson(toJson());

  Map<String, Object?> toJson() => {
        'side': side,
        'element': element,
        'secondary': secondary,
        'palm': palm,
        'fingers': fingers,
        'lineDensity': lineDensity,
        'lines': {for (final e in lines.entries) e.key: e.value.toJson()},
        'mounds': mounds,
        'crossedMounds': crossedMounds.toList(),
        'symbols': [for (final s in symbols) s.toJson()],
        'simian': simian,
        'headLifeJoined': headLifeJoined,
      };

  factory PalmFeatures.fromJson(Map<String, Object?> j) => PalmFeatures(
        side: j['side'] as String? ?? 'right',
        element: j['element'] as String? ?? 'fire',
        secondary: j['secondary'] as String? ?? 'none',
        palm: j['palm'] as String? ?? 'square',
        fingers: j['fingers'] as String? ?? 'medium',
        lineDensity: j['lineDensity'] as String? ?? 'moderate',
        lines: {
          for (final e in ((j['lines'] as Map?) ?? {}).entries)
            e.key as String: LineFeature.fromJson((e.value as Map).cast<String, Object?>()),
        },
        mounds: ((j['mounds'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as String)),
        crossedMounds: {...((j['crossedMounds'] as List?) ?? []).cast<String>()},
        symbols: [
          for (final s in (j['symbols'] as List?) ?? [])
            SymbolMark.fromJson((s as Map).cast<String, Object?>()),
        ],
        simian: j['simian'] as bool? ?? false,
        headLifeJoined: j['headLifeJoined'] as bool? ?? true,
      );
}
