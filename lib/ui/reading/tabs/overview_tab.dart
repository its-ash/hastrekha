import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../../app/app_state.dart';
import '../../../data/history_store.dart';
import '../../../kb/knowledge_base.dart';
import '../../../reading/palm_features.dart';
import '../../../reading/rules_engine.dart';
import '../../../reading/unified.dart';
import '../../../vision/palm_analyzer.dart';
import '../../widgets/common.dart';
import '../../profile/birth_editor.dart';
import '../../widgets/palm_view.dart';
import '../reading_screen.dart';

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.saved, required this.reading});
  final SavedReading saved;
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final f = saved.features;
    final found = [...Vocab.primaryLines, ...Vocab.secondaryLines].where((k) => f.lines[k]?.present ?? false).toList();
    final tones = reading.tones;
    final hi = lang == Lang.hi;

    return TabBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: PalmView(overlay: saved.overlay, file: saved.photoPath, showMinor: false),
            ),
            const UiGap(UiSpace.lg),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hi ? 'मिली रेखाएँ' : 'Lines found', style: context.text.labelMedium),
                  const UiGap(UiSpace.sm),
                  for (final k in found)
                    Padding(
                      padding: const EdgeInsets.only(bottom: UiSpace.xs),
                      child: Row(
                        children: [
                          LineDot(k, size: 10),
                          const UiGap(UiSpace.sm),
                          Expanded(child: Text(kb.lineName(k).of(lang), style: context.text.bodySmall)),
                        ],
                      ),
                    ),
                  const UiGap(UiSpace.md),
                  Text(hi ? 'संकेत' : 'Signs in this reading', style: context.text.labelMedium),
                  const UiGap(UiSpace.sm),
                  Wrap(
                    spacing: UiSpace.xs,
                    runSpacing: UiSpace.xs,
                    children: [
                      UiStatusPill('${tones.positive} ${hi ? 'शुभ' : 'bright'}', status: UiStatus.success),
                      UiStatusPill('${tones.neutral} ${hi ? 'सामान्य' : 'neutral'}', status: UiStatus.info),
                      UiStatusPill('${tones.caution} ${hi ? 'ध्यान दें' : 'to work on'}', status: UiStatus.warning),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        _UnifiedSection(features: f),
        _HandTypeCard(features: f),
        if (reading.highlights.isNotEmpty) ...[
          UiSectionHeader(hi ? 'मुख्य बातें' : 'Key insights'),
          for (final r in reading.highlights) InsightCard(r),
        ],
        if (reading.patternInsights.isNotEmpty) ...[
          UiSectionHeader(hi ? 'विशेष रेखा संयोग' : 'Line patterns'),
          for (final r in reading.patternInsights) InsightCard(r),
        ],
        if (reading.moundInsights.isNotEmpty) ...[
          UiSectionHeader(hi ? 'पर्वत (माउंट)' : 'Mounds', subtitle: hi ? 'ग्रहों के पर्वत' : 'The planets on your palm'),
          for (final r in reading.moundInsights) InsightCard(r),
        ],
        if (reading.symbolInsights.isNotEmpty) ...[
          UiSectionHeader(hi ? 'चिह्न' : 'Signs (chinha)'),
          for (final r in reading.symbolInsights) InsightCard(r),
        ],
        const Disclaimer(),
      ],
    );
  }
}

/// The palm read together with the birth chart: rising sign against the
/// hand type, the strongest and weakest planet across both, the period
/// running now and the name sign. Without birth details, an invitation
/// to add them.
class _UnifiedSection extends StatelessWidget {
  const _UnifiedSection({required this.features});
  final PalmFeatures features;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final hi = app.lang == Lang.hi;
    final profile = app.profile;
    final chart = profile.chart;
    if (chart == null || !profile.isComplete) {
      return UiAlert(
        hi
            ? 'अपना नाम और जन्म विवरण जोड़ें, ताकि हथेली को आपकी जन्म कुंडली के साथ पढ़ा जा सके।'
            : 'Add your name and birth details to read this palm together with your birth chart.',
        title: hi ? 'हथेली + कुंडली' : 'Palm + birth chart',
        status: UiStatus.info,
        icon: Icons.auto_awesome_outlined,
        action: UiButton(
          hi ? 'जन्म विवरण जोड़ें' : 'Add birth details',
          size: UiSize.sm,
          onPressed: () => showBirthEditor(context),
        ),
      );
    }
    final unified = UnifiedReading.build(palm: features, chart: chart, kb: app.kb, nameSign: profile.nameSign);
    if (unified.summary.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiSectionHeader(
          hi ? 'हथेली + कुंडली' : 'Palm + birth chart',
          subtitle: hi ? 'दोनों को मिलाकर पढ़ा गया' : 'Your palm and your planets, read together',
        ),
        const UiGap(UiSpace.md),
        UiColumn(
          gap: UiSpace.md,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final r in unified.summary) InsightCard(r)],
        ),
      ],
    );
  }
}

/// Air / Fire / Water hand with its dosha, shown with the element mix.
class _HandTypeCard extends StatelessWidget {
  const _HandTypeCard({required this.features});
  final PalmFeatures features;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final el = kb.elements[features.element];
    final mixed = features.secondary == 'none' ? null : kb.mixedFor(features.element, features.secondary);
    final scores = PalmAnalyzer.elementScores(features);
    final hi = lang == Lang.hi;
    return UiCard(
      header: Row(
        children: [
          const UiIconBox(Icons.back_hand_outlined),
          const UiGap(UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hi ? 'आपके हाथ का प्रकार' : 'Your hand type', style: context.text.labelMedium),
                LText2(el?.name ?? LText(Labels.value(features.element)), style: context.text.titleLarge),
                if (el?.str('dosha') != null)
                  Text('${el!.str('dosha')} dosha · ${el.str('devanagari') ?? ''}', style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: UiDonutChart(
              size: 150,
              thickness: 16,
              segments: [
                for (final e in Vocab.elements)
                  UiChartSegment(kb.elements[e]?.name.of(lang) ?? Labels.value(e, lang), scores[e] ?? 0),
              ],
              valueFormat: (v) {
                final total = scores.values.fold<double>(0, (a, b) => a + b);
                return total == 0 ? '0%' : '${(v / total * 100).round()}%';
              },
              center: Text(Labels.value(features.element, lang), style: context.text.titleMedium),
            ),
          ),
          const UiGap(UiSpace.lg),
          if (el?.text('nature') != null) LText2(el!.text('nature')!),
          if (mixed?.text('nature') != null) ...[
            const UiGap(UiSpace.md),
            Text(
              hi
                  ? 'मिश्रित हाथ: ${Labels.value(features.element, lang)} + ${Labels.value(features.secondary, lang)}'
                  : 'Mixed hand: ${Labels.value(features.element)} with ${Labels.value(features.secondary)}',
              style: context.text.titleSmall,
            ),
            const UiGap(UiSpace.xs),
            LText2(mixed!.text('nature')!),
          ],
          if (el != null && el.texts('strengths').isNotEmpty) ...[
            const UiGap(UiSpace.lg),
            Text(hi ? 'आपकी शक्तियाँ' : 'Strengths', style: context.text.titleSmall),
            const UiGap(UiSpace.xs),
            for (final s in el.texts('strengths')) _Bullet(s, icon: Icons.check_circle_outline_rounded),
          ],
          if (el != null && el.texts('balance').isNotEmpty) ...[
            const UiGap(UiSpace.md),
            Text(hi ? 'संतुलन के उपाय' : 'Keep in balance', style: context.text.titleSmall),
            const UiGap(UiSpace.xs),
            for (final s in el.texts('balance')) _Bullet(s, icon: Icons.spa_outlined),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {required this.icon});
  final LText text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: UiSpace.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: context.colors.accent),
            ),
            const UiGap(UiSpace.sm),
            Expanded(child: LText2(text)),
          ],
        ),
      );
}

/// Bullet list item, shared by other tabs.
class BulletText extends StatelessWidget {
  const BulletText(this.text, {super.key, this.icon = Icons.circle});
  final LText text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _Bullet(text, icon: icon);
}
