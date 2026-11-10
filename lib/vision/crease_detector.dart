import 'dart:math' as math;
import 'dart:typed_data';

import 'float_image.dart';

/// Crease (palm line) enhancement and binarization.
///
/// Palm lines are thin dark valleys in the skin. The detector:
/// 1. flattens lighting by dividing by a heavy blur,
/// 2. measures "valley-ness" with the Hessian (second derivatives) at a
///    few scales: across a crease the intensity curves up strongly, along
///    it barely at all,
/// 3. thins the response with non-maximum suppression across the line,
/// 4. keeps strong ridges, the weaker pixels connected to them
///    (hysteresis) and long weak ridges (faint lines), then skeletonizes
///    to one-pixel-wide lines.
///
/// [respond] and [extract] are separate so the responses of several
/// photos of the same palm can be fused before thresholding.
class CreaseDetector {
  const CreaseDetector({
    this.scales = const [1.4, 2.0, 3.2, 4.5],
    this.high = 0.42,
    this.low = 0.2,
    this.minComponent = 0.033,
    this.weakLength = 0.14,
  });

  /// Gaussian scales in pixels for a palm [refPalmWidth] px wide; scaled
  /// with the actual palm width.
  final List<double> scales;
  static const refPalmWidth = 400.0;

  /// Hysteresis thresholds on the normalized response (0..1).
  final double high;
  final double low;

  /// Smallest skeleton component kept, as a fraction of the palm width.
  final double minComponent;

  /// A connected ridge above [low] this long (fraction of the palm
  /// width) is kept even when no pixel reaches [high]: faint lines are
  /// weak but long, skin texture is weak and short.
  final double weakLength;

  CreaseMap detect(FloatImage gray, Uint8List mask, {required double palmWidth}) =>
      extract(respond(gray, mask, palmWidth: palmWidth), mask, palmWidth: palmWidth);

  /// Steps 1–2: lighting flattening and the normalized valley response.
  CreaseResponse respond(FloatImage gray, Uint8List mask, {required double palmWidth}) {
    final w = gray.width, h = gray.height;

    // 1. Lighting: divide by the local mean brightness of the skin. Only
    // palm pixels are averaged (normalized convolution), and outside the
    // palm the image is set to neutral, so the palm's border with the
    // background does not look like a crease.
    final sigma = math.max(4.0, palmWidth / 22);
    final m = FloatImage(w, h);
    final gm = FloatImage(w, h);
    for (var i = 0; i < m.data.length; i++) {
      if (mask[i] == 0) continue;
      m.data[i] = 1;
      gm.data[i] = gray.data[i];
    }
    final mb = m.blur(sigma), gb = gm.blur(sigma);
    final bg = FloatImage(w, h);
    final flat = FloatImage(w, h);
    for (var i = 0; i < flat.data.length; i++) {
      final b = mb.data[i] > 0.05 ? gb.data[i] / mb.data[i] : gray.data[i];
      bg.data[i] = b;
      flat.data[i] = mask[i] == 0 ? 1.0 : gray.data[i] / (b + 1.0);
    }

    // 2. Multi-scale Hessian valley response.
    final response = FloatImage(w, h);
    final normal = Float32List(w * h); // angle of the line's normal
    for (final s0 in scales) {
      final s = s0 * palmWidth / refPalmWidth;
      final l = flat.blur(s);
      final s2 = s * s;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (mask[i] == 0) continue;
          final c = l.data[i];
          final lxx = l.data[i + 1] - 2 * c + l.data[i - 1];
          final lyy = l.data[i + w] - 2 * c + l.data[i - w];
          final lxy = (l.data[i + w + 1] - l.data[i + w - 1] - l.data[i - w + 1] + l.data[i - w - 1]) * 0.25;
          final half = (lxx - lyy) * 0.5;
          final root = math.sqrt(half * half + lxy * lxy);
          final mid = (lxx + lyy) * 0.5;
          final lMax = mid + root;
          final lMin = mid - root;
          if (lMax <= 0) continue;
          // Line-like: strong curvature across, little along.
          final v = s2 * (lMax - 0.7 * lMin.abs());
          if (v > response.data[i]) {
            response.data[i] = v;
            normal[i] = 0.5 * math.atan2(2 * lxy, lxx - lyy);
          }
        }
      }
    }

    // Normalize to 0..1 by a high percentile inside the palm.
    final ref = response.percentile(0.985, mask: mask);
    if (ref > 0) {
      for (var i = 0; i < response.data.length; i++) {
        response.data[i] = math.min(1.0, response.data[i] / ref);
      }
    }
    return CreaseResponse(response: response, normal: normal, background: bg);
  }

  /// Steps 3–4: thin ridges, threshold, skeletonize.
  CreaseMap extract(CreaseResponse r, Uint8List mask, {required double palmWidth}) {
    final response = r.response, normal = r.normal;
    final w = response.width, h = response.height;

    // 3. Non-maximum suppression across the line.
    final thin = Float32List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final v = response.data[i];
        if (v < low) continue;
        final nx = math.cos(normal[i]), ny = math.sin(normal[i]);
        final a = response.sample(x + nx, y + ny);
        final b = response.sample(x - nx, y - ny);
        if (v >= a && v >= b) thin[i] = v;
      }
    }

    // 4. Hysteresis: keep ridges (connected pixels above [low], with
    // one-pixel NMS gaps closed) that reach [high] somewhere, or that are
    // long enough to be a faint line rather than texture.
    final cand = Uint8List(w * h);
    for (var i = 0; i < thin.length; i++) {
      if (thin[i] >= low) cand[i] = 1;
    }
    final ridges = _bridge(cand, w, h);
    final cc = Masks.components(ridges, w, h);
    final strong = List<bool>.filled(cc.sizes.length, false);
    // Length of each ridge counted away from the palm border, where
    // leftover edge effects make weak false ridges.
    final inner = Masks.erode(mask, w, h, math.max(1, (palmWidth * 0.03).round()));
    final innerSize = List<int>.filled(cc.sizes.length, 0);
    for (var i = 0; i < thin.length; i++) {
      final l = cc.labels[i];
      if (l == 0) continue;
      if (thin[i] >= high) strong[l] = true;
      if (inner[i] != 0) innerSize[l]++;
    }
    final longEnough = palmWidth * weakLength;
    final bin = Uint8List(w * h);
    for (var i = 0; i < bin.length; i++) {
      final l = cc.labels[i];
      if (l != 0 && (strong[l] || innerSize[l] >= longEnough)) bin[i] = 1;
    }

    final skel = thinZhangSuen(bin, w, h);

    // Drop specks.
    final sc = Masks.components(skel, w, h);
    final minPx = palmWidth * minComponent;
    for (var i = 0; i < skel.length; i++) {
      if (skel[i] != 0 && sc.sizes[sc.labels[i]] < minPx) skel[i] = 0;
    }

    return CreaseMap(
        width: w, height: h, response: response, normal: normal, skeleton: skel, background: r.background);
  }

  /// Sets a pixel when it has set neighbors on two opposite sides, which
  /// closes one-pixel gaps without fattening lines.
  Uint8List _bridge(Uint8List m, int w, int h) {
    final out = Uint8List.fromList(m);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (m[i] != 0) continue;
        if ((m[i - 1] != 0 && m[i + 1] != 0) ||
            (m[i - w] != 0 && m[i + w] != 0) ||
            (m[i - w - 1] != 0 && m[i + w + 1] != 0) ||
            (m[i - w + 1] != 0 && m[i + w - 1] != 0)) {
          out[i] = 1;
        }
      }
    }
    return out;
  }
}

/// Valley response of one photo (or several fused), before thresholding.
class CreaseResponse {
  CreaseResponse({required this.response, required this.normal, required this.background});

  /// Normalized valley strength, 0..1.
  final FloatImage response;

  /// Angle (radians) of the crease normal at each pixel.
  final Float32List normal;

  /// Local mean brightness (heavy blur of the gray image).
  final FloatImage background;
}

/// Output of [CreaseDetector].
class CreaseMap {
  CreaseMap({
    required this.width,
    required this.height,
    required this.response,
    required this.normal,
    required this.skeleton,
    required this.background,
  });

  final int width;
  final int height;

  /// Normalized valley strength, 0..1. Used to judge line depth and to
  /// search for faint lines.
  final FloatImage response;

  /// Angle (radians) of the crease normal at each pixel; the line runs
  /// along (-sin, cos).
  final Float32List normal;

  /// One-pixel-wide crease pixels (0/1).
  final Uint8List skeleton;

  /// Local mean brightness (heavy blur of the gray image).
  final FloatImage background;
}

/// Zhang-Suen thinning to a one-pixel-wide, 8-connected skeleton.
Uint8List thinZhangSuen(Uint8List src, int w, int h) {
  final m = Uint8List.fromList(src);
  // Clear the border so neighbor reads stay in range.
  for (var x = 0; x < w; x++) {
    m[x] = 0;
    m[(h - 1) * w + x] = 0;
  }
  for (var y = 0; y < h; y++) {
    m[y * w] = 0;
    m[y * w + w - 1] = 0;
  }
  final remove = <int>[];
  var changed = true;
  while (changed) {
    changed = false;
    for (var pass = 0; pass < 2; pass++) {
      remove.clear();
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (m[i] == 0) continue;
          final p2 = m[i - w], p3 = m[i - w + 1], p4 = m[i + 1], p5 = m[i + w + 1];
          final p6 = m[i + w], p7 = m[i + w - 1], p8 = m[i - 1], p9 = m[i - w - 1];
          final b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
          if (b < 2 || b > 6) continue;
          var a = 0;
          if (p2 == 0 && p3 == 1) a++;
          if (p3 == 0 && p4 == 1) a++;
          if (p4 == 0 && p5 == 1) a++;
          if (p5 == 0 && p6 == 1) a++;
          if (p6 == 0 && p7 == 1) a++;
          if (p7 == 0 && p8 == 1) a++;
          if (p8 == 0 && p9 == 1) a++;
          if (p9 == 0 && p2 == 1) a++;
          if (a != 1) continue;
          if (pass == 0) {
            if (p2 * p4 * p6 != 0 || p4 * p6 * p8 != 0) continue;
          } else {
            if (p2 * p4 * p8 != 0 || p2 * p6 * p8 != 0) continue;
          }
          remove.add(i);
        }
      }
      if (remove.isNotEmpty) {
        changed = true;
        for (final i in remove) {
          m[i] = 0;
        }
      }
    }
  }
  return m;
}
