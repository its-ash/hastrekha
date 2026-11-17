import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theme/theme.dart';

import '../../data/capture_log.dart';
import '../../vision/auto_capture.dart';
import '../../vision/palm_analyzer.dart';
import '../../vision/palm_geometry.dart';
import 'palm_frame.dart';

export 'palm_frame.dart' show PalmFramePainter;

/// Photos taken on the capture screen, and the hand they show.
class CaptureResult {
  const CaptureResult(this.photos, this.hand, this.guideScales);

  /// The same palm from a few distances; the analyzer combines them.
  final List<Uint8List> photos;
  final String hand;

  /// Size of the outline each photo was taken with (1 = normal).
  final List<double> guideScales;
}

/// One guided shot: how far to hold the phone, and how big the palm box is.
class CaptureStep {
  const CaptureStep(this.label, this.hint, this.scale, this.icon);
  final String label;
  final String hint;
  final double scale;
  final IconData icon;
}

/// The shots. Far shows the whole hand and its shape; close shows the
/// fine lines in detail; the middle one ties them together. The first
/// [minPhotos] are required; the extra ones are optional and bring out
/// faint lines further. The analyzer lines them all up and combines them.
const captureSteps = [
  CaptureStep('Far', 'A little farther away: the palm fits the small box, the whole hand in view.', 0.78,
      Icons.zoom_out_rounded),
  CaptureStep('Close', 'Closer: the palm fills the large box.', 1.18, Icons.zoom_in_rounded),
  CaptureStep('Middle', 'Normal distance: the palm fits the box.', 1.0, Icons.crop_free_rounded),
  CaptureStep('Extra', 'Optional: a little farther away. Each extra clear photo brings out faint lines.', 0.9,
      Icons.add_a_photo_rounded),
  CaptureStep('Extra', 'Optional: a little closer.', 1.08, Icons.add_a_photo_rounded),
  CaptureStep('Extra', 'Optional: a last one at a normal distance.', 1.0, Icons.add_a_photo_rounded),
];

/// Good photos needed before the palm is read. One photo often misses
/// faint lines; three aligned and combined give a steady reading.
const minPhotos = 3;

/// Most photos combined into one reading (gallery picks too).
const maxPhotos = 9;

/// Frames taken in one guided shot: ambient light, torch (or a second
/// ambient frame when the phone has no torch), ambient again. Creases
/// show differently under each, and the analyzer stacks them.
const burstSize = 3;

/// Full-screen camera with a hand outline to line the palm up with.
///
/// With [existing] (a finished capture of the same palm) it only adds
/// optional extra shots to it, to bring out lines that were not clear;
/// [focusLines] names them in the guidance.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.hand, this.existing, this.focusLines = const []});
  final String hand;
  final CaptureResult? existing;
  final List<String> focusLines;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  Object? _error;
  bool _busy = false;

  /// Frames that passed the quality check. Only these count.
  final _photos = <Uint8List>[];
  final _scales = <double>[];

  /// Frames kept from each finished shot (for Retake).
  final _perStep = <int>[];
  bool _torch = false;
  bool _hasTorch = true;

  /// Guided shots finished. In retake mode the three required ones were
  /// taken before, so it starts at the extras.
  int _stepsDone = 0;
  int get _step => _stepsDone;
  late String _hand = widget.hand;

  final _gate = AutoCaptureGate();
  AutoState _auto = AutoState.noHand;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  /// After a shot the next one waits until the hand has moved to the new
  /// distance, so the same pose is not captured twice.
  bool _armed = true;
  bool _sawChange = false;

  /// Debug and profile builds: every frame is kept for replay in tests.
  CaptureLog? _log;
  bool _loggedStream = false;
  int _gateFrames = 0;

  /// When focus and exposure were last pointed at the palm.
  DateTime _lastAim = DateTime.fromMillisecondsSinceEpoch(0);

  /// Most frames this capture may hold. A retake keeps every earlier
  /// frame and has room for one more shot.
  int get _cap => widget.existing == null ? maxPhotos : maxPhotos + burstSize;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _hand = e.hand;
      // Keep room for one more burst.
      final keep = math.min(e.photos.length, _cap - burstSize);
      _photos.addAll(e.photos.take(keep));
      _scales.addAll(e.guideScales.take(keep));
      _stepsDone = minPhotos;
    }
    WidgetsBinding.instance.addObserver(this);
    // The outline and the auto capture are laid out for an upright phone.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  /// Points focus and exposure at the palm, not the whole frame: a dark
  /// or bright background must not set the exposure of the skin. The
  /// camera drops the point after a few seconds, so this is called again
  /// each time a palm arrives in the outline.
  Future<void> _aimAtPalm(CameraController c) async {
    _lastAim = DateTime.now();
    const palm = Offset(PalmGeometry.guideCenterU, PalmGeometry.guideCenterV);
    try {
      await c.setExposurePoint(palm);
      await c.setFocusPoint(palm);
    } catch (_) {
      // Not supported on this camera: it keeps metering the whole frame.
    }
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('NoCamera', 'This phone has no camera.');
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      try {
        await c.setFocusMode(FocusMode.auto);
        await c.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      _aimAtPalm(c);
      _startStream(c);
      if (CaptureLog.enabled && _log == null) {
        final size = MediaQuery.sizeOf(context);
        _log = await CaptureLog.start({
          'hand': _hand,
          'camera': cam.name,
          'sensorOrientation': cam.sensorOrientation,
          'previewSize': [c.value.previewSize?.width, c.value.previewSize?.height],
          'screen': [size.width, size.height],
          'steps': [for (final s in captureSteps) s.scale],
          'retake': widget.existing != null,
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && c == null) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _controller?.dispose();
    super.dispose();
  }

  /// Reads the camera's image stream to take each shot by itself when the
  /// palm fits the outline of the current shot, is steady and in focus.
  /// The shutter button stays as the manual fallback.
  void _startStream(CameraController c) {
    if (c.value.isStreamingImages) return;
    // Stream frames come as the sensor sees them; the gate turns them upright.
    final rotation = c.description.sensorOrientation ~/ 90;
    try {
      c.startImageStream((image) {
        final now = DateTime.now();
        if (_busy || !mounted || now.difference(_lastFrame).inMilliseconds < 120) return;
        _lastFrame = now;
        final planes = image.planes;
        if (planes.length < 3) return;
        if (!_loggedStream && _log != null) {
          _loggedStream = true;
          _log!.note('stream ${image.width}x${image.height} rowStride ${planes[0].bytesPerRow} '
              'uvPixelStride ${planes[1].bytesPerPixel}');
        }
        final state = _gate.add(
          PreviewFrame(
            width: image.width,
            height: image.height,
            y: planes[0].bytes,
            yRowStride: planes[0].bytesPerRow,
            u: planes[1].bytes,
            v: planes[2].bytes,
            uvRowStride: planes[1].bytesPerRow,
            uvPixelStride: planes[1].bytesPerPixel ?? 1,
            rotation: rotation,
          ),
          scale: captureSteps[math.min(_step, captureSteps.length - 1)].scale,
        );
        if (_log != null && ++_gateFrames % 8 == 0) {
          final g = _gate;
          _log!.note('gate ${state.name} fill ${g.fill.toStringAsFixed(2)} size ${g.size.toStringAsFixed(2)} '
              'offset ${g.offset.toStringAsFixed(2)} bright ${g.brightness.toStringAsFixed(0)} '
              'glare ${g.glare.toStringAsFixed(3)} motion ${g.motion.toStringAsFixed(3)} '
              'sharp ${g.sharpness.toStringAsFixed(4)} skinBg ${g.skinLikeBackground}');
        }
        final still = state.aligned && state != AutoState.moving;
        if (!_armed) {
          // Wait for the hand to move (new distance) before arming again.
          if (!still) _sawChange = true;
          if (_sawChange && still) {
            _armed = true;
            _sawChange = false;
          }
        }
        // A palm has just arrived in the outline: focus and meter on it.
        if (state.aligned && !_auto.aligned && now.difference(_lastAim).inSeconds >= 3) _aimAtPalm(c);
        if (state != _auto || state == AutoState.ready) {
          setState(() => _auto = state);
        }
        if (state == AutoState.ready && _armed && _stepsDone < captureSteps.length && _photos.length < _cap) {
          _shoot(auto: true);
        }
      });
    } catch (_) {
      // No image stream on this phone: the shutter button still works.
    }
  }

  /// One frame at the current flash setting.
  Future<Uint8List?> _grab(CameraController c) async {
    try {
      final file = await c.takePicture();
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Takes a short burst for this step (ambient, torch, ambient), keeps
  /// the frames that pass the quality check, and moves on when at least
  /// one is good.
  Future<void> _shoot({bool auto = false}) async {
    final c = _controller;
    if (c == null || _busy || _step >= captureSteps.length || _photos.length >= _cap) return;
    setState(() => _busy = true);
    final scale = captureSteps[_step].scale;
    final startTorch = _torch;
    final frames = <Uint8List>[];
    final n = math.min(burstSize, _cap - _photos.length);
    for (var i = 0; i < n; i++) {
      // Middle frame under the opposite light, when the phone has a torch.
      final flip = i == 1 && _hasTorch;
      if (flip) {
        try {
          await c.setFlashMode(startTorch ? FlashMode.off : FlashMode.torch);
          await Future<void>.delayed(const Duration(milliseconds: 350));
        } catch (_) {
          _hasTorch = false;
        }
      }
      final b = await _grab(c);
      if (flip && _hasTorch) {
        try {
          await c.setFlashMode(startTorch ? FlashMode.torch : FlashMode.off);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } catch (_) {}
      }
      if (b != null) frames.add(b);
    }
    if (frames.isEmpty) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showToast('Could not take the photo. Try again.', status: UiStatus.danger);
      return;
    }
    // Check light, focus and the hand before each frame counts.
    final checks = await Future.wait([
      for (final b in frames) checkPhotoInBackground(b, rightHand: _hand == 'right', guideScale: scale),
    ]);
    final log = _log;
    if (log != null) {
      for (var i = 0; i < frames.length; i++) {
        log.frame('s${_step}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg', frames[i],
            'scale $scale hand $_hand auto $auto state ${_auto.name} gate ${_gate.size.toStringAsFixed(2)}/${_gate.offset.toStringAsFixed(2)} ${checks[i]}');
      }
    }
    if (!mounted) return;
    var kept = 0;
    for (var i = 0; i < frames.length; i++) {
      if (checks[i].main == null) {
        _photos.add(frames[i]);
        _scales.add(scale);
        kept++;
      }
    }
    _gate.reset();
    _armed = false;
    _sawChange = false;
    if (kept == 0) {
      setState(() => _busy = false);
      await _explain(checks.first.main!);
      _armed = true;
      return;
    }
    _perStep.add(kept);
    setState(() {
      _stepsDone++;
      _busy = false;
    });
    if (_stepsDone >= captureSteps.length || _photos.length >= _cap) {
      _finish();
    } else {
      context.showToast(
        _stepsDone < minPhotos
            ? 'Good${auto ? ', taken automatically' : ''}. ${minPhotos - _stepsDone} more to go.'
            : 'Good photo.',
        status: UiStatus.success,
        duration: const Duration(milliseconds: 1400),
      );
    }
  }

  /// Tells the user why the photo was not kept and how to take a better one.
  Future<void> _explain(QualityProblem problem) {
    final torchTip = problem == QualityProblem.tooDark && !_torch
        ? ' You can also turn on the flashlight at the top right.'
        : '';
    return UiDialog.alert(
      context,
      title: problem.title,
      message: '${problem.advice}$torchTip\n\nThis photo was not used. Please take it again.',
      okLabel: 'Retake',
      status: UiStatus.warning,
      icon: switch (problem) {
        QualityProblem.tooDark => Icons.wb_sunny_outlined,
        QualityProblem.tooBright => Icons.wb_shade_rounded,
        QualityProblem.blurry => Icons.blur_on_rounded,
        QualityProblem.noHand => Icons.back_hand_outlined,
        QualityProblem.tooSmall => Icons.zoom_in_rounded,
        QualityProblem.lowContrast => Icons.contrast_rounded,
        QualityProblem.unreadable => Icons.broken_image_outlined,
      },
    );
  }

  /// Reads the palm from the good photos taken so far.
  void _finish() {
    if (!_canRead) return;
    Navigator.of(context).pop(CaptureResult(List.of(_photos), _hand, List.of(_scales)));
  }

  /// A reading needs the three required shots; in retake mode, one new one.
  bool get _canRead => widget.existing == null ? _stepsDone >= minPhotos : _perStep.isNotEmpty;

  /// Drops the frames of the last guided shot so it can be taken again.
  void _retakeLast() {
    if (_perStep.isEmpty) return;
    final n = _perStep.removeLast();
    setState(() {
      _photos.removeRange(_photos.length - n, _photos.length);
      _scales.removeRange(_scales.length - n, _scales.length);
      _stepsDone--;
      _armed = true;
    });
  }

  /// Live guidance on the camera view, from the auto-capture gate: what
  /// to do next, in a word or two, and why.
  _Guide? _guide() {
    if (_controller == null || _stepsDone >= captureSteps.length) return null;
    if (_busy) return const _Guide(Icons.photo_camera_rounded, 'Hold still', 'Taking the photo', good: true);
    return switch (_auto) {
      AutoState.noHand => const _Guide(Icons.back_hand_outlined, 'Put your palm in the box', 'Fingers up, palm facing the camera'),
      // The view shows the picture upright, so the gate's offset is a
      // direction on screen.
      AutoState.offCentre => _gate.offset > 0
          ? const _Guide(Icons.arrow_back_rounded, 'Move your hand left', 'Centre the palm in the box')
          : const _Guide(Icons.arrow_forward_rounded, 'Move your hand right', 'Centre the palm in the box'),
      AutoState.tooFar => const _Guide(Icons.zoom_in_rounded, 'Move closer', 'The palm should fill the box'),
      AutoState.tooClose => const _Guide(Icons.zoom_out_rounded, 'Move back', 'The palm should fit inside the box'),
      AutoState.tooDark => const _Guide(Icons.wb_sunny_outlined, 'Too dark', 'Find more light or turn on the flashlight'),
      AutoState.tooBright => const _Guide(Icons.wb_shade_rounded, 'Too bright', 'Move out of direct light'),
      AutoState.glare => const _Guide(Icons.flare_rounded, 'Shiny patch on the palm', 'Tilt your hand a little'),
      AutoState.moving => const _Guide(Icons.pan_tool_rounded, 'Hold steady', 'Keep the phone and hand still', good: true),
      AutoState.soft => const _Guide(Icons.center_focus_weak_rounded, 'Focusing', 'Keep still, the photo is taken by itself', good: true),
      AutoState.ready => const _Guide(Icons.check_circle_rounded, 'Good, hold still', 'Taking the photo', good: true),
    };
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {
      _hasTorch = false;
      if (mounted) context.showToast('No flashlight on this camera.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final colors = context.colors;
    final step = captureSteps[math.min(_step, captureSteps.length - 1)];
    final guide = _guide();
    final good = _busy || _auto.aligned;
    final onCamera = colors.onSurfaceInverse;

    // Shade behind text on the camera picture, fading out towards the middle.
    BoxDecoration scrim(Alignment from) => BoxDecoration(
          gradient: LinearGradient(
            begin: from,
            end: -from,
            colors: [colors.surfaceInverse.withValues(alpha: 0.72), colors.surfaceInverse.withValues(alpha: 0)],
          ),
        );

    final title = _step < minPhotos
        ? '${_hand == 'right' ? 'Right' : 'Left'} palm · photo ${_step + 1} of $minPhotos · ${step.label}'
        : widget.existing != null
            ? 'Extra photo for unclear lines'
            : 'Extra photo ${_step + 1} of ${captureSteps.length} (optional)';
    final hint = widget.focusLines.isNotEmpty && widget.existing != null
        ? 'To read the ${widget.focusLines.join(', ')} line, use soft light from one side. ${step.hint}'
        : '${step.hint} Soft light from one side, plain background.';
    final status = _canRead
        ? '${_photos.length} clear frames. Tap Read, or add more for faint lines.'
        : '$_stepsDone of $minPhotos photos done';

    final camera = _error != null
        ? Center(child: _CameraError(error: _error!, onRetry: _init))
        : c == null || !c.value.isInitialized
            ? const Center(child: UiSpinner(size: 28))
            : Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  // Preview size is reported in landscape.
                  aspectRatio: 1 / c.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(c),
                      // The palm box: green when the palm sits right in it.
                      IgnorePointer(
                        child: CustomPaint(
                          painter: PalmFramePainter(
                            color: good ? colors.success : onCamera,
                            good: good,
                            scale: step.scale,
                          ),
                        ),
                      ),
                      // What to do now, big, below the top bar.
                      Positioned(
                        left: UiSpace.lg,
                        right: UiSpace.lg,
                        top: 96,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: guide == null
                                ? const SizedBox.shrink()
                                : _GuidePill(key: ValueKey(guide.title), guide: guide),
                          ),
                        ),
                      ),
                      // How to take this shot, and progress.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: scrim(Alignment.bottomCenter),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(UiSpace.xl, UiSpace.xxl, UiSpace.xl, UiSpace.md),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    hint,
                                    textAlign: TextAlign.center,
                                    style: context.text.bodyMedium?.copyWith(color: onCamera),
                                  ),
                                  const UiGap(UiSpace.xs),
                                  Text(
                                    status,
                                    textAlign: TextAlign.center,
                                    style: context.text.labelMedium?.copyWith(
                                      color: onCamera.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );

    return Scaffold(
      backgroundColor: colors.surfaceInverse,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: camera),
                  // Top bar over the camera: close, title and steps, flashlight.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: DecoratedBox(
                      decoration: scrim(Alignment.topCenter),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(UiSpace.xs, UiSpace.xs, UiSpace.xs, UiSpace.lg),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(Icons.close_rounded, color: onCamera),
                              tooltip: 'Close',
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: UiSpace.sm),
                                child: Column(
                                  children: [
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: context.text.titleSmall?.copyWith(color: onCamera),
                                    ),
                                    const UiGap(UiSpace.xs),
                                    _StepTrack(done: _step),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: c == null ? null : _toggleTorch,
                              icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: onCamera),
                              tooltip: 'Flashlight',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Only the controls below the camera.
            Padding(
              padding: const EdgeInsets.fromLTRB(UiSpace.xl, UiSpace.md, UiSpace.xl, UiSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: widget.existing == null && _photos.isEmpty
                        ? UiSegmentedControl<String>(
                            const [UiSegment('left', label: 'Left'), UiSegment('right', label: 'Right')],
                            value: _hand,
                            size: UiSize.sm,
                            onChanged: (v) => setState(() => _hand = v),
                          )
                        : _perStep.isEmpty
                            ? const SizedBox()
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _busy ? null : _retakeLast,
                                  icon: Icon(Icons.undo_rounded, color: onCamera),
                                  label: Text('Retake', style: TextStyle(color: onCamera)),
                                ),
                              ),
                  ),
                  const UiGap(UiSpace.xl),
                  _ShutterButton(busy: _busy, onPressed: c == null ? null : _shoot),
                  const UiGap(UiSpace.xl),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: !_canRead
                          ? const SizedBox()
                          : TextButton(
                              onPressed: _busy ? null : _finish,
                              child: Text(
                                'Read (${_photos.length})',
                                style: TextStyle(color: onCamera, fontWeight: FontWeight.w600),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One piece of live guidance: an icon, what to do, and why. [good]
/// means the palm is in place and the shot is about to be taken.
class _Guide {
  const _Guide(this.icon, this.title, this.detail, {this.good = false});
  final IconData icon;
  final String title;
  final String detail;
  final bool good;
}

/// The guidance shown large on the camera view: green when the palm is
/// in place, amber when something needs to change.
class _GuidePill extends StatelessWidget {
  const _GuidePill({super.key, required this.guide});
  final _Guide guide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = guide.good ? colors.success : colors.warning;
    final fg = colors.onSurfaceInverse;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: UiSpace.sm),
      decoration: BoxDecoration(
        color: colors.surfaceInverse.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(UiRadius.lg),
        border: Border.all(color: tone, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(guide.icon, color: tone, size: 32),
          const UiGap(UiSpace.md),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guide.title, style: context.text.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                Text(guide.detail, style: context.text.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The required shots (Far · Close · Middle) as labelled chips, then the
/// optional extras as small circles; shots already taken are ticked.
class _StepTrack extends StatelessWidget {
  const _StepTrack({required this.done});
  final int done;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget chip(int i) {
      final current = i == done;
      final required = i < minPhotos;
      final fg = current ? colors.onAccent : colors.onSurfaceInverse;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: required ? UiSpace.sm : 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(UiRadius.full),
          color: current ? colors.accent : Colors.transparent,
          border: Border.all(
            color: colors.onSurfaceInverse.withValues(alpha: i <= done ? 0.9 : (required ? 0.35 : 0.2)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i < done ? Icons.check_rounded : captureSteps[i].icon, size: 14, color: fg),
            if (required) ...[
              const SizedBox(width: 4),
              Text(captureSteps[i].label, style: context.text.labelSmall?.copyWith(color: fg)),
            ],
          ],
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: UiSpace.xs,
      runSpacing: UiSpace.xs,
      children: [
        for (var i = 0; i < captureSteps.length; i++) ...[
          if (i == minPhotos)
            Text('+', style: context.text.labelMedium?.copyWith(color: colors.onSurfaceInverse.withValues(alpha: 0.6))),
          chip(i),
        ],
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Take photo',
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.onSurfaceInverse, width: 4),
          ),
          padding: const EdgeInsets.all(5),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: busy ? colors.textDisabled : colors.accent),
            child: busy ? Center(child: UiSpinner(size: 22, color: colors.onAccent)) : null,
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error is CameraException && (error as CameraException).code.contains('Access');
    return Padding(
      padding: const EdgeInsets.all(UiSpace.xl),
      child: UiSurface(
        child: UiErrorState(
          compact: true,
          title: denied ? 'Camera access is off' : 'Camera not available',
          message: denied
              ? 'Allow camera access for Hastrekha in your phone settings, or pick a photo from the gallery.'
              : 'You can still pick a palm photo from the gallery.',
          onRetry: onRetry,
        ),
      ),
    );
  }
}
