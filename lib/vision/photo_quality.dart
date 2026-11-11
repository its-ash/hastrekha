import 'dart:math' as math;
import 'dart:typed_data';

import 'float_image.dart';

/// Why a captured photo is not good enough to read, most important first.
enum QualityProblem {
  unreadable('This photo could not be opened', 'Take the photo again.'),
  tooDark('The photo is too dark', 'Move to a brighter place, near a window or under a lamp, and try again.'),
  tooBright('The palm is washed out', 'Move out of direct sun or away from the lamp, so the light is soft.'),
  noHand('No open palm was found', 'Fill the outline with your open palm, fingers slightly apart, and try again.'),
  blurry('The photo is blurry', 'Hold the phone steady and wait a moment for the camera to focus.'),
  lowContrast('The palm lines are too faint in this light', 'Use light from one side, not from straight above, so the lines show.');

  const QualityProblem(this.title, this.advice);

  final String title;
  final String advice;
}

/// Measured quality of one photo, in the working image (palm scaled to
/// [PalmAnalyzer.workPalmWidth] = 400 px), so the numbers do not depend on
/// the camera resolution or the distance.
class PhotoQuality {
  const PhotoQuality({
    required this.handFound,
    required this.brightness,
    required this.clipped,
    required this.sharpness,
    required this.lineContrast,
  }) : unreadable = false;

  const PhotoQuality.unreadable()
      : unreadable = true,
        handFound = false,
        brightness = 0,
        clipped = 0,
        sharpness = 0,
        lineContrast = 0;

  // Thresholds, measured with test/photo_quality_test.dart on the synthetic
  // palms of test/vision_test.dart and edited copies of them:
  //
  //   photo                 brightness  sharpness  line contrast
  //   good (faint, noisy)        175       7.0        0.070
  //   clean                      175       3.8        0.126
  //   far shot (zoom 0.8)        174       8.9        0.112
  //   light × 0.45                78       2.8        0.069
  //   light × 0.3                 52       1.7        0.068
  //   blown out                  254       0.4        0.004
  //   blur radius 4              174       1.1        0.040
  //   blur radius 9              173       0.5        0.017
  //   table top, no hand          93       0.0        0.000
  //
  // Good photos sit far from every limit; each bad one crosses at least one.
  // Real skin has more texture than the synthetic palms (higher sharpness)
  // and softer creases (lower line contrast), so the line-contrast limit is
  // set well under the faintest good photo.

  /// Mean palm gray level (0..255) below which the photo is too dark. Well
  /// lit palms measure 140–200 (darker skin tones ~110); under 80 the
  /// camera's noise swamps the faint lines.
  static const minBrightness = 80.0;

  /// Mean palm gray level above which the skin is washed out.
  static const maxBrightness = 225.0;

  /// Share of palm pixels at 245+ (blown highlights, glare). Lines vanish
  /// where the sensor clips.
  static const maxClipped = 0.25;

  /// Mean absolute Laplacian at a 300 px palm width (`_sharpness` in
  /// palm_analyzer.dart; the same 1.2 marks a reading's photo as blurry).
  /// Even slightly out-of-focus photos fall under it.
  static const minSharpness = 1.2;

  /// How much darker the strongest creases are than the skin around them,
  /// as a fraction of the skin brightness (so it does not depend on
  /// exposure). Flat, frontal light or glare gives low values.
  static const minLineContrast = 0.03;

  final bool unreadable;
  final bool handFound;
  final double brightness;
  final double clipped;
  final double sharpness;
  final double lineContrast;

  /// Problems in priority order: light first (it also hides the hand), then
  /// the hand, then focus, then line contrast.
  List<QualityProblem> get problems {
    if (unreadable) return const [QualityProblem.unreadable];
    return [
      if (brightness < minBrightness) QualityProblem.tooDark,
      if (brightness > maxBrightness || clipped > maxClipped) QualityProblem.tooBright,
      if (!handFound) QualityProblem.noHand,
      if (sharpness < minSharpness) QualityProblem.blurry,
      if (lineContrast < minLineContrast) QualityProblem.lowContrast,
    ];
  }

  bool get ok => problems.isEmpty;

  /// The single problem to tell the user about, or null when the photo is good.
  QualityProblem? get main => ok ? null : problems.first;

  @override
  String toString() => 'PhotoQuality(hand: $handFound, brightness: ${brightness.toStringAsFixed(1)}, '
      'clipped: ${clipped.toStringAsFixed(3)}, sharpness: ${sharpness.toStringAsFixed(2)}, '
      'lineContrast: ${lineContrast.toStringAsFixed(3)}, problems: ${problems.map((p) => p.name).toList()})';
}

/// Mean gray level and the share of clipped (>= 245) pixels inside [mask].
(double, double) exposureOf(FloatImage gray, Uint8List mask) {
  var s = 0.0;
  var clipped = 0;
  var n = 0;
  for (var i = 0; i < gray.data.length; i++) {
    if (mask[i] == 0) continue;
    final v = gray.data[i];
    s += v;
    if (v >= 245) clipped++;
    n++;
  }
  if (n == 0) return (0, 0);
  return (s / n, clipped / n);
}

/// How much darker the strongest creases are than the skin around them:
/// the 98th percentile of (local mean − pixel) inside [mask], divided by
/// the mean brightness [brightness]. Creases are narrow dark valleys, so a
/// 4 px blur gives the skin level around them.
double lineContrastOf(FloatImage gray, Uint8List mask, double brightness) {
  if (brightness <= 0) return 0;
  final around = gray.blur(4);
  final valley = FloatImage(gray.width, gray.height);
  for (var i = 0; i < gray.data.length; i++) {
    valley.data[i] = math.max(0, around.data[i] - gray.data[i]);
  }
  return valley.percentile(0.98, mask: mask) / brightness;
}
