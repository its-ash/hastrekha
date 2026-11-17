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
/// centre, found by [registerView], corrects it. A hand is not rigid and
/// photos from different distances differ in perspective, so
/// [refineWarp] then adds a smooth local [field] of small shifts.
class ViewWarp {
  ViewWarp({
    required this.from,
    required this.to,
    this.tx = 0,
    this.ty = 0,
    this.angle = 0,
    this.sx = 1,
    this.sy = 1,
    this.field,
  })  : _cx = (from.x0 + from.x1) / 2,
        _cy = (from.y0 + from.y1) / 2,
        _cos = math.cos(angle),
        _sin = math.sin(angle);

  final PalmFrame from;
  final PalmFrame to;
  final double tx, ty, angle, sx, sy;
  final double _cx, _cy, _cos, _sin;

  /// Local correction applied before the global warp (primary pixels).
  final LocalField? field;

  (double, double) map(double x, double y) {
    final f = field;
    if (f != null) {
      final (ox, oy) = f.offset(x, y);
      x += ox;
      y += oy;
    }
    final dx = x - _cx, dy = y - _cy;
    final qx = _cx + sx * (_cos * dx - _sin * dy) + tx;
    final qy = _cy + sy * (_sin * dx + _cos * dy) + ty;
    final (u, v) = from.toUV(qx, qy);
    return to.toXY(u, v);
  }

  ViewWarp copyWith({double? tx, double? ty, double? angle, double? sx, double? sy, LocalField? field}) => ViewWarp(
        from: from,
        to: to,
        tx: tx ?? this.tx,
        ty: ty ?? this.ty,
        angle: angle ?? this.angle,
        sx: sx ?? this.sx,
        sy: sy ?? this.sy,
        field: field ?? this.field,
      );

  /// How well this photo lines up at a primary pixel (0..1); 1 without a
  /// local field.
  double confidenceAt(double x, double y) => field?.confidenceAt(x, y) ?? 1;
}

/// Smooth field of small shifts on a coarse grid of primary pixels, with
/// how well each cell lined up. Values between grid points are bilinear.
class LocalField {
  LocalField(this.cols, this.rows, this.cell, this.dx, this.dy, this.conf);
  final int cols, rows;
  final double cell;
  final Float32List dx, dy, conf;

  (int, int, double, double) _at(double x, double y) {
    final gx = (x / cell - 0.5).clamp(0.0, cols - 1.0);
    final gy = (y / cell - 0.5).clamp(0.0, rows - 1.0);
    final x0 = math.min(gx.floor(), cols - 2 < 0 ? 0 : cols - 2);
    final y0 = math.min(gy.floor(), rows - 2 < 0 ? 0 : rows - 2);
    return (x0, y0, gx - x0, gy - y0);
  }

  double _lerp(Float32List g, int x0, int y0, double fx, double fy) {
    final x1 = math.min(x0 + 1, cols - 1), y1 = math.min(y0 + 1, rows - 1);
    final a = g[y0 * cols + x0], b = g[y0 * cols + x1];
    final c = g[y1 * cols + x0], d = g[y1 * cols + x1];
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  }

  (double, double) offset(double x, double y) {
    final (x0, y0, fx, fy) = _at(x, y);
    return (_lerp(dx, x0, y0, fx, fy), _lerp(dy, x0, y0, fx, fy));
  }

  double confidenceAt(double x, double y) {
    final (x0, y0, fx, fy) = _at(x, y);
    return _lerp(conf, x0, y0, fx, fy);
  }
}

/// Refines a global [warp] with local shifts.
///
/// The moving response is first resampled into the primary's pixels with
/// the global warp. The primary palm is then cut into overlapping tiles
/// (about an eighth of the palm wide); each tile finds the shift (up to
/// [maxShift] pixels, sub-pixel from a parabola fit) that best matches
/// the primary there. Tiles without enough crease structure, with a weak
/// match or a shift far from their neighbours take their neighbours'
/// shift. Without this, a hand photographed from three distances lines
/// up to within a few pixels only, and averaging smears thin lines.
ViewWarp refineWarp({
  required FloatImage ref,
  required Uint8List refMask,
  required FloatImage moving,
  required ViewWarp warp,
  int maxShift = 7,
}) {
  final w = ref.width, h = ref.height;
  final a = ref.blur(1.2);
  final mb = moving.blur(1.2);
  final b = FloatImage(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (mx, my) = warp.map(x.toDouble(), y.toDouble());
      b.data[y * w + x] =
          (mx < 0 || my < 0 || mx > mb.width - 1 || my > mb.height - 1) ? double.nan : mb.sample(mx, my);
    }
  }

  final cell = math.max(16.0, warp.from.width / 8);
  final cols = math.max(1, (w / cell).ceil()), rows = math.max(1, (h / cell).ceil());
  final half = (cell * 0.8).round();
  final dx = Float32List(cols * rows), dy = Float32List(cols * rows), conf = Float32List(cols * rows);
  final valid = List<bool>.filled(cols * rows, false);
  final span = 2 * maxShift + 1;
  final scores = Float64List(span * span);

  for (var gy = 0; gy < rows; gy++) {
    for (var gx = 0; gx < cols; gx++) {
      final g = gy * cols + gx;
      final cx = ((gx + 0.5) * cell).round(), cy = ((gy + 0.5) * cell).round();
      // Sample points of this tile inside the palm, every second pixel.
      final pts = <int>[];
      for (var y = cy - half; y <= cy + half; y += 2) {
        if (y < maxShift || y >= h - maxShift) continue;
        for (var x = cx - half; x <= cx + half; x += 2) {
          if (x < maxShift || x >= w - maxShift) continue;
          if (refMask[y * w + x] != 0) pts.add(y * w + x);
        }
      }
      if (pts.length < half * half * 0.25) continue;
      var sa = 0.0, saa = 0.0;
      for (final i in pts) {
        sa += a.data[i];
        saa += a.data[i] * a.data[i];
      }
      final n0 = pts.length;
      final da = saa - sa * sa / n0;
      // Too little structure (no creases) to align on.
      if (da / n0 < 1e-4) continue;
      var best = -2.0;
      var bi = -1;
      for (var sy = -maxShift; sy <= maxShift; sy++) {
        for (var sx = -maxShift; sx <= maxShift; sx++) {
          final off = sy * w + sx;
          var n = 0;
          var sb = 0.0, sab = 0.0, sbb = 0.0, sa2 = 0.0, saa2 = 0.0;
          for (final i in pts) {
            final vb = b.data[i + off];
            if (vb.isNaN) continue;
            final va = a.data[i];
            n++;
            sa2 += va;
            saa2 += va * va;
            sb += vb;
            sab += va * vb;
            sbb += vb * vb;
          }
          var s = -1.0;
          if (n > n0 * 0.8) {
            final cov = sab - sa2 * sb / n;
            final va = saa2 - sa2 * sa2 / n, vb = sbb - sb * sb / n;
            if (va > 0 && vb > 0) s = cov / math.sqrt(va * vb);
          }
          final k = (sy + maxShift) * span + sx + maxShift;
          scores[k] = s;
          if (s > best) {
            best = s;
            bi = k;
          }
        }
      }
      if (bi < 0 || best < 0.25) continue;
      final bx = bi % span, by = bi ~/ span;
      // A peak on the edge of the search is not a real match.
      if (bx == 0 || by == 0 || bx == span - 1 || by == span - 1) continue;
      double sub(double l, double c, double r) {
        final d = l - 2 * c + r;
        return d >= 0 ? 0 : (0.5 * (l - r) / d).clamp(-0.5, 0.5);
      }

      dx[g] = bx - maxShift + sub(scores[bi - 1], best, scores[bi + 1]);
      dy[g] = by - maxShift + sub(scores[bi - span], best, scores[bi + span]);
      conf[g] = best;
      valid[g] = true;
    }
  }
  if (!valid.contains(true)) return warp;

  // Drop shifts far from their neighbours' median (a tile that locked on
  // the wrong crease), then fill and smooth.
  double median(List<double> v) => (v..sort())[v.length ~/ 2];
  final keep = List<bool>.from(valid);
  for (var g = 0; g < cols * rows; g++) {
    if (!valid[g]) continue;
    final gx = g % cols, gy = g ~/ cols;
    final nx = <double>[], ny = <double>[];
    for (var yy = gy - 1; yy <= gy + 1; yy++) {
      for (var xx = gx - 1; xx <= gx + 1; xx++) {
        if (xx < 0 || yy < 0 || xx >= cols || yy >= rows || (xx == gx && yy == gy)) continue;
        final k = yy * cols + xx;
        if (valid[k]) {
          nx.add(dx[k]);
          ny.add(dy[k]);
        }
      }
    }
    if (nx.length >= 2) {
      final ex = dx[g] - median(nx), ey = dy[g] - median(ny);
      if (ex * ex + ey * ey > 2.5 * 2.5) keep[g] = false;
    }
  }
  // Fill cells without a shift from their neighbours, ring by ring; the
  // filled cells carry a low confidence.
  var have = List<bool>.from(keep);
  for (var pass = 0; pass < cols + rows; pass++) {
    final next = List<bool>.from(have);
    var changed = false;
    for (var g = 0; g < cols * rows; g++) {
      if (have[g]) continue;
      final gx = g % cols, gy = g ~/ cols;
      var sx = 0.0, sy = 0.0, sc = 0.0;
      var n = 0;
      for (var yy = gy - 1; yy <= gy + 1; yy++) {
        for (var xx = gx - 1; xx <= gx + 1; xx++) {
          if (xx < 0 || yy < 0 || xx >= cols || yy >= rows) continue;
          final k = yy * cols + xx;
          if (!have[k]) continue;
          sx += dx[k];
          sy += dy[k];
          sc += conf[k];
          n++;
        }
      }
      if (n == 0) continue;
      dx[g] = sx / n;
      dy[g] = sy / n;
      conf[g] = math.min(sc / n, 0.4) * (valid[g] ? 0.6 : 1);
      next[g] = true;
      changed = true;
    }
    have = next;
    if (!changed) break;
  }
  // Light smoothing so the field bends, not jumps, between tiles.
  Float32List smooth(Float32List f) {
    final out = Float32List(f.length);
    for (var g = 0; g < f.length; g++) {
      final gx = g % cols, gy = g ~/ cols;
      var s = f[g] * 2;
      var n = 2.0;
      for (final (xx, yy) in [(gx - 1, gy), (gx + 1, gy), (gx, gy - 1), (gx, gy + 1)]) {
        if (xx < 0 || yy < 0 || xx >= cols || yy >= rows) continue;
        s += f[yy * cols + xx];
        n++;
      }
      out[g] = s / n;
    }
    return out;
  }

  return warp.copyWith(field: LocalField(cols, rows, cell, smooth(dx), smooth(dy), conf));
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
        // Where this photo does not line up well, it counts less.
        final c = o.warp.field == null ? 1.0 : ((o.warp.confidenceAt(x.toDouble(), y.toDouble()) - 0.2) / 0.3).clamp(0.0, 1.0);
        final wt = o.weight * c;
        if (wt <= 0) continue;
        sum += wt * v / (b + 1.0);
        wsum += wt;
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
