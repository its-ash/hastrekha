import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../../app/app_state.dart';
import '../../../data/history_store.dart';
import '../../../kb/knowledge_base.dart';
import '../../../reading/chart.dart';
import '../../../reading/unified.dart';
import '../../profile/birth_editor.dart';
import '../../widgets/common.dart';
import '../../widgets/kundali_view.dart';
import '../../widgets/nakshatra_view.dart';
import '../reading_screen.dart';

/// The birth chart worked out from the profile, and how each planet in
/// it compares with the palm.
class ChartTab extends StatelessWidget {
  const ChartTab({super.key, required this.saved});
  final SavedReading saved;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final profile = app.profile;
    final chart = profile.chart;
    if (chart == null || !profile.isComplete) {
      return UiEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: hi ? 'अपनी जन्म कुंडली जोड़ें' : 'Add your birth chart',
        message: hi
            ? 'नाम और जन्म तिथि (और हो सके तो समय और स्थान) जोड़ें। ग्रहों की गणना फ़ोन पर ही होती है और हथेली के साथ पढ़ी जाती है।'
            : 'Add your name and birth date, and the time and place if you know them. The planets are worked out on your phone and read together with your palm.',
        action: UiButton(hi ? 'जन्म विवरण जोड़ें' : 'Add birth details', onPressed: () => showBirthEditor(context)),
      );
    }
    final unified = UnifiedReading.build(palm: saved.features, chart: chart, kb: kb, nameSign: profile.nameSign);
    final now = DateTime.now();
    final dasha = chart.dashaAt(now);
    final nameSign = profile.nameSign;

    String deg(double d) => '${d.floor()}°${((d - d.floor()) * 60).floor().toString().padLeft(2, '0')}\'';
    String strengthLabel(Strength s) => switch (s) {
          Strength.strong => hi ? 'प्रबल' : 'Strong',
          Strength.moderate => hi ? 'सामान्य' : 'Balanced',
          Strength.weak => hi ? 'कमज़ोर' : 'Weak',
        };
    UiStatus strengthStatus(Strength s) => switch (s) {
          Strength.strong => UiStatus.success,
          Strength.moderate => UiStatus.neutral,
          Strength.weak => UiStatus.warning,
        };
    String dignity(Dignity d) => switch (d) {
          Dignity.exalted => hi ? 'उच्च' : 'Exalted',
          Dignity.own => hi ? 'स्वराशि' : 'Own sign',
          Dignity.friendly => hi ? 'मित्र' : 'Friendly',
          Dignity.neutral => hi ? 'सम' : 'Neutral',
          Dignity.enemy => hi ? 'शत्रु' : 'Unfriendly',
          Dignity.debilitated => hi ? 'नीच' : 'Debilitated',
        };

    final placements = [for (final p in Ephemeris.planets) chart.planets[p]!];
    final verdicts = {for (final v in unified.verdicts) v.planet: v};

    return TabBody(
      children: [
        UiCard(
          header: Row(
            children: [
              const UiIconBox(Icons.person_outline_rounded),
              const UiGap(UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: context.text.titleMedium),
                    Text(
                      [
                        UiDateFormat.date(profile.birthDate!),
                        if (profile.birthTime != null) UiDateFormat.time(context, profile.birthTime!),
                        if (profile.place != null) profile.place!.name,
                      ].join(' · '),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              UiIconButton(Icons.edit_outlined, tooltip: 'Edit birth details', onPressed: () => showBirthEditor(context)),
            ],
          ),
          child: UiKeyValueList([
            if (chart.lagna != null)
              UiKeyValue(hi ? 'लग्न' : 'Rising sign', '${kb.nameOf(chart.lagna!).of(lang)} ${deg(chart.ascendant! % 30)}'),
            UiKeyValue(hi ? 'चंद्र राशि' : 'Moon sign', kb.nameOf(chart.moon.rashi).of(lang)),
            UiKeyValue(hi ? 'सूर्य राशि' : 'Sun sign', kb.nameOf(chart.planets['sun']!.sign).of(lang)),
            UiKeyValue(hi ? 'जन्म नक्षत्र' : 'Birth star',
                '${kb.nakshatras[chart.moon.nakshatra - 1].name.of(lang)} · ${hi ? 'चरण' : 'pada'} ${chart.moon.pada}'),
            if (nameSign != null)
              UiKeyValue(hi ? 'नाम राशि' : 'Name sign',
                  '${kb.nameOf(nameSign.rashi).of(lang)} (${kb.nakshatras[nameSign.nakshatra - 1].name.of(lang)})'),
            if (dasha != null)
              UiKeyValue(hi ? 'दशा' : 'Period now',
                  '${kb.placeName(dasha.main.lord).of(lang)} / ${kb.placeName(dasha.sub.lord).of(lang)}'),
          ]),
        ),
        if (chart.lagna == null)
          UiAlert(
            hi
                ? 'जन्म का समय और स्थान जोड़ें तो लग्न और भाव भी दिखेंगे।'
                : 'Add the time and place of birth to see the rising sign and the houses.',
            status: UiStatus.info,
            action: UiButton(hi ? 'जोड़ें' : 'Add', size: UiSize.sm, variant: UiButtonVariant.ghost, onPressed: () => showBirthEditor(context)),
          ),
        KundaliView(chart: chart),
        Text(
          hi
              ? 'हरा: बलवान ग्रह · लाल: कमज़ोर ग्रह · (व): वक्री'
              : 'Green: strong planet · Red: weak planet · (R): retrograde',
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
        UiSectionHeader(hi ? 'ग्रह' : 'Planets', subtitle: hi ? 'कुंडली और हथेली में' : 'In your chart and on your palm'),
        UiTable<PlanetPlacement>(
          dense: true,
          striped: true,
          columns: [
            UiTableColumn(hi ? 'ग्रह' : 'Planet', text: (p) => kb.placeName(p.key).of(lang)),
            UiTableColumn(hi ? 'राशि' : 'Sign',
                text: (p) => '${kb.nameOf(p.sign).of(lang)} ${deg(p.degreeInSign)}${p.retrograde && p.key != 'rahu' && p.key != 'ketu' ? (hi ? ' व' : ' R') : ''}'),
            UiTableColumn(hi ? 'नक्षत्र' : 'Star', text: (p) => kb.nakshatras[p.nakshatra - 1].name.of(lang)),
            if (chart.lagna != null) UiTableColumn(hi ? 'भाव' : 'House', text: (p) => '${p.house}', numeric: true),
            UiTableColumn(hi ? 'स्थिति' : 'Dignity', text: (p) => '${dignity(p.dignity)}${p.combust ? (hi ? ', अस्त' : ', combust') : ''}'),
            UiTableColumn(hi ? 'कुंडली' : 'Chart',
                builder: (context, p) => UiTag(strengthLabel(verdicts[p.key]!.chart), status: strengthStatus(verdicts[p.key]!.chart))),
            UiTableColumn(hi ? 'हथेली' : 'Palm',
                builder: (context, p) => UiTag(strengthLabel(verdicts[p.key]!.palm), status: strengthStatus(verdicts[p.key]!.palm))),
          ],
          rows: placements,
        ),
        if (unified.planetInsights.isNotEmpty) ...[
          UiSectionHeader(
            hi ? 'हथेली और कुंडली साथ में' : 'Palm and chart together',
            subtitle: hi ? 'जहाँ दोनों मिलते हैं और जहाँ अलग हैं' : 'Where they agree, and where they differ',
          ),
          for (final r in unified.planetInsights) InsightCard(r, showArea: false),
        ],
        if (dasha != null) ...[
          UiSectionHeader(hi ? 'विंशोत्तरी दशा' : 'Planetary periods (Vimshottari dasha)'),
          UiTimeline(
            items: [
              for (final md in chart.mahadashas().where((m) => m.end.isAfter(chart.utc)).take(9))
                UiTimelineItem(
                  '${kb.placeName(md.lord).of(lang)}${md.contains(now) ? (hi ? ' · अभी' : ' · now') : ''}',
                  time: '${md.start.year}–${md.end.year}',
                  status: md.contains(now) ? UiStatus.success : (md.end.isBefore(now) ? UiStatus.neutral : UiStatus.info),
                  description: md.contains(now)
                      ? [
                          for (final ad in BirthChart.antardashas(md))
                            '${ad.contains(now) ? '▸ ' : ''}${kb.placeName(ad.lord).of(lang)}: '
                                '${ad.start.year}/${ad.start.month.toString().padLeft(2, '0')} – '
                                '${ad.end.year}/${ad.end.month.toString().padLeft(2, '0')}',
                        ].join('\n')
                      : kb.planetThemes[md.lord]?.text('dasha')?.of(lang),
                ),
            ],
          ),
        ],
        UiSectionHeader(hi ? 'जन्म नक्षत्र' : 'Birth star'),
        NakshatraView(placement: chart.moon, timeKnown: profile.birthTime != null),
        const Disclaimer(),
      ],
    );
  }
}
