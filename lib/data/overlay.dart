/// Line drawings over the palm photo. Coordinates are fractions (0..1)
/// of the photo, so the overlay fits any display size.
class PalmOverlay {
  const PalmOverlay({
    required this.photoWidth,
    required this.photoHeight,
    required this.paths,
    required this.minor,
    required this.palmRect,
    required this.thumbOnLeft,
    this.issues = const [],
    this.elementScores = const {},
  });

  final int photoWidth;
  final int photoHeight;

  /// Line key → polylines, each flattened as [x0, y0, x1, y1, ...].
  final Map<String, List<List<double>>> paths;
  final List<List<double>> minor;

  /// left, top, right, bottom.
  final List<double> palmRect;
  final bool thumbOnLeft;
  final List<String> issues;
  final Map<String, double> elementScores;

  double get aspect => photoHeight == 0 ? 1 : photoWidth / photoHeight;

  Map<String, Object?> toJson() => {
        'w': photoWidth,
        'h': photoHeight,
        'paths': paths,
        'minor': minor,
        'palm': palmRect,
        'thumbOnLeft': thumbOnLeft,
        'issues': issues,
        'elements': elementScores,
      };

  factory PalmOverlay.fromJson(Map<String, Object?> j) {
    List<List<double>> polys(Object? v) => [
          for (final p in (v as List?) ?? const [])
            [for (final n in p as List) (n as num).toDouble()],
        ];
    return PalmOverlay(
      photoWidth: (j['w'] as num?)?.toInt() ?? 1,
      photoHeight: (j['h'] as num?)?.toInt() ?? 1,
      paths: {
        for (final e in ((j['paths'] as Map?) ?? const {}).entries) e.key as String: polys(e.value),
      },
      minor: polys(j['minor']),
      palmRect: [for (final n in (j['palm'] as List?) ?? const [0.2, 0.3, 0.8, 0.8]) (n as num).toDouble()],
      thumbOnLeft: j['thumbOnLeft'] as bool? ?? false,
      issues: [for (final s in (j['issues'] as List?) ?? const []) s.toString()],
      elementScores: {
        for (final e in ((j['elements'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toDouble(),
      },
    );
  }
}
