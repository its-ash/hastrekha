import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hastrekha/app/app_state.dart';
import 'package:hastrekha/app/home_shell.dart';
import 'package:hastrekha/data/history_store.dart';
import 'package:hastrekha/data/overlay.dart';
import 'package:hastrekha/data/places.dart';
import 'package:hastrekha/data/settings.dart';
import 'package:hastrekha/kb/knowledge_base.dart';
import 'package:hastrekha/reading/palm_features.dart';
import 'package:hastrekha/ui/home/home_screen.dart';
import 'package:hastrekha/ui/profile/birth_editor.dart';
import 'package:hastrekha/ui/reading/reading_screen.dart';
import 'package:hastrekha/ui/review/review_screen.dart';
import 'package:hastrekha/vision/palm_analyzer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme/theme.dart';

import 'kb_test.dart' show loadKb;
import 'vision_test.dart' show syntheticPalm;

void main() {
  late AppState state;
  late SavedReading saved;
  late PalmAnalysis analysis;

  setUpAll(() async {
    UiTypography.useGoogleFonts = false;
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('hastrekha_test');
    state = AppState(
      kb: loadKb(),
      settings: SettingsStore(await SharedPreferences.getInstance()),
      history: HistoryStore(tmp),
    );
    analysis = const PalmAnalyzer().analyze(syntheticPalm(), rightHand: true);
    analysis.features.symbols.add(const SymbolMark('star', 'sun'));
    saved = await state.history.save(
      features: analysis.features,
      overlay: PalmOverlay.fromJson(analysis.overlayJson()),
      photo: analysis.photo,
    );
    state.readings = await state.history.list();
    state.profile = BirthProfile(
      name: 'Asha',
      birthDate: DateTime(1995, 8, 15),
      birthTime: const TimeOfDay(hour: 6, minute: 30),
      place: const Place(name: 'Mumbai', region: 'Maharashtra, India', latitude: 19.08, longitude: 72.88, utcOffsetMinutes: 330),
    );
  });

  Widget wrap(Widget child) => AppScope(
        state: state,
        child: UiApp(title: 'test', home: child),
      );

  testWidgets('home, readings, library and profile tabs render', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeShell()));
    await tester.pumpAndSettle();
    expect(find.text('Read my palm'), findsOneWidget);
    // The home list is lazy; the birth-star card sits below the Today card.
    await tester.scrollUntilVisible(
      find.text('Your birth star'),
      300,
      scrollable: find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Your birth star'), findsOneWidget);

    await tester.tap(find.text('Readings').last);
    await tester.pumpAndSettle();
    expect(find.text('Right hand'), findsWidgets);

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Lines (rekha)'), findsOneWidget);
    await tester.tap(find.text('Nakshatras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ashwini').first);
    await tester.pumpAndSettle();
    expect(find.text('Nature'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every reading tab renders in English and Hindi', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final lang in Lang.values) {
      state.lang = lang;
      await tester.pumpWidget(wrap(ReadingScreen(saved: saved)));
      await tester.pumpAndSettle();
      for (final tab in ['Birth chart', 'Lines', 'Life areas', 'Timeline', 'Remedies', 'Overview']) {
        // The tab bar scrolls; bring the tab into view before tapping it.
        await tester.ensureVisible(find.text(tab).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab in ${lang.name}');
      }
    }
    state.lang = Lang.en;
  });

  testWidgets('palm and birth chart are read together', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(ReadingScreen(saved: saved)));
    await tester.pumpAndSettle();
    expect(find.text('Palm + birth chart'), findsOneWidget);
    expect(find.textContaining('Rising sign'), findsWidgets);
    expect(find.textContaining('Name sign'), findsWidgets);

    await tester.tap(find.text('Birth chart').first);
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Rising sign'), findsOneWidget);
    expect(find.text('Sidereal · Lahiri'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birth details sheet asks for name and date', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final saved = state.profile;
    state.profile = const BirthProfile();
    late BuildContext ctx;
    await tester.pumpWidget(wrap(Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    final result = showBirthEditor(ctx, prompt: true);
    await tester.pumpAndSettle();
    expect(find.text('Add your birth details'), findsOneWidget);
    expect(find.text('Place of birth'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    await tester.ensureVisible(find.text('Skip for now'));
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(tester.takeException(), isNull);
    state.profile = saved;
  });

  testWidgets('birth sheet keeps room for the name while typing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    late BuildContext ctx;
    await tester.pumpWidget(wrap(Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    showBirthEditor(ctx, prompt: true);
    await tester.pumpAndSettle();
    final name = find.byType(EditableText).first;
    await tester.tap(name);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 960);
    await tester.pumpAndSettle();
    final viewport = tester.getSize(find.byType(SingleChildScrollView).last);
    expect(viewport.height, greaterThan(200));
    expect(tester.getSize(find.ancestor(of: name, matching: find.byType(InputDecorator)).first).height,
        greaterThanOrEqualTo(48));
    await tester.enterText(name, 'Asha');
    expect(find.text('Asha'), findsWidgets);
    tester.view.viewInsets = FakeViewPadding.zero;
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('review screen shows signs and hand-type pictures', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(ReviewScreen(
      features: analysis.features,
      overlay: PalmOverlay.fromJson(analysis.overlayJson()),
      photo: analysis.photo,
    )));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Your signs'), 300, scrollable: list);
    expect(find.text('Moon sign (rashi)'), findsOneWidget);
    expect(find.text('Rising sign (lagna)'), findsOneWidget);
    expect(find.text('Name sign'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Clearly longer than it is wide'), 300, scrollable: list);
    await tester.tap(find.text('Clearly longer than it is wide'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Palm marks (chinha)'), 300, scrollable: list);
    expect(find.text('Add a palm mark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review screen shows the detected lines', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(ReviewScreen(
      features: analysis.features,
      overlay: PalmOverlay.fromJson(analysis.overlayJson()),
      photo: analysis.photo,
    )));
    await tester.pumpAndSettle();
    expect(find.text('See my reading'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Heart Line'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Life Line'), findsOneWidget);
    // Align the row at the top, clear of the sticky bottom bar.
    await tester.ensureVisible(find.text('Heart Line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heart Line'));
    await tester.pumpAndSettle();
    expect(find.text('I can see this line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
