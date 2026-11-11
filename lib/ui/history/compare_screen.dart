import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/history_store.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/palm_features.dart';
import '../widgets/common.dart';
import '../widgets/palm_view.dart';

/// Left and right palms side by side, line by line.
class CompareScreen extends StatelessWidget {
  const CompareScreen({super.key, required this.left, required this.right});
  final SavedReading left;
  final SavedReading right;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final dominant = app.dominantHand;
    final born = dominant == 'right' ? left : right;
    final made = dominant == 'right' ? right : left;
    final keys = [
      ...Vocab.primaryLines,
      ...Vocab.secondaryLines.where((k) => (left.features.lines[k]?.present ?? false) || (right.features.lines[k]?.present ?? false)),
    ];

    String describe(LineFeature? l) {
      if (l == null || !l.present) return hi ? 'नहीं' : 'Not found';
      return [
        Labels.value(l.length, lang),
        Labels.value(l.depth, lang),
        if (l.breaks != 'none') hi ? 'टूटन' : 'breaks',
      ].join(', ');
    }

    return Scaffold(
      appBar: const UiAppBar(title: 'Both hands', actions: [Padding(padding: EdgeInsets.only(right: UiSpace.md), child: LangToggle())]),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          UiAlert(
            hi
                ? 'आप ${dominant == 'left' ? 'बाएँ' : 'दाएँ'} हाथ से लिखते हैं। परंपरा के अनुसार दूसरा हाथ जन्म से मिले गुण दिखाता है, और लिखने वाला हाथ बताता है कि आपने उन्हें कैसे निखारा है।'
                : 'You write with your $dominant hand. Traditionally the other hand shows what you were born with, '
                    'and your writing hand shows what you are making of it.',
            status: UiStatus.info,
          ),
          const UiGap(UiSpace.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, r) in [
                (hi ? 'जन्मजात' : 'Born with', born),
                (hi ? 'वर्तमान' : 'Making now', made),
              ]) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$label · ${Labels.value(r.hand, lang)}', style: context.text.labelMedium),
                      const UiGap(UiSpace.xs),
                      PalmView(overlay: r.overlay, file: r.photoPath, showMinor: false, radius: UiRadius.md),
                      const UiGap(UiSpace.xs),
                      LText2(kb.elements[r.features.element]?.name ?? LText(r.features.element), style: context.text.titleSmall),
                    ],
                  ),
                ),
                if (r == born) const UiGap(UiSpace.md),
              ],
            ],
          ),
          const UiGap(UiSpace.xl),
          UiTable<String>(
            columns: [
              UiTableColumn(hi ? 'रेखा' : 'Line', text: (k) => kb.lineName(k).of(lang)),
              UiTableColumn(hi ? 'जन्मजात' : 'Born with', text: (k) => describe(born.features.lines[k])),
              UiTableColumn(hi ? 'वर्तमान' : 'Making now', text: (k) => describe(made.features.lines[k])),
            ],
            rows: keys,
            dense: true,
            striped: true,
          ),
          const UiGap(UiSpace.xl),
          for (final k in keys) ..._changes(context, k, born.features.lines[k], made.features.lines[k]),
          const UiGap(UiSpace.lg),
          const Disclaimer(),
        ],
      ),
    );
  }

  /// A plain sentence for each line that differs between the hands.
  List<Widget> _changes(BuildContext context, String key, LineFeature? a, LineFeature? b) {
    final app = context.app;
    final hi = app.lang == Lang.hi;
    final name = app.kb.lineName(key).of(app.lang);
    final pa = a?.present ?? false, pb = b?.present ?? false;
    String? msg;
    UiStatus status = UiStatus.info;
    int rank(String v, List<String> order) => order.indexOf(v);
    if (!pa && pb) {
      msg = hi ? '$name केवल लिखने वाले हाथ में है: यह गुण आप ख़ुद विकसित कर रहे हैं।' : '$name appears only on your active hand: a quality you are building yourself.';
      status = UiStatus.success;
    } else if (pa && !pb) {
      msg = hi ? '$name जन्म से मिली है, पर अभी आप इस गुण का कम उपयोग कर रहे हैं।' : '$name is a gift from birth that you are not drawing on much right now.';
    } else if (pa && pb) {
      final dl = rank(b!.length, Vocab.lengths) - rank(a!.length, Vocab.lengths);
      final dd = rank(b.depth, Vocab.depths) - rank(a.depth, Vocab.depths);
      if (dl + dd > 0) {
        msg = hi ? 'लिखने वाले हाथ में $name ज़्यादा मज़बूत है: इस क्षेत्र में आप आगे बढ़ रहे हैं।' : '$name is stronger on your active hand: you are growing in this area.';
        status = UiStatus.success;
      } else if (dl + dd < 0) {
        msg = hi ? 'लिखने वाले हाथ में $name हल्की है: इस क्षेत्र पर थोड़ा ध्यान दें।' : '$name is lighter on your active hand: this area could use some attention.';
        status = UiStatus.warning;
      }
    }
    if (msg == null) return const [];
    return [UiAlert(msg, status: status, showIcon: true), const UiGap(UiSpace.sm)];
  }
}
