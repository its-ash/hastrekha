import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/overlay.dart';
import '../../vision/palm_analyzer.dart';
import '../profile/birth_editor.dart';
import '../review/review_screen.dart';
import 'capture_screen.dart';

/// Camera or gallery → analysis → review screen.
///
/// The camera guides three required shots (far, close, middle) and up to
/// three optional extras, checking each one; from the gallery the user
/// picks [minPhotos] to [maxPhotos] photos of the same palm, checked on the
/// analyzing screen. Only clear photos count. They are aligned and
/// combined, which brings out faint lines.
Future<void> startReading(BuildContext context, {required String hand, required bool fromCamera}) async {
  // The reading combines the palm with the birth chart, so ask for the
  // name and birth details first when they are missing (skippable).
  if (!context.appRead.profile.isComplete) {
    await showBirthEditor(context, prompt: true);
    if (!context.mounted) return;
  }
  List<Uint8List> photos;
  List<double>? scales;
  var chosenHand = hand;
  if (fromCamera) {
    final shot = await Navigator.of(context).push<CaptureResult>(
      MaterialPageRoute(builder: (_) => CaptureScreen(hand: hand), fullscreenDialog: true),
    );
    if (shot == null) return;
    photos = shot.photos;
    scales = shot.guideScales;
    chosenHand = shot.hand;
  } else {
    final files = await ImagePicker().pickMultiImage(maxWidth: 2400, maxHeight: 2400, limit: maxPhotos);
    if (files.isEmpty) return;
    if (files.length < minPhotos) {
      if (!context.mounted) return;
      await UiDialog.alert(
        context,
        title: 'Pick at least $minPhotos photos',
        message: 'A reading combines $minPhotos to $maxPhotos clear photos of the same palm, taken in good light. '
            'One or two photos often miss the faint lines.',
        icon: Icons.photo_library_outlined,
      );
      return;
    }
    photos = [for (final f in files.take(maxPhotos)) await f.readAsBytes()];
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AnalyzingScreen(
        photos: photos,
        hand: chosenHand,
        guideScales: scales,
        // Camera shots were checked one by one as they were taken.
        checkQuality: !fromCamera,
      ),
    ),
  );
}

/// Gallery photos that did not pass the quality check.
class NotEnoughGoodPhotos implements Exception {
  const NotEnoughGoodPhotos(this.good, this.problems);
  final int good;

  /// Photo number (1-based) → why it was left out.
  final Map<int, QualityProblem> problems;

  String get message {
    final lines = [
      for (final e in problems.entries) 'Photo ${e.key}: ${e.value.title}. ${e.value.advice}',
    ];
    return '${good == 0 ? 'None' : 'Only $good'} of the photos ${good == 1 ? 'is' : 'are'} clear enough, and a '
        'reading needs at least $minPhotos of the same palm.\n\n${lines.join('\n')}';
  }
}

/// Runs the vision pipeline with a short explanation of each step, then
/// replaces itself with the review screen.
class AnalyzingScreen extends StatefulWidget {
  const AnalyzingScreen({
    super.key,
    required this.photos,
    required this.hand,
    this.guideScales,
    this.checkQuality = false,
  });
  final List<Uint8List> photos;
  final String hand;

  /// Check each photo first and read only the clear ones (gallery picks).
  final bool checkQuality;

  /// Capture outline size per photo (camera only).
  final List<double>? guideScales;

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen> {
  late final _steps = [
    if (widget.checkQuality) 'Checking light and focus',
    'Finding your hand',
    'Measuring the palm and fingers',
    if (widget.photos.length > 1) 'Lining up ${widget.photos.length} photos',
    'Tracing the lines',
    'Looking for faint lines',
    'Naming each line',
  ];
  int _step = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    // The analysis runs in one go on a background isolate; advance the
    // step labels on a timer so the wait reads as progress.
    var done = false;
    () async {
      for (var i = 1; i < _steps.length && !done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted && !done) setState(() => _step = i);
      }
    }();
    try {
      var photos = widget.photos;
      var scales = widget.guideScales;
      if (widget.checkQuality) {
        final good = <Uint8List>[];
        final goodScales = <double>[];
        final problems = <int, QualityProblem>{};
        for (var i = 0; i < photos.length; i++) {
          final scale = scales != null && i < scales.length ? scales[i] : 1.0;
          final q = await checkPhotoInBackground(photos[i], rightHand: widget.hand == 'right', guideScale: scale);
          if (q.ok) {
            good.add(photos[i]);
            goodScales.add(scale);
          } else {
            problems[i + 1] = q.main!;
          }
        }
        if (good.length < minPhotos) throw NotEnoughGoodPhotos(good.length, problems);
        photos = good;
        scales = goodScales;
      }
      final a = await analyzePalmInBackground(
        photos,
        rightHand: widget.hand == 'right',
        guideScales: scales,
      );
      done = true;
      if (!mounted) return;
      final overlay = PalmOverlay.fromJson(a.overlayJson());
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ReviewScreen(
          features: a.features,
          overlay: overlay,
          photo: a.photo,
          source: CaptureResult(photos, widget.hand, scales ?? [for (final _ in photos) 1.0]),
        ),
      ));
    } catch (e) {
      done = true;
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UiAppBar(title: 'Reading your palm'),
      body: _error != null
          ? switch (_error) {
              NotEnoughGoodPhotos e => SingleChildScrollView(
                  child: UiErrorState(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Not enough clear photos',
                    message: e.message,
                    onRetry: () => Navigator.of(context).pop(),
                    retryLabel: 'Pick other photos',
                  ),
                ),
              _ => UiErrorState(
                  title: 'Could not read this photo',
                  message: _error is FormatException ? (_error as FormatException).message : '$_error',
                  onRetry: () => Navigator.of(context).pop(),
                  retryLabel: 'Try another photo',
                ),
            }
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(UiSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(UiRadius.lg),
                      child: Image.memory(widget.photos.first, height: 220, fit: BoxFit.cover),
                    ),
                    const UiGap(UiSpace.xxl),
                    UiSteps(
                      steps: _steps,
                      current: _step,
                      direction: Axis.vertical,
                    ),
                    const UiGap(UiSpace.lg),
                    const UiProgressBar(null),
                  ],
                ),
              ),
            ),
    );
  }
}
