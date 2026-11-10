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

/// Breaks, branches and forks along the timed lines, placed at an
/// approximate age using the book's timing (kālamāna rekha).
class TimelineTab extends StatelessWidget {
  const TimelineTab({super.key, required this.saved, required this.reading});
  final SavedReading saved;
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final f = saved.features;

    final events = <_Event>[];
    for (final t in kb.timeline) {
      final key = t.str('line') ?? '';
      final line = f.lines[key];
      if (line == null || !line.present) continue;
      final start = t.integer('startAge') ?? 0;
      final end = t.integer('endAge') ?? 60;
      for (final e in line.events) {
        events.add(_Event(key, e.type, (start + e.t.clamp(0, 1) * (end - start)).round()));
      }
    }
    events.sort((a, b) => a.age.compareTo(b.age));
    final about = kb.timeline.where((t) => t.str('line') == 'life').firstOrNull?.text('about');

    return TabBody(
      children: [
        UiAlert(
          hi
              ? 'उम्र अनुमानित है। परंपरा में हर मुख्य रेखा लगभग 60 वर्ष का एक चक्र दिखाती है, जिसे 12-12 वर्ष के भागों में पढ़ा जाता है।'
              : 'Ages are approximate. In this tradition each main line spans a cycle of about 60 years, '
                  'read in steps of 12 years.',
          status: UiStatus.info,
          icon: Icons.schedule_rounded,
        ),
        if (about != null) UiExpandableText(about.of(lang), maxLines: 3,
            moreLabel: hi ? 'और पढ़ें' : 'Read more', lessLabel: hi ? 'कम दिखाएँ' : 'Show less'),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: PalmView(
              overlay: saved.overlay,
              file: saved.photoPath,
              only: {for (final t in kb.timeline) t.str('line') ?? ''},
            ),
          ),
        ),
        if (events.isEmpty)
          UiEmptyState(
            compact: true,
            icon: Icons.timeline_rounded,
            title: hi ? 'कोई बड़ा मोड़ नहीं दिखा' : 'No turning points found',
            message: hi
                ? 'मुख्य रेखाओं पर कोई टूटन या शाखा नहीं मिली। यह एक स्थिर मार्ग का संकेत है।'
                : 'The camera saw no breaks or branches on the main lines, a sign of a steady path.',
          )
        else
          UiTimeline(
            items: [
              for (final e in events)
                UiTimelineItem(
                  '${hi ? 'लगभग' : 'Around age'} ${e.age}${hi ? ' वर्ष' : ''} · ${kb.lineName(e.line).of(lang)}',
                  description: _meaning(e, lang),
                  icon: _icon(e.type),
                  status: switch (e.type) {
                    'branch_up' || 'fork' => UiStatus.success,
                    'break' => UiStatus.warning,
                    _ => UiStatus.info,
                  },
                ),
            ],
          ),
        UiSectionHeader(hi ? 'रेखाओं की अवधि' : 'How far each line runs'),
        for (final t in kb.timeline)
          if (f.lines[t.str('line')]?.present ?? false) _SpanRow(entry: t, line: f.lines[t.str('line')]!),
        const Disclaimer(),
      ],
    );
  }

  static IconData _icon(String type) => switch (type) {
        'break' => Icons.call_split_rounded,
        'branch_up' => Icons.north_east_rounded,
        'branch_down' => Icons.south_east_rounded,
        'fork' => Icons.alt_route_rounded,
        _ => Icons.circle_outlined,
      };

  /// What an event means on a given line. Kept short and constructive.
  static String _meaning(_Event e, Lang lang) {
    const domains = {
      'life': ('your energy, home and daily life', 'आपकी ऊर्जा, घर और दिनचर्या'),
      'head': ('your thinking, studies and plans', 'आपकी सोच, पढ़ाई और योजनाएँ'),
      'heart': ('your feelings and relationships', 'आपकी भावनाएँ और रिश्ते'),
      'fate': ('your work and direction in life', 'आपका काम और जीवन की दिशा'),
      'bracelets': ('your wellbeing and fortune', 'आपकी भलाई और भाग्य'),
    };
    final d = domains[e.line] ?? ('this part of life', 'जीवन के इस भाग');
    final hi = lang == Lang.hi;
    return switch (e.type) {
      'break' => hi
          ? '${d.$2} में बदलाव या नई शुरुआत का समय। धैर्य रखें और नई दिशा को अपनाएँ।'
          : 'A change or fresh start in ${d.$1}. Give yourself time to settle into the new direction.',
      'branch_up' => hi
          ? '${d.$2} में उन्नति, नया अवसर या बढ़ता प्रयास।'
          : 'A rise: a new opportunity or extra effort that lifts ${d.$1}.',
      'branch_down' => hi
          ? '${d.$2} में ऐसा समय जो धैर्य और देखभाल माँगता है।'
          : 'A period in ${d.$1} that asks for patience and care.',
      'fork' => hi
          ? 'आगे चलकर ${d.$2} में कई रास्ते और बहुमुखी प्रतिभा।'
          : 'Later on, more than one path opens in ${d.$1}; you can combine them.',
      _ => '',
    };
  }
}

class _Event {
  _Event(this.line, this.type, this.age);
  final String line;
  final String type;
  final int age;
}

class _SpanRow extends StatelessWidget {
  const _SpanRow({required this.entry, required this.line});
  final KbEntry entry;
  final LineFeature line;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final key = entry.str('line') ?? '';
    final start = entry.integer('startAge') ?? 0;
    final end = entry.integer('endAge') ?? 60;
    final share = switch (line.length) { 'long' => 1.0, 'medium' => 0.7, _ => 0.45 };
    final reach = (start + share * (end - start)).round();
    return Row(
      children: [
        LineDot(key),
        const UiGap(UiSpace.sm),
        SizedBox(width: 110, child: Text(app.kb.lineName(key).of(app.lang), style: context.text.bodySmall)),
        Expanded(
          child: UiProgressBar(
            share,
            label: app.lang == Lang.hi ? '$start–$reach वर्ष तक' : 'Ages $start–$reach',
          ),
        ),
      ],
    );
  }
}
