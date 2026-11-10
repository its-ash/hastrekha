import '../kb/knowledge_base.dart';
import 'palm_features.dart';

/// Matches knowledge-base rules against palm features.
class RulesEngine {
  const RulesEngine(this.kb);
  final KnowledgeBase kb;

  /// True when every condition of [rule] holds for [facts] / [symbols].
  static bool matches(KbRule rule, Map<String, String> facts, List<SymbolMark> symbols) {
    for (final e in rule.when.entries) {
      final key = e.key;
      final accepted = e.value;
      if (key.startsWith('symbol.')) {
        final sym = key.substring(7);
        final marks = symbols.where((s) => s.symbol == sym);
        if (marks.isEmpty) return false;
        final ok = marks.any((m) => accepted.contains('any') || m.location == 'any' || accepted.contains(m.location));
        if (!ok) return false;
        continue;
      }
      final fact = facts[key];
      if (fact == null || !accepted.contains(fact)) return false;
    }
    return rule.when.isNotEmpty;
  }

  Reading evaluate(PalmFeatures features) {
    final facts = features.toFacts();
    final matched = kb.rules.where((r) => matches(r, facts, features.symbols)).toList()
      ..sort((a, b) {
        final w = b.weight.compareTo(a.weight);
        if (w != 0) return w;
        // More specific rules first.
        return b.when.length.compareTo(a.when.length);
      });
    return Reading(features: features, insights: matched, kb: kb);
  }
}

/// The interpreted reading: matched rules grouped for display.
class Reading {
  Reading({required this.features, required this.insights, required this.kb});

  final PalmFeatures features;
  final List<KbRule> insights;
  final KnowledgeBase kb;

  /// Life areas in display order, each with its insights.
  Map<String, List<KbRule>> get byArea {
    final out = <String, List<KbRule>>{};
    for (final a in Vocab.areas) {
      final list = insights.where((r) => r.area == a).toList();
      if (list.isNotEmpty) out[a] = list;
    }
    return out;
  }

  List<KbRule> forLine(String key) => insights.where((r) => r.lineKeys.contains(key)).toList();

  List<KbRule> get handInsights => insights.where((r) => r.when.keys.any((k) => k.startsWith('hand.'))).toList();

  List<KbRule> get moundInsights => insights.where((r) => r.when.keys.any((k) => k.startsWith('mound.'))).toList();

  List<KbRule> get symbolInsights => insights.where((r) => r.when.keys.any((k) => k.startsWith('symbol.'))).toList();

  List<KbRule> get patternInsights =>
      insights.where((r) => r.when.keys.any((k) => k.startsWith('pattern.'))).toList();

  /// The few strongest insights for the summary.
  List<KbRule> get highlights {
    final seen = <String>{};
    final out = <KbRule>[];
    for (final r in insights) {
      // One highlight per area keeps the summary varied.
      if (seen.add(r.area)) out.add(r);
      if (out.length == 6) break;
    }
    return out;
  }

  /// Planets that would benefit from remedies: those named by caution
  /// insights, plus flat or heavily crossed mounds. Most pressing first.
  List<String> get planetsToStrengthen {
    final score = <String, int>{};
    for (final r in insights) {
      if (r.tone == 'caution' && r.planet != null) {
        score[r.planet!] = (score[r.planet!] ?? 0) + r.weight;
      }
    }
    for (final p in Vocab.planets) {
      if (features.mounds[p] == 'flat') score[p] = (score[p] ?? 0) + 1;
      if (features.crossedMounds.contains(p)) score[p] = (score[p] ?? 0) + 1;
    }
    final list = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list) e.key];
  }

  /// Balance of positive / neutral / caution insights.
  ({int positive, int neutral, int caution}) get tones => (
        positive: insights.where((r) => r.tone == 'positive').length,
        neutral: insights.where((r) => r.tone == 'neutral').length,
        caution: insights.where((r) => r.tone == 'caution').length,
      );
}
