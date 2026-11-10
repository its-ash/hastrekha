import 'dart:math' as math;
import 'dart:typed_data';

/// Single-channel float image, row-major. The basic buffer for all vision
/// code. Pure Dart so it runs inside an isolate and in unit tests.
class FloatImage {
  FloatImage(this.width, this.height) : data = Float32List(width * height);

  FloatImage.from(this.width, this.height, this.data)
      : assert(data.length == width * height);

  final int width;
  final int height;
  final Float32List data;

  double at(int x, int y) => data[y * width + x];

  void set(int x, int y, double v) => data[y * width + x] = v;

  /// Value at (x, y) with coordinates clamped to the image.
  double clamped(int x, int y) {
    final cx = x < 0 ? 0 : (x >= width ? width - 1 : x);
    final cy = y < 0 ? 0 : (y >= height ? height - 1 : y);
    return data[cy * width + cx];
  }

  /// Bilinear sample at a fractional position.
  double sample(double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    final a = clamped(x0, y0), b = clamped(x0 + 1, y0);
    final c = clamped(x0, y0 + 1), d = clamped(x0 + 1, y0 + 1);
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  }

  FloatImage copy() => FloatImage.from(width, height, Float32List.fromList(data));

  /// Resizes with bilinear sampling (area-averaged when shrinking a lot).
  FloatImage resize(int w, int h) {
    var src = this;
    // Halve first while the shrink is large, so bilinear does not alias.
    while (src.width >= w * 2 && src.height >= h * 2) {
      src = src._half();
    }
    final out = FloatImage(w, h);
    final sx = src.width / w, sy = src.height / h;
    for (var y = 0; y < h; y++) {
      final fy = (y + 0.5) * sy - 0.5;
      for (var x = 0; x < w; x++) {
        out.data[y * w + x] = src.sample((x + 0.5) * sx - 0.5, fy);
      }
    }
    return out;
  }

  FloatImage _half() {
    final w = width ~/ 2, h = height ~/ 2;
    final out = FloatImage(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * 2) * width + x * 2;
        out.data[y * w + x] =
            (data[i] + data[i + 1] + data[i + width] + data[i + width + 1]) * 0.25;
      }
    }
    return out;
  }

  /// Separable Gaussian blur. Edges are clamped.
  FloatImage blur(double sigma) {
    if (sigma <= 0.01) return copy();
    final k = gaussianKernel(sigma);
    final r = k.length ~/ 2;
    final tmp = Float32List(width * height);
    final out = FloatImage(width, height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          var xx = x + i;
          if (xx < 0) xx = 0;
          if (xx >= width) xx = width - 1;
          s += data[row + xx] * k[i + r];
        }
        tmp[row + x] = s;
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          var yy = y + i;
          if (yy < 0) yy = 0;
          if (yy >= height) yy = height - 1;
          s += tmp[yy * width + x] * k[i + r];
        }
        out.data[y * width + x] = s;
      }
    }
    return out;
  }

  /// Percentile (0..1) of the values where [mask] is set (all when null).
  double percentile(double p, {Uint8List? mask}) {
    final values = <double>[];
    for (var i = 0; i < data.length; i++) {
      if (mask == null || mask[i] != 0) values.add(data[i]);
    }
    if (values.isEmpty) return 0;
    values.sort();
    final idx = ((values.length - 1) * p).round().clamp(0, values.length - 1);
    return values[idx];
  }

  double mean({Uint8List? mask}) {
    var s = 0.0;
    var n = 0;
    for (var i = 0; i < data.length; i++) {
      if (mask == null || mask[i] != 0) {
        s += data[i];
        n++;
      }
    }
    return n == 0 ? 0 : s / n;
  }
}

/// Normalized 1-D Gaussian kernel of radius ceil(3 sigma).
Float32List gaussianKernel(double sigma) {
  final r = math.max(1, (sigma * 3).ceil());
  final k = Float32List(2 * r + 1);
  var sum = 0.0;
  for (var i = -r; i <= r; i++) {
    final v = math.exp(-(i * i) / (2 * sigma * sigma));
    k[i + r] = v;
    sum += v;
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  return k;
}

/// Binary mask helpers. Masks are `Uint8List` of 0/1, row-major.
class Masks {
  Masks._();

  /// Square erosion (min filter) with the given radius, separable.
  static Uint8List erode(Uint8List m, int w, int h, int r) =>
      _minMax(m, w, h, r, erode: true);

  /// Square dilation (max filter) with the given radius, separable.
  static Uint8List dilate(Uint8List m, int w, int h, int r) =>
      _minMax(m, w, h, r, erode: false);

  static Uint8List open(Uint8List m, int w, int h, int r) =>
      dilate(erode(m, w, h, r), w, h, r);

  static Uint8List close(Uint8List m, int w, int h, int r) =>
      erode(dilate(m, w, h, r), w, h, r);

  static Uint8List _minMax(Uint8List m, int w, int h, int r, {required bool erode}) {
    if (r <= 0) return Uint8List.fromList(m);
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    // Running count of set pixels in the window: O(n) regardless of r.
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var count = 0;
      for (var x = -r; x <= r; x++) {
        if (x >= 0 && x < w) count += m[row + x];
      }
      for (var x = 0; x < w; x++) {
        final lo = math.max(0, x - r), hi = math.min(w - 1, x + r);
        final span = hi - lo + 1;
        tmp[row + x] = erode ? (count == span ? 1 : 0) : (count > 0 ? 1 : 0);
        final out0 = x - r, in1 = x + r + 1;
        if (out0 >= 0) count -= m[row + out0];
        if (in1 < w) count += m[row + in1];
      }
    }
    for (var x = 0; x < w; x++) {
      var count = 0;
      for (var y = -r; y <= r; y++) {
        if (y >= 0 && y < h) count += tmp[y * w + x];
      }
      for (var y = 0; y < h; y++) {
        final lo = math.max(0, y - r), hi = math.min(h - 1, y + r);
        final span = hi - lo + 1;
        out[y * w + x] = erode ? (count == span ? 1 : 0) : (count > 0 ? 1 : 0);
        final out0 = y - r, in1 = y + r + 1;
        if (out0 >= 0) count -= tmp[out0 * w + x];
        if (in1 < h) count += tmp[in1 * w + x];
      }
    }
    return out;
  }

  /// Labels 8-connected components. Returns labels (0 = background) and
  /// the pixel count of each label (index = label).
  static ({Int32List labels, List<int> sizes}) components(Uint8List m, int w, int h) {
    final labels = Int32List(w * h);
    final sizes = <int>[0];
    final stack = <int>[];
    var next = 1;
    for (var i = 0; i < m.length; i++) {
      if (m[i] == 0 || labels[i] != 0) continue;
      var size = 0;
      labels[i] = next;
      stack.add(i);
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        size++;
        final px = p % w, py = p ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (m[q] != 0 && labels[q] == 0) {
              labels[q] = next;
              stack.add(q);
            }
          }
        }
      }
      sizes.add(size);
      next++;
    }
    return (labels: labels, sizes: sizes);
  }

  /// Fills holes: background regions not connected to the border.
  static Uint8List fillHoles(Uint8List m, int w, int h) {
    final outside = Uint8List(w * h);
    final stack = <int>[];
    void seed(int i) {
      if (m[i] == 0 && outside[i] == 0) {
        outside[i] = 1;
        stack.add(i);
      }
    }

    for (var x = 0; x < w; x++) {
      seed(x);
      seed((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seed(y * w);
      seed(y * w + w - 1);
    }
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final px = p % w, py = p ~/ w;
      if (px > 0) seed(p - 1);
      if (px < w - 1) seed(p + 1);
      if (py > 0) seed(p - w);
      if (py < h - 1) seed(p + w);
    }
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = outside[i] == 0 ? 1 : 0;
    }
    return out;
  }

  /// Chamfer (3-4) distance to the nearest background pixel, in pixels.
  static Float32List distance(Uint8List m, int w, int h) {
    const big = 1e9;
    final d = Float32List(w * h);
    for (var i = 0; i < d.length; i++) {
      d[i] = m[i] == 0 ? 0 : big;
    }
    double g(int x, int y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : d[y * w + x];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        var v = d[i];
        v = math.min(v, g(x - 1, y) + 3);
        v = math.min(v, g(x, y - 1) + 3);
        v = math.min(v, g(x - 1, y - 1) + 4);
        v = math.min(v, g(x + 1, y - 1) + 4);
        d[i] = v;
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        var v = d[i];
        v = math.min(v, g(x + 1, y) + 3);
        v = math.min(v, g(x, y + 1) + 3);
        v = math.min(v, g(x + 1, y + 1) + 4);
        v = math.min(v, g(x - 1, y + 1) + 4);
        d[i] = v;
      }
    }
    for (var i = 0; i < d.length; i++) {
      d[i] /= 3;
    }
    return d;
  }
}
