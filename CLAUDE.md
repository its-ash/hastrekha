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
    the crease response, one global shift/rotation/scale), then
    `refineWarp` adds a local correction field: tiles of ~palm/8 each
    find their own sub-pixel shift (NCC, ±7 px), outliers vs neighbours
    are dropped, gaps filled with low confidence. Without it shots from
    different distances stayed a few pixels off and smeared thin creases
    in the stack; low-confidence areas of a photo get less stack weight.
    The aligned photos are then stacked as images
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
    stream (YUV420, turned upright with `PreviewFrame.rotation` = sensor
    orientation / 90) and checks the palm against the outline of the
    current shot (`add(frame, scale:)`, same rectangle as
    `PalmGeometry.guide`): skin colour is learned from the palm centre
    each frame; `fill` (middle of the outline's palm is skin); `size` and
    `offset` (the palm's own left/right edges on rows of the upper palm,
    above the thumb web, median row; size 0.85..1.2 of the outline, else
    `tooFar` / `tooClose`; offset over 0.15 palm widths = `offCentre`;
    skipped when the frame corners are skin-coloured, where the edges
    cannot be seen), then light, `glare` (clipped share),
    stillness (frame difference) and focus (Laplacian at the palm centre
    at its peak; the peak is forgotten when the hand leaves the outline).
    Scale-free, so no per-phone tuning; tests in
    `test/auto_capture_test.dart`.
  - `photo_quality.dart`: the quality gate. `PalmAnalyzer.assess` /
    `checkPhotoInBackground` measure palm brightness, clipped highlights,
    sharpness (same Laplacian as the reading) and relative crease contrast,
    whether a hand was found and how many pixels wide the palm is (under
    `minPalmPixels` 220 = `tooSmall`); `PhotoQuality.problems` lists what fails
    (`QualityProblem` carries the user-facing title + advice). Thresholds
    and the measurements behind them are documented in the file; tests in
    `test/photo_quality_test.dart`.
  - `skeleton_graph.dart`: skeleton → segments → curves (joins segments that
    continue smoothly, records gaps as breaks).
  - `line_classifier.dart`: names curves by matching `lineTemplates` in palm
    coords (heart, head, life and fate each have `alternates`: other
    common paths measured on real palms, e.g. a lower heart line, a head
    and life line starting high at the thumb web, a wide life line; each
    curve takes its best-fitting shape, alternates weighted 0.9; the
    corridor search tries every shape too). Without them a real palm
    (`test/real_capture_test.dart`) read heart/head as not clear and
    missed the life line. `_venusLines` names short climbing creases
    inside the life line on the mound of Venus by height: progeny
    (lowest), siblings, kinship (nearest the thumb base); then `_traceCorridor` searches each main line's template
    corridor in the raw response (DP best path, crest + contrast checks)
    to find faint lines and complete partial ones; a second piece of a
    single line is refused when it jumps sideways (across the template
    direction) by more than `maxSideJump` (0.06 palm), which stopped a
    crossing crease splitting the heart line and its halves being named
    heart + head;
    measures length/depth/breaks/chains/forks/branches/curve/start/end
    and events along the line (`LineEvent.t` for the age timeline). `PalmMap`
    holds mound and location centres (Rahu between Saturn and Sun, Ketu low
    centre, as in the book).
  - `hand_shape.dart`: fingers and thumb (`HandShape.measure`, run by
    `PalmAnalyzer.measureHandShape` on a skin mask at full working
    resolution, learned from the palm centre). Fingers are split by three
    seams: the darkest path up from the palm between each pair of
    fingers (through the background gap when spread, along the dark
    crevice when they touch), started at 0.26/0.53/0.78 of the palm width
    from the index side; webs are where a seam stops being dark (never
    below the palm top). Per finger: length from its web, width profile,
    tip shape (`pointed`/`conic`/`square`/`spatulate` from the width 0.12
    widths below the tip, or a tip wider than the middle), base ratio,
    knuckle creases (two darkest bands along the finger) → phalanges.
    Thumb: web = lowest row with a real (non-skin) gap between thumb and
    palm, tip = farthest thumb pixel; null when it runs off the picture.
    Categories (`development`, `tips`, `fingerBase`, `phalanx`,
    `thumbLength`, `thumbBuild`) become `PalmFeatures` fields and the
    facts `finger.<name>.length`, `hand.tips`, `hand.finger_base`,
    `hand.phalanx`, `thumb.length`, `thumb.build`; missing ones give no
    fact. They also feed the element scores. Tune on real captures with
    `test/real_capture_test.dart` (draws seams, fingers, knuckles, thumb).
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
- The capture screen shows the full, undimmed camera picture with a palm
  box (`PalmFramePainter` in `lib/ui/capture/palm_frame.dart`: corner
  brackets, green when the gate says the palm is in place) and no hand
  outline (the user asked for that, 2026-11-14). All guidance is on the
  camera view: a big pill below the top bar from `_guide()` (Move
  closer / Move back / Move your hand left/right / Hold steady / light /
  glare), the step track in the top bar, the shot hint and progress at
  the bottom of the picture. Below the camera only the controls.
  The box is in palm units (1 = palm width, box 1.12 tall), so it keeps
  real-palm proportions on any preview aspect. Its numbers live in
  `PalmGeometry` (`guidePalmWidth` 0.48 of the frame width, centre
  (0.5, 0.61), `guidePalmHeight`, `guidePoint(x, y, scale:, aspect:)`);
  `PalmGeometry.guide(aspect:)`, `HandSegmenter.guideCenter*` and
  `AutoCaptureGate` all use them, so change them only there.
  The camera takes three required guided shots (`captureSteps`: far 0.78,
  close 1.18, middle 1.0) and up to three optional extras (0.9, 1.08, 1.0);
  the outline scales around the palm centre, and the scales reach the
  analyzer as `guideScales`.
- Debug and profile builds keep every camera frame (`lib/data/capture_log.dart`)
  in `/sdcard/Android/data/com.itsash.hastrekha/files/captures/<time>/`
  with `info.json` and a `log.txt` of quality checks; pull them with
  `adb pull` to replay real photos in tests. Release builds never write them.
- Capture takes each guided shot automatically (`AutoCaptureGate`; the
  shutter button is the manual fallback) as a burst of `burstSize` (3)
  frames: ambient, torch toggled (second ambient frame if the phone has no
  torch), ambient. Each frame is quality-checked; a shot counts when at
  least one frame passes. Up to `maxPhotos` (9) frames reach the analyzer,
  which stacks them. `CaptureScreen(existing:, focusLines:)` is the
  retake mode: it keeps the earlier frames and adds one extra shot (up to
  `maxPhotos + burstSize` frames).
- The capture screen is locked to portrait, turns the outline green
  while the gate reports `AutoState.aligned`, and points focus and
  exposure at the palm centre (`_aimAtPalm`) each time a palm arrives in
  the outline (the camera drops a metering point after a few seconds).
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
- `test/real_capture_test.dart` replays real phone captures from
  `/tmp/hastrekha_captures` (pulled with adb, see the capture log rule
  above) and writes `/tmp/hastrekha_debug/real_<folder>.jpg`; skipped
  when there are none. Check it after any change to `lib/vision`.
- `test/vision_test.dart` draws synthetic palms; `test/debug_dump_test.dart`
  writes the analysed images with overlays to `/tmp/hastrekha_debug/`.
- `book/` holds the source PDF and is git-ignored; do not ship or commit it.

## Release (Ash Store)
- Published through the Ash Store kit: `store.json` (id `hastrekha`), `store.mk`, `index.html` + `CNAME` (`hastrekha.itsash.in`). See `../ash-store/store-kit/STORE.md`.
- `make deploy` = bump version → build → commit, tag `vX.Y.Z`, push → GitHub release with `hastrekha.apk` → repo topics, homepage, Pages. Never create releases, tags or asset names by hand.
- Do not edit `store.mk` here. Edit `../ash-store/store-kit/store.mk`, then run `make store-sync` at the workspace root.
