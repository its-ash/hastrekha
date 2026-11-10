import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/vision/float_image.dart';
import 'package:hastrekha/vision/crease_detector.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';
import 'package:hastrekha/vision/palm_geometry.dart';
import 'package:hastrekha/vision/skeleton_graph.dart';
import 'package:image/image.dart' as img;

/// Draws a simple right palm (thumb on the image's right) with the four
/// main creases, roughly as a phone camera would frame it with the guide.
Uint8List syntheticPalm({
  int w = 720,
  int h = 1280,
  bool rightHand = true,
  bool withFate = true,
  bool withSun = false,
  double tiltDeg = 0,
  Map<String, double> contrast = const {},
  double noise = 0,
  int seed = 1,
  double shiftX = 0,
  double shiftY = 0,
  double zoom = 1,
}) {
  var im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(40, 46, 60));
  final skin = img.ColorRgb8(224, 172, 140);
  img.Color creaseFor(String key) {
    // 1 = a clear crease, small values = a faint line.
    final c = contrast[key] ?? 1.0;
    int mix(int s, int d) => (s + (d - s) * c).round();
    return img.ColorRgb8(mix(224, 150), mix(172, 100), mix(140, 80));
  }

  // Palm rectangle: about where the guide asks for it.
  // [zoom] scales the hand around the palm centre (far shot < 1 < close-up).
  final pl = w * (0.5 - 0.25 * zoom + shiftX), pr = w * (0.5 + 0.25 * zoom + shiftX);
  final pt = h * (0.61 - 0.19 * zoom + shiftY), pb = h * (0.61 + 0.19 * zoom + shiftY);
  final pw = pr - pl, ph = pb - pt;
  img.fillRect(im, x1: pl.round(), y1: pt.round(), x2: pr.round(), y2: pb.round(), color: skin, radius: 40);
  // Wrist / forearm, narrower.
  img.fillRect(im,
      x1: (pl + pw * 0.15).round(), y1: pb.round() - 20, x2: (pr - pw * 0.15).round(), y2: h, color: skin);
  // Four fingers with gaps.
  final fw = pw / 5.2;
  final lens = [0.78, 0.9, 0.84, 0.66];
  for (var i = 0; i < 4; i++) {
    final x = pl + pw * 0.04 + i * (pw - pw * 0.08) / 4 + (pw / 4 - fw) / 2;
    final len = ph * lens[i];
    img.fillRect(im,
        x1: x.round(), y1: (pt - len).round(), x2: (x + fw).round(), y2: (pt + 30).round(), color: skin, radius: 26);
  }
  // Thumb on the right (right hand, palm facing the camera).
  final tx = rightHand ? pr - 10 : pl - pw * 0.32 + 10;
  img.fillRect(im,
      x1: tx.round(), y1: (pt + ph * 0.35).round(), x2: (tx + pw * 0.32).round(), y2: (pt + ph * 0.85).round(),
      color: skin, radius: 30);

  // Creases in palm coordinates (u from the thumb side, v from the fingers).
  (double, double) xy(double u, double v) => (rightHand ? pr - u * pw : pl + u * pw, pt + v * ph);
  void stroke(String key, List<(double, double)> uv, {double width = 5}) {
    final crease = creaseFor(key);
    for (var i = 1; i < uv.length; i++) {
      final (x0, y0) = xy(uv[i - 1].$1, uv[i - 1].$2);
      final (x1, y1) = xy(uv[i].$1, uv[i].$2);
      final steps = (math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 1.5).ceil();
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        img.fillCircle(im,
            x: (x0 + (x1 - x0) * t).round(), y: (y0 + (y1 - y0) * t).round(), radius: (width / 2).round(), color: crease);
      }
    }
  }

  stroke('heart', [(0.98, 0.24), (0.75, 0.21), (0.52, 0.17), (0.32, 0.12), (0.2, 0.07)]);
  stroke('head', [(0.08, 0.34), (0.3, 0.39), (0.55, 0.45), (0.8, 0.53)]);
  stroke('life', [(0.09, 0.33), (0.19, 0.46), (0.26, 0.61), (0.29, 0.76), (0.31, 0.92)], width: 6);
  if (withFate) stroke('fate', [(0.5, 0.97), (0.48, 0.7), (0.45, 0.45)], width: 4);
  if (withSun) stroke('sun', [(0.67, 0.62), (0.655, 0.38), (0.64, 0.16)], width: 3);

  im = img.gaussianBlur(im, radius: 2);
  if (noise > 0) {
    // Skin texture and sensor noise, so faint lines are not trivially clean.
    // Coarse blobs (pores, folds) plus fine grain.
    final rnd = math.Random(seed);
    final cw = w ~/ 4, ch = h ~/ 4;
    final coarse = List<double>.generate(cw * ch, (_) => rnd.nextDouble() * 2 - 1);
    for (final p in im) {
      final cx = math.min(cw - 1, p.x ~/ 4), cy = math.min(ch - 1, p.y ~/ 4);
      final n = coarse[cy * cw + cx] * noise + (rnd.nextDouble() + rnd.nextDouble() - 1) * noise;
      p
        ..r = (p.r + n).clamp(0, 255)
        ..g = (p.g + n).clamp(0, 255)
        ..b = (p.b + n).clamp(0, 255);
    }
  }
  if (tiltDeg != 0) im = img.copyRotate(im, angle: tiltDeg);
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

/// A palm with clear life and heart lines but faint head, fate and sun
/// lines on noisy skin: the case real photos struggle with.
Uint8List faintPalm({int seed = 1, double shiftX = 0, double shiftY = 0, double noise = 7}) => syntheticPalm(
      withSun: true,
      contrast: const {'head': 0.4, 'fate': 0.22, 'sun': 0.25},
      noise: noise,
      seed: seed,
      shiftX: shiftX,
      shiftY: shiftY,
    );

/// The guided capture: the same faint palm far, close and at a middle
/// distance.
List<Uint8List> distanceShots() => [
      syntheticPalm(withSun: true, contrast: const {'head': 0.4, 'fate': 0.22, 'sun': 0.25}, noise: 9, seed: 7, zoom: 0.8),
      syntheticPalm(withSun: true, contrast: const {'head': 0.4, 'fate': 0.22, 'sun': 0.25}, noise: 9, seed: 8, zoom: 1.15),
      syntheticPalm(withSun: true, contrast: const {'head': 0.4, 'fate': 0.22, 'sun': 0.25}, noise: 9, seed: 9),
    ];

/// Three shots of the same faint, noisy palm, as a burst from a hand
/// that moves a little between them.
List<Uint8List> noisyBurst() => [
      faintPalm(noise: 11, seed: 3),
      faintPalm(noise: 11, seed: 4, shiftX: 0.012, shiftY: -0.008),
      faintPalm(noise: 11, seed: 6, shiftX: -0.01, shiftY: 0.01),
    ];

void main() {
  test('Zhang-Suen thins a thick bar to one pixel', () {
    const w = 40, h = 20;
    final m = Uint8List(w * h);
    for (var y = 7; y < 13; y++) {
      for (var x = 5; x < 35; x++) {
        m[y * w + x] = 1;
      }
    }
    final t = thinZhangSuen(m, w, h);
    for (var x = 10; x < 30; x++) {
      var col = 0;
      for (var y = 0; y < h; y++) {
        col += t[y * w + x];
      }
      expect(col, 1, reason: 'column $x');
    }
  });

  test('crease detector finds a dark line and the graph links a gap', () {
    const w = 200, h = 120;
    final g = FloatImage(w, h);
    for (var i = 0; i < g.data.length; i++) {
      g.data[i] = 200;
    }
    for (var x = 20; x < 180; x++) {
      if (x > 95 && x < 103) continue; // a break
      for (var dy = -1; dy <= 1; dy++) {
        g.set(x, 60 + dy, 120);
      }
    }
    final mask = Uint8List(w * h)..fillRange(0, w * h, 1);
    final c = const CreaseDetector().detect(g.blur(1), mask, palmWidth: 300);
    final graph = SkeletonGraph(c.skeleton, w, h);
    final curves = graph.link(maxGap: 20);
    final long = curves.where((e) => e.length > 120).toList();
    expect(long, hasLength(1));
    expect(long.single.gaps, isNotEmpty);
  });

  test('finds the main lines on a synthetic right palm', () {
    final a = const PalmAnalyzer().analyze(syntheticPalm(), rightHand: true);
    expect(a.issues, isNot(contains(PhotoIssue.handNotFound)));
    expect(a.thumbOnLeft, isFalse);
    final f = a.features;
    for (final k in ['heart', 'head', 'life', 'fate']) {
      expect(f.lines[k]?.present, isTrue, reason: '$k line');
    }
    expect(f.lines['life']!.length, isNot('short'));
    expect(f.lines['fate']!.length, isNot('long'));
    expect(f.simian, isFalse);
    expect(a.photo, isNotEmpty);
  });

  test('left palm and a missing fate line', () {
    final a = const PalmAnalyzer().analyze(syntheticPalm(rightHand: false, withFate: false), rightHand: false);
    expect(a.thumbOnLeft, isTrue);
    expect(a.features.lines['life']?.present, isTrue);
    expect(a.features.lines['heart']?.present, isTrue);
    expect(a.features.lines['fate']?.present, isFalse);
  });

  test('finds faint fate and sun lines on noisy skin', () {
    final f = const PalmAnalyzer().analyze(faintPalm(), rightHand: true).features;
    for (final k in ['heart', 'head', 'life', 'fate', 'sun']) {
      expect(f.lines[k]?.present, isTrue, reason: '$k line');
    }
    expect(f.lines['fate']!.depth, 'faint');
    expect(f.lines['life']!.length, 'long');
  });

  test('does not invent a fate line on noisy skin', () {
    final f = const PalmAnalyzer().analyze(syntheticPalm(withFate: false, noise: 10, seed: 5), rightHand: true).features;
    expect(f.lines['fate']?.present, isFalse);
    expect(f.lines['sun']?.present, isFalse);
    expect(f.lines['mercury']?.present, isFalse);
  });

  test('several photos together find lines one photo misses', () {
    final burst = noisyBurst();
    final single = const PalmAnalyzer().analyze(burst.first, rightHand: true).features;
    expect(single.lines['fate']?.present, isFalse);
    final a = const PalmAnalyzer().analyzeAll(burst, rightHand: true);
    expect(a.photosUsed, 3);
    expect(a.features.lines['fate']?.present, isTrue);
    expect(a.features.lines['sun']?.present, isTrue);
  });

  test('far, close and middle shots are combined', () {
    final a = const PalmAnalyzer().analyzeAll(distanceShots(), rightHand: true, guideScales: const [0.78, 1.18, 1.0]);
    expect(a.photosUsed, 3);
    for (final k in ['heart', 'head', 'life', 'fate']) {
      expect(a.features.lines[k]?.present, isTrue, reason: '$k line');
    }
    expect(a.features.simian, isFalse);
  });

  test('the fallback palm follows the outline size', () {
    final far = PalmGeometry.guide(thumbOnLeft: true, scale: 0.78);
    final normal = PalmGeometry.guide(thumbOnLeft: true);
    expect(far.width, closeTo(normal.width * 0.78, 1e-9));
    expect((far.top + far.bottom) / 2, closeTo((normal.top + normal.bottom) / 2, 0.01));
  });

  test('a photo of something else is left out of the fusion', () {
    final a = const PalmAnalyzer().analyzeAll(
      [faintPalm(), syntheticPalm(rightHand: false)],
      rightHand: true,
    );
    expect(a.photosUsed, 1);
    expect(a.features.lines['fate']?.present, isTrue);
  });

  test('a tilted hand is straightened', () {
    final a = const PalmAnalyzer().analyze(syntheticPalm(tiltDeg: 12), rightHand: true);
    expect(a.features.lines['heart']?.present, isTrue);
    expect(a.features.lines['life']?.present, isTrue);
  });
}
