// Replays real camera captures pulled from a phone (debug or profile build,
// see lib/data/capture_log.dart):
//
//   adb pull /sdcard/Android/data/com.itsash.hastrekha/files/captures /tmp/hastrekha_captures
//   flutter test test/real_capture_test.dart
//
// For each capture folder it prints the quality of every frame, reads the
// palm from the frames that passed (as the app does), and writes the
// overlay to /tmp/hastrekha_debug/real_<folder>.jpg. Skipped when there
// are no captures.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/vision/hand_shape.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';
import 'package:image/image.dart' as img;

const _root = '/tmp/hastrekha_captures';

/// Seams between the fingers from the last analysis (for the overlay).
(List<List<int>>, int)? _seams;

void main() {
  final root = Directory(_root);
  final dirs = root.existsSync()
      ? (root.listSync().whereType<Directory>().where((d) => File('${d.path}/info.json').existsSync()).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <Directory>[];

  test('real captures', () {
    Directory('/tmp/hastrekha_debug').createSync(recursive: true);
    for (final d in dirs) {
      final name = d.path.split('/').last;
      final info = jsonDecode(File('${d.path}/info.json').readAsStringSync()) as Map<String, dynamic>;
      final right = info['hand'] == 'right';
      final frames = d.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (frames.isEmpty) continue;
      // ignore: avoid_print
      print('== $name hand ${info['hand']} preview ${info['previewSize']} frames ${frames.length}');
      final good = <Uint8List>[];
      final scales = <double>[];
      for (final f in frames) {
        final bytes = f.readAsBytesSync();
        final step = int.tryParse(f.path.split('/').last.substring(1).split('_').first) ?? 0;
        final steps = (info['steps'] as List).cast<num>();
        final scale = steps[step.clamp(0, steps.length - 1)].toDouble();
        final q = const PalmAnalyzer().assess(bytes, rightHand: right, guideScale: scale);
        final im = img.decodeJpg(bytes)!;
        // ignore: avoid_print
        print('  ${f.path.split('/').last} ${im.width}x${im.height} $q');
        if (q.ok) {
          good.add(bytes);
          scales.add(scale);
        }
      }
      if (good.isEmpty) continue;
      final log = <String>[];
      HandShape.debug = log.add;
      HandShape.debugMask = (m, w, h) {
        final im = img.Image(width: w, height: h);
        for (var i = 0; i < m.length; i++) {
          im.setPixelRgb(i % w, i ~/ w, m[i] * 255, m[i] * 255, m[i] * 255);
        }
        File('/tmp/hastrekha_debug/real_${name}_mask.png').writeAsBytesSync(img.encodePng(im));
      };
      HandShape.debugSeams = (s, top) => _seams = (s, top);
      _seams = null;
      final a = const PalmAnalyzer().analyzeAll(good, rightHand: right, guideScales: scales);
      HandShape.debug = null;
      HandShape.debugMask = null;
      HandShape.debugSeams = null;
      File('/tmp/hastrekha_debug/real_${name}_fingers.txt').writeAsStringSync(log.join('\n'));
      _drawOverlay(a, '/tmp/hastrekha_debug/real_$name.jpg');
      final s = a.handShape;
      final f = a.features;
      // ignore: avoid_print
      print('  shape: fingers ${f.fingers} dev ${f.fingerDev} tips ${f.tips} base ${f.fingerBase} '
          'thumb ${f.thumbLength}/${f.thumbBuild} phalanx ${f.phalanx}');
      if (s != null) {
        for (final fs in s.fingers.values) {
          // ignore: avoid_print
          print('    ${fs.name}: len ${(fs.length / s.palmWidth).toStringAsFixed(2)} pw, '
              'w50 ${((fs.widthAt(0.5) ?? 0) / s.palmWidth).toStringAsFixed(3)}, tip ${fs.tip} '
              'tipFull ${((fs.widthBelowTip((fs.widthAt(0.5) ?? 0) * 0.12) ?? 0) / (fs.widthAt(0.5) ?? 1)).toStringAsFixed(2)} '
              'base ${fs.baseRatio?.toStringAsFixed(2)} joints ${fs.joints} phal ${fs.longPhalanx}');
        }
        final t = s.thumb;
        // ignore: avoid_print
        print('    thumb: ${t == null ? 'none' : 'len ${(t.length / s.palmWidth).toStringAsFixed(2)} pw, width ${(t.width / s.palmWidth).toStringAsFixed(2)} pw'}');
      }
      // Each good frame read alone: the same palm should give the same
      // lines in every photo.
      if (Platform.environment['SINGLE'] != null) {
        for (var i = 0; i < good.length; i++) {
          final s1 = const PalmAnalyzer().analyzeAll([good[i]], rightHand: right, guideScales: [scales[i]]);
          _drawOverlay(s1, '/tmp/hastrekha_debug/real_${name}_single$i.jpg');
          // ignore: avoid_print
          print('  single $i: ${_summary(s1)}');
        }
      }
      // ignore: avoid_print
      print('  -> photos=${a.photosUsed} issues=${a.issues} palm=${a.palmRect.map((e) => e.toStringAsFixed(2))} '
          'lines=${a.paths.keys.toList()} '
          'features=${a.features.lines.entries.where((e) => e.value.present).map((e) => '${e.key}:${e.value.length}/${e.value.depth}/${e.value.confidence.toStringAsFixed(2)}').toList()}');
    }
  }, skip: dirs.isEmpty ? 'no captures in $_root' : false, timeout: const Timeout(Duration(minutes: 10)));
}

String _summary(PalmAnalysis a) => [
      for (final k in ['heart', 'head', 'life', 'fate'])
        if (a.features.lines[k]?.present ?? false)
          '$k:${a.features.lines[k]!.length}/${a.features.lines[k]!.confidence.toStringAsFixed(2)}'
        else
          '$k:-',
    ].join(' ');

void _drawOverlay(PalmAnalysis a, String path) {
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
  final s = a.handShape;
  if (s != null) {
    // Working-image pixels to photo pixels.
    final k = (a.palmRect[2] - a.palmRect[0]) * im.width / s.palmWidth;
    int px(double v) => (v * k).round();
    final cyan = img.ColorRgb8(0, 255, 255), orange = img.ColorRgb8(255, 140, 0);
    final seams = _seams;
    if (seams != null) {
      for (final xs in seams.$1) {
        for (var r = 1; r < xs.length; r += 1) {
          img.drawPixel(im, px(xs[r].toDouble()), px((seams.$2 + r).toDouble()), img.ColorRgb8(255, 255, 0));
        }
      }
    }
    for (final f in s.fingers.values) {
      img.drawLine(im, x1: px(f.baseX), y1: px(f.baseY), x2: px(f.tipX), y2: px(f.tipY), color: cyan, thickness: 2);
      img.fillCircle(im, x: px(f.tipX), y: px(f.tipY), radius: 5, color: cyan);
      for (final fr in [0.15, 0.5]) {
        final y = (f.baseY - fr * (f.baseY - f.tipY)).round();
        final r = f.rows[y];
        if (r != null) img.drawLine(im, x1: px(r.$1.toDouble()), y1: px(y.toDouble()), x2: px(r.$2.toDouble()), y2: px(y.toDouble()), color: cyan);
      }
      final j = f.joints;
      if (j != null) {
        for (final fr in [j.$1, j.$2]) {
          final y = (f.baseY - fr * (f.baseY - f.tipY)).round();
          final r = f.rows[y];
          if (r != null) img.drawLine(im, x1: px(r.$1.toDouble()), y1: px(y.toDouble()), x2: px(r.$2.toDouble()), y2: px(y.toDouble()), color: orange, thickness: 2);
        }
      }
    }
    final t = s.thumb;
    if (t != null) {
      img.drawLine(im, x1: px(t.webX), y1: px(t.webY), x2: px(t.tipX), y2: px(t.tipY), color: orange, thickness: 3);
      img.fillCircle(im, x: px(t.webX), y: px(t.webY), radius: 6, color: orange);
    }
  }
  final r = a.palmRect;
  img.drawRect(im,
      x1: (r[0] * im.width).round(), y1: (r[1] * im.height).round(),
      x2: (r[2] * im.width).round(), y2: (r[3] * im.height).round(), color: img.ColorRgb8(255, 255, 255));
  File(path).writeAsBytesSync(img.encodeJpg(img.copyResize(im, width: 600), quality: 80));
  File(path.replaceFirst('.jpg', '_full.jpg')).writeAsBytesSync(img.encodeJpg(im, quality: 85));
}
