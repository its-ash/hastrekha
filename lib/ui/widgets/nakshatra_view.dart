import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/astro.dart';
import 'common.dart';

/// Full description of a nakshatra. With [placement] it also shows the
/// pada, rashi and a precision note.
class NakshatraView extends StatelessWidget {
  const NakshatraView({super.key, this.placement, this.entry, this.timeKnown = true})
      : assert(placement != null || entry != null);

  final MoonPlacement? placement;
  final KbEntry? entry;
  final bool timeKnown;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final n = entry ?? kb.nakshatras[placement!.nakshatra - 1];
    final p = placement;
    final nearEdge = p != null && (p.progress < 0.04 || p.progress > 0.96);

    Widget section(String title, LText? text) => text == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const UiGap(UiSpace.xs),
              LText2(text),
            ],
          );

    Widget list(String title, List<LText> items, IconData icon) => items.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const UiGap(UiSpace.xs),
              for (final s in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: UiSpace.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 16, color: context.colors.accent),
                      const UiGap(UiSpace.sm),
                      Expanded(child: LText2(s)),
                    ],
                  ),
                ),
            ],
          );

    return UiColumn(
      gap: UiSpace.lg,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiCard(
          variant: UiCardVariant.filled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p == null ? (hi ? 'नक्षत्र' : 'Nakshatra') : (hi ? 'आपका जन्म नक्षत्र' : 'Your birth star'),
                  style: context.text.labelMedium),
              Text('${n.name.of(lang)}  ${n.str('devanagari') ?? ''}', style: context.text.headlineSmall),
              const UiGap(UiSpace.sm),
              UiKeyValueList([
                UiKeyValue(hi ? 'क्रम' : 'Number', '${n.integer('index')} / 27'),
                if (n.str('ruler') != null) UiKeyValue(hi ? 'स्वामी ग्रह' : 'Ruling planet', kb.placeName(n.str('ruler')!).of(lang)),
                if (n.text('deity') != null) UiKeyValue(hi ? 'देवता' : 'Deity', n.text('deity')!.of(lang)),
                if (n.text('symbol') != null) UiKeyValue(hi ? 'प्रतीक' : 'Symbol', n.text('symbol')!.of(lang)),
                if (p != null) UiKeyValue(hi ? 'चंद्र राशि' : 'Moon sign', kb.placeName(p.rashi).of(lang)),
                if (p != null) UiKeyValue(hi ? 'चरण' : 'Pada', '${p.pada} / 4'),
              ], dividers: false),
            ],
          ),
        ),
        if (p != null && (!timeKnown || nearEdge))
          UiAlert(
            !timeKnown
                ? (hi
                    ? 'जन्म का समय न होने से दोपहर 12 बजे का समय माना गया है। चंद्रमा लगभग एक दिन में एक नक्षत्र पार करता है, इसलिए सही समय से नक्षत्र बदल भी सकता है।'
                    : 'Without a birth time, noon is used. The Moon moves about one nakshatra a day, so the result may differ.')
                : (hi
                    ? 'आपका चंद्रमा दो नक्षत्रों की सीमा के पास है; जन्म का सही समय डालने पर नक्षत्र बदल सकता है।'
                    : 'Your Moon is close to the edge of this nakshatra; an exact birth time matters here.'),
            status: UiStatus.warning,
          ),
        section(hi ? 'स्वभाव' : 'Nature', n.text('qualities')),
        list(hi ? 'शक्तियाँ' : 'Strengths', n.texts('strengths'), Icons.check_circle_outline_rounded),
        list(hi ? 'चुनौतियाँ' : 'Challenges', n.texts('challenges'), Icons.lightbulb_outline_rounded),
        section(hi ? 'हथेली पर स्थान' : 'On the palm', n.text('palm')),
        section(hi ? 'स्वास्थ्य और देखभाल' : 'Health and care', n.text('health')),
        section(hi ? 'नक्षत्र की शांति के उपाय' : 'Honouring this star', n.text('propitiation')),
        const Disclaimer(),
      ],
    );
  }
}
