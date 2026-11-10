# Knowledge base schema

Hastrekha is fully offline. Every interpretation lives in JSON files under
`assets/kb/`. The app loads **every** `assets/kb/*.json` file and merges
them: each file is one JSON object whose top-level keys are any of the
sections below, and arrays with the same key from different files are
concatenated. So a big section can be split over several files
(`lines.json`, `lines_rules.json`, ...).

All content is **paraphrased in our own words** from the source book
(*Vedic Palmistry: Hasta Rekha Shastra*). Never copy sentences from the
book. Short technical terms (Sanskrit names, mantras, yantra numbers) are
fine.

## Text

Every user-facing string is a localized object:

```json
{"en": "You learn best by doing.", "hi": "आप करके सबसे अच्छा सीखते हैं।"}
```

- `en`: plain, warm English, second person ("You ..."), 1-3 sentences.
- `hi`: natural, simple Hindi in Devanagari (not a word-for-word
  translation; keep Sanskrit terms in Devanagari, e.g. आयु रेखा).
- Frame readings as tendencies and possibilities, never certainties.
- Never predict death, an age of death, lifespan in years, or a specific
  disease. Health text speaks of tendencies to care for ("pay attention
  to rest and digestion"), not diagnoses.
- Caution text always ends on something constructive.

## Fixed vocabularies

These keys are shared with the computer-vision code and the UI. Use only
these values.

| Kind | Keys |
|---|---|
| Planet | `sun`, `moon`, `mars`, `mercury`, `jupiter`, `venus`, `saturn`, `rahu`, `ketu` |
| Mound / location | the planet keys, plus `wrist`, `thumb`, `palm_center`, `between_jupiter_saturn`, `any` |
| Rashi | `aries`, `taurus`, `gemini`, `cancer`, `leo`, `virgo`, `libra`, `scorpio`, `sagittarius`, `capricorn`, `aquarius`, `pisces` |
| Element (hand) | `air`, `fire`, `water` |
| Guna | `sattva`, `rajas`, `tamas` |
| Finger | `thumb`, `index`, `middle`, `ring`, `little` |
| Area | `personality`, `mind`, `health`, `love`, `family`, `career`, `wealth`, `spirituality`, `life_events` |
| Tone | `positive`, `neutral`, `caution` |

### Line keys

Primary: `life`, `head`, `heart`, `fate`.
Secondary: `sun`, `jupiter_line`, `jupiter_ring`, `saturn_line`,
`saturn_ring`, `mars_line`, `venus_belt`, `contentment`, `mercury`,
`union`, `bracelets`, `moon_line`, `progeny`, `siblings`, `kinship`,
`fortune`, `thumb_barley`.

### Features a rule can test (`when` keys)

A rule's `when` is a map of feature key → value or list of values. All
entries must match. A list matches if any value matches.

| Key | Values |
|---|---|
| `<line>.present` | `true`, `false` |
| `<line>.length` | `short`, `medium`, `long` |
| `<line>.depth` | `faint`, `medium`, `deep` |
| `<line>.breaks` | `none`, `some`, `many` |
| `<line>.chained` | `true`, `false` (chains or islands along the line) |
| `<line>.fork` | `true`, `false` (fork at the end) |
| `<line>.branches` | `none`, `up`, `down`, `both` |
| `<line>.curve` | `straight`, `gentle`, `steep` |
| `<line>.start` | a location key |
| `<line>.end` | a location key |
| `pattern.simian` | `true`, `false` (head and heart joined into one crease) |
| `pattern.head_life_joined` | `true`, `false` (head and life lines start together) |
| `hand.element` | `air`, `fire`, `water` |
| `hand.secondary` | `air`, `fire`, `water`, `none` |
| `hand.palm` | `square`, `rectangular`, `rounded` |
| `hand.fingers` | `short`, `medium`, `long` |
| `hand.line_density` | `few`, `moderate`, `many` |
| `hand.side` | `left`, `right` |
| `mound.<planet>` | `flat`, `normal`, `raised` |
| `mound.<planet>.crossed` | `true`, `false` (many lines cutting the mound) |
| `symbol.<symbol key>` | a location key where the symbol is seen (`any` = anywhere) |

Values are compared as strings, so `true` and `"true"` are the same.
A line that is not present only matches `<line>.present: false`.

## Rule

```json
{
  "id": "life.long_deep",
  "when": {"life.length": "long", "life.depth": ["medium", "deep"]},
  "area": "health",
  "tone": "positive",
  "weight": 3,
  "planet": "venus",
  "title": {"en": "Steady vitality", "hi": "स्थिर जीवन शक्ति"},
  "text": {"en": "...", "hi": "..."},
  "source": "ch4"
}
```

- `id`: unique across all files, dotted, lowercase.
- `weight`: 1 (minor) to 3 (major). Used to order the reading.
- `planet`: optional; links the result to that planet's remedies.
- `title`: at most 6 words.
- `source`: optional chapter reference such as `ch4`.

## Sections

### `lines`

```json
{"key": "life", "category": "primary", "sanskrit": "Āyu Rekha",
 "devanagari": "आयु रेखा",
 "name": {"en": "Life Line", "hi": "जीवन रेखा"},
 "location": {"en": "Starts near the index finger and curves around the thumb toward the wrist.", "hi": "..."},
 "about": {"en": "...", "hi": "..."},
 "planet": "venus"}
```
`category`: `primary`, `secondary`, `misc`.

### `symbols`

```json
{"key": "star", "sanskrit": "Tara", "devanagari": "तारा",
 "name": {"en": "Star", "hi": "तारा"},
 "shape": {"en": "Three or more short lines crossing at one point.", "hi": "..."},
 "meaning": {"en": "...", "hi": "..."},
 "tone": "positive"}
```
Symbol-specific readings go in `rules` with a `symbol.<key>` condition.

### `elements`

One per hand element (`air`, `fire`, `water`):
```json
{"key": "air", "dosha": "Vāta", "devanagari": "वात",
 "name": {"en": "Air Hand", "hi": "वायु हस्त"},
 "looks": {"en": "...", "hi": "..."},
 "nature": {"en": "...", "hi": "..."},
 "strengths": [{"en": "...", "hi": "..."}],
 "challenges": [{"en": "...", "hi": "..."}],
 "balance": [{"en": "...", "hi": "..."}]}
```
Plus `mixed`: `[{"keys": ["air", "water"], "looks": {...}, "nature": {...}}]`.

### `gunas`

```json
{"key": "sattva", "devanagari": "सत्त्व", "name": {...}, "about": {...},
 "zone": {"en": "Upper palm, below the fingers", "hi": "..."},
 "planets": ["sun", "moon", "jupiter"]}
```

### `fingers`

```json
{"key": "index", "sanskrit": "Tarjani", "devanagari": "तर्जनी",
 "name": {...}, "element": "water", "planet": "jupiter",
 "rashis": ["cancer", "scorpio", "pisces"], "about": {...}}
```

### `planets`

```json
{"key": "jupiter", "sanskrit": "Brihaspati", "devanagari": "बृहस्पति",
 "name": {"en": "Jupiter", "hi": "गुरु"}, "guna": "sattva",
 "mound": {"en": "Below the index finger", "hi": "..."},
 "signifies": {...}, "strong": {...}, "weak": {...},
 "body": {...}}
```
Mound readings go in `rules` with `mound.<planet>` conditions.

### `rashis`

```json
{"key": "aries", "sanskrit": "Mesha", "devanagari": "मेष",
 "name": {...}, "ruler": "mars", "element": "fire", "guna": "rajas",
 "finger": "ring", "phalange": "top", "traits": {...}}
```
`phalange`: `top`, `middle`, `base`.

### `houses` (chart.json)

The twelve houses (bhavas) of the birth chart, keys `"1"` to `"12"`:
```json
{"key": "1", "sanskrit": "Tanu", "name": {"en": "1st house · Self", "hi": "..."}, "about": {...}}
```

### `planet_themes` (chart.json)

One per planet, used by the combined palm + chart reading
(`lib/reading/unified.dart`):
```json
{"key": "jupiter", "strong": {...}, "weak": {...},
 "dasha": {"en": "a time of growth, ...", "hi": "..."}}
```
`strong`: what the planet brings when palm and chart agree it is strong.
`weak`: how to care for it (gentle, no predictions). `dasha`: a phrase that
follows "This is …" for its Vimshottari period.

### `nakshatras`

27 entries in order (index 1-27):
```json
{"index": 1, "key": "ashwini", "sanskrit": "Ashwini", "devanagari": "अश्विनी",
 "ruler": "ketu", "deity": {...}, "symbol": {...}, "rashi": "aries",
 "palm": {"en": "Where it sits on the palm", "hi": "..."},
 "qualities": {...}, "strengths": [{...}], "challenges": [{...}],
 "health": {...}, "propitiation": {...}, "lucky": {"colors": [{...}], "day": {...}}}
```

### `remedies`

One per planet:
```json
{"planet": "saturn",
 "gemstone": {"name": {...}, "sanskrit": "Neelam", "alternatives": [{...}], "finger": "middle", "metal": "...", "day": {...}, "how": {...}},
 "metal": {"name": {...}, "about": {...}},
 "yantra": {"grid": [[8,3,10],[9,7,5],[4,11,6]], "about": {...}},
 "mantra": {"sanskrit": "Om Sham Shanaishcharaya Namah", "devanagari": "ॐ शं शनैश्चराय नमः", "count": 108, "about": {...}},
 "thread": {"color": {...}, "about": {...}},
 "deity": {"name": {...}, "about": {...}},
 "day": {...}, "colors": [{...}],
 "practices": [{...}]}
```

### `timeline`

How ages are read along each line:
```json
{"line": "life", "from": "start", "startAge": 0, "endAge": 84, "about": {...}}
```

### `learn`

Short articles for the in-app library:
```json
{"id": "learn.which_hand", "chapter": 1, "title": {...}, "body": {...}}
```
`body` may contain several paragraphs separated by `\n\n`.
