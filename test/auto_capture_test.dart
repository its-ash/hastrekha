import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/reading/palm_features.dart';
import 'package:hastrekha/vision/auto_capture.dart';

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

AutoState _run(AutoCaptureGate g, List<PreviewFrame> frames) {
  // Returns ready as soon as the gate fires (the app takes the shot then).
  var s = AutoState.noHand;
  for (final f in frames) {
    s = g.add(f);
    if (s == AutoState.ready) return s;
  }
  return s;
}

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
