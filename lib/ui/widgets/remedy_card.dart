import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/palm_features.dart';
import 'common.dart';

/// All remedies (upayas) for one planet.
class RemedyCard extends StatelessWidget {
  const RemedyCard({super.key, required this.planet, this.reasons = const [], this.initiallyOpen = false});
  final String planet;

  /// Why this planet is suggested (insight titles).
  final List<LText> reasons;
  final bool initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final r = kb.remedies[planet];
    final p = kb.planets[planet];
    if (r == null) return const SizedBox.shrink();

    final gem = r.child('gemstone');
    final metal = r.child('metal');
    final yantra = r.child('yantra');
    final mantra = r.child('mantra');
    final thread = r.child('thread');
    final deity = r.child('deity');

    String t(KbEntry? e, String field) => e?.text(field)?.of(lang) ?? '';

    return UiCard(
      padding: EdgeInsets.zero,
      child: UiAccordion(
        items: [
          UiAccordionItem(
            '${kb.placeName(planet).of(lang)}  ${p?.str('devanagari') ?? ''}',
            subtitle: [
              if (gem != null) t(gem, 'name'),
              if (r.text('day') != null) r.text('day')!.of(lang),
            ].where((e) => e.isNotEmpty).join(' · '),
            icon: Icons.brightness_7_outlined,
            initiallyExpanded: initiallyOpen,
            UiColumn(
              gap: UiSpace.lg,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reasons.isNotEmpty)
                  UiAlert(
                    reasons.map((e) => e.of(lang)).join(' · '),
                    title: hi ? 'क्यों सुझाया गया' : 'Why this is suggested',
                    status: UiStatus.info,
                  ),
                if (mantra != null)
                  _Block(
                    icon: Icons.record_voice_over_outlined,
                    title: hi ? 'मंत्र' : 'Mantra',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(mantra.str('devanagari') ?? '', style: context.text.titleMedium)),
                            UiCopyButton(mantra.str('devanagari') ?? mantra.str('sanskrit') ?? ''),
                          ],
                        ),
                        Text(mantra.str('sanskrit') ?? '', style: context.text.bodySmall),
                        if (mantra.integer('count') != null)
                          Text(hi ? '${mantra.integer('count')} बार जपें' : 'Chant ${mantra.integer('count')} times',
                              style: context.text.labelMedium),
                        if (mantra.text('about') != null) ...[const UiGap(UiSpace.xs), LText2(mantra.text('about')!)],
                      ],
                    ),
                  ),
                if (gem != null)
                  _Block(
                    icon: Icons.diamond_outlined,
                    title: hi ? 'रत्न' : 'Gemstone',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${t(gem, 'name')}${gem.str('sanskrit') != null ? ' (${gem.str('sanskrit')})' : ''}',
                            style: context.text.titleSmall),
                        const UiGap(UiSpace.xs),
                        Wrap(
                          spacing: UiSpace.xs,
                          runSpacing: UiSpace.xs,
                          children: [
                            if (gem.str('finger') != null)
                              UiTag('${hi ? 'उंगली' : 'Finger'}: ${kb.nameOf(gem.str('finger')!).of(lang)}'),
                            if (t(gem, 'metal').isNotEmpty) UiTag('${hi ? 'धातु' : 'Metal'}: ${t(gem, 'metal')}'),
                            if (t(gem, 'day').isNotEmpty) UiTag('${hi ? 'दिन' : 'Day'}: ${t(gem, 'day')}'),
                          ],
                        ),
                        if (gem.texts('alternatives').isNotEmpty) ...[
                          const UiGap(UiSpace.sm),
                          Text(
                            '${hi ? 'विकल्प' : 'Gentler alternatives'}: ${gem.texts('alternatives').map((e) => e.of(lang)).join(', ')}',
                            style: context.text.bodySmall,
                          ),
                        ],
                        if (gem.text('how') != null) ...[const UiGap(UiSpace.sm), LText2(gem.text('how')!)],
                      ],
                    ),
                  ),
                if (yantra != null && yantra.raw['grid'] is List)
                  _Block(
                    icon: Icons.grid_on_rounded,
                    title: hi ? 'यंत्र' : 'Yantra',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: YantraGrid(grid: yantra.raw['grid'] as List)),
                        if (yantra.text('about') != null) ...[const UiGap(UiSpace.sm), LText2(yantra.text('about')!)],
                      ],
                    ),
                  ),
                if (metal != null)
                  _Block(
                    icon: Icons.hardware_outlined,
                    title: hi ? 'धातु' : 'Metal',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(metal, 'name'), style: context.text.titleSmall),
                        if (metal.text('about') != null) LText2(metal.text('about')!),
                      ],
                    ),
                  ),
                if (thread != null)
                  _Block(
                    icon: Icons.gesture_rounded,
                    title: hi ? 'रक्षा सूत्र' : 'Charmed thread',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t(thread, 'color').isNotEmpty) Text(t(thread, 'color'), style: context.text.titleSmall),
                        if (thread.text('about') != null) LText2(thread.text('about')!),
                      ],
                    ),
                  ),
                if (deity != null)
                  _Block(
                    icon: Icons.temple_hindu_outlined,
                    title: hi ? 'देवता' : 'Deity',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t(deity, 'name'), style: context.text.titleSmall),
                        if (deity.text('about') != null) LText2(deity.text('about')!),
                      ],
                    ),
                  ),
                if (r.texts('colors').isNotEmpty || r.text('day') != null)
                  _Block(
                    icon: Icons.palette_outlined,
                    title: hi ? 'दिन और रंग' : 'Day and colours',
                    child: Text(
                      [
                        if (r.text('day') != null) r.text('day')!.of(lang),
                        ...r.texts('colors').map((e) => e.of(lang)),
                      ].join(' · '),
                    ),
                  ),
                if (r.texts('practices').isNotEmpty)
                  _Block(
                    icon: Icons.volunteer_activism_outlined,
                    title: hi ? 'सरल उपाय' : 'Simple practices',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final pr in r.texts('practices'))
                          Padding(
                            padding: const EdgeInsets.only(bottom: UiSpace.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  '),
                                Expanded(child: LText2(pr)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UiIconBox(icon, size: 28),
          const UiGap(UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.labelMedium),
                const UiGap(UiSpace.xs),
                child,
              ],
            ),
          ),
        ],
      );
}

/// A 3×3 planetary yantra (magic square).
class YantraGrid extends StatelessWidget {
  const YantraGrid({super.key, required this.grid, this.cell = 48});
  final List grid;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.accent, width: 2),
        borderRadius: BorderRadius.circular(UiRadius.xs),
        color: colors.accentSoft,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in grid)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in row as List)
                  Container(
                    width: cell,
                    height: cell,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(border: Border.all(color: colors.accent.withValues(alpha: 0.4), width: 0.5)),
                    child: Text('$v', style: UiTypography.mono(fontSize: 18, fontWeight: FontWeight.w600, color: colors.onAccentSoft)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Safety note shown with remedies.
class RemedyNote extends StatelessWidget {
  const RemedyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final hi = context.app.lang == Lang.hi;
    return UiAlert(
      hi
          ? 'उपाय पारंपरिक आध्यात्मिक अभ्यास हैं, इलाज नहीं। कोई भी तेज़ रत्न पहनने से पहले किसी जानकार ज्योतिषी से सलाह लें, और स्वास्थ्य संबंधी चिंता के लिए डॉक्टर से मिलें।'
          : 'Upayas are traditional spiritual practices, not treatments. Ask a knowledgeable astrologer before '
              'wearing a strong gemstone, and see a doctor for any health concern.',
      status: UiStatus.warning,
      icon: Icons.health_and_safety_outlined,
    );
  }
}

/// Planets in display order.
List<String> get allPlanets => Vocab.planets;
