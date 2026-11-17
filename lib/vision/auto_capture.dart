import 'dart:math' as math;
import 'dart:typed_data';

import 'palm_geometry.dart';

/// One camera preview frame (YUV420, as the camera image stream gives it).
/// Only the luma plane is required; chroma planes, when present, are used
/// to tell skin from background.
class PreviewFrame {
  const PreviewFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.yRowStride,
    this.u,
    this.v,
    this.uvRowStride = 0,
    this.uvPixelStride = 1,
    this.rotation = 0,
  });

  final int width, height;
  final Uint8List y;
  final int yRowStride;
  final Uint8List? u, v;
  final int uvRowStride, uvPixelStride;

  /// Quarter turns clockwise that make the frame upright, as the user sees
  /// it (the camera's sensor orientation / 90). Stream frames come in the
  /// sensor's own orientation: 1 for most back cameras held in portrait.
  final int rotation;

  /// Pixel of the frame under the upright position ([u], [v]), both 0..1
  /// from the top left of what the user sees.
  (int, int) pixelAt(double u, double v) {
    final (fx, fy) = switch (rotation % 4) {
      1 => (v, 1 - u),
      2 => (1 - u, 1 - v),
      3 => (1 - v, u),
      _ => (u, v),
    };
    return (
      (fx * width).floor().clamp(0, width - 1),
      (fy * height).floor().clamp(0, height - 1),
    );
  }
}

/// Why the shot has not been taken yet; shown as the live hint.
enum AutoState {
  /// No palm at the centre of the outline.
  noHand,

  /// The palm is in the picture but to one side of the outline.
  offCentre,

  /// The palm is smaller than the outline: the phone is too far away.
  tooFar,

  /// The palm spills over the outline: the phone is too close.
  tooClose,
  tooDark,
  tooBright,

  /// A shiny patch (lamp or flashlight reflection) covers part of the palm.
  glare,
  moving,
  soft,
  ready;

  /// The palm sits in the outline at the right size (light and focus may
  /// still be settling).
  bool get aligned => index >= tooBright.index;
}

/// Decides when to take a guided shot by itself: the palm fits the
/// outline drawn on the preview, the light is usable, the picture stops
/// moving and the focus has settled. Fed preview frames (about 8 per
/// second).
///
/// It looks at the same place the outline is drawn (`PalmGeometry.guide`,
/// scaled like the outline of the current shot), in upright coordinates,
/// so it works whatever way the sensor is mounted. All measures are
/// scale-free, so no tuning is needed per phone:
/// - skin: chroma close to the chroma at the palm centre (learned every
///   frame, so it follows the skin tone and the light), which itself must
///   be in a loose skin range. Without chroma planes: neither very dark
///   nor very bright.
/// - [fill]: share of the middle of the outline's palm that is skin; a
///   palm must be there at all.
/// - [size] and [offset]: the palm's own left and right edges, found by
///   walking outwards from the centre along a few rows of the upper palm
///   (above the thumb's web, below the fingers, so neither joins in).
///   [size] is the palm width over the outline's palm width (1 = fits;
///   allowed [minSize]..[maxSize]), [offset] how far its middle is from
///   the outline's, in palm widths. Skipped when the frame corners are
///   skin-coloured too (a wooden table, a beige wall), because then the
///   edges cannot be seen.
/// - [brightness]: mean luma of the palm; [glare]: share of it that clips.
/// - [motion]: mean absolute difference between consecutive frames over
///   the palm, as a fraction of the brightness.
/// - [sharpness]: mean absolute Laplacian at the palm centre, as a
///   fraction of the brightness. It is compared with the best value seen
///   while the palm was in place, so it works whatever the lens: the shot
///   is taken once the focus has reached its peak (>= [sharpFraction] of
///   the best) and stays there.
class AutoCaptureGate {
  AutoCaptureGate({
    this.steadyFrames = 4,
    this.maxMotion = 0.02,
    this.minFill = 0.7,
    this.minSize = 0.85,
    this.maxSize = 1.2,
    this.maxOffset = 0.15,
    this.maxGlare = 0.08,
    this.sharpFraction = 0.85,
    this.minSharpness = 0.004,
  });

  /// Consecutive good frames needed (about half a second).
  final int steadyFrames;
  final double maxMotion;
  final double minFill;
  final double minSize, maxSize;
  final double maxOffset;
  final double maxGlare;
  final double sharpFraction;
  final double minSharpness;

  // Sampling grid over the upright frame (portrait: 9 x 16 cells of 4).
  static const _gw = 36, _gh = 64;
  Float32List? _prev;
  int _good = 0;
  double _bestSharp = 0;

  /// Last measured values, for tests and debugging.
  double fill = 0, size = 0, offset = 0, brightness = 0, glare = 0, motion = 0, sharpness = 0;

  /// The frame corners are skin-coloured, so [size] was not checked.
  bool skinLikeBackground = false;
  AutoState state = AutoState.noHand;

  /// Forget the focus peak and the history (a new shot starts).
  void reset() {
    _prev = null;
    _good = 0;
    _bestSharp = 0;
    state = AutoState.noHand;
  }

  /// Measures [f] against the outline drawn at [scale] and returns the
  /// state; [AutoState.ready] means take the shot now.
  AutoState add(PreviewFrame f, {double scale = 1}) {
    state = _measure(f, scale);
    if (!state.aligned) {
      // The hand is being moved into place: the focus peak seen so far
      // belongs to another distance.
      _bestSharp = 0;
    }
    if (state == AutoState.ready) {
      _good++;
      if (_good < steadyFrames) return AutoState.soft; // keep still a moment
      _good = 0;
      return AutoState.ready;
    }
    _good = 0;
    return state;
  }

  AutoState _measure(PreviewFrame f, double scale) {
    const n = _gw * _gh;
    final luma = Float32List(n);
    final cbs = Uint8List(n), crs = Uint8List(n);
    final pu = f.u, pv = f.v;
    final hasChroma = pu != null && pv != null;
    for (var gy = 0; gy < _gh; gy++) {
      for (var gx = 0; gx < _gw; gx++) {
        final (px, py) = f.pixelAt((gx + 0.5) / _gw, (gy + 0.5) / _gh);
        final i = gy * _gw + gx;
        luma[i] = f.y[py * f.yRowStride + px].toDouble();
        if (hasChroma) {
          final ci = (py >> 1) * f.uvRowStride + (px >> 1) * f.uvPixelStride;
          final ok = ci < pu.length && ci < pv.length;
          cbs[i] = ok ? pu[ci] : 128;
          crs[i] = ok ? pv[ci] : 128;
        }
      }
    }

    // The outline's palm, where the user is asked to put the hand, in palm
    // units (1 = palm width) as the outline is drawn.
    final aspect = f.rotation.isOdd ? f.width / f.height : f.height / f.width;
    (double, double) at(double x, double y) => PalmGeometry.guidePoint(x, y, scale: scale, aspect: aspect);
    final pw = PalmGeometry.guidePalmWidth * scale;
    final cu = PalmGeometry.guideCenterU;
    void region(double x0, double y0, double x1, double y1, void Function(int i) each) {
      final (u0, v0) = at(x0, y0);
      final (u1, v1) = at(x1, y1);
      _cells(u0, u1, v0, v1, each);
    }

    // Skin colour at the palm centre (median of a small patch).
    var skinAtCentre = true;
    var mcb = 0, mcr = 0;
    if (hasChroma) {
      final pcb = <int>[], pcr = <int>[];
      region(-0.14, -0.13, 0.14, 0.23, (i) {
        pcb.add(cbs[i]);
        pcr.add(crs[i]);
      });
      pcb.sort();
      pcr.sort();
      mcb = pcb[pcb.length ~/ 2];
      mcr = pcr[pcr.length ~/ 2];
      skinAtCentre = mcr >= 132 && mcr <= 185 && mcb >= 70 && mcb <= 135;
    }
    bool skinColour(int cb, int cr, double l) =>
        hasChroma ? (cr - mcr).abs() <= 15 && (cb - mcb).abs() <= 15 : l > 40 && l < 235;
    bool skin(int i) => skinColour(cbs[i], crs[i], luma[i]);

    // The middle of the palm: light, movement, and how much of it is skin.
    var cells = 0, skinCells = 0, clipped = 0;
    var sumAll = 0.0, sumSkin = 0.0, diff = 0.0;
    final prev = _prev;
    region(-0.35, -0.45, 0.35, 0.4, (i) {
      final l = luma[i];
      cells++;
      sumAll += l;
      if (l >= 250) clipped++;
      if (prev != null) diff += (l - prev[i]).abs();
      if (skin(i)) {
        skinCells++;
        sumSkin += l;
      }
    });
    _prev = luma;
    final coreMean = sumAll / math.max(1, cells);
    fill = skinCells / math.max(1, cells);
    brightness = skinCells > 0 ? sumSkin / skinCells : coreMean;
    glare = clipped / math.max(1, cells);
    motion = prev == null ? 1 : diff / math.max(1, cells) / math.max(coreMean, 1);

    // The palm's own edges: from the centre outwards along rows of the
    // palm, until the skin ends. Below the thumb's web the thumb joins in
    // and makes a row wider, so a narrow row (lower quartile) counts.
    const steps = 160;
    bool skinAt(int k, double v) {
      final (px, py) = f.pixelAt((k + 0.5) / steps, v);
      final l = f.y[py * f.yRowStride + px].toDouble();
      if (!hasChroma) return skinColour(0, 0, l);
      final ci = (py >> 1) * f.uvRowStride + (px >> 1) * f.uvPixelStride;
      return ci < pu.length && ci < pv.length && skinColour(pu[ci], pv[ci], l);
    }

    final rows = <(double, double)>[]; // width, middle
    final mid = (cu * steps).floor();
    for (final y in const [-0.42, -0.33, -0.24, -0.15, -0.06, 0.03, 0.12]) {
      final (_, v) = at(0, y);
      if (!skinAt(mid, v)) continue;
      // One stray sample (a crease, noise) does not end the run.
      var l = mid, r = mid;
      while (l > 0 && (skinAt(l - 1, v) || (l > 1 && skinAt(l - 2, v)))) {
        l--;
      }
      while (r < steps - 1 && (skinAt(r + 1, v) || (r < steps - 2 && skinAt(r + 2, v)))) {
        r++;
      }
      rows.add(((r - l + 1) / steps, (l + r + 1) / 2 / steps));
    }
    if (rows.length >= 4) {
      rows.sort((a, b) => a.$1.compareTo(b.$1));
      final (width, middle) = rows[rows.length ~/ 4];
      size = width / pw;
      offset = (middle - cu) / pw;
    } else {
      size = 0;
      offset = 0;
    }

    // Frame corners: skin-coloured there means a skin-coloured background.
    var cornerN = 0, cornerSkin = 0;
    for (final (a, b) in const [(0.0, 0.12), (0.88, 1.0)]) {
      for (final (c, d) in const [(0.0, 0.08), (0.92, 1.0)]) {
        _cells(a, b, c, d, (i) {
          cornerN++;
          if (skin(i)) cornerSkin++;
        });
      }
    }
    skinLikeBackground = cornerN > 0 && cornerSkin > cornerN * 0.5;

    // Sharpness at native resolution on a small square at the palm centre.
    final (cx, cy) = at(0, 0.05);
    final (px, py) = f.pixelAt(cx, cy);
    final s = math.min(96, math.min(f.width, f.height) - 2);
    final sx = (px - s ~/ 2).clamp(0, f.width - s), sy = (py - s ~/ 2).clamp(0, f.height - s);
    var lap = 0.0;
    for (var yy = sy + 1; yy < sy + s - 1; yy++) {
      final row = yy * f.yRowStride;
      for (var xx = sx + 1; xx < sx + s - 1; xx++) {
        final i = row + xx;
        lap += (4 * f.y[i] - f.y[i - 1] - f.y[i + 1] - f.y[i - f.yRowStride] - f.y[i + f.yRowStride]).abs();
      }
    }
    sharpness = lap / ((s - 2) * (s - 2)) / math.max(brightness, 1);

    if (coreMean < 55) return AutoState.tooDark;
    if (!skinAtCentre || fill < 0.3) return AutoState.noHand;
    if (!skinLikeBackground) {
      if (size > maxSize) return AutoState.tooClose;
      if (offset.abs() > maxOffset) return AutoState.offCentre;
      if (size < minSize) return AutoState.tooFar;
    }
    if (fill < minFill) return AutoState.tooFar;
    if (brightness > 225) return AutoState.tooBright;
    if (glare > maxGlare) return AutoState.glare;
    if (motion > maxMotion) return AutoState.moving;
    // The peak fades slowly, so a sharp moment long ago cannot block the
    // shot for ever.
    _bestSharp = math.max(sharpness, _bestSharp * 0.98);
    return sharpness >= minSharpness && sharpness >= _bestSharp * sharpFraction ? AutoState.ready : AutoState.soft;
  }

  /// Calls [each] with the grid index of every cell inside the upright
  /// rectangle [u0]..[u1] x [v0]..[v1] (clipped to the frame).
  void _cells(double u0, double u1, double v0, double v1, void Function(int i) each) {
    final x0 = (u0 * _gw).round().clamp(0, _gw), x1 = (u1 * _gw).round().clamp(0, _gw);
    final y0 = (v0 * _gh).round().clamp(0, _gh), y1 = (v1 * _gh).round().clamp(0, _gh);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        each(y * _gw + x);
      }
    }
  }
}
