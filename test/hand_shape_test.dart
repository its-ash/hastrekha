import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/vision/float_image.dart';
import 'package:hastrekha/vision/hand_shape.dart';
import 'package:hastrekha/vision/palm_geometry.dart';

/// A drawn hand, thumb on the left: palm 300 px wide, four spread fingers
/// with their bases on the palm's top edge, and a thumb apart from the
/// palm above its web. [lengths] are the finger lengths against the
/// middle finger (270 px); [squareTips] gives squared instead of round
/// fingertips; [touching] closes the gaps between the fingers so only a
/// dark crevice separates them.
({Uint8List mask, FloatImage gray, PalmFrame frame}) _hand({
  Map<String, double> lengths = const {'index': 0.86, 'middle': 1, 'ring': 0.9, 'little': 0.64},
  bool squareTips = false,
  bool touching = false,
}) {
  const w = 600, h = 900;
  final mask = Uint8List(w * h);
  final gray = FloatImage(w, h);
  for (var i = 0; i < w * h; i++) {
    gray.data[i] = 60;
  }
  void skin(int x, int y, [double v = 150]) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    mask[y * w + x] = 1;
    gray.data[y * w + x] = v;
  }

  // Palm and wrist.
  for (var y = 400; y < 900; y++) {
    for (var x = 150; x < 450; x++) {
      skin(x, y);
    }
  }
  // Fingers: [left, right] at the base, from the index (next to the thumb).
  final spans = touching
      ? const [(150, 224), (225, 299), (300, 374), (375, 449)]
      : const [(152, 222), (228, 298), (304, 372), (378, 440)];
  const names = ['index', 'middle', 'ring', 'little'];
  for (var f = 0; f < 4; f++) {
    final (l, r) = spans[f];
    final len = (270 * lengths[names[f]]!).round();
    final half = (r - l) / 2, cx = (l + r) / 2;
    for (var d = 0; d < len; d++) {
      final y = 400 - d;
      // Distance from the tip: round tips follow a half circle, square
      // ones keep their width until close to the top.
      final fromTip = len - d;
      double hw;
      if (squareTips) {
        hw = fromTip > 6 ? half : half - (6 - fromTip) * 1.5;
      } else {
        final t = (half - fromTip).clamp(0, half).toDouble();
        hw = fromTip >= half ? half : math.sqrt(math.max(0, half * half - t * t));
      }
      for (var x = (cx - hw).round(); x <= (cx + hw).round(); x++) {
        skin(x, y);
      }
    }
    // Between touching fingers: a dark crevice.
    if (touching && f < 3) {
      for (var y = 400 - (270 * 0.6).round(); y < 400; y++) {
        for (var x = r - 1; x <= r + 1; x++) {
          skin(x, y, 105);
        }
      }
    }
  }
  // Thumb: apart from the palm above y 560, joined below.
  for (var y = 430; y < 640; y++) {
    for (var x = 40; x < 150; x++) {
      final apart = y < 560 && x >= 130;
      if (!apart) skin(x, y);
    }
  }
  return (mask: mask, gray: gray, frame: PalmFrame(x0: 150, x1: 450, y0: 400, y1: 740, thumbOnLeft: true));
}

HandShape _measure(({Uint8List mask, FloatImage gray, PalmFrame frame}) h) =>
    HandShape.measure(mask: h.mask, gray: h.gray, frame: h.frame)!;

void main() {
  test('finds four spread fingers with their lengths', () {
    final s = _measure(_hand());
    expect(s.fingers.keys, containsAll(HandShape.fingerNames));
    final m = s.fingers['middle']!.length;
    expect(m, closeTo(270, 12));
    expect(s.fingers['little']!.length / m, closeTo(0.64, 0.05));
    expect(s.development.values.toSet(), {'medium'}, reason: '${s.development}');
  });

  test('a long index and a short little finger stand out', () {
    final s = _measure(_hand(lengths: const {'index': 1.0, 'middle': 1, 'ring': 0.9, 'little': 0.5}));
    expect(s.development['index'], 'long');
    expect(s.development['little'], 'short');
  });

  test('round fingertips read as conic, squared ones as square', () {
    expect(_measure(_hand()).tips, 'conic');
    expect(_measure(_hand(squareTips: true)).tips, 'square');
  });

  test('fingers that touch are told apart by the dark crevice between them', () {
    final log = <String>[];
    HandShape.debug = log.add;
    final h = _hand(touching: true);
    final shape = HandShape.measure(mask: h.mask, gray: h.gray, frame: h.frame);
    HandShape.debug = null;
    expect(shape, isNotNull, reason: log.join('\n'));
    final s = shape!;
    expect(s.fingers.keys, containsAll(HandShape.fingerNames));
    expect(s.fingers['middle']!.length, closeTo(270, 15));
  });

  test('the thumb is found from its web to its tip', () {
    final t = _measure(_hand()).thumb;
    expect(t, isNotNull);
    expect(t!.webY, closeTo(559, 4));
    expect(t.width, greaterThan(40));
  });
}
