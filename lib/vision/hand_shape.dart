import 'dart:math' as math;
import 'dart:typed_data';

import 'float_image.dart';
import 'palm_geometry.dart';

/// One finger as measured on the photo, in working-image pixels.
class FingerShape {
  FingerShape({
    required this.name,
    required this.baseX,
    required this.baseY,
    required this.tipX,
    required this.tipY,
    required this.rows,
    this.joints,
  });

  /// `index`, `middle`, `ring` or `little`.
  final String name;

  /// Middle of the finger where it leaves the palm (its web), and its tip.
  final double baseX, baseY, tipX, tipY;

  /// Skin run (left, right) on each image row from the tip down to the
  /// base, keyed by row.
  final Map<int, (int, int)> rows;

  /// Knuckle creases, as fractions of the length from the base (the base
  /// phalanx ends at the first, the middle one at the second).
  final (double, double)? joints;

  double get length => math.sqrt((tipX - baseX) * (tipX - baseX) + (tipY - baseY) * (tipY - baseY));

  /// Lean of the finger: cosine of its angle from straight up. Widths are
  /// measured across image rows, so they are multiplied by this.
  double get _cos => length == 0 ? 1 : ((baseY - tipY) / length).abs();

  /// Width across the finger at [f] of its length from the base (0) to the
  /// tip (1), or null where it was not traced.
  double? widthAt(double f) {
    final y = (baseY - f * (baseY - tipY)).round();
    final r = rows[y];
    return r == null ? null : (r.$2 - r.$1 + 1) * _cos;
  }

  /// Width [d] pixels below the tip.
  double? widthBelowTip(double d) {
    final r = rows[(tipY + d / _cos).round()];
    return r == null ? null : (r.$2 - r.$1 + 1) * _cos;
  }

  /// Fingertip shape from the outline of the last joint: `pointed`,
  /// `conic` (oval, rounded), `square` or `spatulate` (wider at the tip).
  String? get tip {
    final mid = widthAt(0.5);
    if (mid == null || mid < 6) return null;
    // Spatulate: the end of the finger is wider than its middle.
    var widest = 0.0;
    for (var f = 0.8; f <= 0.93; f += 0.01) {
      widest = math.max(widest, widthAt(f) ?? 0);
    }
    if (widest >= mid * 1.05) return 'spatulate';
    // How full the tip is just below its top: a half circle gives 0.65 at
    // 0.12 widths down, a square tip with small corners over 0.9.
    final near = widthBelowTip(mid * 0.12);
    if (near == null) return null;
    final t = near / mid;
    return t >= 0.8 ? 'square' : (t >= 0.58 ? 'conic' : 'pointed');
  }

  /// Width near the base against the middle of the finger.
  double? get baseRatio {
    final b = widthAt(0.15), m = widthAt(0.5);
    return b == null || m == null || m == 0 ? null : b / m;
  }

  /// The longest of the three phalanges, when the knuckle creases were
  /// found and one is clearly longer: `base`, `middle` or `tip`.
  String? get longPhalanx {
    final j = joints;
    if (j == null) return null;
    final parts = {'base': j.$1, 'middle': j.$2 - j.$1, 'tip': 1 - j.$2};
    final best = parts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 0.38 ? best.key : 'even';
  }
}

/// The thumb: from the web between thumb and index finger to its tip.
class ThumbShape {
  ThumbShape(this.webX, this.webY, this.tipX, this.tipY, this.width);
  final double webX, webY, tipX, tipY;

  /// Width across the thumb half way along it.
  final double width;

  double get length => math.sqrt((tipX - webX) * (tipX - webX) + (tipY - webY) * (tipY - webY));
}

/// Shape of the fingers and thumb, measured from the hand mask and the
/// gray image, with the categories palmistry reads from them. Every value
/// is null when it could not be measured (fingers touching all the way,
/// thumb out of the picture), so no rule fires on a guess.
///
/// Typical proportions (lengths from the finger web, as measured here):
/// index 0.90, ring 0.94 and little finger 0.74 of the middle finger; the
/// thumb from its web 0.65 of the palm width and 0.26 of it thick.
class HandShape {
  HandShape({required this.fingers, required this.thumb, required this.palmWidth, required this.palmHeight});

  final Map<String, FingerShape> fingers;
  final ThumbShape? thumb;
  final double palmWidth, palmHeight;

  static const fingerNames = ['index', 'middle', 'ring', 'little'];

  /// Tests set this to see how the fingers were traced.
  static void Function(String message)? debug;

  /// Tests set this to get the fine hand mask (mask, width, height).
  static void Function(Uint8List mask, int w, int h)? debugMask;

  /// Tests set this to get the seams between the fingers (x per row from
  /// [top]).
  static void Function(List<List<int>> seams, int top)? debugSeams;

  /// Typical length of each finger against the middle finger, measured
  /// from each finger's own web (so the little finger, set lower, reads
  /// shorter than in bone measurements): between textbook proportions and
  /// a real hand of ordinary proportions measured with this code (index
  /// 0.82, ring 0.87, little 0.56; middle 1.18 of index and ring).
  static const _typical = {'index': 0.86, 'ring': 0.90, 'little': 0.64};
  static const _typicalMiddle = 1.13;

  /// Each finger's development: `short`, `medium` or `long` for its kind.
  /// The middle finger is compared with the index and ring fingers, the
  /// others with the middle finger.
  Map<String, String> get development {
    final out = <String, String>{};
    final m = fingers['middle']?.length;
    if (m == null || m == 0) return out;
    for (final e in _typical.entries) {
      final f = fingers[e.key];
      if (f == null) continue;
      final r = f.length / m - e.value;
      out[e.key] = r > 0.07 ? 'long' : (r < -0.09 ? 'short' : 'medium');
    }
    final i = fingers['index']?.length, r = fingers['ring']?.length;
    if (i != null && r != null && i + r > 0) {
      final d = m / ((i + r) / 2) - _typicalMiddle;
      out['middle'] = d > 0.08 ? 'long' : (d < -0.08 ? 'short' : 'medium');
    }
    return out;
  }

  /// The commonest fingertip shape of the four fingers (the middle finger
  /// decides a tie).
  String? get tips => _mode([for (final n in fingerNames) fingers[n]?.tip], fingers['middle']?.tip);

  /// Fingers that narrow where they join the palm (Air), keep an even
  /// width (Fire), or widen at the base (Water).
  String? get fingerBase {
    final rs = [for (final f in fingers.values) f.baseRatio].whereType<double>().toList()..sort();
    if (rs.length < 3) return null;
    final m = rs[rs.length ~/ 2];
    return m < 0.97 ? 'narrowing' : (m > 1.12 ? 'widening' : 'even');
  }

  /// Which phalanges stand out across the fingers.
  String? get phalanx => _mode([for (final n in fingerNames) fingers[n]?.longPhalanx], fingers['middle']?.longPhalanx);

  String? get thumbLength {
    final t = thumb;
    if (t == null || palmWidth == 0) return null;
    final r = t.length / palmWidth;
    return r < 0.55 ? 'short' : (r > 0.78 ? 'long' : 'medium');
  }

  String? get thumbBuild {
    final t = thumb;
    if (t == null || palmWidth == 0) return null;
    final r = t.width / palmWidth;
    return r < 0.22 ? 'slim' : (r > 0.31 ? 'thick' : 'medium');
  }

  static String? _mode(List<String?> values, String? tieBreak) {
    final counts = <String, int>{};
    for (final v in values.whereType<String>()) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final best = counts.values.reduce(math.max);
    final top = [for (final e in counts.entries) if (e.value == best) e.key];
    if (top.length == 1) return top.first;
    return top.contains(tieBreak) ? tieBreak : top.first;
  }

  /// Measures the fingers and thumb. [mask] is the hand (1 = skin) and
  /// [gray] the brightness, both in working-image pixels, where [frame] is
  /// the palm rectangle. Returns null when the fingers cannot be told
  /// apart.
  static HandShape? measure({required Uint8List mask, required FloatImage gray, required PalmFrame frame}) {
    final w = gray.width, h = gray.height;
    final pw = frame.width;
    if (pw < 40) return null;
    final g = gray.blur(1);
    debugMask?.call(mask, w, h);
    // Half width of the window a pixel is compared with.
    final k = math.max(3, (pw * 0.03).round());

    bool skin(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] != 0;

    // How a pixel compares with the skin beside it: under 1 in a crease or
    // in the crevice between two fingers that touch. Background counts as
    // a clear gap, but no cheaper than a crevice, so a seam does not cut
    // across a finger to reach it.
    double cost(int x, int y) {
      if (!skin(x, y)) return 0.5;
      var s = 0.0;
      var n = 0;
      for (var d = -k; d <= k; d += 2) {
        final xx = x + d;
        if (xx < 0 || xx >= w) continue;
        s += g.data[y * w + xx];
        n++;
      }
      final m = s / n;
      return m <= 0 ? 1 : (g.data[y * w + x] / m).clamp(0.5, 1.2);
    }

    // The four fingers together are as wide as the palm where they join
    // it. (A row just above the palm can miss the little finger, which
    // often sits lower and already stands apart there.)
    final ys = (frame.y0 - pw * 0.06).round();
    if (ys < 4) return null;
    final a = frame.x0.round(), b = frame.x1.round();
    final span = (b - a).toDouble();

    // Highest skin over the fingers.
    var yTop = ys;
    for (var y = 0; y < ys; y++) {
      var any = false;
      for (var x = math.max(0, a - (pw * 0.1).round()); x <= math.min(w - 1, b + (pw * 0.1).round()); x += 2) {
        if (mask[y * w + x] != 0) {
          any = true;
          break;
        }
      }
      if (any) {
        yTop = y;
        break;
      }
    }
    final yBottom = math.min(h - 1, (frame.y0 + pw * 0.06).round());
    final nRows = yBottom - yTop + 1;
    if (nRows < pw * 0.4) return null;

    // Three seams between the fingers: the darkest path from just inside
    // the palm up past the fingertips, moving at most a pixel sideways per
    // row and staying near where that gap is on a typical hand (index
    // 0.26 of the width, middle 0.27, ring 0.25, little 0.22).
    const splits = [0.26, 0.53, 0.78];
    final band = (pw * 0.12).round();
    final seams = <List<int>>[]; // x per row, index 0 = yTop
    for (final f in splits) {
      final x0 = (frame.thumbOnLeft ? a + span * f : b - span * f).round();
      final lo = math.max(1, x0 - band), hi = math.min(w - 2, x0 + band);
      final cols = hi - lo + 1;
      final acc = Float64List(nRows * cols);
      final from = Int8List(nRows * cols);
      for (var r = nRows - 1; r >= 0; r--) {
        final y = yTop + r;
        for (var c = 0; c < cols; c++) {
          final x = lo + c;
          var best = 0.0;
          if (r == nRows - 1) {
            // Start near the expected gap.
            best = (x - x0).abs() <= pw * 0.06 ? 0 : 1e9;
          } else {
            best = double.infinity;
            for (var d = -1; d <= 1; d++) {
              final cc = c + d;
              if (cc < 0 || cc >= cols) continue;
              final v = acc[(r + 1) * cols + cc] + (d == 0 ? 0 : 0.01);
              if (v < best) {
                best = v;
                from[r * cols + c] = d;
              }
            }
          }
          acc[r * cols + c] = best + cost(x, y);
        }
      }
      var c = 0;
      for (var cc = 1; cc < cols; cc++) {
        if (acc[cc] < acc[c]) c = cc;
      }
      final xs = List<int>.filled(nRows, 0);
      for (var r = 0; r < nRows; r++) {
        xs[r] = lo + c;
        if (r < nRows - 1) c += from[r * cols + c];
      }
      seams.add(xs);
    }

    // Each seam's web: going down it, the last row where it still runs in
    // a gap or a clearly dark crevice (short interruptions allowed). It is
    // not below the top of the palm: lower down a seam only follows the
    // palm's own creases.
    //
    // Searched upwards from the palm: fingers pressed together can hide
    // the crevice higher up, so the first clearly dark stretch above the
    // palm marks the web.
    final webs = <int>[];
    final stretch = math.max(4, (pw * 0.05).round());
    bool dark(int y) {
      final r = y - yTop;
      return r >= 0 && r < nRows && cost(seams[webs.length][r], y) < 0.9;
    }

    for (var si = 0; si < seams.length; si++) {
      var web = frame.y0.round();
      for (var y = frame.y0.round(); y > frame.y0 - pw * 0.3 && y > yTop; y--) {
        if (!dark(y)) continue;
        var n = 0;
        for (var d = 0; d < stretch; d++) {
          if (dark(y - d)) n++;
        }
        if (n >= stretch * 0.6) {
          web = y;
          break;
        }
      }
      webs.add(web);
    }
    debug?.call('span ${(span / pw).toStringAsFixed(2)} top $yTop palm top ${frame.y0.round()} webs $webs');

    // Each finger between its seams (or its seam and the hand's side),
    // from its base up to its tip.
    final minLen = math.max(4, (pw * 0.05).round());
    (int, int)? runBetween(int y, int? lo, int? hi, int inner) {
      // Without a seam on a side, the finger runs to the hand's edge there.
      // A seam may run in the gap beside the finger: step over the gap to
      // the finger first.
      final gapMax = pw * 0.12;
      var l = inner;
      if (lo != null) {
        l = lo;
      } else {
        while (l > 0 && !skin(l, y) && inner - l < gapMax) {
          l--;
        }
        while (l > 0 && skin(l - 1, y) && inner - l < pw * 0.45) {
          l--;
        }
      }
      var r = inner;
      if (hi != null) {
        r = hi;
      } else {
        while (r < w - 1 && !skin(r, y) && r - inner < gapMax) {
          r++;
        }
        while (r < w - 1 && skin(r + 1, y) && r - inner < pw * 0.45) {
          r++;
        }
      }
      var s = l, e = r;
      while (s < e && !skin(s, y)) {
        s++;
      }
      while (e > s && !skin(e, y)) {
        e--;
      }
      return e - s + 1 >= minLen ? (s, e) : null;
    }

    final fingers = <String, FingerShape>{};
    for (var fi = 0; fi < 4; fi++) {
      // Seams on either side, in image order.
      final inner = fi == 0 ? 0 : fi - 1, outer = fi == 3 ? 2 : fi;
      final baseY = fi == 0
          ? webs[0]
          : fi == 3
              ? webs[2]
              : ((webs[fi - 1] + webs[fi]) / 2).round();
      final rows = <int, (int, int)>{};
      var tipY = baseY;
      var gap = 0;
      for (var y = baseY; y >= yTop; y--) {
        final r = y - yTop;
        int? lo, hi;
        final int ref;
        if (fi == 0) {
          ref = seams[0][r];
        } else if (fi == 3) {
          ref = seams[2][r];
        } else {
          ref = (seams[inner][r] + seams[outer][r]) ~/ 2;
        }
        // Seam to the thumb side and to the little-finger side.
        final thumbSide = fi == 0 ? null : seams[fi - 1][r];
        final littleSide = fi == 3 ? null : seams[fi][r];
        if (frame.thumbOnLeft) {
          lo = thumbSide;
          hi = littleSide;
        } else {
          lo = littleSide;
          hi = thumbSide;
        }
        final run = runBetween(y, lo == null ? null : lo + 1, hi == null ? null : hi - 1, ref);
        if (run == null) {
          if (++gap > 3) break;
          continue;
        }
        gap = 0;
        rows[y] = run;
        tipY = y;
      }
      final base = rows[baseY], tip = rows[tipY];
      if (base == null || tip == null || tipY <= 2) continue;
      final shape = FingerShape(
        name: fingerNames[fi],
        baseX: (base.$1 + base.$2) / 2,
        baseY: baseY.toDouble(),
        tipX: (tip.$1 + tip.$2) / 2,
        tipY: tipY.toDouble(),
        rows: rows,
      );
      debug?.call('${shape.name}: base $baseY tip $tipY length ${(shape.length / pw).toStringAsFixed(2)}');
      if (shape.length < pw * 0.3) continue;
      fingers[shape.name] = FingerShape(
        name: shape.name,
        baseX: shape.baseX,
        baseY: shape.baseY,
        tipX: shape.tipX,
        tipY: shape.tipY,
        rows: rows,
        joints: _joints(shape, g),
      );
    }
    if (fingers.length < 3) return null;
    debugSeams?.call(seams, yTop);

    return HandShape(
      fingers: fingers,
      thumb: _thumb(mask, w, h, frame),
      palmWidth: pw,
      palmHeight: frame.height,
    );
  }

  /// Knuckle creases: the two darkest bands across the finger, one in the
  /// lower half and one in the upper half, each clearly darker than the
  /// skin around it.
  static (double, double)? _joints(FingerShape f, FloatImage g) {
    final len = f.length;
    if (len < 20) return null;
    final n = len.floor();
    final prof = Float64List(n);
    for (var s = 0; s < n; s++) {
      final y = (f.baseY - s * (f.baseY - f.tipY) / n).round();
      final r = f.rows[y];
      if (r == null) return null;
      final c = (r.$1 + r.$2) / 2, half = (r.$2 - r.$1) * 0.25;
      var sum = 0.0;
      var cnt = 0;
      for (var x = (c - half).round(); x <= (c + half).round(); x++) {
        sum += g.clamped(x, y);
        cnt++;
      }
      prof[s] = sum / math.max(1, cnt);
    }
    final win = math.max(3, (n * 0.07).round());
    double dark(int s) {
      var sum = 0.0;
      var cnt = 0;
      for (var d = -win; d <= win; d++) {
        final j = s + d;
        if (j < 0 || j >= n) continue;
        sum += prof[j];
        cnt++;
      }
      return sum / cnt - prof[s];
    }

    final mean = prof.reduce((a, b) => a + b) / n;
    (int, double) peak(double a, double b) {
      var best = -1;
      var bv = 0.0;
      for (var s = (n * a).round(); s <= (n * b).round() && s < n; s++) {
        final d = dark(s);
        if (d > bv) {
          bv = d;
          best = s;
        }
      }
      return (best, bv);
    }

    final (s1, d1) = peak(0.2, 0.5);
    final (s2, d2) = peak(0.52, 0.82);
    if (s1 < 0 || s2 < 0 || d1 < mean * 0.03 || d2 < mean * 0.03) return null;
    return (s1 / n, s2 / n);
  }

  /// The thumb: the skin outside the palm on the thumb side. Its web is the
  /// lowest point of the gap between thumb and index finger; its tip the
  /// thumb pixel farthest from the web.
  static ThumbShape? _thumb(Uint8List mask, int w, int h, PalmFrame frame) {
    // Only real gaps count here: the creases at the ball of the thumb are
    // dark too, and would look like a gap all the way down.
    bool sep(int x, int y) => x < 0 || y < 0 || x >= w || y >= h || mask[y * w + x] == 0;
    final pw = frame.width;
    final left = frame.thumbOnLeft;
    final edge = left ? frame.x0 : frame.x1;
    final out = left ? -1 : 1;
    bool beyond(int x) => left ? x < edge - pw * 0.04 : x > edge + pw * 0.04;

    // Going down the palm side: rows with a thumb run that is split from
    // the palm by a gap. The last such row is the web.
    int? webY;
    double? webX;
    for (var y = math.max(1, (frame.y0 - pw * 0.6).round()); y < frame.y1; y++) {
      // Walk out from inside the palm to the palm edge, then across a gap.
      var x = (edge - out * pw * 0.1).round();
      while (x > 0 && x < w - 1 && !sep(x, y)) {
        x += out;
      }
      final gapStart = x;
      while (x > 0 && x < w - 1 && sep(x, y) && (x - gapStart).abs() < pw * 0.5) {
        x += out;
      }
      final hasThumb = x > 0 && x < w - 1 && !sep(x, y) && beyond(x) && (x - gapStart).abs() >= 2;
      if (hasThumb) {
        webY = y;
        webX = gapStart.toDouble();
      } else if (webY != null && y > webY + pw * 0.05) {
        break;
      }
    }
    if (webY == null || webX == null) return null;

    // Tip: the thumb pixel farthest from the web.
    var best = 0.0;
    var tx = 0, ty = 0;
    for (var y = math.max(0, (webY - pw * 0.9).round()); y < math.min(h, webY + pw * 0.6); y++) {
      for (var x = 0; x < w; x++) {
        if (mask[y * w + x] == 0 || !beyond(x)) continue;
        final d = (x - webX) * (x - webX) + (y - webY) * (y - webY);
        if (d > best) {
          best = d.toDouble();
          tx = x;
          ty = y;
        }
      }
    }
    // A thumb that runs off the picture cannot be measured.
    if (best == 0 || tx <= 4 || tx >= w - 5 || ty <= 4) return null;

    // Width half way along, across the thumb.
    final mx = (webX + tx) / 2, my = (webY + ty) / 2;
    final ax = tx - webX, ay = ty - webY;
    final al = math.sqrt(ax * ax + ay * ay);
    final nx = -ay / al, ny = ax / al;
    bool skin(double x, double y) {
      final xi = x.round(), yi = y.round();
      return xi >= 0 && yi >= 0 && xi < w && yi < h && mask[yi * w + xi] != 0;
    }

    if (!skin(mx, my)) return null;
    var a = 0.0, b = 0.0;
    while (skin(mx + nx * (a + 1), my + ny * (a + 1)) && a < pw) {
      a++;
    }
    while (skin(mx - nx * (b + 1), my - ny * (b + 1)) && b < pw) {
      b++;
    }
    final width = a + b + 1;
    // Wider than half the palm: the cut went along the palm, not across
    // the thumb.
    if (width > pw * 0.5) return null;
    return ThumbShape(webX, webY.toDouble(), tx.toDouble(), ty.toDouble(), width);
  }
}
