# Hastrekha · हस्तरेखा

Offline Vedic palm reading from a photo, in English or Hindi.

**[Website](https://hastrekha.itsash.in)** · **[Download APK](https://github.com/its-ash/hastrekha/releases/latest/download/hastrekha.apk)** · Get it in **[Ash Store](https://store.itsash.in)**

## Features

- **Guided camera**: a hand outline, a left/right switch and a flashlight. You
  can also pick a photo from the gallery.
- **On-device line detection**:
  - finds the hand and straightens it if it leans;
  - measures the palm and fingers;
  - traces the creases and names the life, head, heart and fate lines, plus
    the sun, mercury, union and moon lines, girdle of Venus, bracelets and
    others;
  - for each line, judges length, depth, breaks, chains, forks, branches and
    shape.
- **Review step**: check each line on the photo before the reading. You can
  fix or add lines, adjust the mounds and mark signs (star, cross, triangle, …).
- **Reading**, in tabs:
  - **Overview**: hand type (Air, Fire or Water, with its dosha), key insights,
    mounds and signs.
  - **Lines**: an explorer that highlights each line on the photo.
  - **Life areas**: personality, mind, health, love, family, career, wealth and
    spiritual path.
  - **Timeline**: turning points at approximate ages.
  - **Birth star**: your nakshatra, worked out offline from your birth details.
  - **Remedies**: mantra, gemstone, yantra, metal, thread, deity, day and
    colours.
- **History**: past readings, and a side-by-side comparison of your left and
  right hands.
- **Library**: articles plus every line, sign, hand type, planet, rashi,
  nakshatra and remedy, with search.
- **Daily**: the day's planet, today's Moon nakshatra and a mantra for the day.
- **Sharing**: share a reading as an image card or as text.
- **Settings**: light and dark mode, reading language, and erase all data.

Nothing leaves your phone.

## Install

- **Ash Store**: install [Ash Store](https://store.itsash.in) once, then install and update Hastrekha from it.
- **APK**: download the [latest APK](https://github.com/its-ash/hastrekha/releases/latest/download/hastrekha.apk) on your phone and open it. Allow your browser to install unknown apps if Android asks.

## Develop

Needs Flutter ≥ 3.44 and the shared theme package at `../theme`.

```bash
make run      # flutter pub get && flutter run
make build    # release APK
make test
make deploy   # bump version, build, tag, push, GitHub release (see store.mk)
```

## Release

`make deploy` follows the Ash Store kit (`store.mk`, `store.json`): it bumps the
version in `pubspec.yaml`, builds, commits, tags `vX.Y.Z`, pushes, and publishes
a GitHub release with `hastrekha.apk`. Ash Store and the website pick up the new
version from that release.

## Project layout

See `CLAUDE.md` for the code layout and `docs/KNOWLEDGE_SCHEMA.md` for the
knowledge-base format.

## License

No license file is included yet.

Interpretations are retold in our own words from the tradition of Vedic
palmistry. They are meant for reflection and enjoyment, and are not medical,
legal or financial advice.

Built by [itsash.in](https://itsash.in).
