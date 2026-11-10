import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../reading/palm_features.dart';
import 'overlay.dart';

/// One saved palm reading.
class SavedReading {
  SavedReading({
    required this.id,
    required this.createdAt,
    required this.features,
    required this.overlay,
    required this.photoPath,
    this.note = '',
  });

  final String id;
  final DateTime createdAt;
  final PalmFeatures features;
  final PalmOverlay overlay;
  final String photoPath;
  final String note;

  String get hand => features.side;

  Map<String, Object?> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'features': features.toJson(),
        'overlay': overlay.toJson(),
        'note': note,
      };

  static SavedReading fromJson(Map<String, Object?> j, String photoPath) => SavedReading(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        features: PalmFeatures.fromJson((j['features'] as Map).cast<String, Object?>()),
        overlay: PalmOverlay.fromJson((j['overlay'] as Map).cast<String, Object?>()),
        photoPath: photoPath,
        note: j['note'] as String? ?? '',
      );
}

/// Saves readings as `readings/<id>/reading.json` + `photo.jpg` in the
/// app's private documents folder. Nothing leaves the device.
class HistoryStore {
  HistoryStore(this.root);
  final Directory root;

  static Future<HistoryStore> open() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/readings');
    await dir.create(recursive: true);
    return HistoryStore(dir);
  }

  Future<List<SavedReading>> list() async {
    final out = <SavedReading>[];
    if (!await root.exists()) return out;
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final f = File('${e.path}/reading.json');
      if (!await f.exists()) continue;
      try {
        final j = (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();
        out.add(SavedReading.fromJson(j, '${e.path}/photo.jpg'));
      } catch (_) {
        // A damaged entry should not hide the others.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<SavedReading> save({
    required PalmFeatures features,
    required PalmOverlay overlay,
    required Uint8List photo,
    String? id,
    DateTime? createdAt,
  }) async {
    final rid = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final dir = Directory('${root.path}/$rid');
    await dir.create(recursive: true);
    final photoFile = File('${dir.path}/photo.jpg');
    if (!await photoFile.exists() || id == null) await photoFile.writeAsBytes(photo, flush: true);
    final r = SavedReading(
      id: rid,
      createdAt: createdAt ?? DateTime.now(),
      features: features,
      overlay: overlay,
      photoPath: photoFile.path,
    );
    // Write then rename, so a crash never leaves half a file.
    final tmp = File('${dir.path}/reading.json.tmp');
    await tmp.writeAsString(jsonEncode(r.toJson()), flush: true);
    await tmp.rename('${dir.path}/reading.json');
    return r;
  }

  Future<void> delete(String id) async {
    final dir = Directory('${root.path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }
}
