import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../data/overlay.dart';
import 'common.dart';

/// The palm photo with the detected lines drawn on top.
class PalmView extends StatelessWidget {
  const PalmView({
    super.key,
    required this.overlay,
    this.file,
    this.bytes,
    this.highlight,
    this.showLines = true,
    this.showMinor = true,
    this.only,
    this.radius = UiRadius.lg,
  }) : assert(file != null || bytes != null);

  final PalmOverlay overlay;
  final String? file;
  final Uint8List? bytes;

  /// Line drawn bold while the others fade.
  final String? highlight;
  final bool showLines;
  final bool showMinor;

  /// When set, draw only these lines.
  final Set<String>? only;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        : Image.file(File(file!), fit: BoxFit.cover, gaplessPlayback: true);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: overlay.aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (showLines)
              CustomPaint(
                painter: _OverlayPainter(
                  overlay: overlay,
                  highlight: highlight,
                  showMinor: showMinor,
                  only: only,
                  colors: [for (var i = 0; i < 8; i++) context.colors.chartColor(i)],
                  minorColor: context.colors.onSurfaceInverse.withValues(alpha: 0.45),
                  halo: context.colors.surfaceInverse.withValues(alpha: 0.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.overlay,
    required this.highlight,
    required this.showMinor,
    required this.only,
    required this.colors,
    required this.minorColor,
    required this.halo,
  });

  final PalmOverlay overlay;
  final String? highlight;
  final bool showMinor;
  final Set<String>? only;
  final List<Color> colors;
  final Color minorColor;
  final Color halo;

  Path _path(List<double> p, Size s) {
    final path = Path();
    for (var i = 0; i + 1 < p.length; i += 2) {
      final o = Offset(p[i] * s.width, p[i + 1] * s.height);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 300;
    if (showMinor && highlight == null && only == null) {
      final paint = Paint()
        ..color = minorColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * unit
        ..strokeCap = StrokeCap.round;
      for (final m in overlay.minor) {
        canvas.drawPath(_path(m, size), paint);
      }
    }
    for (final e in overlay.paths.entries) {
      if (only != null && !only!.contains(e.key)) continue;
      final dim = highlight != null && highlight != e.key;
      final color = colors[Labels.lineColorIndex(e.key) % colors.length];
      final width = (highlight == e.key ? 4.2 : 2.8) * unit;
      final haloPaint = Paint()
        ..color = halo.withValues(alpha: dim ? 0.1 : halo.a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 2.5 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final paint = Paint()
        ..color = color.withValues(alpha: dim ? 0.25 : 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final p in e.value) {
        final path = _path(p, size);
        canvas.drawPath(path, haloPaint);
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.overlay != overlay || old.highlight != highlight || old.showMinor != showMinor || old.only != only ||
      old.colors.first != colors.first;
}

/// A small colored dot used as a line legend.
class LineDot extends StatelessWidget {
  const LineDot(this.lineKey, {super.key, this.size = 12});
  final String lineKey;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.colors.chartColor(Labels.lineColorIndex(lineKey)),
          shape: BoxShape.circle,
        ),
      );
}
