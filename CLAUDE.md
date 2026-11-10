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
  - `multi_view.dart`: several photos of one palm (camera burst or gallery
    pick, up to 3) are aligned to the sharpest (`registerView`, NCC over
    the crease response) and their responses averaged (`fuseResponses`).
    A photo that does not line up is dropped (`PalmAnalysis.photosUsed`).
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
  The camera takes three guided shots (`captureSteps`: far 0.78, close 1.18,
  middle 1.0); the outline and `PalmGeometry.guide(scale:)` scale around the
  palm centre (0.5, 0.61), and the scales reach the analyzer as `guideScales`.
- No INTERNET permission, no analytics. `UiTypography.useGoogleFonts = false`.

## Build / test

- `make run`, `make build` (release APK), `make test`, `make analyze`.
- `test/vision_test.dart` draws synthetic palms; `test/debug_dump_test.dart`
  writes the analysed images with overlays to `/tmp/hastrekha_debug/`.
- `book/` holds the source PDF and is git-ignored; do not ship or commit it.

## Release (Ash Store)
- Published through the Ash Store kit: `store.json` (id `hastrekha`), `store.mk`, `index.html` + `CNAME` (`hastrekha.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub release with `hastrekha.apk` → repo topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
