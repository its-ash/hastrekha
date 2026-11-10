// Debug helper: writes the analysed synthetic palms with their overlay to
// /tmp/hastrekha_debug so the pipeline can be inspected by eye.
import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:hastrekha/ui/capture/capture_screen.dart';
import 'package:hastrekha/ui/widgets/hand_sketch.dart';
import 'package:theme/theme.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';
import 'package:image/image.dart' as img;

import 'vision_test.dart' show faintPalm, noisyBurst, syntheticPalm;

void main() {
  testWidgets('capture guide', (tester) async {
    Directory('/tmp/hastrekha_debug').createSync(recursive: true);
    for (final left in [true, false]) {
      final recorder = ui.PictureRecorder();
      const size = Size(360, 640);
      final canvas = Canvas(recorder)..drawRect(Offset.zero & size, Paint()..color = const Color(0xFF6B5A4E));
      HandGuidePainter(thumbOnLeft: left, line: const Color(0xFFFFFFFF), shade: const Color(0xFF000000))
          .paint(canvas, size);
      await tester.runAsync(() async {
        final image = await recorder.endRecording().toImage(360, 640);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/hastrekha_debug/guide_${left ? 'left' : 'right'}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });

  testWidgets('hand sketches', (tester) async {
    Directory('/tmp/hastrekha_debug').createSync(recursive: true);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: UiTheme.light(),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.white,
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final row in [
                [HandSketch.element('air'), HandSketch.element('fire', selected: true), HandSketch.element('water')],
                [const HandSketch(palm: 'square'), const HandSketch(palm: 'rectangular'), const HandSketch(palm: 'rounded')],
                [const HandSketch(fingers: 'short'), const HandSketch(fingers: 'medium'), const HandSketch(fingers: 'long')],
              ])
                Row(children: [for (final s in row) Expanded(child: SizedBox(height: 110, child: s))]),
            ]),
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/hastrekha_debug/hand_sketches.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });

  test('dump', () {
    Directory('/tmp/hastrekha_debug').createSync(recursive: true);
    for (final (name, photos, right) in [
      ('right', [syntheticPalm()], true),
      ('left', [syntheticPalm(rightHand: false, withFate: false)], false),
      ('faint', [faintPalm()], true),
      ('faint-noisy', [faintPalm(noise: 11, seed: 3)], true),
      ('noisy-nofate', [syntheticPalm(withFate: false, noise: 10, seed: 5)], true),
      ('fused', noisyBurst(), true),
    ]) {
      final a = const PalmAnalyzer().analyzeAll(photos, rightHand: right);
      final im = img.decodeJpg(a.photo)!;
      void poly(List<double> p, img.Color c) {
        for (var i = 2; i < p.length; i += 2) {
          img.drawLine(im,
              x1: (p[i - 2] * im.width).round(), y1: (p[i - 1] * im.height).round(),
              x2: (p[i] * im.width).round(), y2: (p[i + 1] * im.height).round(), color: c, thickness: 3);
        }
      }

      for (final m in a.minorPaths) {
        poly(m, img.ColorRgb8(0, 0, 255));
      }
      final colors = {
        'life': img.ColorRgb8(255, 0, 0),
        'head': img.ColorRgb8(0, 200, 0),
        'heart': img.ColorRgb8(255, 0, 255),
        'fate': img.ColorRgb8(255, 255, 0),
      };
      for (final e in a.paths.entries) {
        for (final p in e.value) {
          poly(p, colors[e.key] ?? img.ColorRgb8(0, 255, 255));
        }
      }
      final r = a.palmRect;
      img.drawRect(im,
          x1: (r[0] * im.width).round(), y1: (r[1] * im.height).round(),
          x2: (r[2] * im.width).round(), y2: (r[3] * im.height).round(), color: img.ColorRgb8(255, 255, 255));
      final small = img.copyResize(im, width: 260);
      File('/tmp/hastrekha_debug/$name.jpg').writeAsBytesSync(img.encodeJpg(small, quality: 70));
      // ignore: avoid_print
      print('$name photos=${a.photosUsed} thumbOnLeft=${a.thumbOnLeft} issues=${a.issues} palm=${r.map((e) => e.toStringAsFixed(2))} '
          'lines=${a.paths.keys.toList()} minor=${a.minorPaths.length} '
          'features=${a.features.lines.entries.where((e) => e.value.present).map((e) => '${e.key}:${e.value.length}/${e.value.depth}/${e.value.confidence.toStringAsFixed(2)}').toList()}');
    }
  });
}
