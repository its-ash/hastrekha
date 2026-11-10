import 'dart:math' as math;
import 'dart:typed_data';

import 'float_image.dart';

/// Planar YCrCb copy of an RGB image.
class YCrCb {
  YCrCb(this.width, this.height)
      : y = FloatImage(width, height),
        cr = FloatImage(width, height),
        cb = FloatImage(width, height);

  final int width;
  final int height;
  final FloatImage y;
  final FloatImage cr;
  final FloatImage cb;

  /// Builds from interleaved 8-bit RGB bytes.
  factory YCrCb.fromRgb(Uint8List rgb, int width, int height) {
    final out = YCrCb(width, height);
    for (var i = 0, p = 0; i < width * height; i++, p += 3) {
      final r = rgb[p].toDouble(), g = rgb[p + 1].toDouble(), b = rgb[p + 2].toDouble();
      final yy = 0.299 * r + 0.587 * g + 0.114 * b;
      out.y.data[i] = yy;
      out.cr.data[i] = (r - yy) * 0.713 + 128;
      out.cb.data[i] = (b - yy) * 0.564 + 128;
    }
    return out;
  }

  YCrCb resize(int w, int h) {
    final out = YCrCb._(w, h, y.resize(w, h), cr.resize(w, h), cb.resize(w, h));
    return out;
  }

  YCrCb._(this.width, this.height, this.y, this.cr, this.cb);
}

/// Result of finding the hand in a low-resolution frame.
class HandMask {
  HandMask({
    required this.mask,
    required this.width,
    required this.height,
    required this.palmCenterX,
    required this.palmCenterY,
    required this.palmRadius,
    required this.fingerAngle,
    required this.areaFraction,
  });

  final Uint8List mask;
  final int width;
  final int height;

  /// Center of the largest circle that fits inside the hand.
  final double palmCenterX;
  final double palmCenterY;
  final double palmRadius;

  /// Angle (radians) of the finger direction from straight up. Positive
  /// means the fingers lean to the right of the image.
  final double fingerAngle;

  /// Hand area divided by frame area.
  final double areaFraction;

  bool get plausible => areaFraction > 0.06 && areaFraction < 0.92 && palmRadius > width * 0.06;
}

/// Finds the hand by skin color.
///
/// Skin chroma is learned from a patch where the guide puts the palm
/// (center of the frame, a little below the middle), then every pixel is
/// scored by its chroma distance to that sample, with a loose classic
/// Cr/Cb skin range as a prior. The largest component that covers the
/// sample point is the hand.
class HandSegmenter {
  const HandSegmenter();

  /// Where the capture guide places the palm center, as a fraction of the
  /// frame.
  static const guideCenterX = 0.5;
  static const guideCenterY = 0.6;

  HandMask? segment(YCrCb img) {
    final w = img.width, h = img.height;
    final stats = _sampleSkin(img);
    if (stats == null) return null;

    final raw = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      final cr = img.cr.data[i], cb = img.cb.data[i], yy = img.y.data[i];
      final dcr = (cr - stats.cr) / stats.sdCr;
      final dcb = (cb - stats.cb) / stats.sdCb;
      final d = math.sqrt(dcr * dcr + dcb * dcb);
      final classic = cr >= 128 && cr <= 180 && cb >= 72 && cb <= 135;
      final limit = classic ? 3.4 : 2.2;
      if (d < limit && yy > 25) raw[i] = 1;
    }

    // Light cleanup only: a large closing would fill the gaps between
    // the fingers, which the palm geometry needs to find the finger base.
    final r = math.max(1, (w / 300).round());
    var m = Masks.open(raw, w, h, r);
    m = Masks.close(m, w, h, r);

    // Keep the component under the sample point (or the largest one).
    final cc = Masks.components(m, w, h);
    final sx = (w * guideCenterX).round(), sy = (h * guideCenterY).round();
    var label = cc.labels[sy * w + sx];
    if (label == 0) {
      var best = 0;
      for (var l = 1; l < cc.sizes.length; l++) {
        if (cc.sizes[l] > best) {
          best = cc.sizes[l];
          label = l;
        }
      }
    }
    if (label == 0) return null;
    var hand = Uint8List(w * h);
    var area = 0;
    for (var i = 0; i < hand.length; i++) {
      if (cc.labels[i] == label) {
        hand[i] = 1;
        area++;
      }
    }
    hand = Masks.fillHoles(hand, w, h);

    // Palm = the deepest point of the distance transform.
    final dist = Masks.distance(hand, w, h);
    var best = 0.0;
    var bx = 0, by = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = dist[y * w + x];
        if (v > best) {
          best = v;
          bx = x;
          by = y;
        }
      }
    }
    if (best <= 0) return null;

    return HandMask(
      mask: hand,
      width: w,
      height: h,
      palmCenterX: bx.toDouble(),
      palmCenterY: by.toDouble(),
      palmRadius: best,
      fingerAngle: _fingerAngle(hand, w, h, bx.toDouble(), by.toDouble(), best),
      areaFraction: area / (w * h),
    );
  }

  /// Mean and spread of Cr/Cb in a patch around the guide's palm center.
  ({double cr, double cb, double sdCr, double sdCb})? _sampleSkin(YCrCb img) {
    final w = img.width, h = img.height;
    final cx = (w * guideCenterX).round(), cy = (h * guideCenterY).round();
    final r = math.max(2, (w * 0.06).round());
    final crs = <double>[], cbs = <double>[];
    for (var y = cy - r; y <= cy + r; y++) {
      for (var x = cx - r; x <= cx + r; x++) {
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        crs.add(img.cr.at(x, y));
        cbs.add(img.cb.at(x, y));
      }
    }
    if (crs.length < 8) return null;
    // Median is robust against a crease or shadow in the patch.
    crs.sort();
    cbs.sort();
    final mcr = crs[crs.length ~/ 2], mcb = cbs[cbs.length ~/ 2];
    double mad(List<double> v, double m) {
      final d = v.map((e) => (e - m).abs()).toList()..sort();
      return d[d.length ~/ 2] * 1.4826;
    }

    return (
      cr: mcr,
      cb: mcb,
      sdCr: math.max(3.5, mad(crs, mcr) * 1.5),
      sdCb: math.max(3.5, mad(cbs, mcb) * 1.5),
    );
  }

  /// Direction from the palm center to the mass of the fingers.
  double _fingerAngle(Uint8List m, int w, int h, double cx, double cy, double r) {
    var sx = 0.0, sy = 0.0;
    var n = 0;
    final inner = r * 1.55, outer = r * 3.2;
    for (var y = 0; y < h; y++) {
      final dy = y - cy;
      if (dy > -r * 0.3) continue; // only above the palm center
      for (var x = 0; x < w; x++) {
        if (m[y * w + x] == 0) continue;
        final dx = x - cx;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < inner || d > outer) continue;
        sx += dx;
        sy += dy;
        n++;
      }
    }
    if (n < 10) return 0;
    final a = math.atan2(sx / n, -sy / n);
    // The thumb pulls the mean sideways; never trust large tilts.
    return a.clamp(-0.7, 0.7);
  }
}
