import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Debug and profile builds only (never release): keeps every camera frame
/// of each capture in the app's external files folder, with what the
/// quality check said about it, so real photos can be pulled from a phone
/// and replayed in tests:
///
///     adb pull /sdcard/Android/data/com.itsash.hastrekha/files/captures /tmp/hastrekha_captures
///
/// Each capture is one folder: `info.json` (hand, camera and preview
/// sizes), `s<step>_<frame>.jpg` per frame, and `log.txt` (one line per
/// frame: file, guide scale, quality).
class CaptureLog {
  CaptureLog._(this._dir);
  final Directory _dir;

  /// Writes run one after another, so log lines are not lost.
  Future<void> _queue = Future.value();
  Future<void> _run(Future<void> Function() job) => _queue = _queue.then((_) => job()).catchError((_) {});

  static bool get enabled => !kReleaseMode;

  /// Starts a new capture folder, or returns null in release builds or
  /// when the folder cannot be made.
  static Future<CaptureLog?> start(Map<String, Object?> info) async {
    if (!enabled) return null;
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final dir = Directory('${base.path}/captures/$stamp');
      await dir.create(recursive: true);
      await File('${dir.path}/info.json').writeAsString(const JsonEncoder.withIndent('  ').convert(info));
      return CaptureLog._(dir);
    } catch (_) {
      return null;
    }
  }

  /// Adds facts learned after the start (e.g. the stream frame size).
  Future<void> note(String line) =>
      _run(() => File('${_dir.path}/log.txt').writeAsString('$line\n', mode: FileMode.append, flush: true));

  /// Saves one frame and a log line about it.
  Future<void> frame(String name, Uint8List bytes, String line) {
    _run(() => File('${_dir.path}/$name').writeAsBytes(bytes));
    return note('$name $line');
  }
}
