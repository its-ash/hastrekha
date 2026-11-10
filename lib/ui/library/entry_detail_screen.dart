import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../widgets/common.dart';
import '../widgets/nakshatra_view.dart';
import '../widgets/remedy_card.dart';

enum EntryKind {
  article('Articles', Icons.article_outlined),
  line('Lines (rekha)', Icons.gesture_rounded),
  symbol('Signs (chinha)', Icons.star_outline_rounded),
  element('Hand types', Icons.back_hand_outlined),
  guna('Gunas', Icons.blur_circular_rounded),
  finger('Fingers', Icons.front_hand_outlined),
  planet('Planets and mounds', Icons.public_rounded),
  rashi('Rashis on the fingers', Icons.brightness_5_outlined),
  nakshatra('Nakshatras', Icons.auto_awesome_outlined),
  remedy('Remedies (upaya)', Icons.spa_outlined);

  const EntryKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

Future<void> openEntry(BuildContext context, KbEntry entry, {required EntryKind kind}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EntryDetailScreen(entry: entry, kind: kind)));

/// One knowledge-base entry, laid out by kind.
class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({super.key, required this.entry, required this.kind});
  final KbEntry entry;
  final EntryKind kind;

  static const _textFields = <String, (String, String)>{
    'about': ('About', 'परिचय'),
    'location': ('Where to find it', 'कहाँ होती है'),
    'shape': ('What it looks like', 'कैसा दिखता है'),
    'meaning': ('Meaning', 'अर्थ'),
    'looks': ('How it looks', 'पहचान'),
    'nature': ('Nature', 'स्वभाव'),
    'zone': ('On the palm', 'हथेली पर'),
    'mound': ('Mound', 'पर्वत'),
    'signifies': ('Signifies', 'कारकत्व'),
    'strong': ('When strong', 'बलवान होने पर'),
    'weak': ('When weak', 'कमज़ोर होने पर'),
    'body': ('Body', 'शरीर'),
    'traits': ('Traits', 'गुण'),
  };

  static const _listFields = <String, (String, String)>{
    'strengths': ('Strengths', 'शक्तियाँ'),
    'challenges': ('Challenges', 'चुनौतियाँ'),
    'balance': ('Keep in balance', 'संतुलन के उपाय'),
  };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final hi = lang == Lang.hi;
    final pad = UiContent.pagePadding(context);

    final title = kind == EntryKind.remedy ? kb.placeName(entry.key) : (kind == EntryKind.line ? kb.lineName(entry.key) : entry.name);
    final sub = [entry.str('sanskrit'), entry.str('devanagari'), entry.str('dosha')].whereType<String>().join(' · ');

    final related = switch (kind) {
      EntryKind.line => kb.rules.where((r) => r.lineKeys.contains(entry.key)),
      EntryKind.symbol => kb.rules.where((r) => r.when.containsKey('symbol.${entry.key}')),
      EntryKind.planet => kb.rules.where((r) => r.when.keys.any((k) => k.startsWith('mound.${entry.key}'))),
      EntryKind.element => kb.rules.where((r) => r.when['hand.element']?.contains(entry.key) ?? false),
      _ => const <KbRule>[],
    }
        .toList();

    final body = <Widget>[
      if (kind == EntryKind.article)
        for (final para in (entry.text('body')?.of(lang) ?? '').split('\n\n'))
          Text(para.trim(), style: context.text.bodyLarge?.copyWith(height: hi ? 1.6 : 1.45)),
      if (kind == EntryKind.nakshatra) NakshatraView(entry: entry),
      if (kind == EntryKind.remedy) ...[const RemedyNote(), RemedyCard(planet: entry.key, initiallyOpen: true)],
      if (kind != EntryKind.article && kind != EntryKind.nakshatra && kind != EntryKind.remedy) ...[
        if (_facts(context, kb, lang).isNotEmpty) UiCard(child: UiKeyValueList(_facts(context, kb, lang), dividers: false)),
        for (final e in _textFields.entries)
          if (entry.text(e.key) != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hi ? e.value.$2 : e.value.$1, style: context.text.titleSmall),
                const UiGap(UiSpace.xs),
                LText2(entry.text(e.key)!),
              ],
            ),
        for (final e in _listFields.entries)
          if (entry.texts(e.key).isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hi ? e.value.$2 : e.value.$1, style: context.text.titleSmall),
                const UiGap(UiSpace.xs),
                for (final t in entry.texts(e.key))
                  Padding(
                    padding: const EdgeInsets.only(bottom: UiSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [const Text('•  '), Expanded(child: LText2(t))],
                    ),
                  ),
              ],
            ),
        if (kind == EntryKind.planet && kb.remedies[entry.key] != null) ...[
          UiSectionHeader(hi ? 'उपाय' : 'Remedies'),
          RemedyCard(planet: entry.key),
        ],
        if (related.isNotEmpty) ...[
          UiSectionHeader(hi ? 'हथेली पर इसका अर्थ' : 'What it can mean on your palm', subtitle: '${related.length}'),
          for (final r in related.take(40)) InsightCard(r),
        ],
      ],
    ];

    return Scaffold(
      appBar: UiAppBar(
        title: title.of(lang),
        subtitle: sub.isEmpty ? null : sub,
        actions: const [Padding(padding: EdgeInsets.only(right: UiSpace.md), child: LangToggle())],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, UiSpace.md, pad, UiSpace.xxxl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: UiColumn(gap: UiSpace.lg, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
            ),
          ),
        ],
      ),
    );
  }

  List<UiKeyValue> _facts(BuildContext context, KnowledgeBase kb, Lang lang) {
    final hi = lang == Lang.hi;
    String? planet(String f) => entry.str(f) == null ? null : kb.placeName(entry.str(f)!).of(lang);
    return [
      if (entry.str('category') != null) UiKeyValue(hi ? 'प्रकार' : 'Type', entry.str('category')!),
      if (entry.str('planet') != null && kind != EntryKind.remedy) UiKeyValue(hi ? 'ग्रह' : 'Planet', planet('planet')!),
      if (entry.str('ruler') != null) UiKeyValue(hi ? 'स्वामी' : 'Ruler', planet('ruler')!),
      if (entry.str('element') != null) UiKeyValue(hi ? 'तत्व' : 'Element', Labels.value(entry.str('element')!, lang)),
      if (entry.str('guna') != null) UiKeyValue(hi ? 'गुण' : 'Guna', kb.nameOf(entry.str('guna')!).of(lang)),
      if (entry.str('finger') != null) UiKeyValue(hi ? 'उंगली' : 'Finger', kb.nameOf(entry.str('finger')!).of(lang)),
      if (entry.str('phalange') != null) UiKeyValue(hi ? 'पोर' : 'Phalange', entry.str('phalange')!),
      if (entry.strings('rashis').isNotEmpty)
        UiKeyValue(hi ? 'राशियाँ' : 'Rashis', entry.strings('rashis').map((r) => kb.nameOf(r).of(lang)).join(', ')),
      if (entry.strings('planets').isNotEmpty)
        UiKeyValue(hi ? 'ग्रह' : 'Planets', entry.strings('planets').map((r) => kb.placeName(r).of(lang)).join(', ')),
      if (entry.str('tone') != null) UiKeyValue(hi ? 'प्रभाव' : 'Tone', entry.str('tone')!),
    ];
  }
}
