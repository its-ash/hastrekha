import 'dart:math' as math;
import 'dart:typed_data';

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
  });

  final int width, height;
  final Uint8List y;
  final int yRowStride;
  final Uint8List? u, v;
  final int uvRowStride, uvPixelStride;
}

/// Why the shot has not been taken yet; shown as the live hint.
enum AutoState { noHand, tooDark, tooBright, moving, soft, ready }

/// Decides when to take a guided shot by itself: the palm fills the
/// middle of the frame, the light is usable, the picture stops moving
/// and the focus has settled. Fed preview frames (about 8 per second).
///
/// All measures are scale-free so no tuning is needed per phone:
/// - fill: share of the central box that has skin colour (chroma planes;
///   without them, share that is neither very dark nor very bright),
/// - brightness: mean luma of the box,
/// - motion: mean absolute difference between consecutive frames, as a
///   fraction of the brightness,
/// - sharpness: mean absolute Laplacian over the box, as a fraction of the
///   brightness. It is compared with the best value seen in this shot, so
///   it works whatever the lens: the shot is taken once the focus has
///   reached its peak (>= [sharpFraction] of the best) and stays there.
class AutoCaptureGate {
  AutoCaptureGate({
    this.steadyFrames = 4,
    this.maxMotion = 0.02,
    this.minFill = 0.5,
    this.sharpFraction = 0.85,
    this.minSharpness = 0.004,
  });

  /// Consecutive good frames needed (about half a second).
  final int steadyFrames;
  final double maxMotion;
  final double minFill;
  final double sharpFraction;
  final double minSharpness;

  static const _grid = 48;
  Float32List? _prev;
  int _good = 0;
  double _bestSharp = 0;

  /// Last measured values, for tests and debugging.
  double fill = 0, brightness = 0, motion = 0, sharpness = 0;
  AutoState state = AutoState.noHand;

  /// Forget the focus peak and the history (a new shot starts).
  void reset() {
    _prev = null;
    _good = 0;
    _bestSharp = 0;
    state = AutoState.noHand;
  }

  /// Measures [f] and returns the state; [AutoState.ready] means take the
  /// shot now.
  AutoState add(PreviewFrame f) {
    // Central box: 56% of each side, in frame pixels.
    final bw = (f.width * 0.56).floor(), bh = (f.height * 0.56).floor();
    final x0 = (f.width - bw) ~/ 2, y0 = (f.height - bh) ~/ 2;

    // Downsampled grid of luma for motion and brightness; skin share.
    final grid = Float32List(_grid * _grid);
    var skin = 0, sum = 0.0;
    for (var gy = 0; gy < _grid; gy++) {
      final py = y0 + (gy * bh ~/ _grid);
      for (var gx = 0; gx < _grid; gx++) {
        final px = x0 + (gx * bw ~/ _grid);
        final l = f.y[py * f.yRowStride + px].toDouble();
        grid[gy * _grid + gx] = l;
        sum += l;
        final u = f.u, v = f.v;
        if (u != null && v != null) {
          final ci = (py >> 1) * f.uvRowStride + (px >> 1) * f.uvPixelStride;
          if (ci < u.length && ci < v.length) {
            final cb = u[ci], cr = v[ci];
            if (cr >= 133 && cr <= 180 && cb >= 77 && cb <= 135) skin++;
          }
        } else if (l > 40 && l < 235) {
          skin++;
        }
      }
    }
    brightness = sum / (_grid * _grid);
    fill = skin / (_grid * _grid);

    var diff = 0.0;
    final prev = _prev;
    if (prev != null) {
      for (var i = 0; i < grid.length; i++) {
        diff += (grid[i] - prev[i]).abs();
      }
      motion = diff / grid.length / math.max(brightness, 1);
    } else {
      motion = 1;
    }
    _prev = grid;

    // Sharpness at native resolution on a 96-px square at the box centre.
    const s = 96;
    final sx = f.width ~/ 2 - s ~/ 2, sy = f.height ~/ 2 - s ~/ 2;
    var lap = 0.0;
    for (var yy = sy + 1; yy < sy + s - 1; yy++) {
      final row = yy * f.yRowStride;
      for (var xx = sx + 1; xx < sx + s - 1; xx++) {
        final i = row + xx;
        lap += (4 * f.y[i] - f.y[i - 1] - f.y[i + 1] - f.y[i - f.yRowStride] - f.y[i + f.yRowStride]).abs();
      }
    }
    sharpness = lap / ((s - 2) * (s - 2)) / math.max(brightness, 1);

    if (fill < minFill) {
      state = AutoState.noHand;
    } else if (brightness < 55) {
      state = AutoState.tooDark;
    } else if (brightness > 225) {
      state = AutoState.tooBright;
    } else if (motion > maxMotion) {
      state = AutoState.moving;
    } else {
      if (sharpness > _bestSharp) _bestSharp = sharpness;
      state = sharpness >= minSharpness && sharpness >= _bestSharp * sharpFraction ? AutoState.ready : AutoState.soft;
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
}
