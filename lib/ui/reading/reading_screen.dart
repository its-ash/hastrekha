import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../../app/app_state.dart';
import '../../data/history_store.dart';
import '../review/review_screen.dart';
import '../share/share_sheet.dart';
import '../widgets/common.dart';
import 'tabs/areas_tab.dart';
import 'tabs/chart_tab.dart';
import 'tabs/lines_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/remedies_tab.dart';
import 'tabs/timeline_tab.dart';

/// Opens a saved reading.
Future<void> openSavedReading(BuildContext context, SavedReading r) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadingScreen(saved: r)));

/// The full reading of one palm, in tabs.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.saved});
  final SavedReading saved;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  late SavedReading _saved = widget.saved;

  Future<void> _edit() async {
    final photo = await File(_saved.photoPath).readAsBytes();
    if (!mounted) return;
    final updated = await Navigator.of(context).push<SavedReading>(MaterialPageRoute(
      builder: (_) => ReviewScreen(
        features: _saved.features,
        overlay: _saved.overlay,
        photo: photo,
        savedId: _saved.id,
        savedAt: _saved.createdAt,
      ),
    ));
    if (updated != null && mounted) setState(() => _saved = updated);
  }

  Future<void> _delete() async {
    final ok = await UiDialog.confirm(
      context,
      title: 'Delete this reading?',
      message: 'The photo and the reading will be removed from this phone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.appRead.deleteReading(_saved.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final reading = app.evaluate(_saved.features);
    return Scaffold(
      appBar: UiAppBar(
        title: 'Your reading',
        subtitle: '${Labels.value(_saved.hand)} · ${UiFormat.relativeTime(_saved.createdAt)}',
        actions: [
          const LangToggle(),
          UiIconButton(
            Icons.ios_share_rounded,
            tooltip: 'Share',
            onPressed: () => showShareSheet(context, _saved, reading),
          ),
          UiMenuButton<String>(
            items: const [
              UiMenuItem('edit', 'Edit lines', icon: Icons.edit_outlined),
              UiMenuItem('delete', 'Delete', icon: Icons.delete_outline_rounded, destructive: true),
            ],
            onSelected: (v) => v == 'edit' ? _edit() : _delete(),
          ),
        ],
      ),
      body: UiTabView(
        scrollable: true,
        variant: UiTabsVariant.pill,
        tabsPadding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: UiSpace.sm),
        tabs: const ['Overview', 'Birth chart', 'Lines', 'Life areas', 'Timeline', 'Remedies'],
        children: [
          OverviewTab(saved: _saved, reading: reading),
          ChartTab(saved: _saved),
          LinesTab(saved: _saved, reading: reading),
          AreasTab(reading: reading),
          TimelineTab(saved: _saved, reading: reading),
          RemediesTab(reading: reading),
        ],
      ),
    );
  }
}

/// Standard scrolling body for a reading tab.
class TabBody extends StatelessWidget {
  const TabBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pad = UiContent.pagePadding(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, UiSpace.md, pad, UiSpace.xxxl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: UiColumn(gap: UiSpace.lg, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}
