import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../../app/app_state.dart';
import '../../../data/history_store.dart';
import '../../../kb/knowledge_base.dart';
import '../../../reading/palm_features.dart';
import '../../../reading/rules_engine.dart';
import '../../widgets/common.dart';
import '../../widgets/palm_view.dart';
import '../reading_screen.dart';

/// Pick a line, see it on the photo, read what it says.
class LinesTab extends StatefulWidget {
  const LinesTab({super.key, required this.saved, required this.reading});
  final SavedReading saved;
  final Reading reading;

  @override
  State<LinesTab> createState() => _LinesTabState();
}

class _LinesTabState extends State<LinesTab> {
  String _selected = 'life';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final f = widget.saved.features;
    final keys = [
      ...Vocab.primaryLines,
      ...Vocab.secondaryLines.where((k) => f.lines[k]?.present ?? false),
    ];
    if (!keys.contains(_selected)) _selected = keys.first;
    final line = f.lines[_selected] ?? LineFeature();
    final entry = kb.lines[_selected];
    final insights = widget.reading.forLine(_selected);
    final hi = lang == Lang.hi;
    final unclear = f.isUnclear(_selected);

    return TabBody(
      children: [
        UiChipGroup(
          scrollable: true,
          children: [
            for (final k in keys)
              UiChip(
                kb.lineName(k).of(lang),
                avatar: LineDot(k),
                selected: _selected == k,
                showCheck: false,
                onTap: () => setState(() => _selected = k),
              ),
          ],
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: PalmView(overlay: widget.saved.overlay, file: widget.saved.photoPath, highlight: _selected),
          ),
        ),
        UiCard(
          header: Row(
            children: [
              LineDot(_selected, size: 16),
              const UiGap(UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText2(kb.lineName(_selected), style: context.text.titleLarge),
                    if (entry != null)
                      Text(
                        [entry.str('sanskrit'), entry.str('devanagari')].whereType<String>().join(' · '),
                        style: context.text.bodySmall,
                      ),
                  ],
                ),
              ),
              if (unclear)
                UiStatusPill(hi ? 'स्पष्ट नहीं' : 'Not clear', status: UiStatus.warning)
              else if (!line.present)
                UiStatusPill(hi ? 'नहीं मिली' : 'Not found', status: UiStatus.neutral)
              else if (entry?.str('category') == 'primary')
                UiStatusPill(hi ? 'मुख्य रेखा' : 'Primary line', status: UiStatus.accent),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (line.present && !unclear)
                Wrap(
                  spacing: UiSpace.xs,
                  runSpacing: UiSpace.xs,
                  children: [
                    UiTag(Labels.value(line.length, lang)),
                    UiTag(Labels.value(line.depth, lang)),
                    UiTag(Labels.value(line.curve, lang)),
                    if (line.breaks != 'none')
                      UiTag('${hi ? 'टूटन' : 'Breaks'}: ${Labels.value(line.breaks, lang)}', status: UiStatus.warning),
                    if (line.chained) UiTag(hi ? 'जंजीरदार' : 'Chained', status: UiStatus.warning),
                    if (line.fork) UiTag(hi ? 'सिरे पर दो शाखाएँ' : 'Forked end', status: UiStatus.info),
                    if (line.branches != 'none')
                      UiTag('${hi ? 'शाखाएँ' : 'Branches'}: ${Labels.value(line.branches, lang)}', status: UiStatus.info),
                    if (line.start != null) UiTag('${hi ? 'शुरुआत' : 'From'}: ${kb.placeName(line.start!).of(lang)}'),
                    if (line.end != null) UiTag('${hi ? 'समाप्ति' : 'To'}: ${kb.placeName(line.end!).of(lang)}'),
                  ],
                ),
              if (entry?.text('about') != null) ...[
                const UiGap(UiSpace.md),
                UiExpandableText(entry!.text('about')!.of(lang), maxLines: 4,
                    moreLabel: hi ? 'और पढ़ें' : 'Read more', lessLabel: hi ? 'कम दिखाएँ' : 'Show less'),
              ],
              if (entry?.text('location') != null) ...[
                const UiGap(UiSpace.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place_outlined, size: 16, color: context.colors.textMuted),
                    const UiGap(UiSpace.xs),
                    Expanded(child: LText2(entry!.text('location')!, style: context.text.bodySmall)),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (unclear)
          UiAlert(
            hi
                ? 'आपकी तस्वीरों में यह रेखा साफ़ नहीं दिखी, इसलिए इसका फल नहीं दिया गया। '
                    'नरम, बग़ल की रोशनी में नई रीडिंग शुरू करें और इस रेखा के लिए कुछ और फ़ोटो लें।'
                : 'This line was not clear in your photos, so no reading is given for it. '
                    'Start a new reading in soft side light and take a few extra photos for this line.',
            title: hi ? 'स्पष्ट नहीं, दोबारा फ़ोटो लें' : 'Not clear, retake for this line',
            status: UiStatus.warning,
          )
        else if (insights.isEmpty)
          UiEmptyState(
            compact: true,
            icon: Icons.blur_on_rounded,
            title: hi ? 'इस रेखा में कुछ ख़ास नहीं' : 'Nothing special to note',
            message: hi ? 'यह रेखा सामान्य दिखती है, और यह अच्छी बात है।' : 'This line looks ordinary, which is fine.',
          )
        else
          for (final r in insights) InsightCard(r),
      ],
    );
  }
}
