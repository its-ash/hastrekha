import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../reading/palm_features.dart';
import '../widgets/common.dart';

/// Bottom sheet to correct one line. Returns the edited copy, or null.
Future<LineFeature?> showLineEditor(BuildContext context, String key, LineFeature line) {
  final kb = context.appRead.kb;
  final l = line.copy();
  final entry = kb.lines[key];
  return UiSheet.show<LineFeature>(
    context,
    title: kb.lineName(key).en,
    subtitle: [entry?.str('sanskrit'), entry?.str('devanagari')].whereType<String>().join(' · '),
    expand: true,
    child: StatefulBuilder(
      builder: (context, setState) {
        List<UiChoice<String>> opts(List<String> v) => [for (final x in v) UiChoice(x, Labels.value(x))];
        Widget field(String label, Widget child) => UiFieldLabel(label: label, child: child);
        return UiColumn(
          gap: UiSpace.lg,
          children: [
            if (entry?.text('location') != null) Text(entry!.text('location')!.en, style: context.text.bodySmall),
            UiSwitch(l.present, label: 'I can see this line', onChanged: (v) => setState(() => l.present = v)),
            if (l.present) ...[
              field('Length', UiChoiceChips<String>(options: opts(Vocab.lengths), value: l.length, onChanged: (v) => setState(() => l.length = v))),
              field('Depth', UiChoiceChips<String>(options: opts(Vocab.depths), value: l.depth, onChanged: (v) => setState(() => l.depth = v))),
              field('Breaks', UiChoiceChips<String>(options: opts(Vocab.breaks), value: l.breaks, onChanged: (v) => setState(() => l.breaks = v))),
              field('Branches', UiChoiceChips<String>(options: opts(Vocab.branches), value: l.branches, onChanged: (v) => setState(() => l.branches = v))),
              field('Shape', UiChoiceChips<String>(options: opts(Vocab.curves), value: l.curve, onChanged: (v) => setState(() => l.curve = v))),
              UiSwitch(l.chained, label: 'Chained or has islands', onChanged: (v) => setState(() => l.chained = v)),
              UiSwitch(l.fork, label: 'Splits into a fork at the end', onChanged: (v) => setState(() => l.fork = v)),
              field(
                'Starts at',
                UiSelect<String>(
                  value: l.start,
                  hint: 'Not sure',
                  options: [for (final p in Vocab.locations) UiOption(p, kb.placeName(p).en)],
                  onChanged: (v) => setState(() => l.start = v),
                ),
              ),
              field(
                'Ends at',
                UiSelect<String>(
                  value: l.end,
                  hint: 'Not sure',
                  options: [for (final p in Vocab.locations) UiOption(p, kb.placeName(p).en)],
                  onChanged: (v) => setState(() => l.end = v),
                ),
              ),
            ],
            UiButton(
              'Done',
              expand: true,
              onPressed: () {
                l
                  ..edited = true
                  ..confidence = 1;
                Navigator.of(context).pop(l);
              },
            ),
          ],
        );
      },
    ),
  );
}
