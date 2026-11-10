import 'dart:math' as math;

import 'hand_segmenter.dart';

/// The palm rectangle and hand proportions, measured on an upright hand
/// (fingers pointing up). Coordinates are fractions (0..1) of the frame
/// the mask came from, so they scale to any resolution of the same image.
class PalmGeometry {
  const PalmGeometry({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.thumbOnLeft,
    required this.thumbDetected,
    this.fingerRatio,
    this.fillRatio,
    this.fingerTop,
  });

  /// Palm edges. [top] is the base of the fingers, [bottom] the wrist.
  final double left;
  final double right;
  final double top;
  final double bottom;

  /// True when the thumb is on the left side of the image.
  final bool thumbOnLeft;

  /// Whether [thumbOnLeft] came from the image (true) or from the hand the
  /// user picked (false).
  final bool thumbDetected;

  /// Middle finger length divided by palm length, when measurable.
  final double? fingerRatio;

  /// Share of the palm rectangle covered by the hand (rounded palms have
  /// emptier corners).
  final double? fillRatio;

  /// Tip of the middle finger (fraction of frame height), when found.
  final double? fingerTop;

  double get width => right - left;
  double get height => bottom - top;

  /// Default palm placement used when the hand cannot be found: where the
  /// capture guide asks the user to put the palm. [scale] is the size the
  /// outline was drawn at (far shot < 1 < close-up), around the palm
  /// centre (0.5, 0.61) as in `HandGuidePainter`.
  factory PalmGeometry.guide({required bool thumbOnLeft, double scale = 1}) {
    double sx(double u) => 0.5 + (u - 0.5) * scale;
    double sy(double v) => 0.61 + (v - 0.61) * scale;
    return PalmGeometry(
      left: sx(0.24),
      right: sx(0.76),
      top: sy(0.40),
      bottom: sy(0.82),
      thumbOnLeft: thumbOnLeft,
      thumbDetected: false,
    );
  }

  /// Measures the palm from a hand mask. [rightHand] is the user's choice,
  /// used when the thumb side cannot be seen.
  static PalmGeometry fromMask(HandMask hand, {required bool rightHand}) {
    final w = hand.width, h = hand.height, m = hand.mask;
    final cx = hand.palmCenterX.round(), cy = hand.palmCenterY.round();
    final r = hand.palmRadius;

    bool on(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && m[y * w + x] != 0;

    // The run of hand pixels on row y that contains (or is nearest to) x.
    (int, int)? runAt(int y, int x) {
      if (y < 0 || y >= h) return null;
      var sx = x;
      if (!on(sx, y)) {
        var found = false;
        for (var d = 1; d < r * 0.6; d++) {
          if (on(x - d, y)) {
            sx = x - d;
            found = true;
            break;
          }
          if (on(x + d, y)) {
            sx = x + d;
            found = true;
            break;
          }
        }
        if (!found) return null;
      }
      var l = sx, rr = sx;
      while (on(l - 1, y)) {
        l--;
      }
      while (on(rr + 1, y)) {
        rr++;
      }
      return (l, rr);
    }

    // Palm width: the narrowest plausible row between the palm center and
    // the fingers. The thumb only ever makes rows wider.
    var pl = (cx - r).toDouble(), pr = (cx + r).toDouble();
    var bestW = double.infinity;
    for (var y = cy; y > cy - r * 1.1; y--) {
      final run = runAt(y, cx);
      if (run == null) continue;
      final rw = (run.$2 - run.$1).toDouble();
      if (rw > r * 1.4 && rw < r * 2.8 && rw < bestW) {
        bestW = rw;
        pl = run.$1.toDouble();
        pr = run.$2.toDouble();
      }
    }
    final pw = pr - pl;

    // Finger base: going up, the first rows where the hand splits into
    // three or more runs across the palm width (spread fingers).
    var top = cy - r * 1.05;
    var streak = 0;
    for (var y = cy; y > cy - r * 1.8 && y > 0; y--) {
      var runs = 0;
      var inRun = false;
      var len = 0;
      for (var x = (pl - pw * 0.1).round(); x <= (pr + pw * 0.1).round(); x++) {
        if (on(x, y)) {
          if (!inRun) {
            inRun = true;
            len = 0;
          }
          len++;
        } else if (inRun) {
          inRun = false;
          if (len > pw * 0.06) runs++;
        }
      }
      if (inRun && len > pw * 0.06) runs++;
      streak = runs >= 3 ? streak + 1 : 0;
      if (streak >= 2) {
        // Finger webs sit a little above where the palm creases end.
        top = y + 2 + pw * 0.04;
        break;
      }
    }
    top = top.clamp(cy - r * 1.5, cy - r * 0.8);

    // Wrist: going down, where the hand narrows well below the palm width.
    var bottom = cy + r * 1.25;
    for (var y = (cy + r * 0.7).round(); y < h; y++) {
      final run = runAt(y, cx);
      if (run == null) {
        bottom = y.toDouble();
        break;
      }
      if (run.$2 - run.$1 < pw * 0.78) {
        bottom = y.toDouble();
        break;
      }
    }
    bottom = bottom.clamp(cy + r * 0.9, cy + r * 1.6);

    // Thumb: more hand outside the palm edge on that side, mid to low palm.
    var leftOut = 0, rightOut = 0;
    for (var y = (cy - r * 0.2).round(); y < cy + r; y++) {
      for (var x = 0; x < w; x++) {
        if (!on(x, y)) continue;
        if (x < pl - pw * 0.1) leftOut++;
        if (x > pr + pw * 0.1) rightOut++;
      }
    }
    bool thumbOnLeft;
    var detected = false;
    if (leftOut > rightOut * 1.6 && leftOut > r * r * 0.15) {
      thumbOnLeft = true;
      detected = true;
    } else if (rightOut > leftOut * 1.6 && rightOut > r * r * 0.15) {
      thumbOnLeft = false;
      detected = true;
    } else {
      // A right palm facing the camera has its thumb on the image's right.
      thumbOnLeft = !rightHand;
    }

    // Middle finger: the longest column of hand pixels above the palm
    // in the middle band of the palm width.
    double? fingerRatio;
    double? fingerTop;
    var bestLen = 0;
    var cutOff = false;
    for (var x = (pl + pw * 0.3).round(); x <= (pl + pw * 0.7).round(); x++) {
      var y = top.round();
      var len = 0;
      while (on(x, y - 1)) {
        y--;
        len++;
      }
      if (len > bestLen) {
        bestLen = len;
        cutOff = y <= 1;
      }
    }
    final ph = bottom - top;
    if (bestLen > ph * 0.3 && !cutOff) {
      fingerRatio = bestLen / ph;
      fingerTop = (top - bestLen) / h;
    }

    // Fill of the palm rectangle.
    var filled = 0, total = 0;
    for (var y = top.round(); y <= bottom.round(); y++) {
      for (var x = pl.round(); x <= pr.round(); x++) {
        total++;
        if (on(x, y)) filled++;
      }
    }

    return PalmGeometry(
      left: pl / w,
      right: pr / w,
      top: top / h,
      bottom: math.min(bottom, h - 1.0) / h,
      thumbOnLeft: thumbOnLeft,
      thumbDetected: detected,
      fingerRatio: fingerRatio,
      fillRatio: total == 0 ? null : filled / total,
      fingerTop: fingerTop,
    );
  }
}

/// Maps between image pixels and palm coordinates.
///
/// Palm coordinates: `u` runs across the palm from the thumb side (0) to
/// the little-finger side (1); `v` runs from the base of the fingers (0)
/// to the wrist (1). This makes every template the same for left and
/// right hands.
class PalmFrame {
  PalmFrame({
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.thumbOnLeft,
  });

  /// Palm rectangle in pixels of the working image.
  final double x0, x1, y0, y1;
  final bool thumbOnLeft;

  double get width => x1 - x0;
  double get height => y1 - y0;

  (double, double) toUV(double x, double y) {
    final u = thumbOnLeft ? (x - x0) / width : (x1 - x) / width;
    return (u, (y - y0) / height);
  }

  (double, double) toXY(double u, double v) {
    final x = thumbOnLeft ? x0 + u * width : x1 - u * width;
    return (x, y0 + v * height);
  }
}
