import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../app/home_shell.dart';
import '../../reading/astro.dart';
import '../capture/start_reading.dart';
import '../library/entry_detail_screen.dart';
import '../reading/reading_screen.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final name = app.profile.name.trim();
    return Scaffold(
      appBar: UiAppBar(
        title: 'Hastrekha',
        subtitle: 'हस्तरेखा · Vedic palm reading',
        actions: const [Padding(padding: EdgeInsets.only(right: UiSpace.md), child: LangToggle())],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          if (name.isNotEmpty) ...[
            Text('Namaste, $name', style: context.text.headlineSmall),
            const UiGap(UiSpace.lg),
          ],
          const _ReadCard(),
          const UiGap(UiSpace.xl),
          const _TodayCard(),
          const UiGap(UiSpace.xl),
          const _BirthStarCard(),
          if (app.readings.isNotEmpty) ...[
            const UiGap(UiSpace.xl),
            const _LatestReading(),
          ],
          const UiGap(UiSpace.xl),
          const _WhichHandTip(),
        ],
      ),
    );
  }
}

/// The main call to action: pick a hand, then camera or gallery.
class _ReadCard extends StatefulWidget {
  const _ReadCard();

  @override
  State<_ReadCard> createState() => _ReadCardState();
}

class _ReadCardState extends State<_ReadCard> {
  String? _hand;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final hand = _hand ?? app.dominantHand;
    return UiCard(
      variant: UiCardVariant.filled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const UiIconBox(Icons.back_hand_rounded, size: 44),
              const UiGap(UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Read my palm', style: context.text.titleLarge),
                    Text('Take a photo. Everything stays on your phone.', style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const UiGap(UiSpace.lg),
          Text('Which hand?', style: context.text.labelMedium),
          const UiGap(UiSpace.sm),
          UiSegmentedControl<String>(
            const [
              UiSegment('left', label: 'Left', icon: Icons.front_hand_outlined),
              UiSegment('right', label: 'Right', icon: Icons.back_hand_outlined),
            ],
            value: hand,
            expand: true,
            onChanged: (v) => setState(() => _hand = v),
          ),
          const UiGap(UiSpace.lg),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  'Camera',
                  icon: Icons.photo_camera_rounded,
                  expand: true,
                  onPressed: () => startReading(context, hand: hand, fromCamera: true),
                ),
              ),
              const UiGap(UiSpace.sm),
              Expanded(
                child: UiButton(
                  'Gallery',
                  icon: Icons.photo_library_outlined,
                  variant: UiButtonVariant.outline,
                  expand: true,
                  onPressed: () => startReading(context, hand: hand, fromCamera: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's ruling planet (vara), the Moon's nakshatra now, and a mantra.
class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final now = DateTime.now();
    final planetKey = Astro.weekdayRuler[now.weekday]!;
    final planet = kb.planets[planetKey];
    final remedy = kb.remedies[planetKey];
    final moon = Astro.moonPlacement(now.toUtc());
    final nak = kb.nakshatras.length >= moon.nakshatra ? kb.nakshatras[moon.nakshatra - 1] : null;
    final mantra = remedy?.child('mantra');
    return UiSection(
      title: 'Today',
      subtitle: _weekday(now.weekday),
      child: UiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiListTile(
              'Day of ${kb.placeName(planetKey).of(lang)}',
              subtitle: planet?.text('signifies')?.of(lang),
              icon: Icons.wb_sunny_outlined,
              chevron: planet != null,
              onTap: planet == null ? null : () => openEntry(context, planet, kind: EntryKind.planet),
            ),
            const UiDivider(),
            UiListTile(
              'Moon in ${nak?.name.of(lang) ?? 'nakshatra ${moon.nakshatra}'}',
              subtitle: '${kb.placeName(moon.rashi).of(lang)} · pada ${moon.pada}',
              icon: Icons.nightlight_outlined,
              chevron: nak != null,
              onTap: nak == null ? null : () => openEntry(context, nak, kind: EntryKind.nakshatra),
            ),
            if (mantra != null) ...[
              const UiDivider(),
              const UiGap(UiSpace.md),
              Text('Mantra for today', style: context.text.labelMedium),
              const UiGap(UiSpace.xs),
              Text(mantra.str('devanagari') ?? '', style: context.text.titleMedium),
              Text(mantra.str('sanskrit') ?? '', style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  static String _weekday(int d) =>
      const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d - 1];
}

class _BirthStarCard extends StatelessWidget {
  const _BirthStarCard();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final lang = app.lang;
    final moon = app.profile.moon;
    if (moon == null) {
      return UiCard(
        onTap: () => HomeShell.goTo(context, HomeShell.profile),
        child: const UiListTile(
          'Find your birth star',
          subtitle: 'Add your birth date to see your nakshatra and its remedies.',
          icon: Icons.auto_awesome_outlined,
          chevron: true,
        ),
      );
    }
    final nak = app.kb.nakshatras[moon.nakshatra - 1];
    return UiCard(
      onTap: () => openEntry(context, nak, kind: EntryKind.nakshatra),
      child: Row(
        children: [
          const UiIconBox(Icons.auto_awesome_rounded, size: 44),
          const UiGap(UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your birth star', style: context.text.labelMedium),
                Text('${nak.name.of(lang)}  ${nak.str('devanagari') ?? ''}', style: context.text.titleMedium),
                Text(
                  'Moon in ${app.kb.placeName(moon.rashi).of(lang)} · ruled by ${app.kb.placeName(nak.str('ruler') ?? '').of(lang)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _LatestReading extends StatelessWidget {
  const _LatestReading();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final r = app.readings.first;
    final el = app.kb.elements[r.features.element];
    return UiSection(
      title: 'Latest reading',
      actionLabel: 'See all',
      onAction: () => HomeShell.goTo(context, HomeShell.readings),
      child: UiCard(
        onTap: () => openSavedReading(context, r),
        padding: const EdgeInsets.all(UiSpace.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(UiRadius.sm),
              child: Image.file(File(r.photoPath), width: 64, height: 80, fit: BoxFit.cover),
            ),
            const UiGap(UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Labels.value(r.hand), style: context.text.titleSmall),
                  Text(el?.name.of(app.lang) ?? Labels.value(r.features.element), style: context.text.bodyMedium),
                  Text(UiFormat.relativeTime(r.createdAt), style: context.text.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _WhichHandTip extends StatelessWidget {
  const _WhichHandTip();

  @override
  Widget build(BuildContext context) {
    final kb = context.app.kb;
    final article = kb.learn.where((e) => e.key.contains('which_hand')).firstOrNull;
    return UiAlert(
      'Read both hands. Traditionally one shows what you were born with and the other '
      'what you are making of it.',
      title: 'Tip',
      status: UiStatus.info,
      icon: Icons.tips_and_updates_outlined,
      action: article == null
          ? null
          : TextButton(
              onPressed: () => openEntry(context, article, kind: EntryKind.article),
              child: const Text('Which hand to read?'),
            ),
    );
  }
}

