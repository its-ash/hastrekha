import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';

/// Labels for the fixed vocabulary, in both languages.
abstract final class Labels {
  static const areas = <String, (String, String, IconData)>{
    'personality': ('Personality', 'व्यक्तित्व', Icons.person_outline_rounded),
    'mind': ('Mind', 'मन और बुद्धि', Icons.psychology_outlined),
    'health': ('Health & energy', 'स्वास्थ्य और ऊर्जा', Icons.spa_outlined),
    'love': ('Love & relationships', 'प्रेम और रिश्ते', Icons.favorite_outline_rounded),
    'family': ('Family', 'परिवार', Icons.family_restroom_rounded),
    'career': ('Career', 'करियर', Icons.work_outline_rounded),
    'wealth': ('Wealth', 'धन', Icons.savings_outlined),
    'spirituality': ('Spiritual path', 'आध्यात्मिक मार्ग', Icons.self_improvement_rounded),
    'life_events': ('Life events', 'जीवन की घटनाएँ', Icons.timeline_rounded),
  };

  static String area(String key, Lang lang) {
    final a = areas[key];
    if (a == null) return key;
    return lang == Lang.hi ? a.$2 : a.$1;
  }

  static IconData areaIcon(String key) => areas[key]?.$3 ?? Icons.circle_outlined;

  static const _values = <String, (String, String)>{
    'short': ('Short', 'छोटी'),
    'medium': ('Medium', 'मध्यम'),
    'long': ('Long', 'लंबी'),
    'faint': ('Faint', 'हल्की'),
    'deep': ('Deep', 'गहरी'),
    'none': ('None', 'कोई नहीं'),
    'some': ('A few', 'कुछ'),
    'many': ('Many', 'कई'),
    'up': ('Upward', 'ऊपर की ओर'),
    'down': ('Downward', 'नीचे की ओर'),
    'both': ('Both ways', 'दोनों ओर'),
    'straight': ('Straight', 'सीधी'),
    'gentle': ('Gently curved', 'हल्की घुमावदार'),
    'steep': ('Strongly curved', 'बहुत घुमावदार'),
    'square': ('Square', 'चौकोर'),
    'rectangular': ('Long (rectangular)', 'लंबी (आयताकार)'),
    'rounded': ('Rounded', 'गोल'),
    'few': ('Few', 'कम'),
    'moderate': ('Moderate', 'सामान्य'),
    'flat': ('Flat', 'सपाट'),
    'normal': ('Normal', 'सामान्य'),
    'raised': ('Raised', 'उभरा हुआ'),
    'left': ('Left hand', 'बायाँ हाथ'),
    'right': ('Right hand', 'दायाँ हाथ'),
    'air': ('Air', 'वायु'),
    'fire': ('Fire', 'अग्नि'),
    'water': ('Water', 'जल'),
  };

  static String value(String v, [Lang lang = Lang.en]) {
    final x = _values[v];
    if (x == null) return v;
    return lang == Lang.hi ? x.$2 : x.$1;
  }

  static UiStatus tone(String tone) => switch (tone) {
        'positive' => UiStatus.success,
        'caution' => UiStatus.warning,
        _ => UiStatus.info,
      };

  static IconData toneIcon(String tone) => switch (tone) {
        'positive' => Icons.auto_awesome_rounded,
        'caution' => Icons.lightbulb_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  /// Chart color index for each line, so a line has the same color
  /// everywhere.
  static int lineColorIndex(String key) => switch (key) {
        'life' => 0,
        'head' => 1,
        'heart' => 2,
        'fate' => 3,
        'sun' => 4,
        'mercury' => 5,
        _ => 6 + key.hashCode.abs() % 2,
      };
}

/// Text in the reading language, with Devanagari-friendly line height.
class LText2 extends StatelessWidget {
  const LText2(this.text, {super.key, this.style, this.maxLines});
  final LText text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final lang = context.app.lang;
    final base = style ?? context.text.bodyMedium;
    return Text(
      text.of(lang),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: lang == Lang.hi ? base?.copyWith(height: 1.55) : base,
    );
  }
}

/// EN / हिन्दी switch for the reading text.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return UiSegmentedControl<Lang>(
      [for (final l in Lang.values) UiSegment(l, label: l == Lang.en ? 'EN' : 'हिं')],
      value: app.lang,
      size: UiSize.sm,
      onChanged: (v) => context.appRead.lang = v,
    );
  }
}

/// One matched rule shown as a card.
class InsightCard extends StatelessWidget {
  const InsightCard(this.rule, {super.key, this.showArea = true});
  final KbRule rule;
  final bool showArea;

  @override
  Widget build(BuildContext context) {
    final lang = context.app.lang;
    final tone = context.colors.tone(Labels.tone(rule.tone));
    return UiSurface(
      padding: const EdgeInsets.all(UiSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UiIconBox(Labels.toneIcon(rule.tone), status: Labels.tone(rule.tone)),
          const UiGap(UiSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rule.title.en.isNotEmpty) LText2(rule.title, style: context.text.titleSmall),
                if (rule.title.en.isNotEmpty) const UiGap(UiSpace.xs),
                LText2(rule.text),
                if (showArea) ...[
                  const UiGap(UiSpace.sm),
                  Row(
                    children: [
                      Icon(Labels.areaIcon(rule.area), size: 14, color: tone.color),
                      const UiGap(UiSpace.xs),
                      Flexible(
                        child: Text(
                          Labels.area(rule.area, lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.labelSmall?.copyWith(color: tone.color),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Short disclaimer shown under readings and remedies.
class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final hi = context.app.lang == Lang.hi;
    return Text(
      hi
          ? 'हस्तरेखा परंपरा पर आधारित यह पठन आत्म-चिंतन और मनोरंजन के लिए है। यह चिकित्सा, कानूनी या आर्थिक सलाह नहीं है।'
          : 'This reading follows the tradition of Vedic palmistry. It is for reflection and enjoyment, '
              'not medical, legal or financial advice.',
      style: context.text.bodySmall,
      textAlign: TextAlign.center,
    );
  }
}

/// A key: value line for small fact lists.
class Fact extends StatelessWidget {
  const Fact(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => UiKeyValue(label, value);
}
