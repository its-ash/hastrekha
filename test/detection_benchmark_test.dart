// Measures how many of the four main lines are found across hard synthetic
// palms (faint, noisy, unevenly lit, soft focus), with one photo and with
// several. Prints a table; the test asserts a floor so regressions show.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';

import 'vision_test.dart' show syntheticPalm;

const _main = ['heart', 'head', 'life', 'fate'];

class _Case {
  _Case(this.name, this.make);
  final String name;

  /// Photo number [i] of the burst (0 = the first, a mid-distance shot).
  final Uint8List Function(int i) make;
}

const _zoom = [1.0, 0.8, 1.15, 0.9, 1.08, 1.0];
const _dx = [0.0, 0.012, -0.01, 0.008, -0.006, 0.004];
const _dy = [0.0, -0.008, 0.01, 0.006, -0.01, 0.0];
const _scales = [1.0, 0.78, 1.18, 0.9, 1.08, 1.0];

Uint8List _palm(int i,
        {Map<String, double> contrast = const {},
        double noise = 0,
        double gradient = 0,
        double blur = 0,
        double tilt = 0,
        int motion = 0,
        bool glare = false}) =>
    syntheticPalm(
      contrast: contrast,
      noise: noise,
      seed: 20 + i * 7,
      zoom: _zoom[i],
      shiftX: _dx[i],
      shiftY: _dy[i],
      lightGradient: gradient,
      extraBlur: blur,
      tiltDeg: tilt,
      motionBlur: motion,
      glare: glare,
    );

final _cases = [
  _Case('clear', (i) => _palm(i, noise: 4)),
  _Case('faint head .3 n10', (i) => _palm(i, contrast: {'head': .3}, noise: 10)),
  _Case('faint fate .2 n9', (i) => _palm(i, contrast: {'fate': .2}, noise: 9)),
  _Case('all faint n9', (i) => _palm(i, contrast: {'heart': .45, 'head': .3, 'life': .5, 'fate': .22}, noise: 9)),
  _Case('uneven light', (i) => _palm(i, contrast: {'head': .4, 'fate': .3}, noise: 7, gradient: .35)),
  _Case('soft focus', (i) => _palm(i, contrast: {'head': .6, 'fate': .5}, noise: 5, blur: 2)),
  _Case('very noisy n14', (i) => _palm(i, contrast: {'head': .4, 'fate': .3}, noise: 14)),
  _Case('tilt 10', (i) => _palm(i, contrast: {'head': .4, 'fate': .3}, noise: 8, tilt: 10)),
  // Real-hand burst: frames differ by a few pixels and a few degrees, one
  // is smeared by hand shake, one has a highlight over the head line.
  _Case(
    'shake+glare+rot',
    (i) => _palm(i,
        contrast: {'head': .4, 'fate': .3},
        noise: 9,
        tilt: const [0.0, 3.0, -2.0][i % 3],
        motion: i % 3 == 1 ? 9 : 0,
        glare: i % 3 == 2),
  ),
  _Case(
    'one very bad frame',
    (i) => _palm(i, contrast: {'head': .4, 'fate': .3}, noise: 9, tilt: i == 1 ? 3 : 0, motion: i == 1 ? 17 : 0),
  ),
];

void main() {
  test('detection benchmark', () {
    final rows = <String>[];
    final found = {1: 0, 3: 0, 6: 0};
    var total = 0;
    for (final c in _cases) {
      total += _main.length;
      final cells = <String>[];
      for (final n in [1, 3, 6]) {
        final photos = [for (var i = 0; i < n; i++) c.make(i)];
        final a = const PalmAnalyzer().analyzeAll(photos, rightHand: true, guideScales: _scales.sublist(0, n));
        final got = _main.where((k) => a.features.lines[k]?.present ?? false).toList();
        found[n] = found[n]! + got.length;
        final miss = _main.where((k) => !got.contains(k)).join(',');
        cells.add('$n=${got.length}/4${got.length < 4 ? ' (miss $miss)' : ''} used=${a.photosUsed}');
      }
      rows.add('${c.name.padRight(20)} ${cells.join(' | ')}');
    }
    // ignore: avoid_print
    print('\n${rows.join('\n')}\nTOTAL of $total: 1 photo ${found[1]}, 3 photos ${found[3]}, 6 photos ${found[6]}');
    expect(found[3]!, greaterThanOrEqualTo(found[1]!));
    // The guided three-shot capture must find every main line in every case.
    expect(found[3]!, total);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
