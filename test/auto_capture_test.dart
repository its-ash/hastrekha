import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/reading/palm_features.dart';
import 'package:hastrekha/vision/auto_capture.dart';
import 'package:hastrekha/vision/palm_geometry.dart';

int _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0xffff;
}

/// A preview frame of a palm: skin colour, fine texture (so focus can be
/// measured) shifted by [shift] pixels to simulate motion.
PreviewFrame _frame({int shift = 0, double texture = 14, int luma = 140, int cb = 108, int cr = 150, int smooth = 1}) {
  const w = 320, h = 240;
  final y = Uint8List(w * h);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      // Average [smooth] x [smooth] cells of texture: bigger = softer focus.
      var s = 0.0;
      for (var k = 0; k < smooth; k++) {
        s += _hash(i + shift - k, j) / 65535 - 0.5;
      }
      y[j * w + i] = (luma + texture * 2 * s / smooth).round().clamp(0, 255);
    }
  }
  return PreviewFrame(
    width: w,
    height: h,
    y: y,
    yRowStride: w,
    u: Uint8List(w * h ~/ 4)..fillRange(0, w * h ~/ 4, cb),
    v: Uint8List(w * h ~/ 4)..fillRange(0, w * h ~/ 4, cr),
    uvRowStride: w ~/ 2,
  );
}

/// A preview frame of an open hand on a grey background, as the user
/// sees it: palm, spread fingers, forearm and a thumb on the left, [size]
/// times the size of the normal outline and moved sideways by [dx] (frame
/// widths). Drawn in palm units like the outline. [rotation] stores it
/// the way a sensor mounted that many quarter turns would. [glare] puts a
/// clipped blob in the middle of the palm.
PreviewFrame _hand({double size = 1, double dx = 0, int rotation = 0, bool glare = false, int shift = 0}) {
  const uw = 240, uh = 320; // upright size
  final turned = rotation.isOdd;
  final w = turned ? uh : uw, h = turned ? uw : uh;
  const pw = PalmGeometry.guidePalmWidth;
  bool skin(double u, double v) {
    final x = (u - 0.5 - dx) / (pw * size), y = (v - 0.61) * (uh / uw) / (pw * size);
    if (x.abs() <= 0.5 && y >= -0.56 && y <= 0.56) return true; // palm
    if (x.abs() <= 0.3 && y > 0.56) return true; // wrist and forearm
    if (y >= -1.4 && y < -0.56) {
      for (final (a, b) in const [(-0.47, -0.25), (-0.23, -0.01), (0.01, 0.23), (0.25, 0.45)]) {
        if (x >= a && x <= b) return true; // fingers, a little apart
      }
    }
    if (x >= -0.75 && x < -0.5 && y >= -0.1 && y <= 0.35) return true; // ball of the thumb
    return x >= -0.95 && x < -0.6 && y >= -0.45 && y < -0.1; // thumb tip, a gap away from the palm
  }

  (double, double) upright(int x, int y) {
    final fx = (x + 0.5) / w, fy = (y + 0.5) / h;
    return switch (rotation % 4) {
      1 => (1 - fy, fx),
      2 => (1 - fx, 1 - fy),
      3 => (fy, 1 - fx),
      _ => (fx, fy),
    };
  }

  final y = Uint8List(w * h);
  final cw = w ~/ 2, ch = h ~/ 2;
  final cb = Uint8List(cw * ch), cr = Uint8List(cw * ch);
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final (u, v) = upright(i, j);
      final s = skin(u, v);
      final t = (_hash(i + shift, j) / 65535 - 0.5) * 28;
      var l = (s ? 150 : 70) + t;
      if (glare && (u - 0.5).abs() < 0.09 && (v - 0.62).abs() < 0.07) l = 255;
      y[j * w + i] = l.round().clamp(0, 255);
      final ci = (j >> 1) * cw + (i >> 1);
      cb[ci] = s ? 108 : 128;
      cr[ci] = s ? 150 : 128;
    }
  }
  return PreviewFrame(width: w, height: h, y: y, yRowStride: w, u: cb, v: cr, uvRowStride: cw, rotation: rotation);
}

AutoState _run(AutoCaptureGate g, List<PreviewFrame> frames, {double scale = 1}) {
  // Returns ready as soon as the gate fires (the app takes the shot then).
  var s = AutoState.noHand;
  for (final f in frames) {
    s = g.add(f, scale: scale);
    if (s == AutoState.ready) return s;
  }
  return s;
}

/// Eight identical frames (a still hand).
List<PreviewFrame> _still(PreviewFrame f) => [for (var i = 0; i < 8; i++) f];

void main() {
  test('a steady, sharp palm that fills the box is taken', () {
    final g = AutoCaptureGate();
    expect(_run(g, [for (var i = 0; i < 8; i++) _frame()]), AutoState.ready);
  });

  test('a moving hand is not taken', () {
    final g = AutoCaptureGate();
    expect(_run(g, [for (var i = 0; i < 8; i++) _frame(shift: i * 7)]), AutoState.moving);
  });

  test('no skin in the box: not taken', () {
    final g = AutoCaptureGate();
    expect(_run(g, [for (var i = 0; i < 8; i++) _frame(cb: 128, cr: 128)]), AutoState.noHand);
  });

  test('too dark and too bright are reported', () {
    expect(_run(AutoCaptureGate(), [for (var i = 0; i < 6; i++) _frame(luma: 30)]), AutoState.tooDark);
    expect(_run(AutoCaptureGate(), [for (var i = 0; i < 6; i++) _frame(luma: 245, texture: 6)]), AutoState.tooBright);
  });

  test('out of focus after being sharp waits for focus', () {
    final g = AutoCaptureGate();
    _run(g, [for (var i = 0; i < 3; i++) _frame()]);
    expect(_run(g, [for (var i = 0; i < 6; i++) _frame(smooth: 6)]), AutoState.soft);
  });

  group('the palm against the outline', () {
    test('a hand that fits the outline is taken, however the sensor is mounted', () {
      for (var r = 0; r < 4; r++) {
        final g = AutoCaptureGate();
        expect(_run(g, _still(_hand(rotation: r))), AutoState.ready, reason: 'rotation $r: fill ${g.fill}, size ${g.size}, offset ${g.offset}');
        expect(g.size, closeTo(1, 0.06));
        expect(g.offset.abs(), lessThan(0.04));
      }
    });

    test('a hand too far away asks to come closer', () {
      final g = AutoCaptureGate();
      expect(_run(g, _still(_hand(size: 0.6, rotation: 1))), AutoState.tooFar, reason: 'size ${g.size}');
    });

    test('a hand too close asks to move back', () {
      final g = AutoCaptureGate();
      expect(_run(g, _still(_hand(size: 1.4, rotation: 1))), AutoState.tooClose, reason: 'size ${g.size}');
    });

    test('a hand to one side asks to centre it', () {
      for (final dx in [-0.12, 0.12]) {
        final g = AutoCaptureGate();
        expect(_run(g, _still(_hand(dx: dx, rotation: 1))), AutoState.offCentre, reason: 'offset ${g.offset}');
      }
    });

    test('each shot wants the hand at the size of its own outline', () {
      // Far shot: the small outline.
      expect(_run(AutoCaptureGate(), _still(_hand(size: 0.78)), scale: 0.78), AutoState.ready);
      expect(_run(AutoCaptureGate(), _still(_hand(size: 1.0)), scale: 0.78), AutoState.tooClose);
      // Close-up: the large outline.
      expect(_run(AutoCaptureGate(), _still(_hand(size: 1.18)), scale: 1.18), AutoState.ready);
      expect(_run(AutoCaptureGate(), _still(_hand(size: 0.78)), scale: 1.18), AutoState.tooFar);
    });

    test('a shiny patch on the palm is reported', () {
      final g = AutoCaptureGate();
      expect(_run(g, _still(_hand(glare: true))), AutoState.glare, reason: 'glare ${g.glare}');
    });

    test('a skin-coloured background does not block the shot', () {
      final g = AutoCaptureGate();
      expect(_run(g, [for (var i = 0; i < 8; i++) _frame()]), AutoState.ready);
      expect(g.skinLikeBackground, isTrue);
    });

    test('the focus peak is forgotten when the hand leaves the outline', () {
      final g = AutoCaptureGate();
      // Very sharp at one distance, then the hand goes away and comes back
      // with a softer picture: the old peak must not block the shot.
      _run(g, [_hand(), _hand()]);
      _run(g, [_hand(size: 0.5)]);
      final soft = _frame(smooth: 2);
      expect(_run(g, [for (var i = 0; i < 8; i++) soft]), AutoState.ready);
    });
  });

  group('lines that are not clear', () {
    PalmFeatures make() => PalmFeatures(lines: {
          'heart': LineFeature(present: true, confidence: 0.9),
          'head': LineFeature(present: true, confidence: 0.3),
          'life': LineFeature(present: false),
          'fate': LineFeature(present: false),
        });

    test('weak and missing main lines are unclear, a missing fate line is not', () {
      expect(make().unclearLines, ['life', 'head']);
    });

    test('unclear lines give no facts, so no rule fires for them', () {
      final f = make().toFacts();
      expect(f.containsKey('head.present'), isFalse);
      expect(f.containsKey('life.present'), isFalse);
      expect(f['heart.present'], 'true');
      expect(f['fate.present'], 'false');
    });

    test('lines edited by hand and simian heart/head are exempt', () {
      final f = make();
      f.lines['head'] = LineFeature(present: true, confidence: 1, edited: true);
      f.lines['life'] = LineFeature(present: true, confidence: 0.8);
      expect(f.unclearLines, isEmpty);
      final s = PalmFeatures(simian: true, lines: {
        'heart': LineFeature(present: false),
        'head': LineFeature(present: true, confidence: 0.9),
        'life': LineFeature(present: true, confidence: 0.9),
      });
      expect(s.unclearLines, isEmpty);
    });
  });
}
