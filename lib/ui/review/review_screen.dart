import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/overlay.dart';
import '../../kb/knowledge_base.dart';
import '../../reading/palm_features.dart';
import '../../vision/palm_analyzer.dart';
import '../profile/birth_editor.dart';
import '../reading/reading_screen.dart';
import '../widgets/common.dart';
import '../widgets/hand_sketch.dart';
import '../widgets/palm_view.dart';
import 'line_editor.dart';

/// Shows what the camera found and lets the user correct it before the
/// reading. Also used to edit a saved reading ([savedId] set).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.features,
    required this.overlay,
    required this.photo,
    this.savedId,
    this.savedAt,
  });

  final PalmFeatures features;
  final PalmOverlay overlay;
  final Uint8List photo;
  final String? savedId;
  final DateTime? savedAt;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final PalmFeatures _f = widget.features.copy();
  String? _highlight;
  bool _showLines = true;
  bool _elementManual = false;
  bool _saving = false;

  void _edit(void Function() change) {
    setState(() {
      change();
      if (!_elementManual) {
        final scores = PalmAnalyzer.elementScores(_f);
        final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        _f.element = ranked.first.key;
        _f.secondary = ranked[1].value >= ranked.first.value * 0.75 ? ranked[1].key : 'none';
      }
    });
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    final app = context.appRead;
    final saved = await app.saveReading(
      features: _f,
      overlay: widget.overlay,
      photo: widget.photo,
      id: widget.savedId,
      createdAt: widget.savedAt,
    );
    if (!mounted) return;
    if (widget.savedId != null) {
      Navigator.of(context).pop(saved);
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReadingScreen(saved: saved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kb = context.app.kb;
    final issues = widget.overlay.issues;
    final detectedKeys = [...Vocab.primaryLines, ...Vocab.detectableSecondary];
    final extraKeys = Vocab.secondaryLines.where((k) => !Vocab.detectableSecondary.contains(k)).toList();
    final shownLines = [
      ...detectedKeys.where((k) => Vocab.primaryLines.contains(k) || (_f.lines[k]?.present ?? false)),
      ...extraKeys.where((k) => _f.lines[k]?.present ?? false),
    ];
    final addable = [...Vocab.secondaryLines].where((k) => !(_f.lines[k]?.present ?? false)).toList();

    return Scaffold(
      appBar: UiAppBar(
        title: widget.savedId == null ? 'Check your lines' : 'Edit reading',
        subtitle: Labels.value(_f.side),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(UiContent.pagePadding(context), UiSpace.sm, UiContent.pagePadding(context), UiSpace.xxxl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: PalmView(
                overlay: widget.overlay,
                bytes: widget.photo,
                highlight: _highlight,
                showLines: _showLines,
              ),
            ),
          ),
          const UiGap(UiSpace.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tap a line below to check it. Correct anything the camera got wrong.',
                  style: context.text.bodySmall,
                ),
              ),
              UiToggleButton.icon(
                Icons.draw_outlined,
                tooltip: 'Show lines',
                selected: _showLines,
                size: UiSize.sm,
                onChanged: (v) => setState(() => _showLines = v),
              ),
            ],
          ),
          for (final i in issues) ...[
            const UiGap(UiSpace.md),
            _IssueAlert(i),
          ],
          const UiGap(UiSpace.xl),
          UiListGroup(
            header: 'Lines',
            footer: 'Confidence shows how sure the camera is. Lines you edit count as certain.',
            children: [
              for (final k in shownLines)
                UiListTile(
                  kb.lineName(k).en,
                  leading: LineDot(k, size: 14),
                  subtitle: _summary(_f.line(k)),
                  trailing: _ConfidencePill(_f.line(k)),
                  selected: _highlight == k,
                  onTap: () async {
                    setState(() => _highlight = k);
                    final edited = await showLineEditor(context, k, _f.line(k));
                    if (edited != null) _edit(() => _f.lines[k] = edited);
                  },
                ),
            ],
          ),
          const UiGap(UiSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: UiButton(
              'Add a line the camera missed',
              icon: Icons.add_rounded,
              variant: UiButtonVariant.ghost,
              onPressed: addable.isEmpty
                  ? null
                  : () async {
                      final k = await UiActionSheet.show<String>(
                        context,
                        title: 'Which line do you see?',
                        actions: [
                          for (final k in addable)
                            UiSheetAction(kb.lineName(k).en, value: k, subtitle: kb.lines[k]?.text('location')?.en),
                        ],
                      );
                      if (k == null || !context.mounted) return;
                      final edited = await showLineEditor(context, k, LineFeature(present: true, confidence: 1, edited: true));
                      if (edited != null) _edit(() => _f.lines[k] = edited);
                    },
            ),
          ),
          const UiGap(UiSpace.xl),
          _BirthSignsSection(f: _f),
          const UiGap(UiSpace.xl),
          _HandSection(
            f: _f,
            elementManual: _elementManual,
            onChanged: (change, {bool element = false}) {
              if (element) _elementManual = true;
              _edit(change);
            },
          ),
          const UiGap(UiSpace.xl),
          _MoundsSection(f: _f, onChanged: _edit),
          const UiGap(UiSpace.xl),
          _SymbolsSection(f: _f, onChanged: _edit),
        ],
      ),
      bottomNavigationBar: UiBottomBar(
        child: UiButton(
          widget.savedId == null ? 'See my reading' : 'Save changes',
          icon: Icons.auto_awesome_rounded,
          expand: true,
          size: UiSize.lg,
          loading: _saving,
          onPressed: _continue,
        ),
      ),
    );
  }

  static String _summary(LineFeature l) {
    if (!l.present) return 'Not found';
    final parts = [
      Labels.value(l.length),
      Labels.value(l.depth).toLowerCase(),
      if (l.breaks != 'none') '${Labels.value(l.breaks).toLowerCase()} breaks',
      if (l.chained) 'chained',
      if (l.fork) 'forked end',
    ];
    return parts.join(' · ');
  }
}

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill(this.line);
  final LineFeature line;

  @override
  Widget build(BuildContext context) {
    if (line.edited) return const UiStatusPill('Edited', status: UiStatus.accent);
    if (!line.present) return const UiStatusPill('Missing', status: UiStatus.neutral);
    final c = line.confidence;
    return c >= 0.7
        ? const UiStatusPill('High', status: UiStatus.success)
        : c >= 0.4
            ? const UiStatusPill('Medium', status: UiStatus.info)
            : const UiStatusPill('Low', status: UiStatus.warning);
  }
}

class _IssueAlert extends StatelessWidget {
  const _IssueAlert(this.issue);
  final String issue;

  @override
  Widget build(BuildContext context) {
    final (title, msg) = switch (PhotoIssue.values.where((e) => e.name == issue).firstOrNull) {
      PhotoIssue.handNotFound => (
          'Hand not clearly found',
          'Lines were read from where the outline places the palm. A plain, darker background helps.'
        ),
      PhotoIssue.blurry => ('Photo looks soft', 'Hold the phone steady and let it focus on the palm.'),
      PhotoIssue.dark => ('Photo is dark', 'Move to a brighter place or turn on the flashlight.'),
      PhotoIssue.bright => ('Photo is too bright', 'Avoid direct sun or flash glare on the palm.'),
      PhotoIssue.fewLines => (
          'Few lines found',
          'Check the lines below and add the ones you can see, or retake the photo in soft side light.'
        ),
      null => ('Note', issue),
    };
    return UiAlert(msg, title: title, status: UiStatus.warning);
  }
}

typedef _Change = void Function(void Function() change, {bool element});

class _HandSection extends StatelessWidget {
  const _HandSection({required this.f, required this.elementManual, required this.onChanged});
  final PalmFeatures f;
  final bool elementManual;
  final _Change onChanged;

  static const _elementHint = {
    'air': 'Long palm, long fingers, many fine lines',
    'fire': 'Square palm, medium fingers, clear lines',
    'water': 'Rounded fleshy palm, short fingers, few deep lines',
  };
  static const _palmHint = {
    'square': 'About as wide as it is long',
    'rectangular': 'Clearly longer than it is wide',
    'rounded': 'Soft, curved, fleshy sides',
  };
  static const _fingerHint = {
    'short': 'Middle finger under ¾ of the palm',
    'medium': 'Middle finger about ¾ of the palm',
    'long': 'Middle finger as long as the palm',
  };
  static const _densityHint = {
    'few': 'Mostly the main lines',
    'moderate': 'Main lines and a few more',
    'many': 'A web of fine lines',
  };

  @override
  Widget build(BuildContext context) {
    final kb = context.app.kb;
    return UiSection(
      title: 'Hand shape',
      subtitle: elementManual
          ? 'Hand type set by you'
          : 'Worked out from the photo. Compare with the pictures and tap the one that looks most like your hand.',
      child: UiCard(
        child: UiColumn(
          gap: UiSpace.xl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiFieldLabel(
              label: 'Hand type (element)',
              helper: kb.elements[f.element]?.text('looks')?.en,
              child: _PictureChoices(
                values: Vocab.elements,
                value: f.element,
                label: (e) => '${Labels.value(e)} · ${kb.elements[e]?.str('dosha') ?? ''}',
                hint: (e) => _elementHint[e] ?? '',
                picture: (e, selected) => HandSketch.element(e, selected: selected),
                onChanged: (v) => onChanged(() => f.element = v, element: true),
              ),
            ),
            UiFieldLabel(
              label: 'Palm shape',
              helper: 'Look at the palm alone, from the base of the fingers to the wrist.',
              child: _PictureChoices(
                values: Vocab.palmShapes,
                value: f.palm,
                label: Labels.value,
                hint: (v) => _palmHint[v] ?? '',
                picture: (v, selected) => HandSketch(palm: v, selected: selected),
                onChanged: (v) => onChanged(() => f.palm = v),
              ),
            ),
            UiFieldLabel(
              label: 'Fingers compared with the palm',
              child: _PictureChoices(
                values: Vocab.fingerLengths,
                value: f.fingers,
                label: Labels.value,
                hint: (v) => _fingerHint[v] ?? '',
                picture: (v, selected) => HandSketch(fingers: v, selected: selected),
                onChanged: (v) => onChanged(() => f.fingers = v),
              ),
            ),
            UiFieldLabel(
              label: 'How many fine lines',
              child: _PictureChoices(
                values: Vocab.densities,
                value: f.lineDensity,
                label: Labels.value,
                hint: (v) => _densityHint[v] ?? '',
                picture: (v, selected) => HandSketch(density: v, selected: selected),
                onChanged: (v) => onChanged(() => f.lineDensity = v),
              ),
            ),
            UiSwitch(
              f.simian,
              label: 'Head and heart lines are one single crease',
              onChanged: (v) => onChanged(() => f.simian = v),
            ),
            UiSwitch(
              f.headLifeJoined,
              label: 'Head and life lines start together',
              onChanged: (v) => onChanged(() => f.headLifeJoined = v),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of picture cards to choose one value from.
class _PictureChoices extends StatelessWidget {
  const _PictureChoices({
    required this.values,
    required this.value,
    required this.label,
    required this.hint,
    required this.picture,
    required this.onChanged,
  });

  final List<String> values;
  final String value;
  final String Function(String) label;
  final String Function(String) hint;
  final Widget Function(String value, bool selected) picture;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const UiGap(UiSpace.sm),
          Expanded(
            child: Semantics(
              selected: values[i] == value,
              button: true,
              label: '${label(values[i])}. ${hint(values[i])}',
              child: UiCard(
                selected: values[i] == value,
                padding: const EdgeInsets.all(UiSpace.sm),
                onTap: () => onChanged(values[i]),
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      SizedBox(height: 92, child: picture(values[i], values[i] == value)),
                      const UiGap(UiSpace.xs),
                      Text(
                        label(values[i]),
                        textAlign: TextAlign.center,
                        style: context.text.labelMedium?.copyWith(
                          color: values[i] == value ? context.colors.accent : null,
                        ),
                      ),
                      const UiGap(2),
                      Text(hint(values[i]), textAlign: TextAlign.center, style: context.text.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The user's signs, filled in from the birth details (no need to enter
/// them), with how the chart's element compares with the hand type.
class _BirthSignsSection extends StatelessWidget {
  const _BirthSignsSection({required this.f});
  final PalmFeatures f;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final kb = app.kb;
    final profile = app.profile;
    final chart = profile.chart;
    if (chart == null || !profile.isComplete) {
      return UiSection(
        title: 'Your signs',
        child: UiAlert(
          'Add your name and date of birth and your Moon sign, Sun sign, rising sign and name sign '
          'are filled in for you and read together with this palm.',
          status: UiStatus.info,
          icon: Icons.auto_awesome_outlined,
          action: UiButton('Add birth details', size: UiSize.sm, onPressed: () => showBirthEditor(context)),
        ),
      );
    }
    final nameSign = profile.nameSign;
    // The chart's leading element, from the rising sign (or the Moon sign
    // without a birth time), in the hand's three-element terms.
    final key = chart.lagna ?? chart.moon.rashi;
    final signElement = kb.rashis[key]?.str('element') ?? 'fire';
    final asHand = const {'fire': 'fire', 'air': 'air', 'water': 'water', 'earth': 'water'}[signElement]!;
    final agrees = asHand == f.element;
    return UiSection(
      title: 'Your signs',
      subtitle: 'Filled in from your birth details, ${profile.name}.',
      action: UiIconButton(Icons.edit_outlined, tooltip: 'Edit birth details', onPressed: () => showBirthEditor(context)),
      child: UiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiKeyValueList([
              if (chart.lagna != null) UiKeyValue('Rising sign (lagna)', kb.nameOf(chart.lagna!).en),
              UiKeyValue('Moon sign (rashi)', kb.nameOf(chart.moon.rashi).en),
              UiKeyValue('Sun sign', kb.nameOf(chart.planets['sun']!.sign).en),
              UiKeyValue('Birth star', kb.nakshatras[chart.moon.nakshatra - 1].name.en),
              if (nameSign != null) UiKeyValue('Name sign', kb.nameOf(nameSign.rashi).en),
            ]),
            const UiGap(UiSpace.md),
            UiAlert(
              agrees
                  ? 'Your ${chart.lagna != null ? 'rising' : 'Moon'} sign ${kb.nameOf(key).en} is a '
                      '${Labels.value(signElement).toLowerCase()} sign, which goes with the '
                      '${Labels.value(f.element)} hand chosen above.'
                  : 'Your ${chart.lagna != null ? 'rising' : 'Moon'} sign ${kb.nameOf(key).en} is a '
                      '${Labels.value(signElement).toLowerCase()} sign, which usually goes with a '
                      '${Labels.value(asHand)} hand. If the pictures above fit you better as '
                      '${Labels.value(asHand)}, choose it; otherwise your reading blends both.',
              status: agrees ? UiStatus.success : UiStatus.info,
              showIcon: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoundsSection extends StatelessWidget {
  const _MoundsSection({required this.f, required this.onChanged});
  final PalmFeatures f;
  final void Function(void Function()) onChanged;

  @override
  Widget build(BuildContext context) {
    final kb = context.app.kb;
    return UiAccordion(
      items: [
        UiAccordionItem(
          'Mounds (parvata)',
          subtitle: 'Fleshy pads under the fingers and around the palm. Estimated from the light; adjust if needed.',
          icon: Icons.landscape_outlined,
          Column(
            children: [
              for (final p in Vocab.planets)
                Padding(
                  padding: const EdgeInsets.only(bottom: UiSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${kb.placeName(p).en} · ${kb.planets[p]?.text('mound')?.en ?? ''}',
                              style: context.text.labelMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const UiGap(UiSpace.xs),
                      Row(
                        children: [
                          Expanded(
                            child: UiSegmentedControl<String>(
                              [for (final l in Vocab.moundLevels) UiSegment(l, label: Labels.value(l))],
                              value: f.mounds[p] ?? 'normal',
                              size: UiSize.sm,
                              expand: true,
                              onChanged: (v) => onChanged(() => f.mounds[p] = v),
                            ),
                          ),
                          const UiGap(UiSpace.sm),
                          UiToggleButton(
                            'Many lines',
                            selected: f.crossedMounds.contains(p),
                            size: UiSize.sm,
                            onChanged: (v) => onChanged(() => v ? f.crossedMounds.add(p) : f.crossedMounds.remove(p)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SymbolsSection extends StatelessWidget {
  const _SymbolsSection({required this.f, required this.onChanged});
  final PalmFeatures f;
  final void Function(void Function()) onChanged;

  @override
  Widget build(BuildContext context) {
    final kb = context.app.kb;
    return UiSection(
      title: 'Palm marks (chinha)',
      subtitle: 'Small shapes on the palm like a star, cross or triangle (not your zodiac sign). '
          'The camera cannot see these reliably, so add any you notice.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (f.symbols.isNotEmpty)
            UiChipGroup(
              children: [
                for (final s in f.symbols)
                  UiChip(
                    '${kb.nameOf(s.symbol).en} · ${kb.placeName(s.location).en}',
                    onDeleted: () => onChanged(() => f.symbols.remove(s)),
                  ),
              ],
            ),
          const UiGap(UiSpace.sm),
          UiButton(
            'Add a palm mark',
            icon: Icons.add_rounded,
            variant: UiButtonVariant.soft,
            onPressed: () async {
              final mark = await showSymbolPicker(context, kb);
              if (mark != null && !f.symbols.contains(mark)) onChanged(() => f.symbols.add(mark));
            },
          ),
        ],
      ),
    );
  }
}

/// Lets the user pick a symbol and where on the palm it is.
Future<SymbolMark?> showSymbolPicker(BuildContext context, KnowledgeBase kb) {
  String? symbol;
  var location = 'any';
  return UiSheet.show<SymbolMark>(
    context,
    title: 'Add a palm mark',
    expand: true,
    child: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mark', style: context.text.labelMedium),
          const UiGap(UiSpace.sm),
          for (final s in kb.symbols.values)
            UiRadioTile<String>(
              s.name.en,
              value: s.key,
              groupValue: symbol,
              subtitle: s.text('shape')?.en,
              onChanged: (v) => setState(() => symbol = v),
            ),
          const UiGap(UiSpace.lg),
          Text('Where is it?', style: context.text.labelMedium),
          const UiGap(UiSpace.sm),
          UiChoiceChips<String>(
            options: [
              const UiChoice('any', 'Not sure'),
              for (final l in Vocab.locations) UiChoice(l, kb.placeName(l).en),
            ],
            value: location,
            onChanged: (v) => setState(() => location = v),
          ),
          const UiGap(UiSpace.xl),
          UiButton(
            'Add',
            expand: true,
            onPressed: symbol == null ? null : () => Navigator.of(context).pop(SymbolMark(symbol!, location)),
          ),
        ],
      ),
    ),
  );
}
