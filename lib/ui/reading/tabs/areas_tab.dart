import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../../app/app_state.dart';
import '../../../kb/knowledge_base.dart';
import '../../../reading/rules_engine.dart';
import '../../widgets/common.dart';
import '../reading_screen.dart';

/// The reading grouped by life area: love, career, health, ...
class AreasTab extends StatelessWidget {
  const AreasTab({super.key, required this.reading});
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final lang = context.app.lang;
    final areas = reading.byArea;
    if (areas.isEmpty) {
      return const UiEmptyState(title: 'No insights yet', message: 'Edit the lines to add what you can see.');
    }
    return TabBody(
      children: [
        Text(
          lang == Lang.hi
              ? 'जीवन के हर क्षेत्र के लिए आपकी हथेली क्या कहती है।'
              : 'What your palm says about each part of life.',
          style: context.text.bodyMedium,
        ),
        UiAccordion(
          multiple: true,
          items: [
            for (final (i, e) in areas.entries.indexed)
              UiAccordionItem(
                Labels.area(e.key, lang),
                subtitle: _summary(e.value, lang),
                icon: Labels.areaIcon(e.key),
                initiallyExpanded: i == 0,
                UiColumn(
                  gap: UiSpace.md,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final r in e.value) InsightCard(r, showArea: false)],
                ),
              ),
          ],
        ),
        const Disclaimer(),
      ],
    );
  }

  static String _summary(List<KbRule> rules, Lang lang) {
    final p = rules.where((r) => r.tone == 'positive').length;
    final c = rules.where((r) => r.tone == 'caution').length;
    if (lang == Lang.hi) return '${rules.length} संकेत · $p शुभ · $c ध्यान योग्य';
    return '${rules.length} insights · $p bright · $c to work on';
  }
}
