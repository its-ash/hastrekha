import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

/// A small drawing of a palm, used to show what each hand type, palm
/// shape, finger length and line count looks like.
///
/// [palm] is `square`, `rectangular` or `rounded`; [fingers] is `short`,
/// `medium` or `long`; [density] is `few`, `moderate` or `many`; [depth]
/// is `faint`, `medium` or `deep`.
class HandSketch extends StatelessWidget {
  const HandSketch({
    super.key,
    this.palm = 'square',
    this.fingers = 'medium',
    this.density = 'moderate',
    this.depth = 'medium',
    this.selected = false,
  });

  final String palm;
  final String fingers;
  final String density;
  final String depth;
  final bool selected;

  /// The typical look of each hand element (Ayurvedic hand type).
  static HandSketch element(String e, {bool selected = false}) => switch (e) {
        'air' => HandSketch(palm: 'rectangular', fingers: 'long', density: 'many', depth: 'faint', selected: selected),
        'water' => HandSketch(palm: 'rounded', fingers: 'short', density: 'few', depth: 'deep', selected: selected),
        _ => HandSketch(palm: 'square', fingers: 'medium', density: 'moderate', depth: 'medium', selected: selected),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: _HandSketchPainter(
        palm: palm,
        fingers: fingers,
        density: density,
        depth: depth,
        fill: selected ? c.accent.withValues(alpha: 0.14) : c.surfaceMuted,
        outline: selected ? c.accent : c.textMuted,
        line: selected ? c.accent : c.text,
      ),
    );
  }
}

class _HandSketchPainter extends CustomPainter {
  _HandSketchPainter({
    required this.palm,
    required this.fingers,
    required this.density,
    required this.depth,
    required this.fill,
    required this.outline,
    required this.line,
  });

  final String palm, fingers, density, depth;
  final Color fill, outline, line;

  @override
  void paint(Canvas canvas, Size size) {
    // Proportions in units of the palm width.
    final aspect = switch (palm) { 'rectangular' => 1.32, 'rounded' => 1.04, _ => 1.0 };
    final fingerRatio = switch (fingers) { 'short' => 0.62, 'long' => 0.98, _ => 0.8 };
    final fingerW = switch (fingers) { 'short' => 0.235, 'long' => 0.19, _ => 0.215 };
    final thumbOut = 0.36;
    final totalW = 1 + thumbOut;
    final totalH = fingerRatio * aspect + aspect + 0.12;
    final unit = math.min(size.width / totalW, size.height / totalH);
    final ox = (size.width - totalW * unit) / 2 + thumbOut * unit;
    final oy = (size.height - totalH * unit) / 2 + fingerRatio * aspect * unit;
    Offset p(double u, double v) => Offset(ox + u * unit, oy + v * unit);

    final ph = aspect; // palm height in units
    // Parts are merged into one silhouette, so no edges cross the palm.
    var shape = Path();
    void union(Path part) => shape = Path.combine(PathOperation.union, shape, part);

    // Palm.
    final radius = palm == 'rounded' ? 0.32 : 0.1;
    shape.addRRect(RRect.fromRectAndCorners(
      Rect.fromPoints(p(0, 0), p(1, ph)),
      topLeft: Radius.circular(0.08 * unit),
      topRight: Radius.circular(0.08 * unit),
      bottomLeft: Radius.circular(radius * unit),
      bottomRight: Radius.circular(radius * unit),
    ));
    if (palm == 'rounded') {
      // Fleshy sides.
      union(Path()..addOval(Rect.fromCenter(center: p(0.04, ph * 0.64), width: 0.17 * unit, height: ph * 0.56 * unit)));
      union(Path()..addOval(Rect.fromCenter(center: p(0.965, ph * 0.6), width: 0.14 * unit, height: ph * 0.56 * unit)));
    }

    // Fingers: index to little.
    const lengths = [0.88, 1.0, 0.93, 0.74];
    final gap = (1 - 4 * fingerW) / 5;
    for (var i = 0; i < 4; i++) {
      final l = gap + i * (fingerW + gap);
      final len = fingerRatio * ph * lengths[i];
      final base = i == 3 ? 0.06 : 0.02;
      union(Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromPoints(p(l, base - len), p(l + fingerW, base + 0.12)),
          Radius.circular(fingerW / 2 * unit),
        )));
    }

    // Thumb, leaning out from the lower thumb side.
    final thumbLen = 0.55 * ph * (fingers == 'short' ? 0.85 : (fingers == 'long' ? 1.08 : 1.0));
    final pivot = p(0.08, ph * 0.78);
    final thumb = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(-fingerW * 0.62 * unit, -thumbLen * unit, fingerW * 1.24 * unit, thumbLen * unit),
        Radius.circular(fingerW * 0.62 * unit),
      ));
    final m = Matrix4.identity()
      ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
      ..rotateZ(-0.62);
    union(thumb.transform(m.storage));

    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Lines.
    final w = switch (depth) { 'deep' => 2.6, 'faint' => 1.0, _ => 1.7 };
    final main = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    void curve(List<(double, double)> pts, Paint paint) {
      final path = Path()..moveTo(p(pts[0].$1, pts[0].$2 * ph).dx, p(pts[0].$1, pts[0].$2 * ph).dy);
      for (var i = 1; i + 1 < pts.length; i += 2) {
        final c1 = p(pts[i].$1, pts[i].$2 * ph), e = p(pts[i + 1].$1, pts[i + 1].$2 * ph);
        path.quadraticBezierTo(c1.dx, c1.dy, e.dx, e.dy);
      }
      canvas.drawPath(path, paint);
    }

    curve([(0.95, 0.2), (0.6, 0.1), (0.2, 0.12)], main); // heart
    curve([(0.1, 0.33), (0.45, 0.36), (0.8, 0.5)], main); // head
    curve([(0.1, 0.34), (0.32, 0.6), (0.3, 0.95)], main); // life
    if (density != 'few') curve([(0.52, 0.95), (0.5, 0.6), (0.46, 0.3)], main); // fate

    if (density == 'many') {
      final fine = Paint()
        ..color = line.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round;
      const extra = [
        [(0.7, 0.9), (0.66, 0.6), (0.68, 0.28)],
        [(0.85, 0.45), (0.7, 0.62), (0.58, 0.8)],
        [(0.9, 0.7), (0.8, 0.72), (0.72, 0.68)],
        [(0.25, 0.5), (0.35, 0.45), (0.42, 0.5)],
        [(0.6, 0.18), (0.65, 0.26), (0.75, 0.3)],
        [(0.2, 0.75), (0.15, 0.8), (0.12, 0.88)],
        [(0.4, 0.7), (0.45, 0.75), (0.42, 0.85)],
      ];
      for (final e in extra) {
        curve(e, fine);
      }
    }
  }

  @override
  bool shouldRepaint(_HandSketchPainter old) =>
      old.palm != palm ||
      old.fingers != fingers ||
      old.density != density ||
      old.depth != depth ||
      old.fill != fill ||
      old.outline != outline ||
      old.line != line;
}
