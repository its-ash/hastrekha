# Hastrekha (package: hastrekha / com.itsash.hastrekha)

Offline Vedic palm reading for Android. The user photographs a palm; on-device
computer vision finds the hand and traces the lines; a rules engine turns the
measured features into a reading (English or Hindi) from a built-in knowledge
base retold from *Vedic Palmistry: Hasta Rekha Shastra*. No network access.

## Layout

- `lib/vision/` — pure-Dart computer vision, runs in a background isolate
  (`analyzePalmInBackground`). No ML model, no native code.
  - `hand_segmenter.dart`: skin-colour hand mask (chroma learned from the
    palm patch under the capture guide), palm centre via distance transform,
    finger tilt.
  - `palm_geometry.dart`: palm rectangle (finger base found where the hand
    splits into finger runs, wrist where it narrows), thumb side, finger
    ratio. `PalmFrame` maps pixels ↔ palm coords: `u` 0 = thumb side →
    1 = little-finger side, `v` 0 = finger base → 1 = wrist.
  - `crease_detector.dart`: lighting flattening (skin-only normalized
    blur), multi-scale Hessian valley response (`respond`), then NMS,
    hysteresis that also keeps long weak ridges, Zhang-Suen thinning
    (`extract`). Tuned for `PalmAnalyzer.workPalmWidth` = 400.
  - `multi_view.dart`: several photos of one palm (camera shots or gallery
    pick, 3 to 6) are aligned to the sharpest (`registerView`, NCC over
    the crease response). The aligned photos are then stacked as images
    (`stackGray`: each flattened by its own local mean, then averaged) and
    the crease detector runs once on the stack; noise falls by ~1/sqrt(n)
    while real creases stay. (Averaging per-photo responses, the old
    `fuseResponses`, missed faint lines because the Hessian response of
    noise is always positive.) A photo that does not line up is dropped
    (`PalmAnalysis.photosUsed`).
    Each extra photo gets a weight from its registration score and its
    sharpness relative to the primary (`AlignedView.weightOf`); a very
    soft or badly aligned one is dropped, and glare pixels (clipped or
    far brighter than the local mean) do not vote in the stack.
  - `auto_capture.dart`: `AutoCaptureGate` reads the camera preview
    stream (YUV420) and fires when the central box is skin-coloured
    (fill), lit, still (frame difference) and in focus (Laplacian at its
    peak for this shot). Scale-free, so no per-phone tuning; tests in
    `test/auto_capture_test.dart`.
  - `photo_quality.dart`: the quality gate. `PalmAnalyzer.assess` /
    `checkPhotoInBackground` measure palm brightness, clipped highlights,
    sharpness (same Laplacian as the reading) and relative crease contrast,
    and whether a hand was found; `PhotoQuality.problems` lists what fails
    (`QualityProblem` carries the user-facing title + advice). Thresholds
    and the measurements behind them are documented in the file; tests in
    `test/photo_quality_test.dart`.
  - `skeleton_graph.dart`: skeleton → segments → curves (joins segments that
    continue smoothly, records gaps as breaks).
  - `line_classifier.dart`: names curves by matching `lineTemplates` in palm
    coords; then `_traceCorridor` searches each main line's template
    corridor in the raw response (DP best path, crest + contrast checks)
    to find faint lines and complete partial ones;
    measures length/depth/breaks/chains/forks/branches/curve/start/end
    and events along the line (`LineEvent.t` for the age timeline). `PalmMap`
    holds mound and location centres (Rahu between Saturn and Sun, Ketu low
    centre, as in the book).
  - `palm_analyzer.dart`: the pipeline; also crops/straightens the photo,
    computes the Air/Fire/Water element scores and photo issues.
- `lib/reading/` — `palm_features.dart` (feature model + `Vocab`, `toFacts()`),
  `rules_engine.dart` (`Reading`), `astro.dart` (Meeus Moon longitude +
  Lahiri ayanamsa → nakshatra/pada/rashi), `chart.dart` (`Ephemeris`: JPL
  Keplerian elements for the planets, mean node, ascendant; `BirthChart`:
  whole-sign houses, dignity, combustion, strength, Vimshottari dasha),
  `name_sign.dart` (nāma rāśi from the first syllable, Latin or
  Devanagari), `unified.dart` (palm + chart read together → `KbRule` cards).
  `test/chart_test.dart` checks positions against known transits and
  conjunctions.
- `lib/kb/knowledge_base.dart` — loads and merges every `assets/kb/*.json`.
- `assets/kb/` — the knowledge base (rules, lines, symbols, hand types,
  planets, rashis, nakshatras, remedies, timeline, learn articles). Format and
  vocabulary: `docs/KNOWLEDGE_SCHEMA.md`. All text is `{en, hi}`.
- `assets/geo/cities.json` — offline birth places (lat, lon, standard UTC
  offset), loaded by `lib/data/places.dart`.
- `lib/data/` — settings + birth profile with place (shared_preferences), reading history
  (`readings/<id>/reading.json` + `photo.jpg` in app documents), overlay model.
- `lib/ui/` — screens: home, capture (camera + hand guide), review (correct
  detected lines, hand shape, mounds, signs), reading (tabs: overview, lines,
  birth chart, life areas, timeline, remedies; the overview and birth chart
  tabs show the palm + chart combined reading), history + left/right compare,
  library, profile, share card.

## Rules

- UI copy is English; reading text follows the EN / हिं toggle (`AppState.lang`).
- Use `theme` widgets (`../theme`, see `../theme/COMPONENTS.md`); no hardcoded
  colours (the brand accent in `main.dart` is the only one). Line colours come
  from `context.colors.chartColor(Labels.lineColorIndex(key))`.
- `AppScope` must stay above `UiApp` so pushed routes and sheets can read it.
- Knowledge-base text must be paraphrased (the book is copyrighted), warm,
  tendencies not certainties, and must never predict death, lifespan or a
  disease. `test/kb_test.dart` checks every rule against the vocabulary.
- When adding a feature key or value, update `Vocab`, `toFacts()`,
  `docs/KNOWLEDGE_SCHEMA.md` and `allowedFor` in `test/kb_test.dart`.
- The capture guide (`HandGuidePainter`), `HandSegmenter.guideCenter*` and
  `PalmGeometry.guide` describe the same palm placement; change them together.
  The camera takes three required guided shots (`captureSteps`: far 0.78,
  close 1.18, middle 1.0) and up to three optional extras (0.9, 1.08, 1.0);
  the outline and `PalmGeometry.guide(scale:)` scale around the palm centre
  (0.5, 0.61), and the scales reach the analyzer as `guideScales`.
- Capture takes each guided shot automatically (`AutoCaptureGate`; the
  shutter button is the manual fallback) as a burst of `burstSize` (3)
  frames: ambient, torch toggled (second ambient frame if the phone has no
  torch), ambient. Each frame is quality-checked; a shot counts when at
  least one frame passes. Up to `maxPhotos` (9) frames reach the analyzer,
  which stacks them. `CaptureScreen(existing:, focusLines:)` is the
  retake mode: it keeps the earlier frames and adds only extra shots.
- Not-clear lines: `PalmFeatures.isUnclear(key)` (main line found with
  confidence < `unclearBelow` 0.5, or heart/head/life not found; a missing
  fate line is a normal result; hand-edited lines and a simian crease are
  exempt). `toFacts()` emits no facts for them, so no rule fires; the
  review screen shows "Not clear" with a "Retake for these lines" button
  (opens the retake mode, then re-reads), and the Lines tab shows an
  EN/HI "not clear" notice instead of a reading.
- Every photo passes the quality gate before it counts: the camera checks
  each shot and explains a rejection (too dark → move to brighter light,
  blurry → hold steady, no hand → fill the outline); gallery picks are
  checked on the analyzing screen. A reading needs `minPhotos` (3) clear
  photos, at most `maxPhotos` (6).
- No INTERNET permission, no analytics. `UiTypography.useGoogleFonts = false`.

## Build / test

- `make run`, `make build` (release APK), `make test`, `make analyze`.
- `test/detection_benchmark_test.dart` runs 8 hard synthetic palms (faint,
  noisy, uneven light, soft focus, tilt) with 1, 3 and 6 photos, prints
  how many of heart/head/life/fate are found, and requires 3 photos to
  find all of them (10 cases, incl. hand shake, a glare blob over the head
  line and frames rotated 3 degrees). Run it after any change to
  `lib/vision`. Baseline before stacking: 1 photo 31/32, 3 photos 31/32;
  now: 1 photo 39/40, 3 photos 40/40, 6 photos 40/40.
- `test/vision_test.dart` draws synthetic palms; `test/debug_dump_test.dart`
  writes the analysed images with overlays to `/tmp/hastrekha_debug/`.
- `book/` holds the source PDF and is git-ignored; do not ship or commit it.

## Release (Ash Store)
- Published through the Ash Store kit: `store.json` (id `hastrekha`), `store.mk`, `index.html` + `CNAME` (`hastrekha.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub release with `hastrekha.apk` → repo topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
