import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../vision/auto_capture.dart';
import '../../vision/palm_analyzer.dart';

/// Photos taken on the capture screen, and the hand they show.
class CaptureResult {
  const CaptureResult(this.photos, this.hand, this.guideScales);

  /// The same palm from a few distances; the analyzer combines them.
  final List<Uint8List> photos;
  final String hand;

  /// Size of the outline each photo was taken with (1 = normal).
  final List<double> guideScales;
}

/// One guided shot: how far to hold the phone, and how big the outline is.
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
  CaptureStep('Far', 'Hold the phone farther away so the whole hand and wrist fit the small outline.', 0.78,
      Icons.zoom_out_rounded),
  CaptureStep('Close', 'Move closer so the palm fills the large outline. Wait for it to look sharp.', 1.18,
      Icons.zoom_in_rounded),
  CaptureStep('Middle', 'Now a normal distance: fit the palm in the outline and hold still.', 1.0,
      Icons.crop_free_rounded),
  CaptureStep('Extra', 'Optional: one more, a little farther away. Each extra clear photo brings out faint lines.', 0.9,
      Icons.add_a_photo_rounded),
  CaptureStep('Extra', 'Optional: one more, a little closer. Hold still until it looks sharp.', 1.08,
      Icons.add_a_photo_rounded),
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

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _hand = e.hand;
      // Keep room for one more burst.
      final keep = math.min(e.photos.length, maxPhotos - burstSize);
      _photos.addAll(e.photos.take(keep));
      _scales.addAll(e.guideScales.take(keep));
      _stepsDone = minPhotos;
    }
    WidgetsBinding.instance.addObserver(this);
    _init();
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
      _startStream(c);
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
    _controller?.dispose();
    super.dispose();
  }

  /// Reads the camera's image stream to take each shot by itself when the
  /// palm is steady, in focus and fills the outline. The shutter button
  /// stays as the manual fallback.
  void _startStream(CameraController c) {
    if (c.value.isStreamingImages) return;
    try {
      c.startImageStream((image) {
        final now = DateTime.now();
        if (_busy || !mounted || now.difference(_lastFrame).inMilliseconds < 120) return;
        _lastFrame = now;
        final planes = image.planes;
        if (planes.length < 3) return;
        final state = _gate.add(PreviewFrame(
          width: image.width,
          height: image.height,
          y: planes[0].bytes,
          yRowStride: planes[0].bytesPerRow,
          u: planes[1].bytes,
          v: planes[2].bytes,
          uvRowStride: planes[1].bytesPerRow,
          uvPixelStride: planes[1].bytesPerPixel ?? 1,
        ));
        if (!_armed) {
          // Wait for the hand to move (new distance) before arming again.
          if (state == AutoState.moving || state == AutoState.noHand) _sawChange = true;
          if (_sawChange && state != AutoState.moving && state != AutoState.noHand) {
            _armed = true;
            _sawChange = false;
          }
        }
        if (state != _auto || state == AutoState.ready) {
          setState(() => _auto = state);
        }
        if (state == AutoState.ready && _armed && _stepsDone < captureSteps.length && _photos.length < maxPhotos) {
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
    if (c == null || _busy || _step >= captureSteps.length || _photos.length >= maxPhotos) return;
    setState(() => _busy = true);
    final scale = captureSteps[_step].scale;
    final startTorch = _torch;
    final frames = <Uint8List>[];
    final n = math.min(burstSize, maxPhotos - _photos.length);
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
    if (_stepsDone >= captureSteps.length || _photos.length >= maxPhotos) {
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

  /// Live guidance from the auto-capture gate.
  String _autoHint() {
    if (_busy || _controller == null) return '';
    if (_stepsDone >= captureSteps.length) return '';
    return switch (_auto) {
      AutoState.noHand => 'Put your palm inside the outline',
      AutoState.tooDark => 'Too dark. Move to brighter light or use the flashlight',
      AutoState.tooBright => 'Too bright. Step out of direct light',
      AutoState.moving => 'Hold steady',
      AutoState.soft => 'Focusing. Keep still, the photo is taken automatically',
      AutoState.ready => 'Taking the photo',
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
    return Scaffold(
      backgroundColor: colors.surfaceInverse,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.sm, vertical: UiSpace.xs),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: colors.onSurfaceInverse),
                    tooltip: 'Close',
                  ),
                  Expanded(
                    child: Text(
                      _hand == 'right' ? 'Right palm' : 'Left palm',
                      textAlign: TextAlign.center,
                      style: context.text.titleMedium?.copyWith(color: colors.onSurfaceInverse),
                    ),
                  ),
                  IconButton(
                    onPressed: c == null ? null : _toggleTorch,
                    icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: colors.onSurfaceInverse),
                    tooltip: 'Flashlight',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? _CameraError(error: _error!, onRetry: _init)
                    : c == null || !c.value.isInitialized
                        ? const UiSpinner(size: 28)
                        : AspectRatio(
                            // Preview size is reported in landscape.
                            aspectRatio: 1 / c.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(c),
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: HandGuidePainter(
                                      thumbOnLeft: _hand == 'left',
                                      line: colors.onSurfaceInverse,
                                      shade: colors.scrim,
                                      scale: step.scale,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(UiSpace.xl, UiSpace.md, UiSpace.xl, UiSpace.lg),
              child: Column(
                children: [
                  _StepTrack(done: _step),
                  const UiGap(UiSpace.md),
                  Text(
                    _step < minPhotos
                        ? 'Photo ${_step + 1} of $minPhotos · ${step.label}'
                        : widget.existing != null
                            ? 'Extra photo (to bring out unclear lines)'
                            : 'Extra photo ${_step + 1} of ${captureSteps.length} (optional)',
                    style: context.text.titleSmall?.copyWith(color: colors.onSurfaceInverse),
                  ),
                  const UiGap(UiSpace.xs),
                  Text(
                    _busy
                        ? 'Hold still. Taking a few quick frames, with and without the light.'
                        : _canRead
                            ? '${_photos.length} clear frames. Tap Read now, or add more to bring out faint lines.'
                            : '$_stepsDone of $minPhotos shots done. Only clear, well-lit frames count.',
                    textAlign: TextAlign.center,
                    style: context.text.labelMedium?.copyWith(color: colors.onSurfaceInverse),
                  ),
                  const UiGap(UiSpace.xs),
                  Text(
                    _autoHint(),
                    textAlign: TextAlign.center,
                    style: context.text.labelMedium?.copyWith(color: colors.accent, fontWeight: FontWeight.w600),
                  ),
                  const UiGap(UiSpace.xs),
                  Text(
                    widget.focusLines.isNotEmpty && widget.existing != null
                        ? 'To read the ${widget.focusLines.join(', ')} line, use soft light from one side and let the lines show as small shadows. ${step.hint}'
                        : '${step.hint} Spread your fingers a little and use soft light from one side.',
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(color: colors.onSurfaceInverse),
                  ),
                  const UiGap(UiSpace.lg),
                  Row(
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
                                  icon: Icon(Icons.undo_rounded, color: colors.onSurfaceInverse),
                                  label: Text('Retake', style: TextStyle(color: colors.onSurfaceInverse)),
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
                                    style: TextStyle(color: colors.onSurfaceInverse, fontWeight: FontWeight.w600),
                                  ),
                                ),
                        ),
                      ),
                    ],
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

/// Outline of an open palm, drawn as one smooth silhouette: tapered
/// fingers with round tips and webbing between them, a two-jointed thumb,
/// the fleshy mounds at the palm's sides and the wrist. Faint knuckle
/// creases and the three main lines help the user line the hand up.
///
/// The palm (finger base to wrist, 0.24–0.76 across, about 0.40–0.84 down)
/// sits where the analyzer expects it when it cannot find the hand by
/// itself: keep it in step with `PalmGeometry.guide` and
/// `HandSegmenter.guideCenterX/Y`.
class HandGuidePainter extends CustomPainter {
  HandGuidePainter({required this.thumbOnLeft, required this.line, required this.shade, this.scale = 1});
  final bool thumbOnLeft;
  final Color line;
  final Color shade;

  /// Size of the outline around the palm centre: below 1 for a photo from
  /// farther away, above 1 for a close-up. Matches
  /// `PalmGeometry.guide(scale:)`.
  final double scale;

  /// Palm centre the outline is scaled around.
  static const centerU = 0.5, centerV = 0.61;

  /// Fingers from the index (next to the thumb) to the little finger:
  /// base centre u, tip centre u, half width at the base and at the tip,
  /// tip top v, and the v of the web on the little-finger side.
  static const _fingers = [
    (0.322, 0.298, 0.061, 0.052, 0.190, 0.432),
    (0.460, 0.456, 0.063, 0.055, 0.135, 0.425),
    (0.596, 0.618, 0.060, 0.051, 0.160, 0.440),
    (0.718, 0.762, 0.050, 0.043, 0.250, 0.0),
  ];

  /// Path of the hand, in the thumb-on-left frame mapped by [p].
  /// [aspect] is the guide's height / width, so finger tips stay round.
  static Path handPath(Offset Function(double u, double v) p, {required double aspect}) {
    const k = 0.5523; // cubic Bézier circle factor
    final path = Path();
    void moveTo(double u, double v) => path.moveTo(p(u, v).dx, p(u, v).dy);
    void lineTo(double u, double v) => path.lineTo(p(u, v).dx, p(u, v).dy);
    void quad(double cu, double cv, double u, double v) {
      final c = p(cu, cv), e = p(u, v);
      path.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }

    void cubic(double u1, double v1, double u2, double v2, double u, double v) {
      final a = p(u1, v1), b = p(u2, v2), e = p(u, v);
      path.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
    }

    // Wrist, thumb side, then the ball of the thumb.
    moveTo(0.31, 1.04);
    cubic(0.305, 0.95, 0.27, 0.90, 0.255, 0.84);
    // Thumb: outer edge out and up, round tip, inner edge back to the web.
    cubic(0.225, 0.78, 0.15, 0.72, 0.105, 0.64);
    cubic(0.085, 0.60, 0.06, 0.56, 0.058, 0.525);
    cubic(0.056, 0.49, 0.085, 0.468, 0.112, 0.476);
    cubic(0.135, 0.483, 0.15, 0.50, 0.165, 0.525);
    cubic(0.19, 0.565, 0.22, 0.60, 0.248, 0.598);
    // Palm edge up to the index finger.
    cubic(0.262, 0.585, 0.262, 0.52, 0.262, 0.47);

    for (var i = 0; i < _fingers.length; i++) {
      final (baseU, tipU, baseHw, tipHw, tipV, webV) = _fingers[i];
      final r = tipHw;
      // Round tip: the radius is in u units; the same length in v units.
      final rv = r / aspect;
      final l0 = baseU - baseHw, r0 = baseU + baseHw;
      final l1 = tipU - tipHw, r1 = tipU + tipHw;
      final topV = tipV + rv;
      if (i > 0) {
        // Webbing: a soft U from the previous finger's base.
        final (_, _, _, _, _, prevWeb) = _fingers[i - 1];
        quad(l0 - 0.004, prevWeb + 0.012, l0, prevWeb - 0.01);
      }
      // Thumb-side edge of the finger, tapering slightly.
      final startV = i == 0 ? 0.47 : _fingers[i - 1].$6 - 0.01;
      quad(l0 + (l1 - l0) * 0.3, (startV + topV) / 2, l1, topV);
      // Round tip.
      cubic(l1, topV - rv * k, tipU - r * k, tipV, tipU, tipV);
      cubic(tipU + r * k, tipV, r1, topV - rv * k, r1, topV);
      // Little-finger side down to the web (or the palm edge).
      final endV = i == _fingers.length - 1 ? 0.47 : webV - 0.01;
      quad(r0 + (r1 - r0) * 0.3, (topV + endV) / 2, r0, endV);
    }

    // Little-finger edge of the palm, with the soft Moon mound, then wrist.
    cubic(0.772, 0.55, 0.785, 0.66, 0.772, 0.76);
    cubic(0.762, 0.82, 0.71, 0.88, 0.695, 0.93);
    lineTo(0.69, 1.04);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double u, double v) {
      final su = centerU + (u - centerU) * scale, sv = centerV + (v - centerV) * scale;
      return Offset(thumbOnLeft ? su * w : (1 - su) * w, sv * h);
    }

    final hand = handPath(p, aspect: h / w);

    // Dim everything outside the hand.
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), hand);
    canvas.drawPath(outside, Paint()..color = shade.withValues(alpha: 0.42));

    // A soft glow inside the edge, then a crisp outline.
    canvas.save();
    canvas.clipPath(hand);
    canvas.drawPath(
      hand,
      Paint()
        ..color = line.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
    canvas.drawPath(
      hand,
      Paint()
        ..color = line.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );

    final faint = Paint()
      ..color = line.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // Knuckle creases: two short curves across each finger.
    for (final (baseU, tipU, baseHw, tipHw, tipV, _) in _fingers) {
      for (final t in const [0.36, 0.64]) {
        final v = 0.44 + (tipV - 0.44) * t;
        final cu = baseU + (tipU - baseU) * t;
        final hw = (baseHw + (tipHw - baseHw) * t) * 0.62;
        final a = p(cu - hw, v), b = p(cu + hw, v), c = p(cu, v + 0.006);
        canvas.drawPath(Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(c.dx, c.dy, b.dx, b.dy), faint);
      }
    }
    // Thumb joint crease.
    final t0 = p(0.10, 0.585), t1 = p(0.165, 0.565), tc = p(0.135, 0.59);
    canvas.drawPath(Path()
      ..moveTo(t0.dx, t0.dy)
      ..quadraticBezierTo(tc.dx, tc.dy, t1.dx, t1.dy), faint);

    // The main palm lines, dashed, in palm coordinates (u from the thumb
    // side, v from the finger base), as a hint of where they will be read.
    Offset palm(double u, double v) => p(0.24 + u * 0.52, 0.42 + v * 0.42);
    const lines = [
      [(0.97, 0.22), (0.75, 0.19), (0.52, 0.15), (0.30, 0.10), (0.16, 0.06)], // heart
      [(0.06, 0.34), (0.30, 0.40), (0.55, 0.46), (0.78, 0.53)], // head
      [(0.07, 0.33), (0.18, 0.47), (0.25, 0.62), (0.29, 0.78), (0.31, 0.95)], // life
    ];
    final dash = Paint()
      ..color = line.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final pts in lines) {
      final path = Path();
      final first = palm(pts.first.$1, pts.first.$2);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < pts.length; i++) {
        final a = palm(pts[i - 1].$1, pts[i - 1].$2), b = palm(pts[i].$1, pts[i].$2);
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
        if (i == pts.length - 1) path.lineTo(b.dx, b.dy);
      }
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 9) {
          canvas.drawPath(m.extractPath(d, d + 5), dash);
        }
      }
    }
  }

  @override
  bool shouldRepaint(HandGuidePainter old) =>
      old.thumbOnLeft != thumbOnLeft || old.line != line || old.shade != shade || old.scale != scale;
}
