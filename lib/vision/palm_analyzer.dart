import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../reading/palm_features.dart';
import 'crease_detector.dart';
import 'float_image.dart';
import 'hand_segmenter.dart';
import 'line_classifier.dart';
import 'multi_view.dart';
import 'palm_geometry.dart';
import 'photo_quality.dart';
import 'skeleton_graph.dart';

export 'photo_quality.dart' show PhotoQuality, QualityProblem;

/// Why a photo may give a weak reading. Shown as tips on the review screen.
enum PhotoIssue { handNotFound, blurry, dark, bright, fewLines }

/// Everything the vision pipeline returns. Plain data, so it can cross
/// isolates and be saved as JSON.
class PalmAnalysis {
  PalmAnalysis({
    required this.features,
    required this.photo,
    required this.photoWidth,
    required this.photoHeight,
    required this.paths,
    required this.minorPaths,
    required this.palmRect,
    required this.thumbOnLeft,
    required this.issues,
    required this.elementScores,
    this.photosUsed = 1,
  });

  final PalmFeatures features;

  /// How many photos were combined into this reading.
  final int photosUsed;

  /// Upright, cropped JPEG of the hand. All coordinates below are
  /// fractions (0..1) of this photo.
  final Uint8List photo;
  final int photoWidth;
  final int photoHeight;

  /// Line key → polylines, each flattened as [x0, y0, x1, y1, ...].
  final Map<String, List<List<double>>> paths;
  final List<List<double>> minorPaths;

  /// Palm rectangle: left, top, right, bottom.
  final List<double> palmRect;
  final bool thumbOnLeft;
  final List<PhotoIssue> issues;

  /// Raw element scores (air, fire, water), for the "hand type" chart.
  final Map<String, double> elementScores;

  Map<String, Object?> overlayJson() => {
        'w': photoWidth,
        'h': photoHeight,
        'paths': paths,
        'minor': minorPaths,
        'palm': palmRect,
        'thumbOnLeft': thumbOnLeft,
        'issues': [for (final i in issues) i.name],
        'elements': elementScores,
      };
}

/// Runs the whole pipeline on a background isolate. Several photos of the
/// same palm give a steadier reading of faint lines.
Future<PalmAnalysis> analyzePalmInBackground(
  List<Uint8List> photos, {
  required bool rightHand,
  List<double>? guideScales,
}) =>
    Isolate.run(() => const PalmAnalyzer().analyzeAll(photos, rightHand: rightHand, guideScales: guideScales));

/// Checks one photo (light, focus, hand, line contrast) on a background
/// isolate, before it counts towards a reading.
Future<PhotoQuality> checkPhotoInBackground(Uint8List photo, {required bool rightHand, double guideScale = 1}) =>
    Isolate.run(() => const PalmAnalyzer().assess(photo, rightHand: rightHand, guideScale: guideScale));

/// One photo, decoded, straightened, cropped and scaled to the working
/// palm width.
class _View {
  _View({
    required this.crop,
    required this.gray,
    required this.frame,
    required this.palmMask,
    required this.found,
    required this.geo,
    required this.pwPx,
    required this.phPx,
    required this.sharpness,
  });

  final img.Image crop;
  final FloatImage gray;
  final PalmFrame frame;
  final Uint8List palmMask;
  final bool found;
  final PalmGeometry geo;

  /// Palm size in pixels of the (rotated) photo.
  final double pwPx, phPx;
  final double sharpness;

  int get width => gray.width;
  int get height => gray.height;
}

/// Photo → hand → palm frame → creases → named lines → features.
class PalmAnalyzer {
  const PalmAnalyzer();

  /// Palm width (pixels) used for crease detection. Detector scales and
  /// thresholds are tuned for this size.
  static const workPalmWidth = 400.0;

  /// Largest photo side kept for analysis; more keeps faint lines sharp.
  static const maxPhotoSide = 2000;

  PalmAnalysis analyze(Uint8List bytes, {required bool rightHand}) => analyzeAll([bytes], rightHand: rightHand);

  /// Measures whether one photo is good enough to read (see [PhotoQuality]).
  /// Uses the same decoding, hand finding and palm scaling as the reading,
  /// so the numbers match what the line detector will see.
  PhotoQuality assess(Uint8List bytes, {required bool rightHand, double guideScale = 1}) {
    final _View view;
    try {
      view = _prepare(bytes, rightHand: rightHand, guideScale: guideScale);
    } on FormatException {
      return const PhotoQuality.unreadable();
    } on img.ImageException {
      return const PhotoQuality.unreadable();
    }
    final (brightness, clipped) = exposureOf(view.gray, view.palmMask);
    return PhotoQuality(
      handFound: view.found,
      brightness: brightness,
      clipped: clipped,
      sharpness: view.sharpness,
      lineContrast: lineContrastOf(view.gray, view.palmMask, brightness),
    );
  }

  /// Reads one palm from one or more photos. The sharpest photo with the
  /// hand found is the primary: its picture and coordinates are used.
  /// The others are aligned to it and their crease responses averaged in
  /// (see [fuseResponses]); a photo that does not line up is left out.
  /// Photos may be taken from different distances: each is scaled to the
  /// same palm width first. [guideScales] gives the size of the capture
  /// outline for each photo, used only when the hand is not found.
  PalmAnalysis analyzeAll(List<Uint8List> photos, {required bool rightHand, List<double>? guideScales}) {
    if (photos.isEmpty) throw const FormatException('No photo to read.');
    final views = <_View>[];
    for (var i = 0; i < photos.length; i++) {
      try {
        final scale = guideScales != null && i < guideScales.length ? guideScales[i] : 1.0;
        views.add(_prepare(photos[i], rightHand: rightHand, guideScale: scale));
      } on FormatException {
        if (i == 0 && photos.length == 1) rethrow;
      }
    }
    if (views.isEmpty) throw const FormatException('Could not read the photo.');
    var p = views.first;
    for (final v in views) {
      if ((v.found && !p.found) || (v.found == p.found && v.sharpness > p.sharpness * 1.05)) p = v;
    }

    const detector = CreaseDetector();
    var response = detector.respond(p.gray, p.palmMask, palmWidth: workPalmWidth);
    var used = 1;
    if (p.found) {
      final aligned = <AlignedView>[];
      for (final v in views) {
        if (identical(v, p) || !v.found) continue;
        final r = detector.respond(v.gray, v.palmMask, palmWidth: workPalmWidth);
        final reg = registerView(
          ref: response.response,
          refMask: p.palmMask,
          refFrame: p.frame,
          moving: r.response,
          movingFrame: v.frame,
        );
        if (reg != null) {
          final wt = AlignedView.weightOf(reg.score, v.sharpness, p.sharpness);
          // A badly aligned or very soft photo is left out, not averaged in.
          if (wt > 0.1) aligned.add(AlignedView(r, v.palmMask, reg.warp, v.gray, wt));
        }
      }
      if (aligned.isNotEmpty) {
        // Stack the flattened photos, then find creases on the stack.
        final stack = stackGray(p.gray, response.background, p.palmMask, aligned);
        response = detector.respond(stack, p.palmMask, palmWidth: workPalmWidth);
      }
      used += aligned.length;
    }
    return _read(p, detector.extract(response, p.palmMask, palmWidth: workPalmWidth),
        rightHand: rightHand, photosUsed: used);
  }

  _View _prepare(Uint8List bytes, {required bool rightHand, double guideScale = 1}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not read the photo.');
    }
    var image = img.bakeOrientation(decoded);
    final longSide = math.max(image.width, image.height);
    if (longSide > maxPhotoSide) {
      final s = maxPhotoSide / longSide;
      image = img.copyResize(image,
          width: (image.width * s).round(), height: (image.height * s).round(), interpolation: img.Interpolation.average);
    }

    // Find the hand, straighten it if it leans, and find it again.
    var hand = _segment(image);
    if (hand != null && hand.plausible && hand.fingerAngle.abs() > 0.06) {
      final deg = hand.fingerAngle * 180 / math.pi;
      image = img.copyRotate(image, angle: -deg, interpolation: img.Interpolation.linear);
      hand = _segment(image);
    }
    final found = hand != null && hand.plausible;
    final geo = found
        ? PalmGeometry.fromMask(hand, rightHand: rightHand)
        : PalmGeometry.guide(thumbOnLeft: !rightHand, scale: guideScale);

    // Crop around the hand: fingers above, a little wrist below.
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final pl = geo.left * iw, pr = geo.right * iw, pt = geo.top * ih, pb = geo.bottom * ih;
    final pwPx = pr - pl, phPx = pb - pt;
    final topY = geo.fingerTop != null ? geo.fingerTop! * ih - phPx * 0.06 : pt - phPx * 1.0;
    final cx0 = math.max(0.0, pl - pwPx * 0.45).floorToDouble();
    final cx1 = math.min(iw, pr + pwPx * 0.45).ceilToDouble();
    final cy0 = math.max(0.0, topY).floorToDouble();
    final cy1 = math.min(ih, pb + phPx * 0.22).ceilToDouble();
    final crop = img.copyCrop(image,
        x: cx0.toInt(), y: cy0.toInt(), width: (cx1 - cx0).toInt(), height: (cy1 - cy0).toInt());

    // Working copy scaled to a standard palm width.
    final scale = workPalmWidth / pwPx;
    final ww = math.max(32, (crop.width * scale).round());
    final wh = math.max(32, (crop.height * scale).round());
    final work = img.copyResize(crop, width: ww, height: wh, interpolation: img.Interpolation.average);
    final rgb = work.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
    final gray = FloatImage(ww, wh);
    for (var i = 0, p = 0; i < ww * wh; i++, p += 3) {
      gray.data[i] = 0.25 * rgb[p] + 0.6 * rgb[p + 1] + 0.15 * rgb[p + 2];
    }

    final frame = PalmFrame(
      x0: (pl - cx0) * scale,
      x1: (pr - cx0) * scale,
      y0: (pt - cy0) * scale,
      y1: (pb - cy0) * scale,
      thumbOnLeft: geo.thumbOnLeft,
    );

    // Where to look for creases: the palm (plus a margin for the
    // bracelets), and only on skin when the hand mask is known.
    final palmMask = Uint8List(ww * wh);
    Uint8List? skin;
    if (found) {
      skin = _resampleMask(hand, image.width, image.height, cx0, cy0, scale, ww, wh);
      skin = Masks.erode(skin, ww, wh, (workPalmWidth * 0.025).round());
    }
    for (var y = 0; y < wh; y++) {
      for (var x = 0; x < ww; x++) {
        final (u, v) = frame.toUV(x.toDouble(), y.toDouble());
        if (u < -0.06 || u > 1.04 || v < -0.05 || v > 1.1) continue;
        final i = y * ww + x;
        if (skin != null && skin[i] == 0) continue;
        palmMask[i] = 1;
      }
    }

    return _View(
      crop: crop,
      gray: gray,
      frame: frame,
      palmMask: palmMask,
      found: found,
      geo: geo,
      pwPx: pwPx,
      phPx: phPx,
      sharpness: _sharpness(gray, palmMask),
    );
  }

  PalmAnalysis _read(_View view, CreaseMap creases, {required bool rightHand, required int photosUsed}) {
    final ww = view.width, wh = view.height;
    final frame = view.frame, palmMask = view.palmMask, gray = view.gray, geo = view.geo;
    final found = view.found, crop = view.crop;
    final graph = SkeletonGraph(creases.skeleton, ww, wh);
    final curves = graph.link(maxGap: workPalmWidth * 0.07);
    final palm = const LineClassifier().classify(
      graph: graph,
      curves: curves,
      creases: creases,
      frame: frame,
      palmMask: palmMask,
    );

    // Features.
    final f = PalmFeatures(side: rightHand ? 'right' : 'left');
    for (final key in [...Vocab.primaryLines, ...Vocab.detectableSecondary]) {
      f.lines[key] = palm.lines[key]?.feature ?? LineFeature(present: false);
    }
    f.simian = palm.simian;
    f.headLifeJoined = palm.headLifeJoined;
    f.crossedMounds.addAll(palm.crossedMounds);
    f.mounds.addAll(palm.mounds);

    final ratio = view.phPx / view.pwPx;
    final fill = geo.fillRatio;
    f.palm = !found
        ? 'square'
        : ratio > 1.12
            ? 'rectangular'
            : (fill != null && fill < 0.86 ? 'rounded' : 'square');
    final fr = geo.fingerRatio;
    f.fingers = fr == null ? 'medium' : (fr < 0.74 ? 'short' : (fr > 0.9 ? 'long' : 'medium'));
    f.lineDensity = palm.lineDensity < 4.5 ? 'few' : (palm.lineDensity > 8.5 ? 'many' : 'moderate');

    final scores = elementScores(f);
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    f.element = ranked.first.key;
    f.secondary = ranked[1].value >= ranked.first.value * 0.75 ? ranked[1].key : 'none';

    // Photo quality.
    final issues = <PhotoIssue>[];
    if (!found) issues.add(PhotoIssue.handNotFound);
    final light = gray.mean(mask: palmMask);
    if (light < 60) issues.add(PhotoIssue.dark);
    if (light > 225) issues.add(PhotoIssue.bright);
    if (view.sharpness < 1.2) issues.add(PhotoIssue.blurry);
    final primaryFound = Vocab.primaryLines.where((k) => palm.lines.containsKey(k)).length;
    if (primaryFound < 2) issues.add(PhotoIssue.fewLines);

    // Overlay paths as fractions of the working (= photo) size.
    List<double> flat(List<Pt> pts) {
      final out = <double>[];
      final step = math.max(1, pts.length ~/ 120);
      for (var i = 0; i < pts.length; i += step) {
        out
          ..add(pts[i].x / ww)
          ..add(pts[i].y / wh);
      }
      if ((pts.length - 1) % step != 0) {
        out
          ..add(pts.last.x / ww)
          ..add(pts.last.y / wh);
      }
      return out;
    }

    // Store the photo at a reasonable size.
    var photoImg = crop;
    final photoLong = math.max(crop.width, crop.height);
    if (photoLong > 1200) {
      final s = 1200 / photoLong;
      photoImg = img.copyResize(crop,
          width: (crop.width * s).round(), height: (crop.height * s).round(), interpolation: img.Interpolation.average);
    }

    return PalmAnalysis(
      features: f,
      photo: Uint8List.fromList(img.encodeJpg(photoImg, quality: 88)),
      photoWidth: photoImg.width,
      photoHeight: photoImg.height,
      paths: {
        for (final e in palm.lines.entries) e.key: [for (final p in e.value.pieces) flat(p)],
      },
      minorPaths: [for (final p in palm.minor) flat(p)],
      palmRect: [frame.x0 / ww, frame.y0 / wh, frame.x1 / ww, frame.y1 / wh],
      thumbOnLeft: geo.thumbOnLeft,
      issues: issues,
      elementScores: scores,
      photosUsed: photosUsed,
    );
  }

  /// Ayurvedic hand element from shape and lines. Air (Vāta): long,
  /// rectangular, many fine broken lines. Fire (Pitta): medium build,
  /// clear lines of medium depth with forks. Water (Kapha): rounded or
  /// square, short fingers, few deep unbroken lines.
  static Map<String, double> elementScores(PalmFeatures f) {
    final primaries = Vocab.primaryLines.map((k) => f.lines[k]).whereType<LineFeature>().where((l) => l.present);
    final n = math.max(1, primaries.length);
    final faint = primaries.where((l) => l.depth == 'faint').length / n;
    final deep = primaries.where((l) => l.depth == 'deep').length / n;
    final medium = primaries.where((l) => l.depth == 'medium').length / n;
    final broken = primaries.where((l) => l.breaks != 'none').length / n;
    final forks = primaries.where((l) => l.fork).length;

    var air = 0.0, fire = 0.0, water = 0.0;
    switch (f.palm) {
      case 'rectangular':
        air += 1.2;
        fire += 0.4;
      case 'square':
        fire += 0.6;
        water += 0.8;
      case 'rounded':
        water += 1.3;
    }
    switch (f.fingers) {
      case 'long':
        air += 1.0;
      case 'medium':
        fire += 1.0;
      case 'short':
        water += 1.0;
        air += 0.3;
    }
    switch (f.lineDensity) {
      case 'many':
        air += 1.5;
      case 'moderate':
        fire += 1.0;
      case 'few':
        water += 1.5;
    }
    air += faint * 0.8 + broken * 0.6;
    fire += medium * 0.6 + math.min(2, forks) * 0.4;
    water += deep * 0.8 + (1 - broken) * 0.3;
    return {'air': air, 'fire': fire, 'water': water};
  }

  HandMask? _segment(img.Image image) {
    const lowW = 320;
    final lowH = math.max(8, (image.height * lowW / image.width).round());
    final small = img.copyResize(image, width: lowW, height: lowH, interpolation: img.Interpolation.average);
    final rgb = small.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
    return const HandSegmenter().segment(YCrCb.fromRgb(rgb, lowW, lowH));
  }

  /// Maps the low-resolution hand mask into working-image pixels.
  Uint8List _resampleMask(HandMask hand, int imgW, int imgH, double cx0, double cy0, double scale, int ww, int wh) {
    final out = Uint8List(ww * wh);
    final sx = hand.width / imgW, sy = hand.height / imgH;
    for (var y = 0; y < wh; y++) {
      final iy = ((y / scale + cy0) * sy).floor();
      if (iy < 0 || iy >= hand.height) continue;
      for (var x = 0; x < ww; x++) {
        final ix = ((x / scale + cx0) * sx).floor();
        if (ix < 0 || ix >= hand.width) continue;
        out[y * ww + x] = hand.mask[iy * hand.width + ix];
      }
    }
    return out;
  }

  /// Mean absolute Laplacian inside the palm, measured at a 300 px palm
  /// width so the scale stays the same: low on blurry photos.
  double _sharpness(FloatImage full, Uint8List fullMask) {
    const f = 300 / workPalmWidth;
    final w = (full.width * f).round(), h = (full.height * f).round();
    final g = full.resize(w, h);
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final fy = math.min(full.height - 1, (y / f).floor());
      for (var x = 0; x < w; x++) {
        mask[y * w + x] = fullMask[fy * full.width + math.min(full.width - 1, (x / f).floor())];
      }
    }
    var s = 0.0;
    var n = 0;
    for (var y = 1; y < g.height - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (mask[i] == 0) continue;
        final lap = 4 * g.data[i] - g.data[i - 1] - g.data[i + 1] - g.data[i - w] - g.data[i + w];
        s += lap.abs();
        n++;
      }
    }
    return n == 0 ? 0 : s / n;
  }
}
