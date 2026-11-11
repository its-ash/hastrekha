import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';
import 'package:image/image.dart' as img;

import 'vision_test.dart' show faintPalm, syntheticPalm;

/// Re-encodes [photo] after changing it, like a phone photo taken in
/// worse conditions.
Uint8List _edit(Uint8List photo, img.Image Function(img.Image) change) =>
    Uint8List.fromList(img.encodeJpg(change(img.decodeImage(photo)!), quality: 92));

/// A dim room: light scaled down, plus the sensor noise that comes with it.
Uint8List dim(Uint8List photo, {double factor = 0.3}) => _edit(photo, (im) {
      for (final p in im) {
        p
          ..r = p.r * factor
          ..g = p.g * factor
          ..b = p.b * factor;
      }
      return im;
    });

/// Direct sun / flash: everything pushed towards white.
Uint8List blownOut(Uint8List photo) => _edit(photo, (im) {
      for (final p in im) {
        p
          ..r = (p.r * 1.7 + 40).clamp(0, 255)
          ..g = (p.g * 1.7 + 40).clamp(0, 255)
          ..b = (p.b * 1.7 + 40).clamp(0, 255);
      }
      return im;
    });

/// Out of focus or shaken.
Uint8List outOfFocus(Uint8List photo, {int radius = 9}) => _edit(photo, (im) => img.gaussianBlur(im, radius: radius));

/// Something that is not a hand: a plain table top.
Uint8List noHand() {
  final im = img.Image(width: 720, height: 1280);
  img.fill(im, color: img.ColorRgb8(120, 90, 60));
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

PhotoQuality check(Uint8List photo) => const PalmAnalyzer().assess(photo, rightHand: true);

void main() {
  final good = faintPalm(noise: 7);
  final clean = syntheticPalm(noise: 4, seed: 2);

  test('a clear, well lit palm passes', () {
    for (final photo in [good, clean, syntheticPalm(noise: 9, seed: 3, zoom: 0.8)]) {
      final q = check(photo);
      expect(q.ok, isTrue, reason: '$q');
    }
  });

  test('a dark photo asks for more light', () {
    final q = check(dim(good));
    expect(q.main, QualityProblem.tooDark, reason: '$q');
  });

  test('a blown-out photo asks for softer light', () {
    final q = check(blownOut(good));
    expect(q.problems, contains(QualityProblem.tooBright), reason: '$q');
  });

  test('a blurry photo asks to hold steady', () {
    final q = check(outOfFocus(good));
    expect(q.problems, contains(QualityProblem.blurry), reason: '$q');
    expect(q.ok, isFalse);
  });

  test('a photo without a hand is refused', () {
    final q = check(noHand());
    expect(q.ok, isFalse, reason: '$q');
    expect(q.problems, contains(QualityProblem.noHand));
  });

  test('a file that is not an image is unreadable', () {
    final q = check(Uint8List.fromList([1, 2, 3, 4]));
    expect(q.main, QualityProblem.unreadable);
  });

  test('a slightly out-of-focus photo is caught too', () {
    final q = check(outOfFocus(good, radius: 4));
    expect(q.main, QualityProblem.blurry, reason: '$q');
  });

  test('line contrast does not depend on exposure', () {
    final bright = check(good), dimmer = check(dim(good, factor: 0.6));
    expect(dimmer.ok, isTrue, reason: '$dimmer');
    expect((bright.lineContrast - dimmer.lineContrast).abs(), lessThan(0.02));
  });

  test('every problem has a title and advice', () {
    for (final p in QualityProblem.values) {
      expect(p.title, isNotEmpty);
      expect(p.advice, isNotEmpty);
    }
  });
}
