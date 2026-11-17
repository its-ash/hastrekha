import 'package:flutter/material.dart';

import '../../vision/palm_geometry.dart';

/// The box on the camera view where the palm goes: finger base at the top
/// edge, wrist crease at the bottom, the palm's sides at the side edges.
/// Drawn as four corner brackets over the full, undimmed camera picture;
/// when [good] the whole box is drawn too.
///
/// It is the same rectangle the auto capture and the analyzer measure
/// against (`PalmGeometry.guide`), scaled by [scale] for the far shot
/// (< 1) or the close-up (> 1).
class PalmFramePainter extends CustomPainter {
  PalmFramePainter({required this.color, required this.good, this.scale = 1});

  final Color color;
  final bool good;
  final double scale;

  /// The box in pixels of a camera view of [size].
  static Rect boxOf(Size size, double scale) {
    final g = PalmGeometry.guide(thumbOnLeft: true, scale: scale, aspect: size.height / size.width);
    return Rect.fromLTRB(g.left * size.width, g.top * size.height, g.right * size.width, g.bottom * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = boxOf(size, scale);
    final radius = box.shortestSide * 0.12;
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(radius));

    // A thin line all round, stronger when the palm is in place.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: good ? 0.9 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = good ? 3 : 1.5,
    );

    // Corner brackets.
    final arm = box.shortestSide * 0.24;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final (cx, cy, sx, sy) in [
      (box.left, box.top, 1.0, 1.0),
      (box.right, box.top, -1.0, 1.0),
      (box.left, box.bottom, 1.0, -1.0),
      (box.right, box.bottom, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(cx, cy + sy * arm)
        ..lineTo(cx, cy + sy * radius)
        ..arcToPoint(Offset(cx + sx * radius, cy), radius: Radius.circular(radius), clockwise: sx * sy > 0)
        ..lineTo(cx + sx * arm, cy);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(PalmFramePainter old) => old.color != color || old.good != good || old.scale != scale;
}
