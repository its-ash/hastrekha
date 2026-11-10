import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/astro.dart';
import '../../reading/chart.dart';

/// Birth chart drawn in the South Indian style: the twelve signs sit in
/// fixed squares around the edge, Pisces at the top left, running
/// clockwise. The lagna square is marked and each planet is written in
/// the square of its sign.
class KundaliView extends StatelessWidget {
  const KundaliView({super.key, required this.chart, this.title});
  final BirthChart chart;
  final String? title;

  /// Grid cell (column, row) of each sign, Aries = 0.
  static const _cells = [
    (1, 0), (2, 0), (3, 0), (3, 1), (3, 2), (3, 3),
    (2, 3), (1, 3), (0, 3), (0, 2), (0, 1), (0, 0),
  ];

  static const _abbrEn = {
    'sun': 'Su', 'moon': 'Mo', 'mars': 'Ma', 'mercury': 'Me', 'jupiter': 'Ju',
    'venus': 'Ve', 'saturn': 'Sa', 'rahu': 'Ra', 'ketu': 'Ke',
  };
  static const _abbrHi = {
    'sun': 'सू', 'moon': 'चं', 'mars': 'मं', 'mercury': 'बु', 'jupiter': 'गु',
    'venus': 'शु', 'saturn': 'श', 'rahu': 'रा', 'ketu': 'के',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final hi = app.lang == Lang.hi;
    final colors = context.colors;
    final bySign = <int, List<PlanetPlacement>>{};
    for (final p in chart.planets.values) {
      bySign.putIfAbsent(p.signIndex, () => []).add(p);
    }
    final lagna = chart.lagnaIndex;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final s = c.maxWidth / 4;
          return Stack(
            children: [
              for (var sign = 0; sign < 12; sign++)
                Positioned(
                  left: _cells[sign].$1 * s,
                  top: _cells[sign].$2 * s,
                  width: s,
                  height: s,
                  child: Container(
                    decoration: BoxDecoration(
                      color: sign == lagna ? colors.accent.withValues(alpha: 0.12) : colors.surface,
                      border: Border.all(color: colors.border, width: 0.8),
                    ),
                    padding: const EdgeInsets.all(UiSpace.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                kb.nameOf(Astro.rashiKeys[sign]).of(app.lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.labelSmall?.copyWith(color: colors.textMuted),
                              ),
                            ),
                            if (sign == lagna)
                              Text(hi ? 'लग्न' : 'Asc',
                                  style: context.text.labelSmall?.copyWith(color: colors.accent, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: [
                            for (final p in bySign[sign] ?? const <PlanetPlacement>[])
                              Text(
                                '${(hi ? _abbrHi : _abbrEn)[p.key]}${p.retrograde && p.key != 'rahu' && p.key != 'ketu' ? (hi ? '(व)' : '(R)') : ''}',
                                style: context.text.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: switch (chart.strength(p.key)) {
                                    Strength.strong => colors.success,
                                    Strength.weak => colors.danger,
                                    Strength.moderate => colors.text,
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: s,
                top: s,
                width: 2 * s,
                height: 2 * s,
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: colors.border, width: 0.8)),
                  padding: const EdgeInsets.all(UiSpace.sm),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: colors.accent, size: 22),
                      const UiGap(UiSpace.xs),
                      Text(
                        title ?? (hi ? 'जन्म कुंडली' : 'Birth chart'),
                        textAlign: TextAlign.center,
                        style: context.text.titleSmall,
                      ),
                      Text(
                        hi ? 'राशि चक्र (लाहिड़ी)' : 'Sidereal · Lahiri',
                        textAlign: TextAlign.center,
                        style: context.text.labelSmall?.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
