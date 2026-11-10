import 'dart:math' as math;
import 'dart:typed_data';

import '../reading/palm_features.dart';
import 'crease_detector.dart';
import 'palm_geometry.dart';
import 'skeleton_graph.dart';

/// Where each named spot of the palm sits, in palm coordinates
/// (u: thumb side 0 → little-finger side 1, v: finger base 0 → wrist 1).
abstract final class PalmMap {
  static const locations = <String, (double, double)>{
    'jupiter': (0.14, 0.06),
    'between_jupiter_saturn': (0.27, 0.05),
    'saturn': (0.40, 0.05),
    'sun': (0.63, 0.06),
    'mercury': (0.87, 0.08),
    'mars': (0.07, 0.36),
    // The book places Rahu between the Saturn and Sun mounds, and Ketu
    // low in the palm where the fate line rises.
    'rahu': (0.52, 0.10),
    'ketu': (0.50, 0.86),
    'venus': (0.17, 0.78),
    'moon': (0.86, 0.74),
    'palm_center': (0.50, 0.42),
    'wrist': (0.50, 1.00),
    'thumb': (-0.10, 0.55),
  };

  /// Mound centers used for "crossed" and "raised" estimates.
  static const mounds = <String, (double, double)>{
    'jupiter': (0.14, 0.08),
    'saturn': (0.40, 0.07),
    'sun': (0.63, 0.08),
    'mercury': (0.87, 0.10),
    'mars': (0.08, 0.38),
    'rahu': (0.52, 0.12),
    'ketu': (0.50, 0.86),
    'venus': (0.18, 0.76),
    'moon': (0.85, 0.72),
  };

  static String nearest(double u, double v) {
    var best = 'palm_center';
    var bd = double.infinity;
    for (final e in locations.entries) {
      final du = u - e.value.$1, dv = v - e.value.$2;
      final d = du * du + dv * dv;
      if (d < bd) {
        bd = d;
        best = e.key;
      }
    }
    return best;
  }
}

/// Typical path of a palm line in palm coordinates, from its start to
/// its end as palmistry reads it.
class LineTemplate {
  const LineTemplate(this.key, this.points, {required this.tolerance, required this.minLength, this.multiple = false, this.boost = 1});

  final String key;
  final List<(double, double)> points;

  /// Typical distance (palm units) a real line wanders from the template.
  final double tolerance;

  /// Shortest curve (palm units) that can be this line.
  final double minLength;

  /// Several separate curves may all be this line (bracelets, union lines).
  final bool multiple;

  /// Priority when two lines compete for one curve.
  final double boost;

  double get length {
    var s = 0.0;
    for (var i = 1; i < points.length; i++) {
      final du = points[i].$1 - points[i - 1].$1, dv = points[i].$2 - points[i - 1].$2;
      s += math.sqrt(du * du + dv * dv);
    }
    return s;
  }

  /// Closest point on the template: distance, position along it (0..1)
  /// and the template direction there.
  ({double dist, double t, double tx, double ty}) project(double u, double v) {
    final total = length;
    var acc = 0.0;
    var best = (dist: double.infinity, t: 0.0, tx: 1.0, ty: 0.0);
    for (var i = 1; i < points.length; i++) {
      final ax = points[i - 1].$1, ay = points[i - 1].$2;
      final bx = points[i].$1, by = points[i].$2;
      final dx = bx - ax, dy = by - ay;
      final segLen = math.sqrt(dx * dx + dy * dy);
      var s = segLen == 0 ? 0.0 : ((u - ax) * dx + (v - ay) * dy) / (segLen * segLen);
      s = s.clamp(0.0, 1.0);
      final px = ax + dx * s, py = ay + dy * s;
      final d = math.sqrt((u - px) * (u - px) + (v - py) * (v - py));
      if (d < best.dist) {
        best = (dist: d, t: (acc + s * segLen) / total, tx: dx / segLen, ty: dy / segLen);
      }
      acc += segLen;
    }
    return best;
  }
}

const lineTemplates = <LineTemplate>[
  LineTemplate('heart', [(0.99, 0.25), (0.75, 0.21), (0.52, 0.17), (0.32, 0.12), (0.17, 0.05)],
      tolerance: 0.085, minLength: 0.18, boost: 1.35),
  LineTemplate('head', [(0.07, 0.34), (0.30, 0.39), (0.55, 0.45), (0.78, 0.52), (0.95, 0.57)],
      tolerance: 0.095, minLength: 0.18, boost: 1.35),
  LineTemplate('life', [(0.09, 0.32), (0.19, 0.45), (0.26, 0.60), (0.30, 0.75), (0.31, 0.90), (0.32, 1.02)],
      tolerance: 0.095, minLength: 0.2, boost: 1.35),
  LineTemplate('fate', [(0.50, 1.02), (0.48, 0.72), (0.45, 0.42), (0.42, 0.12), (0.40, 0.0)],
      tolerance: 0.1, minLength: 0.15, boost: 1.25),
  LineTemplate('sun', [(0.68, 0.72), (0.66, 0.40), (0.64, 0.08)], tolerance: 0.07, minLength: 0.12),
  LineTemplate('mercury', [(0.45, 0.92), (0.66, 0.58), (0.86, 0.24)], tolerance: 0.075, minLength: 0.15),
  LineTemplate('venus_belt', [(0.30, 0.04), (0.44, 0.12), (0.60, 0.12), (0.76, 0.04)],
      tolerance: 0.045, minLength: 0.15),
  LineTemplate('union', [(1.02, 0.14), (0.86, 0.13)], tolerance: 0.045, minLength: 0.05, multiple: true),
  LineTemplate('bracelets', [(0.12, 1.03), (0.50, 1.04), (0.88, 1.03)], tolerance: 0.05, minLength: 0.2, multiple: true),
  LineTemplate('mars_line', [(0.05, 0.45), (0.11, 0.60), (0.15, 0.76)], tolerance: 0.045, minLength: 0.1),
  LineTemplate('jupiter_ring', [(0.0, 0.13), (0.12, 0.10), (0.25, 0.0)], tolerance: 0.04, minLength: 0.1),
  LineTemplate('saturn_ring', [(0.29, 0.02), (0.40, 0.07), (0.52, 0.02)], tolerance: 0.035, minLength: 0.1),
  LineTemplate('moon_line', [(1.02, 0.76), (0.84, 0.73)], tolerance: 0.06, minLength: 0.06, multiple: true),
];

/// One recognized line: its curve pieces (ordered start → end) and the
/// measured attributes.
class DetectedLine {
  DetectedLine(this.key, this.feature, this.pieces);
  final String key;
  final LineFeature feature;

  /// Polylines in working-image pixels.
  final List<List<Pt>> pieces;
}

class ClassifiedPalm {
  ClassifiedPalm({
    required this.lines,
    required this.minor,
    required this.simian,
    required this.headLifeJoined,
    required this.crossedMounds,
    required this.mounds,
    required this.lineDensity,
  });

  final Map<String, DetectedLine> lines;

  /// Other crease curves (for drawing), in working-image pixels.
  final List<List<Pt>> minor;
  final bool simian;
  final bool headLifeJoined;
  final Set<String> crossedMounds;
  final Map<String, String> mounds;

  /// Total crease length inside the palm divided by the palm width.
  final double lineDensity;
}

/// Names the curves (life, head, heart ...) by comparing them with
/// [lineTemplates] in palm coordinates, then measures each line.
class LineClassifier {
  const LineClassifier();

  /// Lines searched for when thresholding missed them, weakest-risk first.
  static const guidedLines = ['heart', 'head', 'life', 'fate', 'sun', 'mercury'];

  ClassifiedPalm classify({
    required SkeletonGraph graph,
    required List<Curve> curves,
    required CreaseMap creases,
    required PalmFrame frame,
    required Uint8List palmMask,
  }) {
    final pw = frame.width;
    final uvCurves = [
      for (final c in curves) [for (final p in c.pts) frame.toUV(p.x, p.y)],
    ];

    // Score every curve against every template.
    final cands = <_Cand>[];
    for (var ci = 0; ci < curves.length; ci++) {
      final uv = uvCurves[ci];
      final len = _uvLength(uv);
      for (final t in lineTemplates) {
        if (len < t.minLength) continue;
        final m = _match(uv, t);
        if (m == null || m.score < 0.1) continue;
        cands.add(_Cand(ci, t, m.score * t.boost, m.tMin, m.tMax));
      }
    }
    cands.sort((a, b) => b.score.compareTo(a.score));

    final usedCurve = <int>{};
    final assigned = <String, List<_Cand>>{};
    for (final c in cands) {
      if (usedCurve.contains(c.curve)) continue;
      final list = assigned[c.template.key] ?? [];
      if (!c.template.multiple && list.isNotEmpty) {
        // A second piece is fine only if it covers a different stretch.
        final overlaps = list.any((o) {
          final lo = math.max(o.tMin, c.tMin), hi = math.min(o.tMax, c.tMax);
          return hi - lo > 0.25 * (c.tMax - c.tMin);
        });
        if (overlaps) continue;
      }
      list.add(c);
      assigned[c.template.key] = list;
      usedCurve.add(c.curve);
    }

    // Faint lines: search each main line's corridor directly in the crease
    // response, which finds lines too weak to survive thresholding and
    // fills in lines that were only found in part.
    curves = [...curves];
    _searchFaintLines(
      graph: graph,
      curves: curves,
      uvCurves: uvCurves,
      creases: creases,
      frame: frame,
      palmMask: palmMask,
      assigned: assigned,
      usedCurve: usedCurve,
    );

    // Segment ids that belong to any recognized line.
    final lineSegs = <int>{};
    for (final list in assigned.values) {
      for (final c in list) {
        lineSegs.addAll(curves[c.curve].segmentIds);
      }
    }

    final lines = <String, DetectedLine>{};
    for (final e in assigned.entries) {
      final pieces = e.value..sort((a, b) => a.tMin.compareTo(b.tMin));
      lines[e.key] = _measure(
        e.key,
        pieces,
        curves,
        uvCurves,
        graph,
        creases,
        frame,
        lineSegs,
      );
    }

    // Simian crease: one long crease where the head and heart lines run.
    var simian = false;
    final heart = lines['heart'], head = lines['head'];
    if ((heart == null) != (head == null)) {
      final only = heart ?? head!;
      final uv = [for (final p in only.pieces.expand((e) => e)) frame.toUV(p.x, p.y)];
      final us = uv.map((e) => e.$1);
      final vs = uv.map((e) => e.$2);
      final span = us.reduce(math.max) - us.reduce(math.min);
      final meanV = vs.reduce((a, b) => a + b) / uv.length;
      if (span > 0.75 && meanV > 0.15 && meanV < 0.48 && only.feature.curve != 'steep') {
        simian = true;
        final other = heart == null ? 'heart' : 'head';
        lines[other] = DetectedLine(other, only.feature.copy(), only.pieces);
      }
    }

    // Head and life lines starting together.
    var joined = true;
    final life = lines['life'];
    if (head != null && life != null) {
      final hs = head.pieces.first.first, ls = life.pieces.first.first;
      final (hu, hv) = frame.toUV(hs.x, hs.y);
      final (lu, lv) = frame.toUV(ls.x, ls.y);
      joined = math.sqrt((hu - lu) * (hu - lu) + (hv - lv) * (hv - lv)) < 0.08;
    }

    // Crease density and mound estimates.
    final w = creases.width, h = creases.height;
    var total = 0;
    final sk = creases.skeleton;
    for (var i = 0; i < sk.length; i++) {
      if (sk[i] != 0 && palmMask[i] != 0) total++;
    }
    final palmArea = math.max(1, palmMask.where((e) => e != 0).length);
    final meanDensity = total / palmArea;
    final crossed = <String>{};
    final levels = <String, String>{};
    final palmLight = creases.background.mean(mask: palmMask);
    for (final e in PalmMap.mounds.entries) {
      final (cx, cy) = frame.toXY(e.value.$1, e.value.$2);
      final r = pw * 0.1;
      var n = 0, a = 0;
      var light = 0.0;
      for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
        for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) continue;
          final i = y * w + x;
          if (palmMask[i] == 0) continue;
          a++;
          light += creases.background.data[i];
          if (sk[i] != 0) n++;
        }
      }
      if (a < r * r) {
        levels[e.key] = 'normal';
        continue;
      }
      final d = n / a;
      // Lines that run through on purpose (the fate line ending on
      // Saturn) also count; only clear clutter marks a mound crossed.
      if (d > meanDensity * 1.9 && n > pw * 0.45) crossed.add(e.key);
      final rel = palmLight == 0 ? 1.0 : (light / a) / palmLight;
      levels[e.key] = rel > 1.06 ? 'raised' : (rel < 0.94 ? 'flat' : 'normal');
    }

    final minor = <List<Pt>>[];
    for (var ci = 0; ci < curves.length; ci++) {
      if (usedCurve.contains(ci)) continue;
      if (curves[ci].length < pw * 0.06) continue;
      minor.add(curves[ci].pts);
    }

    return ClassifiedPalm(
      lines: lines,
      minor: minor,
      simian: simian,
      headLifeJoined: joined,
      crossedMounds: crossed,
      mounds: levels,
      lineDensity: total / pw,
    );
  }

  /// Looks for each of [guidedLines] along its template corridor in the
  /// raw crease response (see [_traceCorridor]). A trace is added when
  /// the line was not found at all, and replaces the found pieces when it
  /// follows them but reaches clearly further.
  void _searchFaintLines({
    required SkeletonGraph graph,
    required List<Curve> curves,
    required List<List<(double, double)>> uvCurves,
    required CreaseMap creases,
    required PalmFrame frame,
    required Uint8List palmMask,
    required Map<String, List<_Cand>> assigned,
    required Set<int> usedCurve,
  }) {
    final w = creases.width, h = creases.height;
    final keyIndex = {for (var i = 0; i < lineTemplates.length; i++) lineTemplates[i].key: i};

    // Which line owns each pixel (template index, -1 = none), so a trace
    // does not borrow a neighbouring line.
    // The radius covers the line's whole response, which is wider than its
    // skeleton at the coarser detector scales.
    final owner = Int16List(w * h)..fillRange(0, w * h, -1);
    final reach = math.max(2, (frame.width * 0.016).round());
    void claim(Iterable<Pt> pts, int key) {
      for (final p in pts) {
        final cx = p.x.round(), cy = p.y.round();
        for (var dy = -reach; dy <= reach; dy++) {
          for (var dx = -reach; dx <= reach; dx++) {
            final x = cx + dx, y = cy + dy;
            if (x < 0 || y < 0 || x >= w || y >= h) continue;
            final i = y * w + x;
            if (owner[i] == -1) owner[i] = key;
          }
        }
      }
    }

    for (final e in assigned.entries) {
      for (final c in e.value) {
        claim(curves[c.curve].pts, keyIndex[e.key]!);
      }
    }

    final base = _noiseLevel(creases, palmMask);
    for (final key in guidedLines) {
      final t = lineTemplates.firstWhere((e) => e.key == key);
      final ki = keyIndex[key]!;
      final trace = _traceCorridor(t, ki, creases, frame, palmMask, owner, base);
      if (trace == null) continue;

      // Pixels on and next to the trace.
      final mark = Uint8List(w * h);
      for (final p in trace.runs.expand((e) => e)) {
        final cx = p.x.round(), cy = p.y.round();
        for (var dy = -3; dy <= 3; dy++) {
          for (var dx = -3; dx <= 3; dx++) {
            final x = cx + dx, y = cy + dy;
            if (x >= 0 && y >= 0 && x < w && y < h) mark[y * w + x] = 1;
          }
        }
      }
      double onTrace(List<Pt> pts) {
        if (pts.isEmpty) return 0;
        var n = 0;
        for (final p in pts) {
          final x = p.x.round(), y = p.y.round();
          if (x >= 0 && y >= 0 && x < w && y < h && mark[y * w + x] != 0) n++;
        }
        return n / pts.length;
      }

      final existing = assigned[key];
      if (existing != null) {
        final span = existing.map((e) => e.tMax).reduce(math.max) - existing.map((e) => e.tMin).reduce(math.min);
        if (trace.tMax - trace.tMin < span + 0.12) continue;
        final follows = onTrace([for (final c in existing) ...curves[c.curve].pts]);
        if (follows < 0.5) continue;
      }

      // Skeleton segments along the trace belong to the line (so they are
      // not read as its branches).
      final segIds = [
        for (final s in graph.segments)
          if (onTrace(s.pts) >= 0.6) s.id,
      ];
      final pieces = <_Cand>[];
      for (var r = 0; r < trace.runs.length; r++) {
        final pts = trace.runs[r];
        final uv = [for (final p in pts) frame.toUV(p.x, p.y)];
        final m = _match(uv, t);
        final first = t.project(uv.first.$1, uv.first.$2).t, last = t.project(uv.last.$1, uv.last.$2).t;
        curves.add(Curve(pts, r == 0 ? segIds : const [], const []));
        uvCurves.add(uv);
        pieces.add(_Cand(
          curves.length - 1,
          t,
          (m?.score ?? 0.1) * t.boost * 0.85,
          m?.tMin ?? math.min(first, last),
          m?.tMax ?? math.max(first, last),
        ));
        usedCurve.add(curves.length - 1);
      }
      assigned[key] = pieces;
      claim(trace.runs.expand((e) => e), ki);

      // Thresholded curves that lie on the trace are part of this line now.
      for (var ci = 0; ci < curves.length; ci++) {
        if (!usedCurve.contains(ci) && onTrace(curves[ci].pts) >= 0.5) usedCurve.add(ci);
      }
    }
  }

  /// Typical response of skin with no line: what a path through texture
  /// alone collects per step.
  static double _noiseLevel(CreaseMap creases, Uint8List palmMask) =>
      creases.response.percentile(0.9, mask: palmMask).clamp(0.05, 0.3);

  /// Finds the strongest steady crease inside a template's corridor.
  ///
  /// The corridor is unrolled into a grid: one row per step along the
  /// template, one column per pixel of offset across it. Each cell scores
  /// the crease response there, weighted by how well the crease direction
  /// matches the template, minus the skin noise level [base]. A dynamic
  /// program picks the best-scoring path that moves at most one pixel
  /// sideways per step, and may start and stop anywhere (so a line that
  /// covers only part of the template is found as that part). The path is
  /// then split where the crease fades for a while, which are the breaks.
  _Trace? _traceCorridor(
    LineTemplate t,
    int ownKey,
    CreaseMap creases,
    PalmFrame frame,
    Uint8List palmMask,
    Int16List owner,
    double base,
  ) {
    final w = creases.width, h = creases.height;
    final pw = frame.width;
    const step = 1.5;

    // Template resampled every [step] pixels, with unit tangents.
    final poly = [for (final p in t.points) frame.toXY(p.$1, p.$2)];
    final centers = <(double, double)>[];
    final tangents = <(double, double)>[];
    for (var i = 1; i < poly.length; i++) {
      final (ax, ay) = poly[i - 1];
      final (bx, by) = poly[i];
      final dx = bx - ax, dy = by - ay;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) continue;
      final n = math.max(1, (len / step).ceil());
      for (var s = 0; s < n; s++) {
        centers.add((ax + dx * s / n, ay + dy * s / n));
        tangents.add((dx / len, dy / len));
      }
    }
    final rows = centers.length;
    final half = math.max(2, (t.tolerance * 1.5 * pw).round());
    final cols = 2 * half + 1;
    if (rows < 4) return null;

    final gain = Float32List(rows * cols);
    final support = Float32List(rows * cols);
    final blocked = -2 * base;
    for (var a = 0; a < rows; a++) {
      final (cx, cy) = centers[a];
      final (tx, ty) = tangents[a];
      for (var b = 0; b < cols; b++) {
        final d = (b - half).toDouble();
        final x = cx - ty * d, y = cy + tx * d;
        final xi = x.round(), yi = y.round();
        final j = a * cols + b;
        if (xi < 1 || yi < 1 || xi >= w - 1 || yi >= h - 1) {
          gain[j] = blocked;
          continue;
        }
        final i = yi * w + xi;
        final o = owner[i];
        if (palmMask[i] == 0 || (o != -1 && o != ownKey)) {
          gain[j] = blocked;
          continue;
        }
        final th = creases.normal[i];
        final nx = math.cos(th), ny = math.sin(th);
        final along = (-ny * tx + nx * ty).abs();
        final r = creases.response.sample(x, y);
        // Only the crest of a crease counts in full; its flanks (and the
        // flanks of a neighbouring line) count little.
        final crest = r >= creases.response.sample(x + nx * 1.5, y + ny * 1.5) &&
            r >= creases.response.sample(x - nx * 1.5, y - ny * 1.5);
        final s = r * ((along - 0.5) * 2).clamp(0.0, 1.0) * (crest ? 1.0 : 0.35);
        support[j] = s;
        gain[j] = s - base;
      }
    }

    // Best local path (it restarts wherever the running score drops to 0).
    final score = Float32List(rows * cols);
    final back = Int16List(rows * cols);
    var bestJ = -1;
    var bestScore = 0.0;
    for (var a = 0; a < rows; a++) {
      for (var b = 0; b < cols; b++) {
        var prev = 0.0;
        var arg = -1;
        if (a > 0) {
          for (var db = -1; db <= 1; db++) {
            final bb = b + db;
            if (bb < 0 || bb >= cols) continue;
            final v = score[(a - 1) * cols + bb] - (db == 0 ? 0 : 0.01);
            if (v > prev) {
              prev = v;
              arg = bb;
            }
          }
        }
        final j = a * cols + b;
        score[j] = gain[j] + prev;
        back[j] = arg;
        if (score[j] > bestScore) {
          bestScore = score[j];
          bestJ = j;
        }
      }
    }
    if (bestJ < 0) return null;

    final cells = <(int, int)>[];
    var a = bestJ ~/ cols, b = bestJ % cols;
    while (true) {
      cells.add((a, b));
      final p = back[a * cols + b];
      if (p < 0 || a == 0) break;
      a--;
      b = p;
    }
    final path = cells.reversed.toList();

    // Smoothed support along the path; split where it stays low.
    final n = path.length;
    final sup = [for (final (a, b) in path) support[a * cols + b]];
    final smooth = List<double>.generate(n, (i) {
      var s = 0.0;
      var c = 0;
      for (var k = math.max(0, i - 3); k <= math.min(n - 1, i + 3); k++) {
        s += sup[k];
        c++;
      }
      return s / c;
    });
    final keep = base * 1.1;
    final maxGap = (pw * 0.045 / step).ceil();
    final minRun = (pw * 0.05 / step).ceil();
    final spans = <(int, int)>[];
    int? start;
    var lastOn = -1;
    for (var i = 0; i < n; i++) {
      if (smooth[i] < keep) continue;
      if (start != null && i - lastOn > maxGap) {
        spans.add((start, lastOn));
        start = null;
      }
      start ??= i;
      lastOn = i;
    }
    if (start != null) spans.add((start, lastOn));
    spans.removeWhere((s) => s.$2 - s.$1 + 1 < minRun);
    if (spans.isEmpty) return null;

    Pt at((int, int) c) {
      final (cx, cy) = centers[c.$1];
      final (tx, ty) = tangents[c.$1];
      final d = (c.$2 - half).toDouble();
      return Pt(cx - ty * d, cy + tx * d);
    }

    // Strength on the path, and the response of the skin to either side
    // of it (a few pixels off, across the template).
    final side = math.max(3.0, pw * 0.016);
    var sum = 0.0, beside = 0.0;
    var count = 0;
    var edge = 0;
    final runs = <List<Pt>>[];
    for (final (s, e) in spans) {
      runs.add([for (var i = s; i <= e; i++) at(path[i])]);
      for (var i = s; i <= e; i++) {
        sum += sup[i];
        count++;
        if ((path[i].$2 - half).abs() > half * 0.85) edge++;
        final p = at(path[i]);
        final (tx, ty) = tangents[path[i].$1];
        final l = creases.response.sample(p.x - ty * side, p.y + tx * side);
        final r = creases.response.sample(p.x + ty * side, p.y - tx * side);
        beside += math.max(l, r);
      }
    }
    final strength = sum / count;
    final contrast = strength / math.max(0.02, beside / count);
    var uvLen = 0.0;
    for (final r in runs) {
      uvLen += _uvLength([for (final p in r) frame.toUV(p.x, p.y)]);
    }
    // A real crease stands above the skin texture and clearly above the
    // skin beside it (riding the flank of another line fails this), runs
    // long enough to be this line, and keeps away from the corridor edge
    // (hugging the edge means it is some other crease leaving the
    // corridor).
    if (uvLen < t.minLength || strength < math.max(0.1, base * 1.4) || contrast < 1.8 || edge > count * 0.4) {
      return null;
    }

    final ts = [
      for (final r in runs)
        for (final p in [r.first, r.last])
          () {
            final (u, v) = frame.toUV(p.x, p.y);
            return t.project(u, v).t;
          }(),
    ];
    return _Trace(runs, strength, ts.reduce(math.min), ts.reduce(math.max));
  }

  DetectedLine _measure(
    String key,
    List<_Cand> pieces,
    List<Curve> curves,
    List<List<(double, double)>> uvCurves,
    SkeletonGraph graph,
    CreaseMap creases,
    PalmFrame frame,
    Set<int> lineSegs,
  ) {
    final t = lineTemplates.firstWhere((e) => e.key == key);
    final pw = frame.width;

    // Orient each piece from the line's start to its end.
    final orientedPx = <List<Pt>>[];
    final orientedUv = <List<(double, double)>>[];
    var gapCount = 0;
    var uvLen = 0.0;
    final events = <LineEvent>[];
    double tAt(Pt p) {
      final (u, v) = frame.toUV(p.x, p.y);
      return t.project(u, v).t;
    }

    for (var pi = 0; pi < pieces.length; pi++) {
      final c = pieces[pi];
      var px = curves[c.curve].pts;
      var uv = uvCurves[c.curve];
      final t0 = t.project(uv.first.$1, uv.first.$2).t;
      final t1 = t.project(uv.last.$1, uv.last.$2).t;
      if (t0 > t1) {
        px = px.reversed.toList();
        uv = uv.reversed.toList();
      }
      orientedPx.add(px);
      orientedUv.add(uv);
      uvLen += _uvLength(uv);
      for (final g in curves[c.curve].gaps) {
        if (g.length <= pw * 0.025) continue;
        gapCount++;
        final at = g.at.clamp(0, curves[c.curve].pts.length - 1);
        events.add(LineEvent('break', tAt(curves[c.curve].pts[at])));
      }
      if (pi > 0) events.add(LineEvent('break', tAt(px.first)));
    }
    gapCount += pieces.length - 1;
    final allUv = orientedUv.expand((e) => e).toList();
    final allPx = orientedPx.expand((e) => e).toList();

    final tMin = pieces.map((e) => e.tMin).reduce(math.min);
    final tMax = pieces.map((e) => e.tMax).reduce(math.max);
    final ratio = math.max(uvLen, (tMax - tMin) * t.length) / t.length;
    final length = ratio >= 0.85 ? 'long' : (ratio >= 0.55 ? 'medium' : 'short');

    // Depth from the crease strength along the line.
    final strengths = <double>[];
    for (final p in allPx) {
      var best = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final x = (p.x + dx).round(), y = (p.y + dy).round();
          if (x < 0 || y < 0 || x >= creases.width || y >= creases.height) continue;
          best = math.max(best, creases.response.at(x, y));
        }
      }
      strengths.add(best);
    }
    final meanS = strengths.isEmpty ? 0.0 : strengths.reduce((a, b) => a + b) / strengths.length;
    final depth = meanS >= 0.62 ? 'deep' : (meanS < 0.38 ? 'faint' : 'medium');

    // Fast lookup of line pixels.
    final w = creases.width;
    final near = <int, int>{}; // pixel → index in allPx
    for (var i = 0; i < allPx.length; i++) {
      final p = allPx[i];
      for (var dy = -3; dy <= 3; dy++) {
        for (var dx = -3; dx <= 3; dx++) {
          near.putIfAbsent((p.y.round() + dy) * w + p.x.round() + dx, () => i);
        }
      }
    }

    // Chains and islands show up as many junctions along the line.
    var junctionsOn = 0;
    for (final j in graph.junctions) {
      if (near.containsKey(j.y.round() * w + j.x.round())) junctionsOn++;
    }
    // Junctions per third of a palm width of line.
    final pxLen = allPx.length.toDouble();
    final per100 = junctionsOn / math.max(1.0, pxLen / (pw / 3));
    var cv = 0.0;
    if (strengths.length > 4) {
      final varS = strengths.map((s) => (s - meanS) * (s - meanS)).reduce((a, b) => a + b) / strengths.length;
      cv = meanS == 0 ? 0 : math.sqrt(varS) / meanS;
    }
    final chained = per100 >= 4.5 || (per100 >= 2.5 && cv > 0.45);

    // Side segments touching the line: forks at the end, branches elsewhere.
    var up = false, down = false, fork = false;
    final endPt = allPx.last;
    final (endU, endV) = frame.toUV(endPt.x, endPt.y);
    final tail = allUv.length > 8 ? allUv[(allUv.length * 0.85).floor()] : allUv.first;
    final endTx = endU - tail.$1, endTy = endV - tail.$2;
    for (final s in graph.segments) {
      if (lineSegs.contains(s.id)) continue;
      if (s.length < pw * 0.035) continue;
      for (final (attach, far) in [(s.pts.first, s.pts.last), (s.pts.last, s.pts.first)]) {
        final idx = near[attach.y.round() * w + attach.x.round()];
        if (idx == null) continue;
        final rel = allPx.length <= 1 ? 0.0 : idx / (allPx.length - 1);
        final (au, av) = frame.toUV(attach.x, attach.y);
        final (fu, fv) = frame.toUV(far.x, far.y);
        if (rel >= 0.82) {
          final bx = fu - au, by = fv - av;
          final cos = (bx * endTx + by * endTy) /
              (math.sqrt(bx * bx + by * by) * math.sqrt(endTx * endTx + endTy * endTy) + 1e-9);
          if (cos > 0.25 && !fork) {
            fork = true;
            events.add(LineEvent('fork', tAt(attach)));
          }
        } else if (rel > 0.08) {
          if (fv < av - 0.02) {
            up = true;
            events.add(LineEvent('branch_up', tAt(attach)));
          }
          if (fv > av + 0.02) {
            down = true;
            events.add(LineEvent('branch_down', tAt(attach)));
          }
        }
        break;
      }
    }
    final branches = up && down ? 'both' : (up ? 'up' : (down ? 'down' : 'none'));

    // Shape: how far the line bows away from its chord.
    final a = allUv.first, b = allUv.last;
    final cx = b.$1 - a.$1, cy = b.$2 - a.$2;
    final chord = math.sqrt(cx * cx + cy * cy);
    var maxDev = 0.0;
    if (chord > 0) {
      for (final p in allUv) {
        final dev = ((p.$1 - a.$1) * cy - (p.$2 - a.$2) * cx).abs() / chord;
        maxDev = math.max(maxDev, dev);
      }
    }
    final bow = chord == 0 ? 0 : maxDev / chord;
    final curve = bow < 0.06 ? 'straight' : (bow < 0.16 ? 'gentle' : 'steep');

    final breaks = gapCount == 0 ? 'none' : (gapCount <= 2 ? 'some' : 'many');
    final score = pieces.map((e) => e.score / e.template.boost).reduce(math.max);

    return DetectedLine(
      key,
      LineFeature(
        present: true,
        length: length,
        depth: depth,
        breaks: breaks,
        chained: chained,
        fork: fork,
        branches: branches,
        curve: curve,
        start: PalmMap.nearest(a.$1, a.$2),
        end: PalmMap.nearest(b.$1, b.$2),
        confidence: math.min(1.0, score / 0.55),
        events: events..sort((x, y) => x.t.compareTo(y.t)),
      ),
      orientedPx,
    );
  }

  ({double score, double tMin, double tMax})? _match(List<(double, double)> uv, LineTemplate t) {
    final step = math.max(1, uv.length ~/ 40);
    var n = 0, inliers = 0;
    var distSum = 0.0, cosSum = 0.0;
    var tMin = 1.0, tMax = 0.0;
    for (var i = 0; i < uv.length; i += step) {
      final p = uv[i];
      final pr = t.project(p.$1, p.$2);
      n++;
      distSum += pr.dist;
      final j0 = math.max(0, i - 3), j1 = math.min(uv.length - 1, i + 3);
      final dx = uv[j1].$1 - uv[j0].$1, dy = uv[j1].$2 - uv[j0].$2;
      final dl = math.sqrt(dx * dx + dy * dy);
      final cos = dl == 0 ? 0.0 : ((dx * pr.tx + dy * pr.ty) / dl).abs();
      cosSum += cos;
      if (pr.dist < t.tolerance * 1.5) {
        inliers++;
        tMin = math.min(tMin, pr.t);
        tMax = math.max(tMax, pr.t);
      }
    }
    if (n == 0) return null;
    final inlierFrac = inliers / n;
    if (inlierFrac < 0.6 || tMax <= tMin) return null;
    final meanDist = distSum / n;
    final meanCos = cosSum / n;
    final span = tMax - tMin;
    final score = math.pow(span, 0.7) *
        math.exp(-(meanDist / t.tolerance) * (meanDist / t.tolerance)) *
        meanCos *
        meanCos *
        inlierFrac;
    return (score: score.toDouble(), tMin: tMin, tMax: tMax);
  }

  static double _uvLength(List<(double, double)> uv) {
    var s = 0.0;
    for (var i = 1; i < uv.length; i++) {
      final du = uv[i].$1 - uv[i - 1].$1, dv = uv[i].$2 - uv[i - 1].$2;
      s += math.sqrt(du * du + dv * dv);
    }
    return s;
  }
}

/// A line found by [LineClassifier._traceCorridor]: its pieces (start →
/// end, split at breaks), mean strength and template span.
class _Trace {
  _Trace(this.runs, this.strength, this.tMin, this.tMax);
  final List<List<Pt>> runs;
  final double strength;
  final double tMin;
  final double tMax;
}

class _Cand {
  _Cand(this.curve, this.template, this.score, this.tMin, this.tMax);
  final int curve;
  final LineTemplate template;
  final double score;
  final double tMin;
  final double tMax;
}
