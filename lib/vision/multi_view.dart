import 'dart:math' as math;
import 'dart:typed_data';

import 'crease_detector.dart';
import 'float_image.dart';
import 'palm_geometry.dart';

/// Maps pixels of the primary photo's working image to the matching
/// pixels of another photo of the same palm.
///
/// The palm frames give the first guess (same palm coordinates in both
/// photos); a small rotation, per-axis scale and shift about the palm
/// centre, found by [registerView], corrects it.
class ViewWarp {
  ViewWarp({
    required this.from,
    required this.to,
    this.tx = 0,
    this.ty = 0,
    this.angle = 0,
    this.sx = 1,
    this.sy = 1,
  })  : _cx = (from.x0 + from.x1) / 2,
        _cy = (from.y0 + from.y1) / 2,
        _cos = math.cos(angle),
        _sin = math.sin(angle);

  final PalmFrame from;
  final PalmFrame to;
  final double tx, ty, angle, sx, sy;
  final double _cx, _cy, _cos, _sin;

  (double, double) map(double x, double y) {
    final dx = x - _cx, dy = y - _cy;
    final qx = _cx + sx * (_cos * dx - _sin * dy) + tx;
    final qy = _cy + sy * (_sin * dx + _cos * dy) + ty;
    final (u, v) = from.toUV(qx, qy);
    return to.toXY(u, v);
  }

  ViewWarp copyWith({double? tx, double? ty, double? angle, double? sx, double? sy}) => ViewWarp(
        from: from,
        to: to,
        tx: tx ?? this.tx,
        ty: ty ?? this.ty,
        angle: angle ?? this.angle,
        sx: sx ?? this.sx,
        sy: sy ?? this.sy,
      );
}

/// Aligns another photo's crease response ([moving]) to the primary
/// one ([ref]) by maximizing their normalized cross-correlation inside
/// the primary palm. Returns null when the two do not line up well
/// (different pose, or not the same hand side).
({ViewWarp warp, double score})? registerView({
  required FloatImage ref,
  required Uint8List refMask,
  required PalmFrame refFrame,
  required FloatImage moving,
  required PalmFrame movingFrame,
  double minScore = 0.3,
}) {
  if (refFrame.thumbOnLeft != movingFrame.thumbOnLeft) return null;
  final w = ref.width, h = ref.height;
  // Blur widens the creases so the search has a smooth basin.
  final a = ref.blur(2);
  final b = moving.blur(2);

  // Sample points: every third palm pixel.
  final pts = <int>[];
  for (var y = 0; y < h; y += 3) {
    for (var x = 0; x < w; x += 3) {
      if (refMask[y * w + x] != 0) pts.add(y * w + x);
    }
  }
  if (pts.length < 200) return null;

  double ncc(ViewWarp warp) {
    var n = 0;
    var sa = 0.0, sb = 0.0, sab = 0.0, saa = 0.0, sbb = 0.0;
    for (final i in pts) {
      final (mx, my) = warp.map((i % w).toDouble(), (i ~/ w).toDouble());
      if (mx < 0 || my < 0 || mx > b.width - 1 || my > b.height - 1) continue;
      final va = a.data[i], vb = b.sample(mx, my);
      n++;
      sa += va;
      sb += vb;
      sab += va * vb;
      saa += va * va;
      sbb += vb * vb;
    }
    if (n < pts.length * 0.6) return -1;
    final cov = sab - sa * sb / n;
    final da = saa - sa * sa / n, db = sbb - sb * sb / n;
    if (da <= 0 || db <= 0) return -1;
    return cov / math.sqrt(da * db);
  }

  // Coarse shift search, then hill-climb all five parameters.
  var best = ViewWarp(from: refFrame, to: movingFrame);
  var bestScore = ncc(best);
  final range = (refFrame.width * 0.08).round();
  for (var ty = -range; ty <= range; ty += 3) {
    for (var tx = -range; tx <= range; tx += 3) {
      final c = best.copyWith(tx: tx.toDouble(), ty: ty.toDouble(), angle: 0, sx: 1, sy: 1);
      final s = ncc(c);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
  }
  var steps = [1.5, 1.5, 0.02, 0.015, 0.015];
  for (var round = 0; round < 4; round++) {
    var improved = true;
    var guard = 0;
    while (improved && guard++ < 20) {
      improved = false;
      for (var p = 0; p < 5; p++) {
        for (final sign in const [-1.0, 1.0]) {
          final d = steps[p] * sign;
          final c = switch (p) {
            0 => best.copyWith(tx: best.tx + d),
            1 => best.copyWith(ty: best.ty + d),
            2 => best.copyWith(angle: (best.angle + d).clamp(-0.1, 0.1)),
            3 => best.copyWith(sx: (best.sx + d).clamp(0.9, 1.1)),
            _ => best.copyWith(sy: (best.sy + d).clamp(0.9, 1.1)),
          };
          final s = ncc(c);
          if (s > bestScore + 1e-4) {
            bestScore = s;
            best = c;
            improved = true;
          }
        }
      }
    }
    steps = [for (final s in steps) s / 2];
  }
  if (bestScore < minScore) return null;
  return (warp: best, score: bestScore);
}

/// One extra photo (of up to five), aligned to the primary.
class AlignedView {
  AlignedView(this.response, this.mask, this.warp, [this.gray, this.weight = 1]);
  final FloatImage? gray;

  /// How much this photo counts in the stack (0..1), from how well it
  /// registered and how sharp it is. A blurred or badly aligned photo
  /// gets a low weight, so it cannot wash out a line the others show.
  final double weight;

  /// Weight for a photo from its registration score (NCC with the
  /// primary), and its sharpness relative to the primary's.
  static double weightOf(double score, double sharpness, double primarySharpness) {
    final reg = ((score - 0.3) / 0.3).clamp(0.0, 1.0);
    final sharp = primarySharpness <= 0 ? 1.0 : (sharpness / primarySharpness).clamp(0.0, 1.0);
    return reg * sharp * sharp;
  }
  final CreaseResponse response;
  final Uint8List mask;
  final ViewWarp warp;
}

/// Averages the crease responses of several aligned photos in the
/// primary photo's pixels.
///
/// A real crease shows in every photo and keeps its strength; skin
/// texture, sensor noise and glare differ between shots and average
/// out, so faint lines stand clearer above the noise. Each extra
/// response is first spread by one pixel, so small alignment errors do
/// not split a line. The crease direction comes from whichever photo
/// shows that pixel most strongly.
CreaseResponse fuseResponses(CreaseResponse primary, Uint8List mask, List<AlignedView> others) {
  if (others.isEmpty) return primary;
  final w = primary.response.width, h = primary.response.height;
  final spread = [for (final o in others) _max3(o.response.response)];
  final fused = FloatImage(w, h);
  final normal = Float32List.fromList(primary.normal);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      var best = primary.response.data[i];
      var sum = best;
      var n = 1;
      for (var k = 0; k < others.length; k++) {
        final o = others[k];
        final (mx, my) = o.warp.map(x.toDouble(), y.toDouble());
        final ox = mx.round(), oy = my.round();
        final ow = o.response.response.width;
        if (ox < 0 || oy < 0 || ox >= ow || oy >= o.response.response.height) continue;
        final oi = oy * ow + ox;
        if (o.mask[oi] == 0) continue;
        final v = spread[k].sample(mx, my);
        sum += v;
        n++;
        if (v > best) {
          best = v;
          normal[i] = o.response.normal[oi] - o.warp.angle;
        }
      }
      fused.data[i] = sum / n;
    }
  }
  final ref = fused.percentile(0.985, mask: mask);
  if (ref > 0) {
    for (var i = 0; i < fused.data.length; i++) {
      fused.data[i] = math.min(1.0, fused.data[i] / ref);
    }
  }
  return CreaseResponse(response: fused, normal: normal, background: primary.background);
}

/// Stacks the aligned photos' brightness onto the primary photo's pixels.
///
/// Each photo is first flattened by its own local mean (so exposure and
/// torch on/off differences cancel), then the flat images are averaged.
/// Sensor noise and skin texture that differ per shot shrink by about
/// 1/sqrt(n) while a real crease, present in every shot, keeps its depth;
/// the crease detector then runs on the stack. This beats averaging the
/// responses, because the Hessian response of noise is always positive
/// and does not average away.
FloatImage stackGray(FloatImage primary, FloatImage primaryBg, Uint8List mask, List<AlignedView> others) {
  final w = primary.width, h = primary.height;
  final out = FloatImage(w, h);
  final flatOthers = [
    for (final o in others)
      if (o.gray != null && o.weight > 0.1) (o, o.gray!, o.response.background),
  ];
  // A pixel much brighter than its surroundings is a specular highlight
  // (glare, torch reflection): it hides creases, so that photo does not
  // vote there.
  bool glare(double v, double bg) => v > 238 || v > bg * 1.35 + 12;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 0) {
        out.data[i] = primary.data[i];
        continue;
      }
      final pb = primaryBg.data[i] + 1.0;
      final pv = primary.data[i];
      var sum = 0.0, wsum = 0.0;
      if (!glare(pv, primaryBg.data[i])) {
        sum = pv / pb;
        wsum = 1;
      }
      for (final (o, g, bg) in flatOthers) {
        final (mx, my) = o.warp.map(x.toDouble(), y.toDouble());
        if (mx < 1 || my < 1 || mx > g.width - 2 || my > g.height - 2) continue;
        if (o.mask[my.round() * g.width + mx.round()] == 0) continue;
        final v = g.sample(mx, my), b = bg.sample(mx, my);
        if (glare(v, b)) continue;
        sum += o.weight * v / (b + 1.0);
        wsum += o.weight;
      }
      // Scale back to a brightness-like range so the detector sees the
      // same flattened values as for one photo.
      out.data[i] = wsum > 0 ? sum / wsum * pb : pv;
    }
  }
  return out;
}

/// 3×3 maximum filter.
FloatImage _max3(FloatImage src) {
  final w = src.width, h = src.height;
  final out = FloatImage(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final v = src.data[yy * w + xx];
          if (v > m) m = v;
        }
      }
      out.data[y * w + x] = m;
    }
  }
  return out;
}
