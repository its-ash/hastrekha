import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/history_store.dart';
import '../data/overlay.dart';
import '../data/settings.dart';
import '../kb/knowledge_base.dart';
import '../reading/palm_features.dart';
import '../reading/rules_engine.dart';

/// App-wide state: the knowledge base, preferences and saved readings.
class AppState extends ChangeNotifier {
  AppState({required this.kb, required this.settings, required this.history});

  final KnowledgeBase kb;
  final SettingsStore settings;
  final HistoryStore history;

  List<SavedReading> readings = [];

  static Future<AppState> load() async {
    final results = await Future.wait([
      KnowledgeBase.load(),
      SettingsStore.open(),
      HistoryStore.open(),
    ]);
    final s = AppState(
      kb: results[0] as KnowledgeBase,
      settings: results[1] as SettingsStore,
      history: results[2] as HistoryStore,
    );
    s.readings = await s.history.list();
    return s;
  }

  Lang get lang => settings.lang;
  set lang(Lang v) {
    settings.lang = v;
    notifyListeners();
  }

  BirthProfile get profile => settings.profile;
  set profile(BirthProfile p) {
    settings.profile = p;
    notifyListeners();
  }

  String get dominantHand => settings.dominantHand;
  set dominantHand(String v) {
    settings.dominantHand = v;
    notifyListeners();
  }

  Reading evaluate(PalmFeatures f) => RulesEngine(kb).evaluate(f);

  Future<SavedReading> saveReading({
    required PalmFeatures features,
    required PalmOverlay overlay,
    required Uint8List photo,
    String? id,
    DateTime? createdAt,
  }) async {
    final r = await history.save(features: features, overlay: overlay, photo: photo, id: id, createdAt: createdAt);
    readings = await history.list();
    notifyListeners();
    return r;
  }

  Future<void> deleteReading(String id) async {
    await history.delete(id);
    readings = await history.list();
    notifyListeners();
  }

  Future<void> eraseEverything() async {
    await history.clear();
    await settings.clear();
    readings = [];
    notifyListeners();
  }

  /// Latest saved reading of each hand, for comparing.
  ({SavedReading? left, SavedReading? right}) get latestPair {
    SavedReading? l, r;
    for (final x in readings) {
      if (x.hand == 'left') l ??= x;
      if (x.hand == 'right') r ??= x;
    }
    return (left: l, right: r);
  }
}

/// Gives widgets access to [AppState] and rebuilds them when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes (for callbacks).
  static AppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
}
