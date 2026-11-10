import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/palm_features.dart';
import 'entry_detail_screen.dart';

/// Browse everything the app knows: articles, lines, signs, planets,
/// nakshatras and remedies. Works offline.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';

  static List<KbEntry> entriesOf(KnowledgeBase kb, EntryKind kind) => switch (kind) {
        EntryKind.article => kb.learn,
        EntryKind.line => [
            for (final k in [...Vocab.primaryLines, ...Vocab.secondaryLines]) ?kb.lines[k],
          ],
        EntryKind.symbol => kb.symbols.values.toList(),
        EntryKind.element => kb.elements.values.toList(),
        EntryKind.guna => kb.gunas.values.toList(),
        EntryKind.finger => kb.fingers.values.toList(),
        EntryKind.planet => [for (final p in Vocab.planets) ?kb.planets[p]],
        EntryKind.rashi => kb.rashis.values.toList(),
        EntryKind.nakshatra => kb.nakshatras,
        EntryKind.remedy => [for (final p in Vocab.planets) ?kb.remedies[p]],
      };

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final q = _query.trim().toLowerCase();

    final results = <(EntryKind, KbEntry)>[];
    if (q.isNotEmpty) {
      for (final kind in EntryKind.values) {
        for (final e in entriesOf(kb, kind)) {
          final hay = [e.name.en, e.name.hi, e.str('sanskrit') ?? '', e.str('devanagari') ?? '', e.key].join(' ').toLowerCase();
          if (hay.contains(q)) results.add((kind, e));
        }
      }
    }

    return Scaffold(
      appBar: const UiAppBar(title: 'Library', subtitle: 'Vedic palmistry, offline'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          UiSearchField(
            hint: 'Search lines, signs, stars…',
            onChanged: (v) => setState(() => _query = v),
            onClear: () => setState(() => _query = ''),
          ),
          const UiGap(UiSpace.lg),
          if (q.isNotEmpty)
            results.isEmpty
                ? const UiEmptyState(compact: true, title: 'Nothing found', icon: Icons.search_off_rounded)
                : UiListGroup(
                    children: [
                      for (final (kind, e) in results.take(60))
                        UiListTile(
                          _title(kb, kind, e).of(lang),
                          subtitle: kind.label,
                          icon: kind.icon,
                          chevron: true,
                          onTap: () => openEntry(context, e, kind: kind),
                        ),
                    ],
                  )
          else ...[
            UiListGroup(
              header: 'Learn',
              children: [
                for (final kind in EntryKind.values)
                  if (entriesOf(kb, kind).isNotEmpty)
                    UiListTile(
                      kind.label,
                      icon: kind.icon,
                      value: '${entriesOf(kb, kind).length}',
                      chevron: true,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EntryListScreen(kind: kind),
                      )),
                    ),
              ],
            ),
            const UiGap(UiSpace.lg),
            Text(
              'Content is retold in our own words from the tradition of Vedic palmistry (Hasta Rekha Shastra).',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  static LText _title(KnowledgeBase kb, EntryKind kind, KbEntry e) => switch (kind) {
        EntryKind.remedy => kb.placeName(e.key),
        EntryKind.line => kb.lineName(e.key),
        _ => e.name,
      };
}

/// Entries of one kind.
class EntryListScreen extends StatelessWidget {
  const EntryListScreen({super.key, required this.kind});
  final EntryKind kind;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final lang = app.lang;
    final items = _LibraryScreenState.entriesOf(kb, kind);
    return Scaffold(
      appBar: UiAppBar(title: kind.label),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          UiListGroup(
            children: [
              for (final (i, e) in items.indexed)
                UiListTile(
                  _LibraryScreenState._title(kb, kind, e).of(lang),
                  subtitle: _subtitle(kb, e, lang),
                  leading: kind == EntryKind.nakshatra
                      ? UiAvatar(name: '${i + 1}', size: UiSize.sm)
                      : UiIconBox(kind.icon, size: 32),
                  chevron: true,
                  onTap: () => openEntry(context, e, kind: kind),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String? _subtitle(KnowledgeBase kb, KbEntry e, Lang lang) {
    final parts = [
      e.str('devanagari'),
      e.str('sanskrit'),
      if (kind == EntryKind.nakshatra && e.str('ruler') != null) kb.placeName(e.str('ruler')!).of(lang),
      if (kind == EntryKind.remedy) e.child('gemstone')?.text('name')?.of(lang),
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
